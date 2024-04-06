#!/bin/bash

#
# Hysteria one-click installation script
# https://github.com/LunaticBackend/hysteria
#

export LANG=en_US.UTF-8

DEFAULT_SNI="www.bing.com"
MASQUERADE_URL="speedtest.net" # without https://

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}


REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "apk del -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Note: Please run the script under the root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Does not support the current VPS system, please use the mainstream operating system" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

APP_IMPORT_GUIDE="Open 'HTTP Injector' app -> Tunnel Type set 'Hysteria' -> Settings -> Hysteria -> Paste Hysteria2 config URI to import"

realip(){
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

inst_cert(){
    green "Methods of applying certificate ："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Self-signed certificate ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} ACME script auto-apply"
    echo -e " ${GREEN}3.${PLAIN} Custom Certificate Path"
    echo ""
    read -rp "Please enter options [1-3]: " certInput
    if [[ $certInput == 2 ]]; then
        cert_path="/root/cert.crt"
        key_path="/root/private.key"

        chmod -R 777 /root # Let the Hysteria main program access the /root directory

        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            sni_host=$(cat /root/ca.log)
            green "Legacy domain name detected: certificate for $sni_host, applying"
            hy_host=$sni_host
        else
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                realip
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                realip
            fi
            
            read -p "Please enter the domain name to apply for a certificate：" sni_host
            [[ -z $sni_host ]] && red "No domain name entered, unable to perform operation！" && exit 1
            green "Domain name entered：$sni_host" && sleep 1
            domainIP=$(curl -sm8 ipget.net/?ip="${sni_host}")
            if [[ $sni_hostIP == $ip ]]; then
                ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
                if [[ $SYSTEM == "CentOS" ]]; then
                    ${PACKAGE_INSTALL[int]} cronie
                    systemctl start crond
                    systemctl enable crond
                else
                    ${PACKAGE_INSTALL[int]} cron
                    systemctl start cron
                    systemctl enable cron
                fi
                curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
                source ~/.bashrc
                bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ -n $(echo $ip | grep ":") ]]; then
                    bash ~/.acme.sh/acme.sh --issue -d ${sni_host} --standalone -k ec-256 --listen-v6 --insecure
                else
                    bash ~/.acme.sh/acme.sh --issue -d ${sni_host} --standalone -k ec-256 --insecure
                fi
                bash ~/.acme.sh/acme.sh --install-cert -d ${sni_host} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
                if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]]; then
                    echo $sni_host > /root/ca.log
                    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                    green "Successful! The certificate (cer.crt) and private key (private.key) files applied by the script have been saved to the /root folder"
                    yellow "The certificate crt file path is as follows: /root/cert.crt"
                    yellow "The private key file path is as follows: /root/private.key"
                    hy_host=$sni_host
                fi
            else
                red "The IP resolved by the current domain name does not match the real IP used by the current VPS"
                green "suggestions below:"
                yellow "1. Please make sure CloudFlare is turned off (DNS only), other domain name resolution or CDN website settings are the same"
                yellow "2. Please check whether the IP set by the DNS resolution is the real IP of the VPS"
                yellow "3. The script may not keep up with the times, it is recommended to post screenshots to GitHub Issues, or TG groups for inquiries"
                exit 1
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "Please enter the path of the public key file crt: " cert_path
        yellow "The path of the public key file crt: $cert_path"
        read -p "Please enter the path of the key file key: " key_path
        yellow "The path of the key file key: $key_path"
        read -p "Please enter the domain name of the certificate: " sni_host
        yellow "Certificate domain name: $sni_host"
        hy_host=$sni_host
    else
        inst_sni
        green "will use $sni_host self-signed certificates for Hysteria 2"

        cert_path="/etc/hysteria/cert.crt"
        key_path="/etc/hysteria/private.key"
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
        openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=$sni_host"
        chmod 777 /etc/hysteria/cert.crt
        chmod 777 /etc/hysteria/private.key
        hy_host=$sni_host
    fi
}

inst_port(){
    read -p "Set the Hysteria2 port [1-65535] (Enter will randomly assign the port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by another program, please change the port and try again!  "
            read -p "Set the Hysteria2 port [1-65535] (Enter will randomly assign the port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    delPortHoppingNat

    yellow "The port that will be used on the Hysteria2 server is: $port"
    inst_jump
}

