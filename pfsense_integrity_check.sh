#!/bin/sh
# IRSeC pfSense: display config and loaded rules
# Usage: sh pfsense_integrity_check.sh

echo '== Time and system =='
date
hostname
echo '== pfSense configuration hash =='
if [ -r /conf/config.xml ]; then
  stat -f 'Last modified: %Sm | Bytes: %z | File: %N' /conf/config.xml
  sha256 /conf/config.xml
else
  echo 'Cannot read /conf/config.xml'
fi
echo '== Active loaded PF rule hash =='
pfctl -sr 2>/dev/null | sha256
