#!/bin/sh
#Run: sh pfsense_health.sh

section() { printf '\n===== %s =====\n' "$1"; }
section "Time / Device"
date
hostname
uname -r
section "Interfaces and IPv4 routes"
ifconfig -a
netstat -rn -f inet
section "PF firewall status and loaded rule count"
pfctl -si 2>&1 | sed -n '1,35p'
pfctl -sr 2>&1 | wc -l
section "Loaded rules (first 100 lines)"
pfctl -sr 2>&1 | sed -n '1,100p'
section "Existing connections (first 40 lines)"
pfctl -ss 2>&1 | sed -n '1,40p'
section "Listening IPv4 services"
sockstat -4 -l
section "syslog-ng process (required for Wazuh logging)"
ps auxww | grep '[s]yslog-ng' || echo 'No syslog-ng process observed'
section "Recent firewall log lines"
if [ -r /var/log/filter.log ]; then
  tail -n 12 /var/log/filter.log
else
  echo 'Firewall log unavailable at /var/log/filter.log'
fi