delPortHoppingNat(){
    iptables -t nat -F PREROUTING  2>/dev/null
    ip6tables -t nat -F PREROUTING  2>/dev/null
    if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        netfilter-persistent save 2> /dev/null
    fi
}

inst_jump(){
    green "The Hysteria 2 port usage mode is as follows:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} single port ${YELLOW}(default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} port hopping"
    echo ""
    read -rp "Please enter options [1-2]: " jumpInput
    if [[ $jumpInput == 2 ]]; then
        read -p "Set the starting port of the range port (recommended between 10000-65535)：" firstport
        read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above)：" endport
        
        firstport="${firstport:=10000}"
        endport="${endport:=65535}"

        if [[ $firstport -ge $endport ]]; then
            until [[ $firstport -le $endport ]]; do
                if [[ $firstport -ge $endport ]]; then
                    red "The start port you set is less than the end port, please re-enter the start and end port"
                    read -p "Set the starting port of the range port (recommended between 10000-65535): " firstport
                    read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above):" endport
                fi
            done
        fi
        delPortHoppingNat
        iptables -t nat -A PREROUTING -p udp --dport $firstport:$endport -m comment --comment "NAT $firstport:$endport to $port (PortHopping-hysteria)" -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $firstport:$endport -m comment --comment "NAT $firstport:$endport to $port (PortHopping-hysteria)" -j DNAT --to-destination :$port
        if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
            netfilter-persistent save >/dev/null 2>&1
        else 
            red "netfilter-persistent not enabled, PortHopping forwarding rules cannot be persisted and will fail after restarting the system. Please manually execute netfilter-persistent save. Continuing to execute the script will not affect subsequent configurations..."
        fi
    else
        red "will continue to use single port mode"
    fi
}

inst_verification(){
    input_verification

    if [[ $encryptionType == 2 ]]; then
        inst_pwd
    else
        inst_obfs
    fi
}

input_verification(){
    green "Select Hysteria verification method:"
    yellow "Tips: If you use obfuscation encryption, the anti-blocking ability is better and can be identified as unknown UDP traffic, but it will increase the CPU load and cause the peak speed to decrease. If you are pursuing performance and are not blocked, it is not recommended to use Obfs."
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Obfuscation (obfs+auth) ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Authentication Password (auth)"
    echo ""
    read -rp "Please enter options [1-2]: " encryptionType
}

inst_obfs(){
    read -p "Set Hysteria2 obfuscation password (Enter for random password) :  " auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-16)
    yellow "The obfs password used on the Hysteria server is: $auth_pwd"
    obfs_server_config_key="obfs"
}

inst_pwd(){
    read -p "Set Hysteria2 password (Enter for random password) :  " auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-16)
    yellow "The password used on the Hysteria2 server is: $auth_pwd"
    obfs_server_config_key="obfs_disabled"
}

inst_sni(){
    read -p "Enter your SNI (Default: $DEFAULT_SNI) : " sni_host
    sni_host="${sni_host:=$DEFAULT_SNI}"
}

inst_site(){
    read -rp "Please enter the fake website address of Hysteria 2 (remove https://) [Default : $MASQUERADE_URL]: " proxysite
    [[ -z $proxysite ]] && proxysite=$MASQUERADE_URL
    yellow "The masquerading site used on the Hysteria 2 server is: $proxysite"
}

