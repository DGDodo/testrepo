#!/bin/sh
#
# ========================================
#          SCRIPT TORROUTER SETUP
# ========================================
# mrt 2025 v1.4a            torset_v1.5.sh
#
# Docs & info in KINGSTON/OpenWrt/TorRouter.script/TorRouter_build_AVM4040_DGDodo2.txt
# ../P2812/TSTscripts/TorRouterSetup/torset_v1.4.sh (LD865)
#
# TorRouter v24+ builds for F4040 & vmware have all needed packages, files and scripts installed.
# Almost all needed files are also in this build, although some are made within this script.
#
# tor version: 0.4.8.16

# - Removed wan6 and adjusted wan for TorRouter use.
#    Difference in vmware vs other hw: macaddr within wan definition.
# - Add /etc/tor/ within /etc/sysupgrade.conf ( all TOR related scripts should be in /etc/tor/ )
#
# - Added test & adjust if /etc/tor/nftables.d/tor/sh is executable.
# - Added /etc/tor/torchk.sh
# - If /etc/tor/torchk.sh is installed, add /etc/crontab/root with: '0 * * * * /etc/tor/torchk.sh'
#
# - Adjusted program sequence and some needed checks, packages need to be installed, for example:
#   before commands can be used, luci-app-commands is needed.
#   For Privoxy adjustments, privoxy needs to be installed etc.
#

# 1) INIT
# =======
#
# Set static Parameters
# ---------------------

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

# Set minimum free memory 60MB
FREEMIN=60000

# Get / check program parameters
# ------------------------------
echo ""

# Check Hostname is not $HOSTNAME (on TorRouter versions the name is already TorRouter?)
if [ "$HOSTNAME" = "$(uname -n)" ]; then
  echo "This is NOT recommended !!";
  echo "Current device already has name :"$HOSTNAME"!";
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

