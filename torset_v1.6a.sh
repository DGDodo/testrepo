#!/bin/sh
#
# ========================================
#          SCRIPT TORROUTER SETUP
# ========================================
# dec 2025 v1.6a                 torset.sh
#
# For use with http://TorRouter.nl
#
# This script is for OpenWrt devices: Fritz!box 4040, Linksys WHW03 v2, vmware x86_64.
# It will rename the device and setup all needed for Tor and Privoxy to work properly.
#
# Added:         - Program version for output etc.
#                - Program start / input header
#                - Adjusted crontab info for torchk.sh
#                - Changing deletion of wan6 (testing)
# Added & Fixed: - Linksys WHW03 v2: - WAN mac = LAN mac -1
#                                    - Check if the tool works with these 3 Wifi radios
#                - ZyXEL P2812 will stop after overview
# Fixed:         - Make sure irqbalance is started
#                - Fritzbox F4040 WAN mac = LAN mac + 1
#                - Check if torchk.sh and torsetup_v1.x.sh are executable within building version.
#                - irqbalance version also shown for WHW03 v2
#                - Adjusted torchk command (v1.3)
#                - Adjust LED's according torchk.sh (v1.3, device independed)
#                - Remove all P2812 items (add to own P2812 program)
#
# New TorRouter builds have the following files/scripts already in them:
#  - Latest version of Tor (0.4.8.21)
#  - torset_v1.x.sh	this script (creates also /tmp/TR001.log and -finally- /etc/tor/TR001.log)
#  - torchk.sh (v1.3) Tor check script runs every hour to test Tor (and creates torchk.log)
#  - torrc for use with Tor
#  - custom and nftables.d/tor.sh (will be created here if not already in build)
#  - torsocks.conf and torrc_generated will be generated bij Tor itself (if torsocks installed).
#
# To do:

# apr 2025 v1.4a
#
# TorRouter v24+ builds for F4040 & vmware have all needed packages, files and scripts installed.
# Almost all needed files are also in this build, although some are made within this script.
#
# tor version: 0.4.8.16

# - Removed wan6 and adjusted wan for TorRouter use.
#    Difference in vmware vs other hw: macaddr within wan definition.
# - Add /etc/tor/ within /etc/sysupgrade.conf ( all TOR related scripts should be in /etc/tor/ )
#
# - Added test & adjust if /etc/tor/nftables.d/tor.sh is executable.
# - Added /etc/tor/torchk.sh
# - If /etc/tor/torchk.sh is installed, add /etc/crontab/root with: '0 * * * * /etc/tor/torchk.sh'

# - Adjusted program sequence and some needed checks, packages need to be installed, for example:
#   before commands can be used, luci-app-commands is needed.
#   For Privoxy adjustments, privoxy needs to be installed etc.

# 1) INIT
# =======
#
# Set static Parameters
# ---------------------
# Set program version
Pversion=1.6
# Set hostname TorRouter
HOSTNAME=TorRouter
# Set TorRouter default ip
IPADDR=192.168.100.1
# Set ipaddr2 as copy of ipaddr ending with 0 instead of 1
IPADDR2=$(echo "$IPADDR". | cut -d'.' -f-3).0
# Set hardcoded Lan MAC address when it is empty according program
# For P2812-F1 (and maybe some others) this must end on 0 or 8 !
# Normally the program will grab the correct mac addresses.
MACHARD=00:11:22:33:44:50
# Set default Wifi name & pass (if nothing is being filled in)
WIFINAME=TorRouter
WIFIPASS=TorRouter1234
# Upper parameters could be overwritten in program so we keep ...
WIFINAME2=$WIFINAME
WIFIPASS2=$WIFIPASS
# Set services to be stopped during setup process in sequence.
# Make sure 'network' is mentioned last here.
# Sequence is now "privoxy firewall dnsmasq tor network"
SERVICES="privoxy firewall dnsmasq tor network"
# Set program output parameters
OUTPUT=/tmp/TR001.log
OUTPUT2=/etc/tor/TR001.log
# Set minimum free memory 65MB=65000kB
# Should we ask to stop Tor if it is running before memcheck?
FREEMIN=65000

# Program Input Header
clear
echo ""
echo "'"$HOSTNAME"' setup program."
echo "======================================================= v"$Pversion" ==="
echo "                                 "$(date -R)
echo "This script is for the following OpenWrt devices:"
echo " - Fritz!box 4040"
echo " - Linksys WHW03 v2"
echo " - VMware x86_64"
echo ""
echo "It will install TorRouter fully functional and will 'crash' / end"
echo "when run on any other device."
echo ""
echo "Get and check program parameters ..."
echo ""

# Get / check program parameters
# ------------------------------

