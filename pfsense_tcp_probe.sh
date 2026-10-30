#!/bin/sh
# IRSeC pfSense: a short TCP connection test to a in scope host.
# Usage: sh pfsense_tcp_probe.sh 10.1.1.4 22 

HOST="${1:-}"
PORT="${2:-}"

case "$HOST" in
  ''|*[!0-9.]*|-*) echo 'Specify one in-scope IPv4 address, not a subnet.'; exit 2 ;;
esac
case "$PORT" in
  ''|*[!0-9]*) echo 'Specify one numeric TCP port (1-65535).'; exit 2 ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo 'TCP port must be 1-65535.'
  exit 2
fi
if ! command -v nc >/dev/null 2>&1; then
  echo 'nc (netcat) not installed; no connection attempted.'
  exit 1
fi

printf 'Testing a TCP connection to %s port %s (max ~3 seconds)...\n' "$HOST" "$PORT"
if nc -z -w 3 "$HOST" "$PORT" >/dev/null 2>&1; then
  echo 'TCP connection succeeded'
  exit 0
else
  echo 'TCP connection failed or timed out'
  exit 1
fi
