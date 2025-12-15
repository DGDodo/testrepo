#!/bin/sh
#
# ========================================
#          SCRIPT TORROUTER CHECK
# ========================================
# dec 2025 v1.3a                 torchk.sh
#
# For use with http://TorRouter.nl
#
# This script is for TorRouter devices: Fritz!box 4040, Linksys WHW03 v2, vmware x86_64.
# Program uses Tor and curl to grab 'check.torproject.org'.
# It is used with TorRouter to check good working Tor every hour, with crontab.
# Returns using Tor correctly or not and adjust LED configuration accordingly.

# v1.2
# - Added curl check if installed
# - Added /etc/tor/torchk.log (output of script)
# - Added check Tor = running
# - Added Tor ip in log
# - Added get local lan ip
# - Added log header and adjusted output layout
# - Added Program version (also in log output, v1.2)
# v1.3 (Final release TorRouter 24.10.4 with torset_v1.6.sh)
# - Adjust LED according status (device independent, F4040 & WHW03)
# - Use same log location for torchk.log as Tor: /var/log/tor/
#   Every reboot a new torchk log.
#   Needs also 'Custom Commands' change in torset_v1.6.sh (Done)

# v1.4 (future)
# - Use of function(s) for LED changes in the program 
#   good working Tor =    F4040 -> info LED off           / WHW03->steady green LED
#   defect working Tor =  F4040 -> steady red info LED    / WHW03->steady red LED
#   missing working Tor = F4040 -> blinking red info LED  / WHW03->blinking red LED
# - Added red blinking (info) LED for Tor not running
# - What should be the starting LED config of both devices?
#   WHW03 is blue but trigger status says "none"
#   F4040 is as required (Info LED off)
# - Change hourly crontab check to 5 minutes if failed

# Used:
# - /etc/tor/torchk.sh                  - Folder holds 'this script' and its output-file
# - /var/log/tor/torchk.log             - The actual 'log file'
# - /tmp/torchk.html                    - Holds 'collected data'

# TODO:
#

# Parameters
# ==========
# Program version
Pversion=1.3
# Set log parameter
OUTPUT=/var/log/tor/torchk.log
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

# Functions
# =========
# Function change crontab on error to every 5 minutes, back to hourly if ok
CronTabChange() {
if [ -e /tmp/root.tmp ]; then rm /tmp/root.tmp; fi
if [ -e /etc/crontabs/root ]; then cat /etc/crontabs/root | grep -v /etc/tor/torchk.sh > /tmp/root.tmp; fi
if [ "$1" = "ok" ]; then echo "  0 * * * * /etc/tor/torchk.sh" >> /tmp/root.tmp; fi
if [ "$1" = "error" ]; then echo "0/5 * * * * /etc/tor/torchk.sh" >> /tmp/root.tmp; fi
cp -f /tmp/root.tmp /etc/crontabs/root
rm /tmp/root.tmp
}

# Function LEDs (on=error or off=OK)
AdjustLEDs() {
if [ "$1" = "on" ]; then 
  LEDon="none"
  LEDoff="default-on"
  CronTabChange "error"
fi
if [ "$1" = "off" ]; then
  LEDon="default-on"
  LEDoff="none"
  CronTabChange "ok"
fi
if [ "$1" = "blink" ]; then
  LEDon="none"
  LEDoff="timer"
  LEDdelay=250
  CronTabChange "error"
fi
if [ $DEVICE = "avm,fritzbox-4040" ]; then 
  echo $LEDoff > /sys/class/leds/red:info/trigger;
  if [ $LEDoff = "timer" ]; then
    echo $LEDdelay > /sys/class/leds/red:info/delay_on;
    echo $LEDdelay > /sys/class/leds/red:info/delay_off;
  fi
fi
if [ $DEVICE = "linksys,whw03v2" ]; then
  echo $LEDoff > /sys/class/leds/red:indicator/trigger;
  echo $LEDon > /sys/class/leds/green:indicator/trigger;
  if [ $LEDoff = "timer" ]; then
    echo $LEDdelay > /sys/class/leds/red:indicator/delay_on;
    echo $LEDdelay > /sys/class/leds/red:indicator/delay_off;
  fi
fi
}

# Program
# =======
# Screen header
echo ""
echo "========================================"
echo "            TorRouter Check        v"$Pversion
echo "========================================"
echo "Start:      "$(date)

# Log header
if [ ! "$DEVICE" = "" ] && [ ! $progid -eq 0 ] && [ "$(service tor status)" = "running" ]; then
  if [ ! -f $OUTPUT  ]; then
    echo "Tor check log for TorRouter.nl" > $OUTPUT
    echo "" >> $OUTPUT
    printf "%-6s| %-29s| %-16s| %s\n" progID Date IP Info >> $OUTPUT
    echo "------+------------------------------+-----------------+------------------------------- v"$Pversion" -" >> $OUTPUT
  fi
# Screen info
  printf "%-12s %27s\n" "Output:" "$OUTPUT"
  printf "%-29s %10d\n" "Program ID:" "$progid"
  printf "%-12s %27s\n" "Device:" "$(cat /tmp/sysinfo/model)"
# Grab & check https://check.torproject.org
  if [ ! -f $filestr1 ]; then
    curl -x socks5h://$lanip:9050 --connect-timeout 10 -o $filestr1 https://check.torproject.org 2>/dev/null
    if [ -f $filestr1  ]; then
      check=$(cat $filestr1 | grep -m 1 "Congrat")
      torip=$(cat $filestr1 | grep strong | cut -f3 -d'>' | cut -f1 -d'<')
      torstr=$(echo ${check/browser/device} | cut -f2- -d' ')
# Log & screen info
      if [ -n "$check" ]; then
        printf "%5d | %-29s| %-16s| %s\n" "$progid" "$(date)" "$torip" "$torstr" >> $OUTPUT
        AdjustLEDs "off"
      else
        printf "%5d | %-29s| %-16s| %s\n" "$progid" "$(date)" "$torip" "Did not work properly." >>$OUTPUT
        AdjustLEDs "on"
      fi
    else
      printf "%5d | %-29s| %-16s| %s\n" "$progid" "$(date)" " " "Download failed!" >>$OUTPUT
      AdjustLEDs "on"
    fi
  fi
else
  if [ "$DEVICE" = "" ]; then echo "This is not an OpenWrt device."; fi
  if [ $progid -eq 0 ]; then echo "Package 'curl' is not installed."; fi
  if [ ! "$(service tor status)" = "running" ]; then 
    echo "Service 'Tor' is not running.";
    AdjustLEDs "blink"
  fi
fi

# End
# ===
echo "Stop:       "$(date)
echo ""
