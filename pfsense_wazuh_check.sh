#!/bin/sh
# IRSeC pfSense -> Wazuh port-514 diagnostics
# Usage: sh pfsense_wazuh_check.sh WAZUH_IP 

IP="${1:-}"
case "$IP" in
  ''|-*) echo "Usage: sh pfsense_wazuh_check.sh WAZUH_IP"; exit 2 ;;
esac
section() { printf '\n===== %s =====\n' "$1"; }

section "syslog-ng required process"
ps auxww | grep '[s]yslog-ng' || echo 'WARNING: syslog-ng process not observed'

section "Route and egress interface to Wazuh $IP"
route -n get "$IP" 2>&1

section "Firewall rule references to port 514"
pfctl -sr 2>&1 | grep '514' || echo 'No literal 514 reference in loaded rule text (aliases/default rules may apply)'

section "Live states involving Wazuh IP"
pfctl -ss 2>&1 | grep -F "$IP" || echo 'No matching states observed (not proof of a fault)'

