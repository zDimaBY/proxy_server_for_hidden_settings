#!/bin/bash

REMOTE_ADDRESS=""
REMOTE_USER=""
REMOTE_PASSWORD=""

if [ -z "$REMOTE_ADDRESS" ] || [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_PASSWORD" ]; then
    echo "Змінні REMOTE_ADDRESS, REMOTE_USER або REMOTE_PASSWORD не можуть бути пустими."
    echo "curl -o /usr/local/bin/proxy_server_for_hidden_settings https://raw.githubusercontent.com/zDimaBY/proxy_server_for_hidden_settings/main/proxy_server_for_hidden_settings.sh"
    echo "Виконайте: vim /usr/local/bin/proxy_server_for_hidden_settings та вкажіть значення для змінних REMOTE_ADDRESS, REMOTE_USER та REMOTE_PASSWORD"
    exit 1
fi

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
        echo "$dependency_name не встановлено. Встановлюємо..."

        if ! $UPDATE_DONE; then
            case $operating_system in
            debian | ubuntu)
                apt-get update -y
                ;;
            fedora)
                dnf update -y
                ;;
            centos | oracle)
                yum update -y
                ;;
            arch)
                pacman -Sy --noconfirm
                ;;
            esac
            UPDATE_DONE=true
        fi

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
            echo "Не вдалося встановити $dependency_name. Встановіть його вручну."
            return 1
            ;;
        esac

        echo "$dependency_name успішно встановлено."
    else
        echo "$dependency_name вже встановлено."
    fi
}

function check_ssh_keys() {
    REMOTE_ADDRESS_CHECK="$1"
    # Генерація rsa SSH ключа
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa >/dev/null 2>&1
    fi
    if ssh-keygen -F "$REMOTE_ADDRESS_CHECK" -l &>/dev/null; then
        echo "Ключі для сервера $REMOTE_ADDRESS_CHECK вже існують. Видаляємо їх..."
        ssh-keygen -R "$REMOTE_ADDRESS_CHECK" -f ~/.ssh/known_hosts >/dev/null 2>&1 # Видалення старих ключів
        ssh-keyscan -H "$REMOTE_ADDRESS_CHECK" >>~/.ssh/known_hosts >/dev/null 2>&1
    else
        echo "Додаємо ключі для сервера $REMOTE_ADDRESS_CHECK..."
        ssh-keyscan -H "$REMOTE_ADDRESS_CHECK" >>~/.ssh/known_hosts >/dev/null 2>&1 # Додавання нових ключів
    fi
    if sshpass -p "$REMOTE_PASSWORD" ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_ADDRESS_CHECK" &>/dev/null; then
        echo "Ключі успішно скопійовано на віддалений сервер."
    else
        echo "Сталася помилка під час копіювання ключів на віддалений сервер. Спробуємо виправити."
        if sshpass -p "$REMOTE_PASSWORD" ssh-copy-id -f -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_ADDRESS_CHECK" &>/dev/null; then
            echo "Ключі успішно скопійовано на віддалений сервер із використанням опції -f."
        else
            echo "Сталася помилка під час копіювання ключів на віддалений сервер із використанням опції -f."
        fi
    fi
}

function vpnStartAndConect() {
    echo "Виконуємо функцію vpnStartAndConect"
    output=$(wg-quick down wg0 2>&1)
    if echo "$output" | grep -q "is not a WireGuard interface"; then
        echo "Помилка: wg0 не є інтерфейсом WireGuard."
    else
        echo "З'єднання WireGuard wg0 розірвано."
    fi
    while true; do
        ping -c 1 $REMOTE_ADDRESS >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            break # Вихід з цикла.
        else
            echo "Сервер $REMOTE_ADDRESS не пінгується, очікуємо 1хв"
            sleep 60
        fi
    done
    check_ssh_keys $REMOTE_ADDRESS

    REMOTE_COMMAND="wget -O 4_VPN.sh https://raw.githubusercontent.com/zDimaBY/open_auto_install_scripts/refs/heads/main/scripts/4_VPN.sh && \
        source /etc/os-release && \
        operating_system=\"\$ID\" && \
        if [[ -e /etc/wireguard/params ]]; then echo -e \"5\\ny\" | /root/VPN/wireguard-install.sh; fi && \
        source /root/4_VPN.sh && \
        mkdir -p /root/VPN/wireguard && \
        install_wireguard_scriptLocal"

    sshpass -p "$REMOTE_PASSWORD" ssh -o PasswordAuthentication=no -x "$REMOTE_USER"@"$REMOTE_ADDRESS" "$REMOTE_COMMAND" >/dev/null 2>&1

    sshpass -p "$REMOTE_PASSWORD" rsync -e "ssh -o StrictHostKeyChecking=no" -avz "$REMOTE_USER"@"$REMOTE_ADDRESS":/root/VPN/wireguard/* /root >/dev/null 2>&1

    cp /root/wg0-client-proxy.conf /etc/wireguard/wg0.conf && wg-quick up wg0 >/dev/null 2>&1

    check_ssh_keys "10.0.0.1"

    #REMOTE_COMMAND_IPTABLES="iptables -t nat -A PREROUTING -p tcp ! --dport 22 -m multiport ! --dports 51820 -j DNAT --to-destination 10.0.0.2 && \
    #iptables -t nat -A POSTROUTING -d 10.0.0.2 -j SNAT --to-source $REMOTE_ADDRESS"
    #sshpass -p "$REMOTE_PASSWORD" ssh -o PasswordAuthentication=no -x "$REMOTE_USER"@10.0.0.1 "$REMOTE_COMMAND_IPTABLES"
    
    
}

UPDATE_DONE=false
dependencies=(
    "sshpass sshpass"
    "wg wireguard"
    "resolvconf resolvconf"
    "curl curl"
)
for dependency in "${dependencies[@]}"; do
    check_dependency $dependency
done

while true; do # Авто відновлення тунеля.
    ping -c 1 10.0.0.1 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 10
    else
        echo "Сервер 10.0.0.1 не пінгується"
        vpnStartAndConect # Виконуємо налаштуваня на відаленому сервері
        echo "Функція vpnStartAndConect виконата. Запуск цикла"
    fi
done