# Check Hostname is not $HOSTNAME (on TorRouter versions the name is already TorRouter?)
if [ "$HOSTNAME" = "$(uname -n)" ]; then
  echo "This is NOT recommended !!";
  echo "Current device already has name :"$HOSTNAME"!";
  read -p "Should we continue? (y/N)" userinput;
  if [ -z $userinput ]; then userinput=n; fi
  if [ "$userinput" != "y" ]; then
    echo "Program quit...";
    echo "";
    exit;
  fi
  echo "";
fi

# Check if Program already finished before (OUTPUT2)
if [ -f $OUTPUT2 ]; then
  echo "'"$HOSTNAME"' setup did already finished once! New logfile ("$OUTPUT2") will be created.";
  read -p "Should we continue? (y/N)" userinput;
  if [ -z $userinput ]; then userinput=n; fi
  if [ "$userinput" != "y" ]; then
    echo "Program quit...";
    echo "";
    exit;
  fi
  echo "";
  rm -rf $OUTPUT2>/dev/null;
fi

# Check if /tmp/TR001.log already exist -> (OUTPUT)
# Program has started once, not finished and NO reboot has been performed?
if [ -f $OUTPUT ]; then
  echo "'"$HOSTNAME"' setup did not finished before! We start again with clean log.";
  read -p "Should we continue? (y/N)" userinput;
  if [ -z $userinput ]; then userinput=n; fi
  if [ "$userinput" != "y" ]; then
    echo "Program quit...";
    echo "";
    exit;
  fi
  echo "";
  rm -rf $OUTPUT>/dev/null;
fi

