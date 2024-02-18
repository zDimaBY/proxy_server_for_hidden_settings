#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Будь ласка, запустіть скрипт з привілеями root"
  exit
fi

urls=(
    "https://raw.githubusercontent.com/zDimaBY/proxy_server_for_hidden_settings/main/proxy_server_for_hidden_settings.sh"
    "https://raw.githubusercontent.com/zDimaBY/proxy_server_for_hidden_settings/main/log_with_timestamp.sh"
)
echo -e "${LIGHT_GREEN}Loading script, please wait.${RESET}"
for url in "${urls[@]}"; do
    filename=$(basename "$url")
    wget -qO- "$url" >"/usr/local/bin/$filename"
    chmod +x /usr/local/bin/$filename
done

# Створення конфігураційного файлу для служби
cat <<EOF > /etc/systemd/system/proxy_server_for_hidden_settings.service
[Unit]
Description=sever-vpn_wireguard-proxyserver
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c '/usr/local/bin/proxy_server_for_hidden_settings.sh 2>&1 | /usr/local/bin/log_with_timestamp.sh >> /var/log/proxy_server_for_hidden_settings.log'
StandardOutput=file:/var/log/proxy_server_for_hidden_settings.log
StandardError=file:/var/log/proxy_server_for_hidden_settings.log
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable proxy_server_for_hidden_settings
echo -e "\n\nВиконайте: \nvim /usr/local/bin/proxy_server_for_hidden_settings.sh"
echo -e "systemctl restart proxy_server_for_hidden_settings\n\n"
systemctl status proxy_server_for_hidden_settings