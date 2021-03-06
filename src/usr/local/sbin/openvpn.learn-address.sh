#!/bin/sh
# openvpn learn-address script maintaining DNS entries of connected clients in
# unbound config.

DOMAIN="${1}"
OP="${2}"
IP="${3}"
CN="${4}"

# Trim domain off to avoid duplication if the CN is an FQDN
CN=${CN%%.${DOMAIN}}

DIR="/var/unbound"
PIDFILE="/var/run/unbound.pid"
IPV4REGEX='^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$'

if [ -n "${IP}" -a "$(/usr/bin/basename ${IP})" = "${IP}" ]; then
	if [ $(expr "${IP}" : ${IPV4REGEX}) -ne 0 ]; then
		ARECORD='A' 
	else
		ARECORD='AAAA' 
	fi
	CONF="${DIR}/openvpn.client.${IP}.conf"

	case "${OP}" in

		add|update)
			TMPCONF=$(/usr/bin/mktemp "${CONF}.XXXXXX")
			TMPSRV=$(/usr/bin/mktemp "${CONF}.XXXXXX")

			if [ -f "${TMPCONF}" -a -f "${TMPSRV}" ]; then
				# Remove all configs which mention the FQDN
				/usr/bin/grep -l -null "^local-data: \"${CN}.${DOMAIN} ${ARECORD} " ${DIR}/openvpn.client.*.conf | /usr/bin/xargs -0 /bin/rm
				/bin/test -f "${CONF}" && /bin/rm "${CONF}"

				# Add new local-data entry.
				(
					echo "local-data-ptr: \"${IP} ${CN}.${DOMAIN}\"" &&
					echo "local-data: \"${CN}.${DOMAIN} ${ARECORD} ${IP}\"" &&
					echo "local-data: \"${CN} ${ARECORD} ${IP}\""
				) > "${TMPCONF}"

				# Check syntax, install configuration and restart unbound.
				(
					echo "server:" &&
					echo "chroot: ${DIR}" &&
					echo "directory: ${DIR}" &&
					echo "include: ${TMPCONF}"
				) > "${TMPSRV}"

				/bin/chmod 644 "${TMPCONF}" "${TMPSRV}"
				/usr/local/sbin/unbound-checkconf "${TMPSRV}" && /bin/mv "${TMPCONF}" "${CONF}"

				# do not restart unbound on connect, see https://redmine.pfsense.org/issues/11129
				/usr/bin/su -m unbound -c "unbound-control -c /var/unbound/unbound.conf local_data ${CN}.${DOMAIN} ${ARECORD} ${IP}"
			fi

			/bin/test -f "${TMPCONF}" && /bin/rm "${TMPCONF}"
			/bin/test -f "${TMPSRV}" && /bin/rm "${TMPSRV}"
		;;

		delete)
			# CN is not set on delete
			if [ -f "${CONF}" ]; then
				ENTRY=`/usr/bin/sed -nr 's/(local-data-ptr\:) \"(.*) (.*)"/\3/p' ${CONF}` &&
				/usr/bin/su -m unbound -c "unbound-control -c /var/unbound/unbound.conf local_data_remove ${ENTRY}"
				/bin/rm "${CONF}"
			fi
		;;

	esac
fi

exit 0
