#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Будь ласка, запустіть скрипт з привілеями root"
  exit
fi

# Завантаження скрипту для служби з GitHub
wget -O /usr/local/bin/proxy_server_for_hidden_settings.sh https://raw.githubusercontent.com/zDimaBY/proxy_server_for_hidden_settings/main/proxy_server_for_hidden_settings.sh
chmod +x /usr/local/bin/proxy_server_for_hidden_settings.sh

# Створення конфігураційного файлу для служби
cat <<EOF > /etc/systemd/system/proxy_server_for_hidden_settings.service
[Unit]
Description=sever-vpn_wireguard-proxyserver
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/proxy_server_for_hidden_settings.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable proxy_server_for_hidden_settings
echo -e "\n\nВиконайте: vim /usr/local/bin/proxy_server_for_hidden_settings.sh"
echo -e "systemctl restart proxy_server_for_hidden_settings\n\n"
systemctl status proxy_server_for_hidden_settings