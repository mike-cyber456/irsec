#!/bin/sh
# IRSeC pfSense IP lookup
# Usage: sh pfsense_ip_lookup.sh 10.1.1.3

IP="${1:-}"
case "$IP" in
  ''|-*) echo "Usage: sh pfsense_ip_lookup.sh IP_ADDRESS"; exit 2 ;;
esac

section() { printf '\n===== %s =====\n' "$1"; }
section "Route to $IP"
route -n get "$IP" 2>&1

section "Live PF states mentioning $IP"
pfctl -ss 2>&1 | grep -F "$IP" || echo 'No matching active states found'

section "Loaded rule text mentioning $IP"
pfctl -sr 2>&1 | grep -F "$IP" || echo 'No literal IP match; a rule may use a network or PF alias/table'

section "EasyRule block aliases (where present)"
for TABLE in EasyRuleBlockHostsWAN EasyRuleBlockHostsLAN EasyRuleBlockHostsOPT1; do
  ITEMS=$(pfctl -t "$TABLE" -T show 2>/dev/null)
  if [ -n "$ITEMS" ]; then
    printf '%s:\n' "$TABLE"
    printf '%s\n' "$ITEMS" | grep -F "$IP" || echo '  IP not in this table'
  fi
done