installHysteria(){
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        realip
    fi

    if [[ ! ${SYSTEM} == "CentOS" ]]; then
        ${PACKAGE_UPDATE}
    fi
    ${PACKAGE_INSTALL} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/LunaticBackend/hysteria/main/hy2/install_server.sh
    bash install_server.sh

    rm -f install_server.sh

    if [[ -f "/usr/local/bin/hysteria" ]]; then
        green "Hysteria 2 installed successfully!  "
    else
        red "Hysteria 2 installation failed!  "
        exit 1
    fi

    # Ask user for Hysteria configuration
    inst_cert
    inst_port
    inst_verification
    inst_site

    # Set up the Hysteria configuration file
    cat << EOF > /etc/hysteria/config.yaml
listen: :$port

tls:
  cert: $cert_path
  key: $key_path

${obfs_server_config_key}:
  type: salamander
  salamander:
    password: $auth_pwd

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$proxysite
    rewriteHost: true
EOF

    # Determine the final inbound port range
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    # Add brackets to the IPv6 address
    if [[ -n $(echo $ip | grep ":") ]]; then
        last_ip="[$ip]"
    else
        last_ip=$ip
    fi

    mkdir /root/hy >/dev/null 2>&1
    cat << EOF > /root/hy/hy-client.yaml
server: $ip:$last_port

auth: $auth_pwd

tls:
  sni: $hy_host
  insecure: true

${obfs_server_config_key}: $auth_pwd

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

socks5:
  listen: 127.0.0.1:5080

transport:
  udp:
    hopInterval: 30s
EOF
    cat << EOF > /root/hy/hy-client.json
{
  "server": "$ip:$last_port",
  "auth": "$auth_pwd",
  "tls": {
    "sni": "$hy_host",
    "insecure": true
  },
  "${obfs_server_config_key}": "$auth_pwd",
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "fastOpen": true,
  "socks5": {
    "listen": "127.0.0.1:5080"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF

    if [[ $obfs_server_config_key == "obfs" ]]; then
        obfs_uri="obfs=salamander&obfs-password=$auth_pwd"
    else
        obfs_uri="obfs=&obfs-password="
    fi

    url="hy2://$auth_pwd@$ip:$last_port/?insecure=1&sni=$hy_host&$obfs_uri#HttpInjector-hysteria2"
    echo $url > /root/hy/url.txt
    nohopurl="hy2://$auth_pwd@$ip:$port/?insecure=1&sni=$hy_host&$obfs_uri#HttpInjector-hysteria2"
    echo $nohopurl > /root/hy/url-nohop.txt

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.yaml' ]]; then
        green "Hysteria 2 service started successfully"
    else
        red "The Hysteria 2 service failed to start, please run systemctl status hysteria-server to view the service status and give feedback, the script exits " && exit 1
    fi
    red "======================================================================================"
    green "Hysteria 2 proxy service installation complete"
    #yellow "Hysteria 2 client YML configuration file hy-client.yaml is as follows and saved to /root/hy/hy-client.yaml"
    #red "$(cat /root/hy/hy-client.yaml)"
    #yellow "Hysteria 2 client JSON configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    #red "$(cat /root/hy/hy-client.json)"
    green "$APP_IMPORT_GUIDE"
    yellow "Hysteria 2 config URI (with port hop) is as follows and saved to /root/hy/url.txt"
    red "$(cat /root/hy/url.txt)"
    yellow "Hysteria 2 config URI (without port hop) is as follows and saved to /root/hy/url-nohop.txt"
    red "$(cat /root/hy/url-nohop.txt)"
}

uninstallHysteria(){
    systemctl stop hysteria-server.service >/dev/null 2>&1
    systemctl disable hysteria-server.service >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy /root/hysteria2.sh
    delPortHoppingNat

    green "Hysteria 2 has been completely uninstalled!  "
}

startHysteria(){
    systemctl start hysteria-server
    systemctl enable hysteria-server >/dev/null 2>&1
}

stopHysteria(){
    systemctl stop hysteria-server
    systemctl disable hysteria-server >/dev/null 2>&1
}

switchHysteria(){
    yellow "Please select the operation you need:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Start Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} Stop Hysteria 2"
    echo -e " ${GREEN}3.${PLAIN} Restart Hysteria 2"
    echo ""
    read -rp "Please enter options [0-3]: " switchInput
    case $switchInput in
        1 ) startHysteria ;;
        2 ) stopHysteria ;;
        3 ) stopHysteria && startHysteria ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    oldport=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 1p | awk '{print $2}' | awk -F ":" '{print $2}')
    
    read -p "Set the Hysteria 2 port [1-65535] (Enter will randomly assign the port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by other programs, please change the port and try again!  "
            read -p "Set the Hysteria 2 port [1-65535] (Enter will randomly assign the port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "1s#$oldport#$port#g" /etc/hysteria/config.yaml
    sed -i "1s#$oldport#$port#g" /root/hy/hy-client.yaml
    sed -i "2s#$oldport#$port#g" /root/hy/hy-client.json
    sed -i "s#$oldport#$port#g" /root/hy/url.txt
    sed -i "s#$oldport#$port#g" /root/hy/url-nohop.txt

    stopHysteria && startHysteria

    green "Hysteria 2 port successfully modified to: $port"
    yellow "Please manually update the client configuration"
    cat /root/hy/url.txt
}

change_verification(){
    input_verification

    if [[ $encryptionType == 2 ]]; then
        change_pwd
    else
        change_obfs
    fi
}

