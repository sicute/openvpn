#!/usr/bin/env bash

name=$1

if [ "$name" = "" ]; then
  echo "Usage: make-config.sh name"
  exit;
fi

cd ~/openvpn-ca
source vars

# And error ending in "ending in error 23" is expected
./revoke-full $name

# Install the revocation files
sudo cp ~/openvpn-ca/keys/crl.pem /etc/openvpn

# Configure the server to check the client revocation list. This should only be done once
if [ $(grep -R 'crl-verify crl.pem' /etc/openvpn/server.conf | wc -l) -eq 0 ]; then
  sudo echo "crl-verify crl.pem" >> /etc/openvpn/server.conf
  sudo systemctl restart openvpn@server
fi
