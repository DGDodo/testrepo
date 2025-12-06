# Program to setup Clean OpenWrt on P2812 F1
# Copied parts of torset_v1.5 regarding P2812 F1

# INIT

# Set static Parameters
# ---------------------
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
OUTPUT=/tmp/TMP001.log
OUTPUT2=/etc/tor/TMP001.log
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
if [ -f /etc/tor/torchk.sh ] && [ ! -z $vCurl ]; then vTorchk="('torchk.sh' will be activated)"; fi


# PROGRAM



# END