change_obfs(){
    oldpasswd=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 20p | awk '{print $2}')
    oldobfs=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 10p | awk '{print $2}')

    inst_obfs

    sed -i "s/obfs_disabled:/obfs:/" /etc/hysteria/config.yaml
    sed -i "s/obfs_disabled:/obfs:/" /root/hy/hy-client.yaml
    sed -i "s/\"obfs_disabled\":/\"obfs\":/" /root/hy/hy-client.json
    
    sed -i "s/\&obfs=\&/\&obfs=salamander\&/" /root/hy/url.txt
    sed -i "s/obfs-password=\#/obfs-password=$auth_pwd\#/" /root/hy/url.txt
    sed -i "s/obfs-password=$oldobfs/obfs-password=$auth_pwd/" /root/hy/url.txt

    sed -i "s/obfs=/obfs=salamander/" /root/hy/url-nohop.txt
    sed -i "s/obfs-password=\#/obfs-password=$auth_pwd\#/" /root/hy/url-nohop.txt
    sed -i "s/obfs-password=$oldobfs/obfs-password=$auth_pwd/" /root/hy/url-nohop.txt

    sed -i "20s#$oldpasswd#$auth_pwd#g" /etc/hysteria/config.yaml
    sed -i "10s#$oldobfs#$auth_pwd#g" /etc/hysteria/config.yaml
    sed -i "3s#$oldpasswd#$auth_pwd#g" /root/hy/hy-client.yaml
    sed -i "9s#$oldobfs#$auth_pwd#g" /root/hy/hy-client.yaml
    sed -i "3s#$oldpasswd#$auth_pwd#g" /root/hy/hy-client.json
    sed -i "8s#$oldobfs#$auth_pwd#g" /root/hy/hy-client.json
    sed -i "s#$oldpasswd#$auth_pwd#g" /root/hy/url.txt
    sed -i "s#$oldobfs#$auth_pwd#g" /root/hy/url.txt
    sed -i "s#$oldpasswd#$auth_pwd#g" /root/hy/url-nohop.txt
    sed -i "s#$oldobfs#$auth_pwd#g" /root/hy/url-nohop.txt

    stopHysteria && startHysteria

    green "Hysteria 2 server password successfully changed to: $auth_pwd"
    yellow "Please manually update the client configuration"
    cat /root/hy/url.txt
}

change_pwd(){
    oldpasswd=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 20p | awk '{print $2}')
    oldobfs=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 10p | awk '{print $2}')

    inst_pwd

    sed -i "s/obfs:/obfs_disabled:/" /etc/hysteria/config.yaml
    sed -i "s/obfs:/obfs_disabled:/" /root/hy/hy-client.yaml
    sed -i "s/\"obfs\":/\"obfs_disabled\":/" /root/hy/hy-client.json

    sed -i "s/obfs=salamander/obfs=/" /root/hy/url.txt
    sed -i "s/obfs-password=$oldobfs/obfs-password=/" /root/hy/url.txt

    sed -i "s/obfs=salamander/obfs=/" /root/hy/url-nohop.txt
    sed -i "s/obfs-password=$oldobfs/obfs-password=/" /root/hy/url-nohop.txt

    sed -i "20s#$oldpasswd#$auth_pwd#g" /etc/hysteria/config.yaml
    sed -i "10s#$oldobfs#$auth_pwd#g" /etc/hysteria/config.yaml
    sed -i "3s#$oldpasswd#$auth_pwd#g" /root/hy/hy-client.yaml
    sed -i "9s#$oldobfs#$auth_pwd#g" /root/hy/hy-client.yaml
    sed -i "3s#$oldpasswd#$auth_pwd#g" /root/hy/hy-client.json
    sed -i "8s#$oldobfs#$auth_pwd#g" /root/hy/hy-client.json
    sed -i "s#$oldpasswd#$auth_pwd#g" /root/hy/url.txt
    sed -i "s#$oldobfs#$auth_pwd#g" /root/hy/url.txt
    sed -i "s#$oldpasswd#$auth_pwd#g" /root/hy/url-nohop.txt
    sed -i "s#$oldobfs#$auth_pwd#g" /root/hy/url-nohop.txt

    stopHysteria && startHysteria

    green "Hysteria 2 server password successfully changed to: $auth_pwd"
    yellow "Please manually update the client configuration"
    cat /root/hy/url.txt
}

