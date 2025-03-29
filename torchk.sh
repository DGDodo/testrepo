#!/bin/sh
#
#     mrt 2025 v1.1                  torchk.sh
# torchk7.sh
#
# Program uses tor and curl to check.torproject.org
# Return using Tor correctly or not.

# - Added curl check if installed
# - Added /etc/tor/torchk.log (output of script)
# - Added check tor = running
# - Added tor ip in log
# - Added get local lan ip
# - Added log header and adjusted output layout
# - Used with TorRouter to check good working tor every hour, with crontab

# Used:
# - /etc/tor/torchk.sh                  - Folder holds 'this script' and its output-file
# - /etc/tor/torchk.log                 - The actual 'log file'
# - /tmp/torchk.html                    - Holds 'collected data'

echo ""
echo "========================================"
echo "            TorRouter Check        v1.1"
echo "========================================"
echo "Start:      "$(date)

# Set log parameter
OUTPUT=/etc/tor/torchk.log

# Set output file parameter
filestr1=/tmp/torchk.html

# Remove output file if exist
if [ -f $filestr1 ]; then rm $filestr1; fi

# Get program ID
progid=$$

# Get curl version
vCurl=$(opkg list-installed | grep 'curl - ' | cut -c8-)
if [ ${#vCurl} -eq 0 ]; then progid=0; fi

# We now use board_name instead of model, due to capitals in string 'model'.
# There is difference in OpenWrt versions (P2812) and device model name.
DEVICE=$(ubus call system board | grep board_name | cut -f4 -d\")

# Get lan ip
lanip=$(uci show | grep lan.ipaddr | cut -d\' -f2)

if [ ! "$DEVICE" = "" ] && [ ! $progid -eq 0 ] && [ "$(service tor status)" = "running" ]; then
  if [ ! -f $OUTPUT  ]; then
    printf "%-6s| %-29s| %-16s| %s\n" progID Date IP Info > $OUTPUT
    echo "------+------------------------------+-----------------+--------------------------------------" >> $OUTPUT
  fi
  printf "%-12s %27s\n" "Output:" "$OUTPUT"
  printf "%-29s %10d\n" "Program ID:" "$progid"
  printf "%-12s %27s\n" "Device:" "$(cat /tmp/sysinfo/model)"
  if [ ! -f $filestr1 ]; then
    curl -x socks5h://$lanip:9050 --connect-timeout 10 -o $filestr1 https://check.torproject.org 2>/dev/null
    if [ -f $filestr1  ]; then
      check=$(cat $filestr1 | grep -m 1 "Congrat")
      torip=$(cat $filestr1 | grep strong | cut -f3 -d'>' | cut -f1 -d'<')
      torstr=$(echo ${check/browser/device} | cut -f2- -d' ')
      if [ -n "$check" ]; then
        printf "%5d | %-29s| %-16s| %s\n" "$progid" "$(date)" "$torip" "$torstr" >> $OUTPUT
      else
        printf "%5d | %-29s| %-16s| %s\n" "$progid" "$(date)" "$torip" "Did not work properly." >>$OUTPUT
      fi
    else
      printf "%5d | %-29s| %-16s| %s\n" "$progid" "$(date)" " " "Download failed!" >>$OUTPUT
    fi
  fi
else
  if [ "$DEVICE" = "" ]; then echo "This is not an OpenWrt device."; fi
  if [ ! "$(service tor status)" = "running" ]; then echo "Service 'tor' is not running."; fi
  if [ $progid -eq 0 ]; then echo "Package 'curl' is not installed."; fi
fi

echo "Stop:       "$(date)
echo ""
