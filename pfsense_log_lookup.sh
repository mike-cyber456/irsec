#!/bin/sh
# IRSeC pfSense: find recent firewall log entries with IP
# Usage: sh pfsense_log_lookup.sh IP_ADDRESS

IP="${1:-}"
case "$IP" in
  ''|-*) echo 'Usage: sh pfsense_log_lookup.sh IP_ADDRESS'; exit 2 ;;
esac

if [ ! -r /var/log/filter.log ]; then
  echo 'Cannot read /var/log/filter.log (check permissions and log layout).'
  exit 1
fi

echo "=== Recent firewall log entries mentioning $IP ==="
if command -v filterparser.php >/dev/null 2>&1; then
  tail -n 2000 /var/log/filter.log | filterparser.php | grep -F "$IP" | tail -n 50
else
  tail -n 2000 /var/log/filter.log | grep -F "$IP" | tail -n 50
fi