change_cert(){
    old_cert=$(cat /etc/hysteria/config.yaml | grep cert | awk -F " " '{print $2}')
    old_key=$(cat /etc/hysteria/config.yaml | grep key | awk -F " " '{print $2}')
    old_sni_host=$(cat /root/hy/hy-client.yaml | grep sni | awk '{print $2}')

    inst_cert

    sed -i "s!$old_cert!$cert_path!g" /etc/hysteria/config.yaml
    sed -i "s!$old_key!$key_path!g" /etc/hysteria/config.yaml
    sed -i "6s/$old_sni_host/$sni_host/g" /root/hy/hy-client.yaml
    sed -i "5s/$old_sni_host/$sni_host/g" /root/hy/hy-client.json
    sed -i "s|$old_sni_host|$sni_host|" /root/hy/url.txt
    sed -i "s|$old_sni_host|$sni_host|" /root/hy/url-nohop.txt

    stopHysteria && startHysteria

    green "Hysteria 2 server certificate type successfully modified"
    yellow "Please manually update the client configuration"
}

changeproxysite(){
    oldproxysite=$(cat /etc/hysteria/config.yaml | grep url | awk -F " " '{print $2}' | awk -F "https://" '{print $2}')
    
    inst_site

    sed -i "s#$oldproxysite#$proxysite#g" /etc/hysteria/config.yaml

    stopHysteria && startHysteria

    green "Hysteria 2 server masquerading website has been successfully modified to: $proxysite"
}

changeConf(){
    green "The Hysteria 2 configuration change options are as follows:"
    echo -e " ${GREEN}1.${PLAIN} Change Port"
    echo -e " ${GREEN}2.${PLAIN} Change Verification Method (obfs password/auth password)"
    echo -e " ${GREEN}3.${PLAIN} Change Certificate Type"
    echo -e " ${GREEN}4.${PLAIN} Change Masquerade Website"
    echo ""
    read -p " Please enter options [1-4]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) change_verification ;;
        3 ) change_cert ;;
        4 ) changeproxysite ;;
        * ) exit 1 ;;
    esac
}

showConf(){
    #yellow "Hysteria 2 client YML configuration file hy-client.yaml is as follows and saved to /root/hy/hy-client.yaml"
    #red "$(cat /root/hy/hy-client.yaml)"
    #yellow "Hysteria 2 client JSON configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    #red "$(cat /root/hy/hy-client.json)"
    green "$APP_IMPORT_GUIDE"
    yellow "Hysteria 2 config URI (with port hop) is as follows and saved to /root/hy/url.txt"
    red "$(cat /root/hy/url.txt)"
    yellow "Hysteria 2 config URI (without port hop) is as follows and saved to /root/hy/url-nohop.txt"
    red "$(cat /root/hy/url-nohop.txt)"
}

updateCore(){
    wget -N https://raw.githubusercontent.com/LunaticBackend/hysteria/main/hy2/install_server.sh
    bash install_server.sh
    rm -f install_server.sh
}

showLog(){
    echo -e "${GREEN}Hysteria log, Ctrl+C to exit:${PLAIN}"
    journalctl --no-pager -e -u hysteria-server.service --output cat -f
}

menu() {
    clear
    echo "###############################################################################"
    echo -e "#             ⚡⚡ ${YELLOW}Hysteria || one-click installation script || ${PLAIN}                #"
    echo -e "# ${GREEN}Maintained By ${PLAIN}: LT                                                       #"
    echo -e "# ${GREEN}By ${PLAIN}: Author: LT project | Forked: Lunatic                             #"                                     #"
    echo -e "#                                                                             #"
    echo "###############################################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall Hysteria 2${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Start/Stop/Restart"
    echo -e " ${GREEN}4.${PLAIN} Change configuration"
    echo -e " ${GREEN}5.${PLAIN} Show configuration file"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} Update Hysteria 2 core"
    echo -e " ${GREEN}7.${PLAIN} Show Hysteria 2 log"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} Exit script"
    echo ""
    read -rp "Please enter options [0-7]: " menuInput
    case $menuInput in
        1 ) installHysteria ;;
        2 ) uninstallHysteria ;;
        3 ) switchHysteria ;;
        4 ) changeConf ;;
        5 ) showConf ;;
        6 ) updateCore ;;
        7 ) showLog ;;
        * ) exit 1 ;;
    esac
}

menu
