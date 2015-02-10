#!/bin/sh
#
# Amazon EC2 user-data file for automatic configuration of IPsec/L2TP VPN
# on a Ubuntu server instance. Tested with 14.04 (Trusty) 
# With minor modifications, this script *can also be used* on dedicated servers
# or any KVM- or XEN-based Virtual Private Server (VPS) from other providers.
#
# DO NOT RUN THIS SCRIPT ON YOUR PC OR MAC! THIS IS MEANT TO BE RUN WHEN 
# YOUR AMAZON EC2 INSTANCE STARTS!
#


# Checking if this is a Mac or AWS Ubuntu Server 
if [ "$(uname)" = "Darwin" ]; then
  echo "DO NOT run this script on your Mac! It should only be run on a newly-created EC2 instance"
  echo "or other Dedicated Server / VPS, after you have modified it to set the variables below."
  echo "Please see detailed instructions at the URLs in the comments."
  exit 1
fi
 
# Please define your own values for those variables
IPSEC_PSK=your_very_secure_key
VPN_USER=your_username
VPN_PASSWORD=your_very_secure_password
 
# If you need multiple VPN users with different credentials,
#There are several methods to enable multiple VPN users with different credentials.
#Both methods shown below will produce the same contents of "/etc/ppp/chap-secrets":
 
#user1 l2tpd password1 *
#user2 l2tpd password2 *
 
# Important Notes:
# For Windows users, a registry change is required to allow connections
# to a VPN server behind NAT. Refer to section "Error 809" on this page:
# https://kb.meraki.com/knowledge_base/troubleshooting-client-vpn
 
# iPhone/iOS users may need to replace this line in ipsec.conf:
# "rightprotoport=17/%any" with "rightprotoport=17/0".
 
# If using Amazon EC2, these ports must be open in the security group of
# your VPN server: UDP ports 500 & 4500, and TCP port 22 (optional, for SSH).
 
# In Amazon EC2, these two variables will be found automatically
# For all other servers, you MUST replace them with the actual IPs!
# If your server only has a public IP, use that IP on both lines
# Get public IP:  dig +short myip.opendns.com @resolver1.opendns.com
# Get private IP: ifconfig eth0 | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}'
PUBLIC_IP=$(wget -q -O - 'http://169.254.169.254/latest/meta-data/public-ipv4')
PRIVATE_IP=$(wget -q -O - 'http://169.254.169.254/latest/meta-data/local-ipv4')
 
# Install necessary packages
apt-get update
apt-get install libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
        libcap-ng-dev libcap-ng-utils libselinux1-dev \
        libcurl4-nss-dev libgmp3-dev flex bison gcc make \
        libunbound-dev libnss3-tools wget -y
apt-get install xl2tpd -y
 
# Compile and install Libreswan (https://libreswan.org/)
# To upgrade Libreswan when a newer version is available, just re-run these
# six commands with the new download link, and then restart services with
# "service ipsec restart" and "service xl2tpd restart".
mkdir -p /opt/src
cd /opt/src
wget -qO- https://download.libreswan.org/libreswan-3.12.tar.gz | tar xvz
cd libreswan-3.12
make programs
make install
 
# Prepare various config files
cat > /etc/ipsec.conf <<EOF
version 2.0

config setup
  dumpdir=/var/run/pluto/
  nat_traversal=yes
  virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:!192.168.42.0/24
  oe=off
  protostack=netkey
  nhelpers=0
  interfaces=%defaultroute

conn vpnpsk
  connaddrfamily=ipv4
  auto=add
  left=$PRIVATE_IP
  leftid=$PUBLIC_IP
  leftsubnet=$PRIVATE_IP/32
  leftnexthop=%defaultroute
  leftprotoport=17/1701
  rightprotoport=17/%any
  right=%any
  rightsubnetwithin=0.0.0.0/0
  forceencaps=yes
  authby=secret
  pfs=no
  type=transport
  auth=esp
  ike=3des-sha1,aes-sha1
  phase2alg=3des-sha1,aes-sha1
  rekey=no
  keyingtries=5
  dpddelay=30
  dpdtimeout=120
  dpdaction=clear
EOF
 
cat > /etc/ipsec.secrets <<EOF
$PUBLIC_IP  %any  : PSK "$IPSEC_PSK"
EOF
 
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

;debug avp = yes
;debug network = yes
;debug state = yes
;debug tunnel = yes

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
;ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF
 
cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
lock
lcp-echo-failure 10
lcp-echo-interval 60
connect-delay 5000
EOF
 
# For extra users simply add another line
#user1 l2tpd password1 *
#user2 l2tpd password2 * 
cat > /etc/ppp/chap-secrets <<EOF
# Secrets for authentication using CHAP
# client  server  secret  IP addresses

$VPN_USER  l2tpd  $VPN_PASSWORD  *
EOF
 
