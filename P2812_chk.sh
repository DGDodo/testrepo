# Program to setup Clean OpenWrt on P2812 F1
# Contains copied parts of torset_v1.x regarding P2812 F1
# Wifi functionality available RT3062.eeprom
# Privoxy available
# Removed : Tor
#

# INIT

# Set static Parameters
# ---------------------
# Program version
Pversion=1.1
# Set hostname TorRouter
HOSTNAME=OpenWrt
# Set OpenWrt default ip
IPADDR=192.168.1.1
# Set ipaddr2 as copy of ipaddr ending with 0 instead of 1
IPADDR2=$(echo "$IPADDR". | cut -d'.' -f-3).0
# Set hardcoded Lan MAC address when it is empty according program
# For P2812-F1 (and maybe some others) this must end on 0 or 8 !
# Normally the program will grab the correct mac addresses.
MACHARD=00:11:22:33:44:50
# Set default Wifi name & pass (if nothing is being filled in)
WIFINAME=OpenWrt
WIFIPASS=OpenWrt1234
# Upper parameters could be overwritten in program so we keep ...
WIFINAME2=$WIFINAME
WIFIPASS2=$WIFIPASS
# Set services to be stopped during setup process in sequence.
# Make sure 'network' is mentioned last here.
# Sequence is now "privoxy firewall dnsmasq tor network"
SERVICES="privoxy firewall dnsmasq tor network"
# Set program output parameters
OUTPUT=/tmp/OW001.log
# OUTPUT2=/etc/tor/TMP001.log
# Set minimum free memory 65MB=65000kB
# Should we ask to stop Tor if it is running before memcheck?
FREEMIN=65000

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
  echo "No OpenWrt device is found.";
  echo "";
  exit;
fi

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

# Get current OpenWrt version
# As the wlan mac location for v24.10.0 is different from older versions ?? to be tested on lower P2812 ...
# Wifi encryption is depending on OpenWrt version (wpa2 or sae).
OPENVER=$(cat /etc/openwrt_release | grep RELEASE | cut -f2 -d\')

# Get all wifi devices
#
# find /sys | grep phy | grep macaddress
# Returns all wifi devices even disabled, 1 for P2812, 2 for FB4040
# if there is no wifi nothing will be done
# To get wlan mac(s) : find /sys | grep phy | grep macaddress
#
# P2812 returns   : /sys/devices/pci0000:00/0000:00:0e.0/ieee80211/phy0/macaddress
# For the P2812 the extra command in /etc/rc.local should be run before any result!
# If not done already this script will run the extra command to activate Wifi
if [ "$DEVICE" = "zyxel,p-2812hnu-f1" ] && [ $(echo $OPENVER | cut -f1 -d.) -ge 21  ] && [ -f /etc/rc.local ] && [ -z $(cat /etc/rc.local | grep "echo 1 > /sys>
  echo "Check if P2812 see Wifi after special command... (duration over 10 seconds)"
  echo "When fully run this program, '/etc/rc.local' will be adjusted."
  echo "If still no wifi found? This P2812's wifi is most probably bricked!"
  echo ""
  sleep 1
  echo 1 > /sys/bus/pci/rescan
  sleep 10
  echo ""
fi
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
# =end========================================
# SPECIAL for P-2812HNU-F1 (MACADDR & MACWIFI)

# if OpenWrt version is lower then v19.07.0 only WPA2 (PSK2) is available for WIFICRYPT
# if password length is long enough (8) WIFICRYPT='SAE-MIXED'
WIFICRYPT='psk2'
if [ $(echo $OPENVER | cut -f1 -d.) -ge 19 ] && [ ${#WIFIPASS} -gt 7 ]; then WIFICRYPT='sae-mixed'; fi

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

# Get irqbalance version (F4040 & WHW03):
vIrqb=$(opkg list-installed | grep irqbalance | grep -v luci | cut -f3 -d' ')
if [ ${#vIrqb} -eq 0 ]; then vIrqb="not installed"; fi

# Check if /etc/tor/torchk.sh exist and add text to vCurl ?
# if [ -f /etc/tor/torchk.sh ] && [ ! -z $vCurl ]; then vTorchk="('torchk.sh' will be activated)"; fi

# Start of $OUTPUT
# Print info, all info seems to be ok to change to TorRouter.
clear
echo "" | tee -a "$OUTPUT"
echo "'"$HOSTNAME"' setup program for device : "$(cat /tmp/sysinfo/model) | tee -a "$OUTPUT"
echo "======================================================= v"$Pversion" ===" | tee -a "$OUTPUT"
echo "                                 "$(date -R) | tee -a "$OUTPUT"
echo "Parameters - Please double check these!" | tee -a "$OUTPUT"
echo "----------" | tee -a "$OUTPUT"
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
exit


# PROGRAM

# Write current UCI settings to log
echo "" | tee -a "$OUTPUT"
echo "Copy current UCI config." | tee -a "$OUTPUT"
echo "--------------------------------------------------------------------------------" >> $OUTPUT
uci show >> $OUTPUT
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

# END