# Check if Program already finished before (OUTPUT2)
if [ -f $OUTPUT2 ]; then
  echo "'"$HOSTNAME"' setup did already finished once! New logfile ("$OUTPUT2") will be created.";
  echo "";
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
  echo "";
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
#
DEVICE=""
if [ -f /tmp/sysinfo/board_name ]; then DEVICE=$(cat /tmp/sysinfo/board_name); fi
# If not found, use the jsonfilter example:
if [ -z $DEVICE ]; then DEVICE=$(ubus call system board | grep board_name | cut -f4 -d\"); fi

# Check if DEVICE is an OpenWrt 0ne, ex1t if not.
if [ -z $DEVICE ]; then
  echo "'"$HOSTNAME"' setup was not started on a OpenWrt device and will exit now.";
  echo "No OpenWrt device name is found: '"$DEVICE"'.";
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
#
# Our vm devices can have 2 different lower case names (BIOS vs EFI, Other 4.x or later Linux (64-bit)).
# For program here we set both to vmware-inc-vmware7-1
if [ $DEVICE = "vmware-inc-vmware-virtual-platform" ]; then $DEVICE="vmware-inc-vmware7-1"; fi

# Check MAC address parameters
# ----------------------------
# We only change WAN mac if device is a P2812 ... or?
# Other devices like VMware have already right WAN mac
# VMware          : MACADDR=$(cat /sys/class/net/eth1/address)
# P2812           : MACADDR=<Lan mac + 2hex>
# AVM4040         : MACADDR=$(cat /sys/class/net/wan/address)
# Working OpenWrt : MACADDR=$(cat /sys/class/net/wan/address)
# All others use  : MACADDR=$(cat /sys/class/net/wan/address)  ??

# Get default LAN mac address. Is not used only showed during process
if [ -f /sys/devices/virtual/net/br-lan/address ]; then MACLAN=$(cat /sys/devices/virtual/net/br-lan/address); fi
if [ -z $MACLAN ]; then
  if [ -f /sys/class/net/br-lan/address ]; then MACLAN=$(cat /sys/class/net/br-lan/address); fi
fi
# If empty it is not OpenWrt ?
if [ -z $MACLAN ]; then
  echo "This is most probably NOT a good working (OpenWrt) device for '"$HOSTNAME"'.";
  echo "Lan MAC address is "$MACLAN".";
  echo "No OpenWrt device name is found: '"$DEVICE"'.";
  echo "Program will end now.";
  echo "";
  exit;
fi

# Get default WAN mac address:
if [ -f /sys/class/net/wan/address ]; then MACADDR=$(cat /sys/class/net/wan/address); fi
# if empty we try the 'find /sys' methode:
if [ -z $MACADDR ] && [ ! -z $(find /sys | grep wan | grep address) ]; then MACADDR=$(cat $(find /sys | grep wan | grep address)); fi
# if empty try eth1 (VMware) location:
if [ -z $MACADDR ] && [ -f /sys/class/net/eth1/address ]; then MACADDR=$(cat /sys/class/net/eth1/address); fi
# if still empty, ask for WAN mac input:
if [ -z $MACADDR ]; then
  echo "WAN MAC address is empty. Use format: xx:xx:xx:xx:xx:xx"
  echo "When this input is left empty WAN MAC address wil be: '"$MACHARD"'"
  read -p "Enter WAN MAC address: " MACADDR;
  MACADDR=$(echo $MACADDR | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}');
  if [ -z $MACADDR ]; then
    MACADDR=$MACHARD;
  fi
fi

# Get current OpenWrt version
# As the wlan mac location for v24.10.0 is different from older versions ?? to be tested on lower P2812 ...
# Wifi encryption is depending on OpenWrt version (wpa2 or sae).
OPENVER=$(cat /etc/openwrt_release | grep RELEASE | cut -f2 -d\')

# Memory CHECK ($FREECUR $FREEMIN)
FREECUR=$(free | grep Mem | grep -o '[^ ]*$')
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
# P2812 returns   : /sys/devices/pci0000:00/0000:00:0e.0/ieee80211/phy0/macaddress
# For the P2812 the extra command in /etc/rc.local should be run before any result!
#
if [ "$DEVICE" = "zyxel,p-2812hnu-f1" ] && [ $(echo $OPENVER | cut -f1 -d.) -ge 21  ] && [ -f /etc/rc.local ] && [ -z $(cat /etc/rc.local | grep "echo 1 > /sys/bus/pci/rescan") ]; then
  echo "Check if P2812 see Wifi after special command... (duration over 10 seconds)"
  echo "When fully run this program, '/etc/rc.local' will be adjusted."
  echo "If still no wifi found? This P2812's wifi is most probably bricked!"
  echo ""
  sleep 1
  echo 1 > /sys/bus/pci/rescan
  sleep 10
  echo ""
fi

# F4040 returns   : /sys/devices/platform/soc/a000000.wifi/ieee80211/phy0/macaddress
# and             : /sys/devices/platform/soc/a800000.wifi/ieee80211/phy1/macaddress
# As it has 2 Wifi frequencies.

# Get all wifi devices. MACARRAY will hold all locations, count hold number of wifis
# For do loop needed & $(cat $a) to get the mac addres(ses)
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

# Check if more then 1 wifi devices (count>1)
if [ $count -gt 1 ]; then
  echo "Only 1 wifi name and password is asked and used for all wifis."
fi

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
  echo "Devices with more than 1 wifi device will get all the"
  echo "same name and pass, they can be adjusted afterwards."
  echo ""
  read -p "Enter SSID, normally from the device itself: " WIFINAME;
  if [ -z $WIFINAME ]; then WIFINAME=$WIFINAME2; fi
  echo ""
  read -p "Enter it's password / key: " WIFIPASS;
  if [ -z $WIFIPASS ]; then WIFIPASS=$WIFIPASS2; fi
  echo ""
fi

# if version is lower then v19.07.0 only WPA2 (PSK2) is available for WIFICRYPT
# if password length is long enough (8) WIFICRYPT='SAE'
WIFICRYPT='psk2'
if [ $(echo $OPENVER | cut -f1 -d.) -ge 19 ] && [ ${#WIFIPASS} -gt 7 ]; then WIFICRYPT='sae-mixed'; fi

# SPECIAL for P-2812HNU-F1 (MACADDR & MACWIFI)
# =start======================================

# Create WAN mac address, default WAN mac address is wrong (eth0).
# LAN MAC address is 'off the box' and working.
# So we need the MAC address of the box (will be LAN).
# We add '#02' (hex) to the box address for WAN MAC and add '#04' for first WIFI MAC.
if [ "$DEVICE" = "zyxel,p-2812hnu-f1" ]; then
  if [ "${MACLAN: -1}" = 0 ]; then
    MACADDR=$(echo $MACLAN | cut -c 1-16)2;
    MACWIFI=$(echo $MACLAN | cut -c 1-16)4;
  fi
  if [ "${MACLAN: -1}" = 8 ]; then
    MACADDR=$(echo $MACLAN | cut -c 1-16)a;
    MACWIFI=$(echo $MACLAN | cut -c 1-16)c;
  fi
  if [ ! -f /lib/firmware/RT3062.eeprom ]; then
    echo "File: '/lib/firmware/RT3062.eeprom' is missing."
    if [ -f ./RT3062.eeprom ]; then
      echo " We copy the 'RT3062.eeprom' to it's location."
      cp ./RT3062.eeprom /lib/firmware/RT3062.eeprom
    else
      echo " The file 'RT3062.eeprom' is not found !"
    fi
  fi
fi
# =end==============================
# SPECIAL for P-2812HNU-F1 (MACADDR)

# Additional check for programs and installed packaged like Privoxy & Tor

# Get package versions:
# ---------------------
# Get Privoxy version:
vPriv=$(opkg list-installed | grep 'privoxy' | grep -v 'luci-' | cut -c 11-)
if [ ${#vPriv} -eq 0 ]; then vPriv="not installed"; fi

# Get Tor version:
vTor=$(opkg list-installed | grep 'tor - ' | grep -v 'luci-' | cut -c 7-)
if [ ${#vTor} -eq 0 ]; then vTor="not installed"; fi

# Get curl version:
vCurl=$(opkg list-installed | grep 'curl - ' | cut -c 8-)
if [ ${#vCurl} -eq 0 ]; then vCurl="not installed"; fi

# Get luci-app-commands version:
vLAC=$(opkg list-installed | grep 'luci-app-commands' | cut -c 21-)
if [ ${#vLAC} -eq 0 ]; then vLAC="not installed"; fi

# Get irqbalance version (F4040):
vIrqb=$(opkg list-installed | grep irqbalance | grep -v luci | cut -f3 -d' ')
if [ ${#vIrqb} -eq 0 ]; then vIrqb="not installed"; fi

# Check if /etc/tor/torchk.sh exist and add text to vCurl ?
if [ -f /etc/tor/torchk.sh ] && [ ! -z $vCurl ]; then vTorchk="('torchk.sh' will be activated)"; fi

#  service |grep tor
#  service |grep privoxy

# Start of $OUTPUT
# Print info, all info seems to be ok to change to TorRouter.
echo "" | tee -a "$OUTPUT"
echo "'"$HOSTNAME"' setup program for device : "$(cat /tmp/sysinfo/model) | tee -a "$OUTPUT"
echo "================================================================" | tee -a "$OUTPUT"
echo "                                 "$(date -R) | tee -a "$OUTPUT"
echo "Parameters ( Please double check these! )" | tee -a "$OUTPUT"
echo "----------" | tee -a "$OUTPUT"
echo "Router Name        : "$HOSTNAME"  (on device: "$(cat /tmp/sysinfo/model)")" | tee -a "$OUTPUT"
echo "OpenWrt version    : "$OPENVER | tee -a "$OUTPUT"
echo "Tor version        : "$vTor | tee -a "$OUTPUT"
echo "Curl version       : "$vCurl"  "$vTorchk | tee -a "$OUTPUT"
echo "Privoxy version    : "$vPriv | tee -a "$OUTPUT"
if [ "$DEVICE" = "avm,fritzbox-4040" ]; then echo "Irqbalance version : "$vIrqb | tee -a "$OUTPUT"; fi
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
    echo "Wifi number        : "$B | tee -a "$OUTPUT"
    echo "Wifi name          : "$WIFINAME"  (pass: "$WIFIPASS")" | tee -a "$OUTPUT"
    if [ $B -eq 1 ]; then echo "Wifi MAC address   : "$MACWIFI | tee -a "$OUTPUT"; fi
    if [ $B -ne 1 ]; then echo "Wifi MAC address   : "$(cat $a) | tee -a "$OUTPUT"; fi
    echo "Wifi encryption    : "$WIFICRYPT | tee -a "$OUTPUT"
  done
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


# echo "" | tee -a "$OUTPUT"
# date -R | tee -a "$OUTPUT"
#  echo "" | tee -a "$OUTPUT"


# echo "Versions:"
# echo "Privoxy       : "$vPriv
# echo "Tor version   : "$vTor
# echo "Curl          : "$vCurl"  "$vTorchk
# echo "Luci-Commands : "$vLAC
# echo "IRQbalance    : "$vIrqb
# echo ""
# echo "Device          : "$DEVICE
# echo "Nr of WIfi      : "$count
# echo "Mac addr        : "$MACADDR
# echo "OpenWrt version : "$OPENVER
echo ""

#exit

#
# 2) PROGRAM
# ==========

# Install additional (missing?) packages here ?
# Only if WAN is active / working ?
#

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
echo "List installed OPKG packages." | tee -a "$OUTPUT"
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
uci -q del network.wan6=interface
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
#
echo "Add tor settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! -f /etc/tor/custom ]; then
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
fi
uci del_list tor.conf.tail_include="/etc/tor/custom"
uci add_list tor.conf.tail_include="/etc/tor/custom"
uci commit tor

# F4040 only start
# ==========================================================================
# Adjust /etc/rc.local if not done already
if [ "$DEVICE" = "avm,fritzbox-4040" ]; then
  if [ "$vIrqb" = "not installed" ]; then
    echo " - Package 'irqbalance' is not installed." | tee -a "$OUTPUT"
  else
    if [ -f /etc/rc.local ] && [ -z $(cat /etc/rc.local | grep "echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor") ]; then
      echo " - Adjusting '/etc/rc.local'." | tee -a "$OUTPUT"
      cp /etc/rc.local /etc/rc.old.local
      rm -rf /etc/rc.local
      cat /etc/rc.old.local | grep -v "exit 0" > /etc/rc.local
      cat << EOF >> /etc/rc.local
# F4040 TorRouter
# According https://forum.openwrt.org/t/fritz-box-4040-experiences/64487/5
echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor

exit 0
EOF
    fi
  fi
fi
# ==========================================================================
# F4040 only end

# Adjust /etc/sysupgrade.conf if not done already.
if [ -f /etc/sysupgrade.conf ] && [ -z $(cat /etc/sysupgrade.conf | grep "/etc/tor") ]; then
  echo " - Adjusting '/etc/sysupgrade.conf'." | tee -a "$OUTPUT"
  cp /etc/sysupgrade.conf /etc/sysupgrade.old.conf
  rm -rf /etc/sysupgrade.conf
  cat /etc/sysupgrade.old.conf | grep -v "# /etc/example.conf" | grep -v "# /etc/openvpn/" > /etc/sysupgrade.conf
  cat << EOF >> /etc/sysupgrade.conf
# TorRouter
# https://openwrt.org/docs/guide-user/services/tor/client
/etc/tor

# /etc/example.conf
# /etc/openvpn/
EOF
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
echo "Adjust firewall settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
if [ ! -f /etc/nftables.d/tor.sh ]; then
  cat << "EOF" > /etc/nftables.d/tor.sh
TOR_CHAIN="dstnat_$(uci -q get firewall.tcp_int.src)"
TOR_RULE="$(nft -a list chain inet fw4 ${TOR_CHAIN} \
| sed -n -e "/Intercept-TCP/p")"
nft replace rule inet fw4 ${TOR_CHAIN} \
handle ${TOR_RULE##* } \
fib daddr type != { local, broadcast } ${TOR_RULE}
EOF
fi
# Test if /etc/tor/nftables.d/tor/sh is executable:
if [ -f /etc/nftables.d/tor.sh ] && [ ! "$(ls -al /etc/nftables.d/tor.sh | cut -c -4 | cut -c 4)" = "x" ]; then
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
echo " Disable LAN to WAN forwarding." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci -q delete firewall.@forwarding[0]
# uci commit firewall

# --- below to be checked !!! ---------   For now we leave them, check afterwards
#                                         with also the torscript of OpenWrt.
# Intercept IPv6 DNS traffic
echo " Intercept IPv6 DNS traffic." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
# drop invalid packets
uci del firewall.@defaults[0].syn_flood
uci set firewall.@defaults[0].synflood_protect='1'
uci set firewall.@defaults[0].drop_invalid='1'
uci commit firewall

# Enable DNS over Tor
echo "Enable DNS over Tor." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
# uci set dhcp.@dnsmasq[0].boguspriv="0"

# Disable DNS forwarding for dhcp
echo "Disable DNS forwarding for LAN dhcp." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
# uci set dhcp.@dnsmasq[0].port="0"

# Additional network settings
echo "Additional network settings." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci del dhcp.lan.dhcpv6='server'
uci set dhcp.lan.limit='50'
uci commit dhcp
#
# ---- to be tested   all above here --------

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
if [ ! "$vCurl" = "not installed" ];then
  if [ -f /etc/tor/torchk.sh ] && [ ! -f /etc/crontabs/root ]; then
    echo "0 * * * * /etc/tor/torchk.sh" > /etc/crontabs/root
  else
    if [[ -z "$(cat /etc/crontabs/root | grep '/etc/tor/torchk.sh')" ]]; then
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
    uci set luci.@command[-1].command='cat /etc/tor/torchk.log'
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
#  uci add luci command
#  uci set luci.@command[-1].param='0'
#  uci set luci.@command[-1].public='0'
#  uci set luci.@command[-1].name='Device-banner'
#  uci set luci.@command[-1].command='cat /etc/banner'
#  uci del luci.@command[-1].param
#  uci del luci.@command[-1].public
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

# P2812 Only:
# =start==========
  if [ "$DEVICE" = "zyxel,p-2812hnu-f1" ]; then

    # Adjust /etc/sysupgrade.conf if not done already. Old one gets name sysupgrade.old.conf
    if [ -f /etc/sysupgrade.conf ] && [ -z $(cat /etc/sysupgrade.conf | grep "/lib/firmware/RT3062.eeprom") ]; then
      echo " - Adjusting '/etc/sysupgrade.conf'." | tee -a "$OUTPUT"
      cp /etc/sysupgrade.conf /etc/sysupgrade.old.conf
      rm -rf /etc/sysupgrade.conf
      cat /etc/sysupgrade.old.conf | grep -v "# /etc/example.conf" | grep -v "# /etc/openvpn/" > /etc/sysupgrade.conf
      cat << EOF >> /etc/sysupgrade.conf
# OpenWrt P-2812HNU-F1
# https://openwrt.org/toh/zyxel/p-2812hnu-f1#wifi_on_openwrt
/lib/firmware/RT3062.eeprom

# /etc/example.conf
# /etc/openvpn/
EOF
    fi

    # Adjust /etc/rc.local if not already. Old one gets name rc.old.local
    if [ -f /etc/rc.local ] && [ -z $(cat /etc/rc.local | grep "echo 1 > /sys/bus/pci/rescan") ]; then
      echo " - Adjusting '/etc/rc.local'." | tee -a "$OUTPUT"
      cp /etc/rc.local /etc/rc.old.local
      rm -rf /etc/rc.local
      cat /etc/rc.old.local | grep -v "exit 0" > /etc/rc.local
      cat << EOF >> /etc/rc.local
# OpenWrt P-2812HNU-F1
# https://openwrt.org/toh/zyxel/p-2812hnu-f1#wifi_on_openwrt
echo 1 > /sys/bus/pci/rescan

# Wifi off / on for activation (rt2860.bin)
wifi down
sleep 1
wifi up

exit 0
EOF
    fi
  fi
  # P2812 Only:
  # =end============
fi

# Adjust uHTTPd https setting:
if [ ! -z "$(opkg list-installed | grep 'luci-ssl-')" ]; then
  uci set uhttpd.main.redirect_https='on'
  uci commit uhttpd
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
echo "================================================================" | tee -a "$OUTPUT"
echo "Program will reboot '"$DEVICE"' in 5 seconds ... CTRL-C will break."
echo "Stopped services will NOT be started! A reboot is required!"
echo "And the REBOOT will be performed."
echo ""

# Copy logfile to /etc/tor/
# After a reboot the /tmp version is removed ($OUTPUT).
cp $OUTPUT $OUTPUT2

sleep 5
reboot
