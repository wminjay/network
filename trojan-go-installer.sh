#!/bin/bash

#================================================================
#
# FILE: install.sh
#
# USAGE: bash install.sh
#
# DESCRIPTION: Install trojan-go on CentOS.
#
#================================================================

#color
red='\033[0;31m'
green='\033[0;32m'
reset='\033[0m'

#help
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Usage: Email=example@mail.com Domain=domain.com DP_Id=YOUR_DNSPOD_ID DP_Key=NDSPOD_KEY bash install.sh"
    echo "Test on CentOS Linux release 7.9.2009 (Core)"
    exit 0
fi

#import .env
if [ -f .env ]; then
    source .env
fi
#check root
if [ "$(id -u)" != "0" ]; then
    echo -e $red"This script must be run as root."$reset
    exit 1
fi
#check os
if [ ! -f /etc/redhat-release ]; then
    echo -e $red"This script only supports CentOS."$reset
    exit 1
fi
#check environment variable contains DP_Id and DP_Key.
if [ -z "$DP_Id" ] || [ -z "$DP_Key" ]; then
    echo -e $red"Please set DP_Id and DP_Key."$reset
    exit 1
fi
#check environment variable contains Domain.
if [ -z "$Domain" ]; then
    echo -e $red"Please set Domain."$reset
    exit 1
fi
#check environment variable contains Email.
if [ -z "$Email" ]; then
    echo -e $red"Please set Email."$reset
    exit 1
fi

#read domain from environment variable
domain=$Domain
#read email from environment variable
email=$Email

#update system
yum update -y

yum install epel-release -y
#install nginx
yum install nginx -y
#config nginx
#write config to /etc/nginx/conf/conf.d/trojan.conf
cat > /etc/nginx/conf.d/trojan.conf << EOF
    server {
        listen 80;
        listen [::]:80;
        server_name $domain;
        index index.html index.htm;
        root  /dev/null;
        error_page 400 = /400.html;
    }
EOF
#start nginx
systemctl start nginx
systemctl enable nginx


yum install curl -y
yum install wget -y
yum install unzip -y


#install acme.sh
curl https://get.acme.sh | sh
#install cert
/root/.acme.sh/acme.sh --register-account -m $Email
#need env DP_Id and DP_Key
/root/.acme.sh/acme.sh --issue -d $domain --dns dns_dp


#install trojan-go
wget https://github.com/p4gefau1t/trojan-go/releases/download/v0.10.6/trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip
mv trojan-go /usr/bin/trojan-go
chmod +x /usr/bin/trojan-go
#install trojan-go.service
cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=Trojan-Go - An unidentifiable mechanism that helps you bypass GFW
Documentation=https://p4gefau1t.github.io/trojan-go/
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
#config trojan-go
mkdir -p /etc/trojan-go
# random password
password=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
cat > /etc/trojan-go/config.json << EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "log_level": 0,
    "log_file": "/var/log/trojan-go.log",
    "password": [
        "$password"
    ],
    "ssl": {
        "cert": "/root/.acme.sh/${domain}_ecc/fullchain.cer",
        "key": "/root/.acme.sh/${domain}_ecc/$domain.key",
        "sni": "$domain"
    }
}
EOF
#start trojan-go
systemctl daemon-reload
systemctl start trojan-go
#enable trojan-go
systemctl enable trojan-go

#draw qr code
yum install qrencode -y
qrencode -t ANSIUTF8 -s 8 -l H -v 1 "trojan://$password@$domain:443?sni=$domain#trojan-go_$domain"
echo "Scan QR code to import profile to client."
echo "If you can't scan the QR code, please copy the following text to the client."
echo "trojan://$password@$domain:443?sni=$domain#trojan-go_$domain"
