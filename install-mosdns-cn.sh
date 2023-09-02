#!/bin/bash

# This script is used to install mosdns-cn.

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check if port 53 is occupied.
if [ -n "$(lsof -i:53)" ]; then
    echo "Port 53 is occupied, please check and try again."
    exit 1
fi

DOWNLOAD_PATH="https://github.com/IrineSistiana/mosdns-cn/releases/latest/download"


# Download mosdns-cn
if [ $(uname -m) = "x86_64" ]; then
    wget "$DOWNLOAD_PATH/mosdns-cn-linux-amd64.zip" -O "/tmp/mosdns-cn.zip" || { echo "Failed to download mosdns-cn-linux-amd64"; exit 1; }
elif [ $(uname -m) = "aarch64" ]; then
    wget "$DOWNLOAD_PATH/mosdns-cn-linux-arm64.zip" -O "/tmp/mosdns-cn.zip" || { echo "Failed to download mosdns-cn-linux-arm64"; exit 1; }
else
    echo "Unsupported architecture: $(uname -m)"
    exit 1
fi

# Install mosdns-cn
mkdir -p /opt/mosdns-cn
if ! command -v unzip &> /dev/null; then
    if [ -f /etc/redhat-release ]; then
        yum install -y unzip
    elif [ -f /etc/debian_version ]; then
        apt install -y unzip
    else
        echo "Unsupported operating system"
        exit 1
    fi
fi
unzip /tmp/mosdns-cn.zip -d /opt/mosdns-cn || { echo "Failed to unzip mosdns-cn"; exit 1; }


if [ -f /etc/redhat-release ]; then
    yum install -y redis
elif [ -f /etc/debian_version ]; then
    apt install -y redis-server
else
    echo "Unsupported operating system"
    exit 1
fi

systemctl start redis-server

# Download geoip and geosite files from github and update them every day.
cat <<EOL > /opt/mosdns-cn/update.sh
#!/bin/bash

DOWNLOAD_PATH="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

wget "\$DOWNLOAD_PATH/geosite.dat" -O "/tmp/geosite.dat" || { echo "Failed to download geosite.dat"; exit 1; }
wget "\$DOWNLOAD_PATH/geoip.dat" -O "/tmp/geoip.dat" || { echo "Failed to download geoip.dat"; exit 1; }

wget "\$DOWNLOAD_PATH/geosite.dat.sha256sum" -O "/tmp/geosite.dat.sha256sum" || { echo "Failed to download geosite.dat.sha256sum"; exit 1; }
wget "\$DOWNLOAD_PATH/geoip.dat.sha256sum" -O "/tmp/geoip.dat.sha256sum" || { echo "Failed to download geoip.dat.sha256sum"; exit 1; }

cd /tmp

sha256sum -c geosite.dat.sha256sum || { echo "Failed to check geosite.dat"; exit 1; }
sha256sum -c geoip.dat.sha256sum || { echo "Failed to check geoip.dat"; exit 1; }

cp /tmp/geosite.dat /opt/mosdns-cn || { echo "Failed to copy geosite.dat"; exit 1; }
cp /tmp/geoip.dat /opt/mosdns-cn || { echo "Failed to copy geoip.dat"; exit 1; }

EOL


chmod +x /opt/mosdns-cn/update.sh

echo "0 4 * * * /opt/mosdns-cn/update.sh" | crontab -

/opt/mosdns-cn/update.sh

# Install mosdns-cn service
/opt/mosdns-cn/mosdns-cn "-s" ":53" "--local-upstream" "https://1.12.12.12/dns-query" "--local-domain" "geosite.dat:cn" "--local-ip" "geoip.dat:cn" "--remote-upstream" "https://1.1.1.1/dns-query" "--remote-domain" "geosite.dat:geolocation-!cn" "-c" "10000" "--redis-cache" "redis://:@127.0.0.1:6379/0" "--lazy-cache-ttl" "86400" "--dir" "/opt/mosdns-cn" "--service" "install"
systemctl enable mosdns-cn
systemctl start mosdns-cn

echo "systemctl restart mosdns-cn" | tee -a /opt/mosdns-cn/update.sh