/bin/cp -f /etc/sysctl.conf /etc/sysctl.conf.old-$(date +%Y-%m-%d-%H:%M:%S)
cat > /etc/sysctl.conf <<EOF
kernel.sysrq = 0
kernel.core_uses_pid = 1
net.ipv4.tcp_syncookies = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
kernel.randomize_va_space = 1
net.core.wmem_max=12582912
net.core.rmem_max=12582912
net.ipv4.tcp_rmem= 10240 87380 12582912
net.ipv4.tcp_wmem= 10240 87380 12582912
EOF
 
/bin/cp -f /etc/iptables.rules /etc/iptables.rules.old-$(date +%Y-%m-%d-%H:%M:%S)
cat > /etc/iptables.rules <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:ICMPALL - [0:0]
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p icmp --icmp-type 255 -j ICMPALL
-A INPUT -p udp --dport 67:68 --sport 67:68 -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p udp -m multiport --dports 500,4500 -j ACCEPT
-A INPUT -p udp --dport 1701 -m policy --dir in --pol ipsec -j ACCEPT
-A INPUT -p udp --dport 1701 -j DROP
-A INPUT -j DROP
-A FORWARD -m conntrack --ctstate INVALID -j DROP
-A FORWARD -i eth+ -o ppp+ -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i ppp+ -o eth+ -j ACCEPT
-A FORWARD -j DROP
-A ICMPALL -p icmp -f -j DROP        
-A ICMPALL -p icmp --icmp-type 0 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 3 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 4 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 8 -j ACCEPT
-A ICMPALL -p icmp --icmp-type 11 -j ACCEPT
-A ICMPALL -p icmp -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.42.0/24 -o eth+ -j SNAT --to-source ${PRIVATE_IP}
COMMIT
EOF
 
cat > /etc/network/if-pre-up.d/iptablesload <<EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.rules
exit 0
EOF
 
/bin/cp -f /etc/rc.local /etc/rc.local.old-$(date +%Y-%m-%d-%H:%M:%S)
cat > /etc/rc.local <<EOF
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.
/usr/sbin/service ipsec restart
/usr/sbin/service xl2tpd restart
echo 1 > /proc/sys/net/ipv4/ip_forward
exit 0
EOF
 
if [ ! -f /etc/ipsec.d/cert8.db ] ; then
   echo > /var/tmp/libreswan-nss-pwd
   /usr/bin/certutil -N -f /var/tmp/libreswan-nss-pwd -d /etc/ipsec.d
   /bin/rm -f /var/tmp/libreswan-nss-pwd
fi
 
/sbin/sysctl -p
/bin/chmod +x /etc/network/if-pre-up.d/iptablesload
/bin/chmod 600 /etc/ipsec.secrets /etc/ppp/chap-secrets
/sbin/iptables-restore < /etc/iptables.rules
 
/usr/sbin/service ipsec restart
/usr/sbin/service xl2tpd restart

#block torrent downloading
echo This is to block known signatures of BitTorrent activity.
echo Written by\: Mr\-Protocol
sudo iptables -t raw -A OUTPUT -m string --algo bm --string "GET /announce?info_hash=" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --string "GET /announce?info_hash=" -j DROP
echo Blocking\: \"GET \/announce?info_hash=\"
sleep 1
sudo iptables -t raw -A OUTPUT -m string --algo bm --string "GET /scrape?info_hash=" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --string "GET /scrape?info_hash=" -j DROP
echo Blocking\: \"GET \/scrape?info_hash=\"
sleep 1
sudo iptables -t raw -A OUTPUT -m string --algo bm --string "GET /announce.php?info_hash=" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --string "GET /announce.php?info_hash=" -j DROP
echo Blocking\: \"GET \/announce.php?info_hash=\"
sleep 1
sudo iptables -t raw -A OUTPUT -m string --algo bm --string "GET /scrape.php?info_hash=" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --string "GET /scrape.php?info_hash=" -j DROP
echo Blocking\: \"GET \/scrape.php?info_hash=\"
sleep 1
sudo iptables -t raw -A OUTPUT -m string --algo bm --string "GET /announce.php?passkey=" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --string "GET /announce.php?passkey=" -j DROP
echo Blocking\: \"GET \/announce.php?passkey=\"
sleep 1
sudo iptables -t raw -A OUTPUT -m string --algo bm --string "GET /scrape.php?passkey=" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --string "GET /scrape.php?passkey=" -j DROP
echo Blocking\: \"GET \/scrape.php?passkey=\"
sleep 1
sudo iptables -t raw -A OUTPUT -m string --algo bm --hex-string "|13426974546f7272656e742070726f746f636f6c|" -j DROP
sudo iptables -t raw -A PREROUTING -m string --algo bm --hex-string "|13426974546f7272656e742070726f746f636f6c|" -j DROP
echo Blocking\: \"\(0x13\) \+ \"BitTorrent protocol\"
sleep 1


