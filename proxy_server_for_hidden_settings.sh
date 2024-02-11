#!/bin/bash

REMOTE_ADDRESS=""
REMOTE_USER=""
REMOTE_PASSWORD=""

function check_dependency() {
    local dependency_name=$1
    local package_name=$2

    if [[ -e /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
        debian | ubuntu | fedora | centos | oracle | arch)
            operating_system="$ID"
            ;;
        *)
            echo "Схоже, ви не використовуєте цей інсталятор у системах Debian, Ubuntu, Fedora, CentOS, Oracle або Arch Linux. Ваша система: $ID"
            exit 1
            ;;
        esac
    else
        echo "Не вдалося визначити операційну систему."
    fi
    
    if ! command -v $dependency_name &>/dev/null; then
        echo -e "${RED}$dependency_name не встановлено. Встановлюємо...${RESET}"
        if ! "$UPDATE_DONE"; then
            case $operating_system in
            debian | ubuntu)
                apt-get update
                apt-get install -y "$package_name"
                ;;
            fedora)
                dnf update
                dnf install -y "$package_name"
                ;;
            centos | oracle)
                yum update
                yum install -y "$package_name"
                ;;
            arch)
                pacman -Sy
                pacman -S --noconfirm "$package_name"
                ;;
            *)
                echo -e "${RED}Не вдалося встановити $dependency_name. Будь ласка, встановіть його вручну.${RESET}"
                return 1
                ;;
            esac
            
            UPDATE_DONE=true
        else
            case $operating_system in
            debian | ubuntu)
                apt-get install -y "$package_name"
                ;;
            fedora)
                dnf install -y "$package_name"
                ;;
            centos | oracle)
                yum install -y "$package_name"
                ;;
            arch)
                pacman -S --noconfirm "$package_name"
                ;;
            *)
                echo -e "${RED}Не вдалося встановити $dependency_name. Будь ласка, встановіть його вручну.${RESET}"
                return 1
                ;;
            esac
        fi

        echo -e "${GREEN}$dependency_name успішно встановлено.${RESET}"
    else
        echo -e "${GREEN}$dependency_name вже встановлено.${RESET}"
    fi
}

UPDATE_DONE=false

dependencies=(
    "sshpass sshpass"
    "wireguard wireguard"
    "resolvconf resolvconf"
)

for dependency in "${dependencies[@]}"; do
    check_dependency $dependency
done

# Генерація rsa SSH ключа
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

if ssh-keygen -F "$REMOTE_ADDRESS" -l &> /dev/null; then
    echo "Ключі для сервера $REMOTE_ADDRESS вже існують. Видаляємо їх..."
    ssh-keygen -R "$REMOTE_ADDRESS" -f ~/.ssh/known_hosts
else
    echo "Додаємо ключі для сервера $REMOTE_ADDRESS..."
    ssh-keyscan -H "$REMOTE_ADDRESS" >> ~/.ssh/known_hosts
fi

sshpass -p $REMOTE_PASSWORD ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_ADDRESS

REMOTE_COMMAND="wget https://raw.githubusercontent.com/zDimaBY/setting_up_control_panels/main/scripts/5_VPN.sh && source /etc/os-release && operating_system="\$ID" && source /root/5_VPN.sh && mkdir -p /root/VPN/wireguard && install_wireguard_scriptLocal"
sshpass -p "$REMOTE_PASSWORD" ssh -o PasswordAuthentication=no -x "$REMOTE_USER"@"$REMOTE_ADDRESS" "$REMOTE_COMMAND"

sshpass -p "$REMOTE_PASSWORD" rsync -e "ssh -o StrictHostKeyChecking=no" -avz "$REMOTE_USER"@"$REMOTE_ADDRESS":/root/VPN/wireguard/* /root

cp wg0-client-proxy.conf /etc/wireguard/wg0.conf
wg-quick up wg0