# Get DEVICE from /tmp/sysinfo/board_name (OpenWrt)
# or from ubus call system board | grep board_name | cut -f4 -d\" process
# Empty if not OpenWrt. but different OpenWrt versions return different names ?
# Program crash/end here when not run on a OpenWrt device.
#
DEVICE=""
if [ -f /tmp/sysinfo/board_name ]; then DEVICE=$(cat /tmp/sysinfo/board_name); fi
# If not found, use the jsonfilter example:
if [ -z $DEVICE ] && [ -f /bin/ubus ]; then DEVICE=$(ubus call system board | grep board_name | cut -f4 -d\"); fi

# Check if DEVICE is an OpenWrt 0ne, ex1t if not.
if [ -z $DEVICE ]; then
  echo "'"$HOSTNAME"' setup was not started on a OpenWrt device and will exit now.";
  echo "No OpenWrt device is found.";
  echo "";
  exit;
fi

# DEVICE holds which board we have:
# VMware  = vmware-inc-vmware-virtual-platform	vmware-inc-vmware7-1
#           VMware, Inc. VMware7,1
# P2812   = zyxel,p-2812hnu-f1
#           ZyXEL P-2812HNU-F1
# AVM4040 = avm,fritzbox-4040
#           AVM FRITZ!Box 4040
# Linksys = linksys,whw03v2
#
# Our vm devices can have 2 different lower case names ragerding BIOS vs EFI, Other 4.x or later Linux (64-bit).
# For program here we set both to vmware-inc-vmware7-1
if [ $DEVICE = "vmware-inc-vmware-virtual-platform" ]; then $DEVICE="vmware-inc-vmware7-1"; fi

# Check MAC address parameters
# ----------------------------
# We only change WAN mac if device is a P2812 ... or all?
# Other devices like VMware have already right WAN mac.
# VMware          : MACADDR=$(cat /sys/class/net/eth1/address)
# P2812           : MACADDR=<Lan mac + 2hex>
# AVM4040         : MACADDR=$(cat /sys/class/net/wan/address)  ??
#                   Seems not to be ... Mac wan = MAC lan + 1hex
# Linksys         : MACADDR=<Lan mac - 1hex>
# Working OpenWrt : MACADDR=$(cat /sys/class/net/wan/address)
# All others use  : MACADDR=$(cat /sys/class/net/wan/address)  ??

# Get default LAN mac address. Is not used only showed during process
if [ -f /sys/devices/virtual/net/br-lan/address ]; then MACLAN=$(cat /sys/devices/virtual/net/br-lan/address); fi
if [ -z $MACLAN ]; then
  if [ -f /sys/class/net/br-lan/address ]; then MACLAN=$(cat /sys/class/net/br-lan/address); fi
fi
# If empty it is not OpenWrt ?
if [ -z $MACLAN ]; then
  echo "This '"$DEVICE"' is most probably NOT a good working (OpenWrt) device for '"$HOSTNAME"'.";
  echo "Lan MAC address is empty?";
 #  echo "No OpenWrt device name is found: '"$DEVICE"'.";
  echo "Could also be that the device is running in 'failsafe'?";
  echo "Make sure the router work 'normal', not in 'failsafe'.";
  echo "Program will end now.";
  echo "";
  exit;
fi

# Get default WAN mac address:
if [ -f /sys/class/net/wan/address ]; then MACADDR=$(cat /sys/class/net/wan/address); fi
# if empty we try the 'find /sys' methode:
if [ -z $MACADDR ] && [ -n $(find /sys | grep wan | grep address) ]; then MACADDR=$(cat $(find /sys | grep wan | grep address)); fi
# if empty try eth1 (VMware) location:
if [ -z $MACADDR ] && [ -f /sys/class/net/eth1/address ]; then MACADDR=$(cat /sys/class/net/eth1/address); fi
# if still empty, ask for WAN mac input:
if [ -z $MACADDR ]; then
  echo "WAN MAC address is empty. Use format: xx:xx:xx:xx:xx:xx (0-9,A-F)";
  echo "When this input is left empty WAN MAC address wil be: '"$MACHARD"'";
  echo "This is NOT the MAC address of the box! That is normally used for LAN.";
  echo "If set, check afterwards it does not conflict with other MAC addresses,";
  echo "like Wifi MAC addresses. Several hex numbers less or more than the";
  echo "mentioned MAC of the box should do the job";
  read -p "Enter WAN MAC address: " MACADDR;
  MACADDR=$(echo $MACADDR | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}');
  if [ -z $MACADDR ]; then
    MACADDR=$MACHARD;
  fi
fi

# Check if MACADDR = MACLAN
# This could be in normal operation, but here we want different mac addresses.
#
if [ "$MACADDR" = "$MACLAN" ]; then

 # SPECIAL for Linksys WHW03 v2 (MACADDR vs MACLAN)
 # =start==========================================
 # On default OpenWrt the Linksys could return all the same mac addresses for br-lan, lan and wan
 # If so, we do change the wan to [lan-1] if not done already.
 # In rare situation mac address could end with '00', then we will change wan to end with 'ff'.
  if [ "$DEVICE" = "linksys,whw03v2" ]; then
    if [ "$(printf "%d" 0x${MACADDR: -2})" -ge 1 ]; then
      MACADDR=$(printf $(echo $MACADDR | cut -c 1-15); printf "%x\n" $((0x${MACADDR: -2}-0x01)))
    else
      MACADDR=$(echo $MACADDR | cut -c 1-15)ff;
    fi
  fi
 # =end============================================
 # SPECIAL for Linksys WHW03 v2 (MACADDR vs MACLAN)

 # SPECIAL for AVM Fritzbox F4040
 # =start==========================================
 # On default OpenWrt the Fritzbox could return all the same mac addresses for br-lan, lan and wan
 # If so, we do change the wan to [lan+1] if not done already.
 # In rare situation mac address could end with 'ff', then we will change wan to end with '00'.
  if [ "$DEVICE" = "avm,fritzbox-4040" ]; then
    if [ "$(printf "%d" 0x${MACADDR: -2})" -le 254 ]; then
      MACADDR=$(printf $(echo $MACADDR | cut -c 1-15); printf "%x\n" $((0x${MACADDR: -2}+0x01)))
    else
      MACADDR=$(echo $MACADDR | cut -c 1-15)00;
    fi
  fi
 # =end============================================
 # SPECIAL for AVM Fritzbox F4040

fi

# Get current OpenWrt version
# As the wlan mac location for v24.10.0 is different from older versions ??
# Wifi encryption is depending on OpenWrt version (wpa2 or sae).
OPENVER=$(cat /etc/openwrt_release | grep RELEASE | cut -f2 -d\')

# Memory CHECK ($FREECUR $FREEMIN)
FREECUR=$(free | grep Mem | grep -o '[^ ]*$')
if [ "$FREECUR" -le "$FREEMIN" ] && [ "$(service tor status)" = "running"  ]; then
  echo "Tor is running now and takes a lot of memory."
  read -p "Should we stop Tor to free memory? (y/N)" userinput;
  if [ -z $userinput ]; then userinput=n; fi
  if [ "$userinput" = "y" ]; then
    service tor stop
    sleep 2
    FREECUR=$(free | grep Mem | grep -o '[^ ]*$')
  fi
  echo ""
fi
if [ "$FREECUR" -le "$FREEMIN" ]; then
  echo "        =============";
  echo "        !! WARNING !!";
  echo "        =============";
  echo "Total free memory ("$FREECUR" kb) is below threshold of "$FREEMIN" kb.";
  echo "'"$HOSTNAME"' setup can and will install on this device, but keep in mind";
  echo "that after the 'reboot' Tor will become active and could use all your";
  echo "device memory and will finally crash! And looks bricked!";
  echo "A power cycle is needed to restart correctly.";
  echo "";
  echo "To solve this you have to SSH into your device a.s.a.p. after the";
  echo "reboot and type : 'service tor stop'";
  echo "Followed by : 'service tor disable', to prevent Tor starting next";
  echo "boot.";
  echo "You can also login on the web GUI a.s.a.p. and stop/disable Tor there.";
  echo "To prevent Out Of Memory (OOM) errors.";
  echo "";
  read -p "Should we continue? (y/N)" userinput;
  if [ -z $userinput ]; then userinput=n; fi
  if [ "$userinput" != "y" ]; then
    echo "Program quit...";
    echo "";
    exit;
  fi
  echo "";
fi

# Get all wifi devices
#
# find /sys | grep phy | grep macaddress
# Returns all wifi devices even disabled, 1 for P2812, 2 for FB4040
# if there is no wifi nothing will be done
# To get wlan mac(s) : find /sys | grep phy | grep macaddress
#
# F4040 returns   : /sys/devices/platform/soc/a000000.wifi/ieee80211/phy0/macaddress
#                 : /sys/devices/platform/soc/a800000.wifi/ieee80211/phy1/macaddress
# As it has 2 Wifi radios.
#
# WHW03 v2 returns: /sys/devices/platform/soc/40000000.pci/pci0000:00/0000:00:00.0/0000:01:00.0/ieee80211/phy0/macaddress
#                   /sys/devices/platform/soc/a000000.wifi/ieee80211/phy1/macaddress
#                   /sys/devices/platform/soc/a800000.wifi/ieee80211/phy2/macaddress
# As this device as 3 wifi radios.
#
# Get all wifi devices. MACARRAY will hold all locations, count hold number of wifis
# -For do- loop needed & $(cat $a) to get the mac addres(ses)
# MACWIFI holds first macaddress as it will be changed for P2812 (later)
#
MACARRAY=$(find /sys | grep phy | grep macaddress)
count=0
for a in $MACARRAY;
do
  let count++
  if [ $count -eq 1 ]; then MACWIFI=$(cat $a); fi
done

# We found '$count' number of wifi devices
echo ""
echo "Wireless settings"
echo "================="
echo ""
# Check if more then 1 wifi devices (count>1)
if [ $count -gt 1 ]; then echo "Only 1 wifi name and password is asked and used for all wifi radios."; fi
# Ask for Wifi SSID & WPA2 info off the box, if there is any wifi.
if [ $count -ge 1 ]; then
  if [ $count -eq 1 ]; then echo "Here you can ENTER the SSID and it's password / key."; fi
  echo "Normally the information 'of the box' is used."
  echo "When just press 'ENTER' the wifi-name will be '"$WIFINAME2"'"
  echo "with password '"$WIFIPASS2"'"
  echo ""
  echo "For wireless encryption 'SAE' the password MUST be at"
  echo "least 8 characters."
  echo ""
  echo "Devices with more than 1 wifi radio will get all the"
  echo "same name and pass, they can be adjusted afterwards."
  echo ""
  read -p "Enter SSID, normally from the device itself: " WIFINAME;
  if [ -z $WIFINAME ]; then WIFINAME=$WIFINAME2; fi
  echo ""
  read -p "Enter it's password / key: " WIFIPASS;
  if [ -z $WIFIPASS ]; then WIFIPASS=$WIFIPASS2; fi
  echo ""
fi

# if OpenWrt version is lower then v19.07.0 only WPA2 (PSK2) is available for WIFICRYPT
# if password length is long enough (8) WIFICRYPT='SAE-MIXED'
WIFICRYPT='psk2'
if [ $(echo $OPENVER | cut -f1 -d.) -ge 19 ] && [ ${#WIFIPASS} -gt 7 ]; then WIFICRYPT='sae-mixed'; fi

# Additional check for programs and installed packaged like Privoxy & Tor

# Get package versions:
# ---------------------

# Get Privoxy version:
vPriv=$(opkg list-installed | grep 'privoxy' | grep -v 'luci-' | cut -c 11-)
if [ ${#vPriv} -eq 0 ]; then vPriv="not installed"; fi

# Get Tor version:
vTor=$(opkg list-installed | grep 'tor - ' | grep -v 'luci-' | cut -c 7-)
if [ ${#vTor} -eq 0 ]; then vTor="not installed"; fi

# Get irqbalance version (F4040 & WHW03):
vIrqb=$(opkg list-installed | grep irqbalance | grep -v luci | cut -f3 -d' ')
if [ ${#vIrqb} -eq 0 ]; then vIrqb="not installed"; fi

# Get curl version:
# And check if /etc/tor/torchk.sh exist and add text vTorchk to vCurl
vTorchk=""
vCurl=$(opkg list-installed | grep 'curl - ' | cut -c 8-)
if [ ${#vCurl} -eq 0 ]; then vCurl="not installed"; else
  if [ -f /etc/tor/torchk.sh ]; then vTorchk="('torchk.sh' will be activated)"; fi
fi

# Get luci-app-commands version:
vLAC=$(opkg list-installed | grep 'luci-app-commands' | cut -c 21-)
if [ ${#vLAC} -eq 0 ]; then vLAC="not installed"; fi

# Check if processes are running?
# service |grep tor
# service |grep privoxy - this does not work! Privoxy looks stopped, use 'ps | grep privoxy | grep -v root'
# if [ -n "$(ps|grep "privoxy"|grep -v "root")" ]; then echo "running"; else echo "Prog is NOT running."; fi

# Start of $OUTPUT
# Print info, all info seems to be ok to change to TorRouter.
clear
echo "" | tee -a "$OUTPUT"
echo "'"$HOSTNAME"' setup program for device : "$(cat /tmp/sysinfo/model) | tee -a "$OUTPUT"
echo "======================================================= v"$Pversion" ===" | tee -a "$OUTPUT"
echo "                                 "$(date -R) | tee -a "$OUTPUT"
echo "Parameters - Please double check these!" | tee -a "$OUTPUT"
echo "---------- - All mentioned programs should be installed!" | tee -a "$OUTPUT"
echo "Router Name        : "$HOSTNAME | tee -a "$OUTPUT"
echo "OpenWrt version    : "$OPENVER | tee -a "$OUTPUT"
echo "Tor version        : "$vTor | tee -a "$OUTPUT"
echo "Curl version       : "$vCurl"  "$vTorchk | tee -a "$OUTPUT"
echo "Privoxy version    : "$vPriv | tee -a "$OUTPUT"
if [ ! $vIrqb = "not installed" ]; then echo "Irqbalance version : "$vIrqb | tee -a "$OUTPUT"; fi
echo "" | tee -a "$OUTPUT"
echo "IP address LAN     : "$IPADDR | tee -a "$OUTPUT"
echo "LAN MAC address    : "$MACLAN | tee -a "$OUTPUT"
echo "WAN MAC address    : "$MACADDR | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"
if [ $count -eq 0 ]; then echo "No Wifi capabilities found on this OpenWrt device" | tee -a "$OUTPUT"; fi
if [ $count -ge 1 ]; then
  B=0
  for a in $MACARRAY; do
    let B++
    echo "Wifi radio         : "$B | tee -a "$OUTPUT"
    echo "Wifi name          : "$WIFINAME"  (pass: "$WIFIPASS")" | tee -a "$OUTPUT"
    if [ $B -eq 1 ]; then echo "Wifi MAC address   : "$MACWIFI | tee -a "$OUTPUT"; fi
    if [ $B -ne 1 ]; then echo "Wifi MAC address   : "$(cat $a) | tee -a "$OUTPUT"; fi
    echo "Wifi encryption    : "$WIFICRYPT | tee -a "$OUTPUT"
  done
fi
if [ $DEVICE = "zyxel,p-2812hnu-f1" ]; then
  echo "" | tee -a "$OUTPUT"
  echo "This device: '"$DEVICE"', does not support "$HOSTNAME"." | tee -a "$OUTPUT"
  echo "Program will stop here and nothing is changed." | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
  rm -rf $OUTPUT>/dev/null;
  exit;
fi
echo "" | tee -a "$OUTPUT"
echo " WARNING !" | tee -a "$OUTPUT"
echo "This program will stop several services, including network." | tee -a "$OUTPUT"
echo "When run from a SSH shell, there will be no more in- or output." | tee -a "$OUTPUT"
echo "There is only full in- and output on TTL serial connection!" | tee -a "$OUTPUT"
echo "Keep this in mind, when answering the continue question." | tee -a "$OUTPUT"
echo "You will not be able to stop this program, other then running" | tee -a "$OUTPUT"
echo "this from TTL serial." | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"
echo "A logfile ("$OUTPUT2") will be created, just before reboot." | tee -a "$OUTPUT"
echo "" | tee -a "$OUTPUT"
echo "================================================================" | tee -a "$OUTPUT"
#echo "" | tee -a "$OUTPUT"

# Ask to check and continue, clear log if NO
read -p "Should we continue? (y/N) " userinput
if [ -z $userinput ]; then userinput=n; fi
if [ "$userinput" != "y" ]; then
  echo "Program quit...";
  echo "";
  rm -rf $OUTPUT>/dev/null;
  exit;
fi
echo ""

# TEMPORARLY
#exit

#
# 2) PROGRAM
# ==========

# Install additional (missing?) packages here ?
# Only if WAN is active / working ? Clean OpenWrt on WHW03 v2 does not have working WAN!

# Stop services
echo "Stop services." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
for a in $SERVICES;
do
  if [ $a = network ]; then
    echo "After next message only TTL-serial log is shown on screen."
    echo "SSH is stopped due to stopped service: network."
    echo ""
  fi
  if [ -f /etc/init.d/$a ]; then /etc/init.d/$a stop | tee -a "$OUTPUT"; fi
done

sleep 5
# Following logging is only for file & TTL output.

# Write current UCI settings to log
echo "" | tee -a "$OUTPUT"
echo "Copy current UCI config." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci show >> $OUTPUT
echo "" >> $OUTPUT

# Write installed opkg packages to log
echo "List installed packages." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
opkg list-installed >> $OUTPUT
echo "" >> $OUTPUT

# Set hostname & time settings
echo "Change Hostname." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci set system.@system[0].hostname=$HOSTNAME
uci set system.@system[0].zonename='Europe/Amsterdam'
uci set system.@system[0].timezone='CET-1CEST,M3.5.0,M10.5.0/3'
uci commit system

# Set WAN
echo "Correct setup WAN and LAN." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci -q del network.wan=interface
uci set network.wan=interface
if [ $DEVICE = "vmware-inc-vmware7-1" ]; then
  uci set network.wan.device='eth1'
else
  uci set network.wan.device='wan'
  uci set network.wan.macaddr=$MACADDR
fi
uci set network.wan.proto='dhcp'
uci set network.wan.ipv6='0'
uci set network.wan.hostname='*'
uci set network.wan.peerdns='0'
# Remove wan6
uci del firewall.@zone[1].network
uci add_list firewall.@zone[1].network='wan'
uci -q del network.wan6=interface
uci set network.globals.packet_steering='1'

# Set LAN
uci set network.lan=interface
uci set network.lan.device='br-lan'
uci set network.lan.proto='static'
uci set network.lan.ipaddr=$IPADDR
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.ip6assign='60'
uci set network.lan.delegate='0'
uci set network.lan.ipv6='0'
uci commit network

# Adjust tor settings (1. Tor client)
# Creates /etc/tor/custom, if not already exist.
#
echo "Add tor settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! -f /etc/tor/custom ]; then
  echo "Creating file: /etc/tor/custom" | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
  cat << EOF > /etc/tor/custom
AutomapHostsOnResolve 1
AutomapHostsSuffixes .
VirtualAddrNetworkIPv4 172.16.0.0/12
VirtualAddrNetworkIPv6 [fc00::]/8
DNSPort 0.0.0.0:9053
DNSPort [::]:9053
TransPort 0.0.0.0:9040
TransPort [::]:9040
EOF
else
  echo "File: '/etc/tor/custom' already exist." | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
fi
uci del_list tor.conf.tail_include="/etc/tor/custom"
uci add_list tor.conf.tail_include="/etc/tor/custom"
uci commit tor

# F4040 only start
# ==========================================================================
# Adjust /etc/rc.local if not done already
if [ "$DEVICE" = "avm,fritzbox-4040" ]; then
  if [ "$vIrqb" = "not installed" ]; then
    echo " - Package 'irqbalance' is not installed!" | tee -a "$OUTPUT"
    echo "" | tee -a "$OUTPUT"
  else
#   if [ -f /etc/rc.local ] && [ -z $(cat /etc/rc.local | grep "echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor") ]; then
    if [ -f /etc/rc.local ] && ! grep -q "echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor" /etc/rc.local; then
      echo " - Adjusting '/etc/rc.local'." | tee -a "$OUTPUT"
      echo "" | tee -a "$OUTPUT"
      cp /etc/rc.local /etc/rc.old.local
      rm -rf /etc/rc.local
      cat /etc/rc.old.local | grep -v "exit 0" > /etc/rc.local
      cat << EOF >> /etc/rc.local
# TorRouter dec 2025 - Fritz!Box 4040 version (scripted)
# info: torrouter.nl
# email: torrouter@proton.me or torrouter@protonmail.com
# According: https://forum.openwrt.org/t/fritz-box-4040-experiences/64487/5
echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor

# Put your custom commands below here -before exit 0- that should be executed
# once the system init finished. By default this file does nothing.

exit 0
EOF
    else
      echo "File: 'rc.local' already adjusted." | tee -a "$OUTPUT"
      echo "" | tee -a "$OUTPUT"
    fi
  fi
fi
# ==========================================================================
# F4040 only end

# Adjust /etc/sysupgrade.conf if not done already.
if ! grep -q "/etc/tor" /etc/sysupgrade.conf; then
  echo " - Adjusting '/etc/sysupgrade.conf'." | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
  cp /etc/sysupgrade.conf /etc/sysupgrade.old.conf
  rm -rf /etc/sysupgrade.conf
  cat /etc/sysupgrade.old.conf | grep -v "# /etc/example.conf" | grep -v "# /etc/openvpn/" > /etc/sysupgrade.conf
  cat << EOF >> /etc/sysupgrade.conf

# TorRouter dec 2025 (scripted)
# info: torrouter.nl
# email: torrouter@proton.me or torrouter@protonmail.com
# We use https://openwrt.org/docs/guide-user/services/tor/client
# Folder added in config saves:
/etc/tor

# /etc/example.conf
# /etc/openvpn/
EOF
else
  echo "File: '/etc/sysupgrade.conf' already adjusted." | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
fi

#  Adjust tor settings (2. DNS over Tor)
#
# Intercept DNS traffic
echo "Configure firewall to intercept DNS traffic." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci -q del firewall.dns_int
uci set firewall.dns_int="redirect"
uci set firewall.dns_int.name="Intercept-DNS"
uci set firewall.dns_int.family="any"
uci set firewall.dns_int.proto="tcp udp"
uci set firewall.dns_int.src="lan"
uci set firewall.dns_int.src_dport="53"
uci set firewall.dns_int.target="DNAT"
# uci commit firewall

# Enable DNS over Tor
echo "Redirect DNS traffic to Tor and prevent DNS leaks." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci set dhcp.@dnsmasq[0].localuse="0"
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].rebind_protection="0"
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#9053"
uci add_list dhcp.@dnsmasq[0].server="::1#9053"
# uci commit dhcp

#  Adjust tor settings (3. Firewall)
#
# Adjust firewall settings / Intercept TCP traffic
# /etc/nftables.d/tor.sh will be created if not already exist
#
echo "Adjust firewall settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! -f /etc/nftables.d/tor.sh ]; then
  echo "Create & make executable file: '/etc/nftables.d/tor.sh'" | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
  cat << "EOF" > /etc/nftables.d/tor.sh
TOR_CHAIN="dstnat_$(uci -q get firewall.tcp_int.src)"
TOR_RULE="$(nft -a list chain inet fw4 ${TOR_CHAIN} \
| sed -n -e "/Intercept-TCP/p")"
nft replace rule inet fw4 ${TOR_CHAIN} \
handle ${TOR_RULE##* } \
fib daddr type != { local, broadcast } ${TOR_RULE}
EOF
else
  echo "File: '/etc/nftables.d/tor.sh' already exist." | tee -a "$OUTPUT"
  echo "" | tee -a "$OUTPUT"
fi
# Check & make /etc/tor/nftables.d/tor/sh executable:
if [ ! -x /etc/nftables.d/tor.sh ]; then
  chmod +x /etc/nftables.d/tor.sh
fi
uci -q delete firewall.tor_nft
uci set firewall.tor_nft="include"
uci set firewall.tor_nft.path="/etc/nftables.d/tor.sh"
uci -q delete firewall.tcp_int
uci set firewall.tcp_int="redirect"
uci set firewall.tcp_int.name="Intercept-TCP"
uci set firewall.tcp_int.src="lan"
uci set firewall.tcp_int.src_dport="0-65535"
uci set firewall.tcp_int.dest_port="9040"
uci set firewall.tcp_int.proto="tcp"
uci set firewall.tcp_int.family="any"
uci set firewall.tcp_int.target="DNAT"

# Disable LAN to WAN forwarding
echo "Disable LAN to WAN forwarding." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci -q delete firewall.@forwarding[0]

# Intercept IPv6 DNS traffic
echo "Intercept IPv6 DNS traffic." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
# drop invalid packets
uci del firewall.@defaults[0].syn_flood
uci set firewall.@defaults[0].synflood_protect='1'
uci set firewall.@defaults[0].drop_invalid='1'
uci commit firewall

# Disable DNS forwarding for dhcp LAN
echo "Disable DNS forwarding for LAN dhcp." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci set dhcp.@dnsmasq[0].port="0"

# Additional network settings
echo "Additional network settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci del dhcp.lan.dhcpv6='server'
uci set dhcp.lan.limit='50'
uci commit dhcp

# Adjust privoxy settings
echo "Change privoxy settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! "$vPriv" = "not installed" ]; then
  uci set privoxy.system=system
  uci set privoxy.system.boot_delay='10'
  uci set privoxy.privoxy.listen_address=$IPADDR':8118'
  uci set privoxy.privoxy.permit_access=$IPADDR2'/24'
  uci set privoxy.privoxy.forward_socks5t='/ '$IPADDR':9050 . '
  uci commit privoxy
fi

# Additional TorRouter additions / adjustments

# if /etc/tor/torchk.sh then check if /etc/crontab/root exist and holds torchk.sh already, if not add it
# depends also on curl
echo "Check & adjust crontab." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! "$vCurl" = "not installed" ];then
  if [ -f /etc/tor/torchk.sh ] && [ ! -f /etc/crontabs/root ]; then
    cat << "EOF" > # Info: https://openwrt.org/docs/guide-user/base-system/cron
# TorRouter.nl version for check Tor.
# .----------- Minute (0 - 59)
# | .--------- Hour (0 - 23)
# | | .------- Day (1 - 31)
# | | | .----- Month (1 - 12)
# | | | | .--- Day of week (0 - 6) (Sunday =0)
# | | | | |
# v v v v v
# * * * * * command to execute
  0 * * * * /etc/tor/torchk.sh
EOF
  else
    if ! grep -q "/etc/tor/torchk.sh" /etc/tor/torchk.sh; then
      echo "0 * * * * /etc/tor/torchk.sh" >> /etc/crontabs/root
    fi
  fi
fi

# Add custom commands
# Check if luci-app-commands is installed ?
if [ ! "$vLAC" = "not installed" ]; then
  echo "Add custom commands." | tee -a "$OUTPUT"
  echo "--------------------------------------------------------------------------------" >> $OUTPUT
  if [ ! "$vTor" = "not installed" ]; then
    uci add luci command
    uci set luci.@command[-1].param='0'
    uci set luci.@command[-1].public='0'
    uci set luci.@command[-1].name='Tor full log'
    uci set luci.@command[-1].command='cat /var/log/tor/notices.log'
    uci del luci.@command[-1].param
    uci del luci.@command[-1].public
    uci add luci command
    uci set luci.@command[-1].param='0'
    uci set luci.@command[-1].public='0'
    uci set luci.@command[-1].name='Show tor torrc file'
    uci set luci.@command[-1].command='cat /etc/tor/torrc'
    uci del luci.@command[-1].param
    uci del luci.@command[-1].public
    uci add luci command
    uci set luci.@command[-1].param='0'
    uci set luci.@command[-1].public='0'
    uci set luci.@command[-1].name='Show tor custom file'
    uci set luci.@command[-1].command='cat /etc/tor/custom'
    uci del luci.@command[-1].param
    uci del luci.@command[-1].public
  fi
  uci add luci command
  uci set luci.@command[-1].param='0'
  uci set luci.@command[-1].public='0'
  uci set luci.@command[-1].name='Disk overview'
  uci set luci.@command[-1].command='df -Th'
  uci del luci.@command[-1].param
  uci del luci.@command[-1].public
  uci add luci command
  uci set luci.@command[-1].param='0'
  uci set luci.@command[-1].public='0'
  uci set luci.@command[-1].name='Clear cache'
  uci set luci.@command[-1].command='sync | echo 3 > /proc/sys/vm/drop_caches'
  uci del luci.@command[-1].param
  uci del luci.@command[-1].public
  if [ -f /etc/tor/torchk.sh ]; then
    uci add luci command
    uci set luci.@command[-1].param='0'
    uci set luci.@command[-1].public='0'
    uci set luci.@command[-1].name='TorRouter Check Log'
    uci set luci.@command[-1].command='cat /var/log/tor/torchk.log'
    uci del luci.@command[-1].param
    uci del luci.@command[-1].public
    uci add luci command
    uci set luci.@command[-1].param='0'
    uci set luci.@command[-1].public='0'
    uci set luci.@command[-1].name='Crontab Log'
    uci set luci.@command[-1].command='logread -e cron'
    uci del luci.@command[-1].param
    uci del luci.@command[-1].public
  fi
  uci commit luci
fi

# Set Wifi device(s)
#
if [ $count -gt 0 ]; then
  echo "Set and activate Wifi(s) according device." | tee -a "$OUTPUT";
  echo "--------------------------------------------------------------------------------" >> $OUTPUT
  C=0
  for a in $MACARRAY;
  do
    uci set wireless.radio$C.cell_density='0';
    uci set wireless.radio$C.channel='auto';
    uci set wireless.default_radio$C.ssid=$WIFINAME;
    if [ $C -eq 0 ]; then uci set wireless.default_radio$C.macaddr=$MACWIFI; fi
    if [ $C -ne 0 ]; then uci set wireless.default_radio$C.macaddr=$(cat $a); fi
    uci set wireless.default_radio$C.encryption=$WIFICRYPT;
    uci set wireless.default_radio$C.key=$WIFIPASS;
    uci set wireless.radio$C.disabled='0';
    let C++;
  done
  uci commit wireless;
fi

# Adjust uHTTPd https setting:
echo "Change / adjust webserver settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ -n "$(opkg list-installed | grep 'luci-ssl-')" ]; then
  uci set uhttpd.main.redirect_https='on'
  uci commit uhttpd
fi

# Make sure irqbalance is started
echo "Check and start irqbalance settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! $vIrqb = "not installed" ]; then 
  if [ -z $(uci show irqbalance.irqbalance.enabled | grep 1) ]; then
    uci set irqbalance.irqbalance.enabled='1'
    uci commit irqbalance
  fi
fi

#
# 3) END
# ======
uci commit

# Write new UCI config to log:
echo "" >> $OUTPUT
echo "New UCI config:" | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci show >> $OUTPUT

# Write end info
echo "" | tee -a "$OUTPUT"
echo "                                 "$(date -R) | tee -a "$OUTPUT"
echo "======================================================= v"$Pversion" ===" | tee -a "$OUTPUT"
echo "Program will reboot '"$DEVICE"' in 5 seconds ... CTRL-C will break."
echo "Stopped services will NOT be started! A reboot is required!"
echo "And the REBOOT will be performed."
echo ""

# Copy logfile to /etc/tor/
# After a reboot the /tmp version is removed ($OUTPUT).
cp $OUTPUT $OUTPUT2

sleep 5
reboot
