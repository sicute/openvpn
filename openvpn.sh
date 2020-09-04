#!/usr/bin/env bash

# Change to script directory
sd=`dirname $0`
cd $sd
# if you ran the script from its own directory you actually just got '.'
# so capture the abs path to wd now
sd=`pwd`

# Make sure config file exists
if [ ! -f ./config.sh ]; then
  echo "config.sh not found!"
  exit;
fi
# Load config
source ./config.sh
source ./interfaces.sh

# Install OpenVPN and expect
sudo apt-get -y install openvpn easy-rsa expect

# Set up the CA directory
/usr/bin/make-cadir ~/openvpn-ca
sudo chmod -R 776 ~/openvpn-ca/
sudo chmod -R 776 ~/openvpn-ca/vars
cd ~/openvpn-ca

# Update vars
sudo sed -i "s/export KEY_COUNTRY=\"[^\"]*\"/export KEY_COUNTRY=\"${KEY_COUNTRY}\"/" vars
sudo sed -i "s/export KEY_PROVINCE=\"[^\"]*\"/export KEY_PROVINCE=\"${KEY_PROVINCE}\"/" vars
sudo sed -i "s/export KEY_CITY=\"[^\"]*\"/export KEY_CITY=\"${KEY_CITY}\"/" vars
sudo sed -i "s/export KEY_ORG=\"[^\"]*\"/export KEY_ORG=\"${KEY_ORG}\"/" vars
sudo sed -i "s/export KEY_EMAIL=\"[^\"]*\"/export KEY_EMAIL=\"${KEY_EMAIL}\"/" vars
sudo sed -i "s/export KEY_OU=\"[^\"]*\"/export KEY_OU=\"${KEY_OU}\"/" vars
sudo sed -i "s/export KEY_NAME=\"[^\"]*\"/export KEY_NAME=\"server\"/" vars

# Build the Certificate Authority
source vars
./clean-all
yes "" | ./build-ca

# Create the server certificate, key, and encryption files
$sd/build-key-server.sh
./build-dh
sudo openvpn --genkey --secret keys/ta.key

# Copy the files to the OpenVPN directory
cd ~/openvpn-ca/keys
sudo cp ca.crt ca.key server.crt server.key ta.key dh2048.pem /etc/openvpn
gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz | sudo tee /etc/openvpn/server.conf

# Adjust the OpenVPN configuration
sudo sed -i "s/;tls-auth ta.key 0/tls-auth ta.key 0\nkey-direction 0/" /etc/openvpn/server.conf
sudo sed -i "s/;cipher AES-128-CBC/cipher AES-128-CBC\nauth SHA256/" /etc/openvpn/server.conf
sudo sed -i "s/;user nobody/user nobody/" /etc/openvpn/server.conf
sudo sed -i "s/;group nogroup/group nogroup/" /etc/openvpn/server.conf
sudo sed -i "s/push "route 10.8.0.0 255.255.0.0"" /etc/openvpn/server.conf
sudo sed -i "s/ push "dhcp-option DNS 8.8.8.8"" /etc/openvpn/server.conf
sudo sed -i "s/ push "dhcp-option DNS 208.67.220.220"" /etc/openvpn/server.conf


# Allow IP forwarding
sudo sed -i "s/#net.ipv4.ip_forward/net.ipv4.ip_forward/" /etc/sysctl.conf
sudo sysctl -p

# Install iptables-persistent so that rules can persist across reboots
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt-get install -y iptables-persistent

# Start and enable the OpenVPN service
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server

# Create the client config directory structure
mkdir -p ~/client-configs/files
# Create a base configuration
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf
sudo sed -i "s/remote my-server-1 1194/remote ${PUBLIC_IP} 1194/" ~/client-configs/base.conf
sudo sed -i "s/;user nobody/user nobody/" ~/client-configs/base.conf
sudo sed -i "s/;group nogroup/group nogroup/" ~/client-configs/base.conf
sudo sed -i "s/ca ca.crt/#ca ca.crt/" ~/client-configs/base.conf
sudo sed -i "s/cert client.crt/#cert client.crt/" ~/client-configs/base.conf
sudo sed -i "s/key client.key/#key client.key/" ~/client-configs/base.conf
sudo echo "cipher AES-128-CBC" >> ~/client-configs/base.conf
sudo echo "auth SHA256" >> ~/client-configs/base.conf
sudo echo "key-direction 1" >> ~/client-configs/base.conf
sudo echo "#script-security 2" >> ~/client-configs/base.conf
sudo echo "#up /etc/openvpn/update-resolv-conf" >> ~/client-configs/base.conf
sudo echo "#down /etc/openvpn/update-resolv-conf" >> ~/client-configs/base.conf

# Edit iptables rules to allow for forwarding
sudo iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Make iptables rules persistent across reboots
#sudo iptables-save > /etc/iptables/rules.v4
sudo bash -c "iptables-save > /etc/iptables.rules"

