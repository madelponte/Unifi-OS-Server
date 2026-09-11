#!/bin/bash
set -euo pipefail

# The Podman installer generates and passes a persistent console UUID. Do the
# same on first boot so Compose users do not have to manufacture one.
if [[ ! -s /data/uos_uuid && -z "${UOS_UUID:-}" ]]; then
    UOS_UUID="$(cat /proc/sys/kernel/random/uuid)"
    # UniFi expects a version-5 UUID.
    UOS_UUID="${UOS_UUID:0:14}5${UOS_UUID:15}"
    export UOS_UUID
fi

# Bind-mounted directories are initially root-owned. Ensure the bundled
# database and Network application can initialize their data directories.
mkdir -p /var/lib/unifi /var/lib/mongodb /etc/rabbitmq/ssl
chown unifi:unifi /var/lib/unifi
chown mongodb:mongodb /var/lib/mongodb
chown rabbitmq:rabbitmq /etc/rabbitmq/ssl

# A bind mount over /var/log hides the empty, correctly-owned directories
# supplied by the image, so recreate the ones required during early boot.
install -d -o nginx -g nginx -m 0755 /var/log/nginx
install -d -o mongodb -g mongodb -m 0755 /var/log/mongodb
install -d -o rabbitmq -g rabbitmq -m 0755 /var/log/rabbitmq

# The embedded entrypoint does not apply this Docker-friendly setting itself.
# It controls the inform address advertised to adopted devices.
if [[ -n "${UOS_SYSTEM_IP:-}" ]]; then
    case "$UOS_SYSTEM_IP" in
        *$'\n'*|*$'\r'*|*'|'*|*'&'*)
            echo "UOS_SYSTEM_IP contains an unsupported character" >&2
            exit 1
            ;;
    esac

    properties=/var/lib/unifi/system.properties
    if [[ -f "$properties" ]] && grep -q '^system_ip=' "$properties"; then
        sed -i "s|^system_ip=.*|system_ip=${UOS_SYSTEM_IP}|" "$properties"
    else
        printf 'system_ip=%s\n' "$UOS_SYSTEM_IP" >> "$properties"
    fi
    chown unifi:unifi "$properties"
fi

exec /root/uos-entrypoint.sh
