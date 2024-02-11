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

check_ssh_keys() {
    REMOTE_ADDRESS_CHECK="$1"
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    fi
    if ssh-keygen -F "$REMOTE_ADDRESS_CHECK" -l &>/dev/null; then
        echo "Ключі для сервера $REMOTE_ADDRESS_CHECK вже існують. Видаляємо їх..."
        ssh-keygen -R "$REMOTE_ADDRESS_CHECK" -f ~/.ssh/known_hosts
        ssh-keyscan -H "$REMOTE_ADDRESS_CHECK" >>~/.ssh/known_hosts
    else
        echo "Додаємо ключі для сервера $REMOTE_ADDRESS_CHECK..."
        ssh-keyscan -H "$REMOTE_ADDRESS_CHECK" >>~/.ssh/known_hosts
    fi
    sshpass -p "$REMOTE_PASSWORD" ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_ADDRESS_CHECK"
}

UPDATE_DONE=false
# Перевірка залежностей
dependencies=(
    "sshpass sshpass"
    "wg wireguard"
    "resolvconf resolvconf"
    "curl curl"
)

for dependency in "${dependencies[@]}"; do
    check_dependency $dependency
done

# Перевірка наявності ключів SSH для віддаленого сервера
check_ssh_keys $REMOTE_ADDRESS

REMOTE_COMMAND="wget https://raw.githubusercontent.com/zDimaBY/setting_up_control_panels/main/scripts/5_VPN.sh && source /etc/os-release && operating_system="\$ID" && source /root/5_VPN.sh && mkdir -p /root/VPN/wireguard && install_wireguard_scriptLocal"
sshpass -p "$REMOTE_PASSWORD" ssh -o PasswordAuthentication=no -x "$REMOTE_USER"@"$REMOTE_ADDRESS" "$REMOTE_COMMAND"

sshpass -p "$REMOTE_PASSWORD" rsync -e "ssh -o StrictHostKeyChecking=no" -avz "$REMOTE_USER"@"$REMOTE_ADDRESS":/root/VPN/wireguard/* /root

cp wg0-client-proxy.conf /etc/wireguard/wg0.conf
wg-quick up wg0

check_ssh_keys "10.0.0.1"

REMOTE_COMMAND_IPTABLES="iptables -t nat -A PREROUTING -p tcp ! --dport 51820 -j DNAT --to-destination 10.0.0.2 && iptables -t nat -A POSTROUTING -d 10.0.0.2 -j SNAT --to-source $REMOTE_ADDRESS"
sshpass -p "$REMOTE_PASSWORD" ssh -o PasswordAuthentication=no -x "$REMOTE_USER"@10.0.0.1 "$REMOTE_COMMAND_IPTABLES"

echo -e "\e[32m$(curl ifconfig.me)\e[0m"
