#!/bin/bash

REMOTE_IP_ADDRESS_SERVER=''
REMOTE_USER=''
REMOTE_PASSWORD_ROOT=''

if [ -z "$REMOTE_IP_ADDRESS_SERVER" ] || [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_PASSWORD_ROOT" ]; then
    echo "Змінні REMOTE_IP_ADDRESS_SERVER, REMOTE_USER або REMOTE_PASSWORD_ROOT не можуть бути пустими."
    echo "Виконайте: vim /usr/local/bin/proxy_server_for_hidden_settings та вкажіть значення для змінних REMOTE_IP_ADDRESS_SERVER, REMOTE_USER та REMOTE_PASSWORD_ROOT."
    exit 1
fi

function check_system_release() {
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
}

function remote_ssh_command() {
    # Функція для підключення до віддаленого сервера 
    # sshpass -p "$REMOTE_PASSWORD_ROOT" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10" root@$REMOTE_IP_ADDRESS_SERVER "ls"

    # Параметри:
    # $1 - команда, яку потрібно виконати на віддаленому сервері

    output=$(sshpass -p "$REMOTE_PASSWORD_ROOT" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$REMOTE_USER"@"$REMOTE_IP_ADDRESS_SERVER" "$1" 2>&1)
    exit_code=$?

    if [[ $output == *"ufw: command not found"* ]]; then
        echo "Попередження: ufw не знайдено, продовжуємо виконання."
    elif [ $exit_code -ne 0 ]; then
        echo "Помилка під час виконання команди через SSH: $1"
        echo "Вихідний код: $exit_code"
        echo "Вивід: $output"
        exit 1
    fi
}

function remote_rsync() {
    # Функція для копіювання файлів або каталогів з віддаленого сервера
    # sshpass -p "$REMOTE_PASSWORD_ROOT" rsync -avz -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10" root@$REMOTE_IP_ADDRESS_SERVER:/root/client.conf /etc/wireguard/wg0.conf

    # Параметри:
    # $1 - шлях до віддаленого файлу або каталогу
    # $2 - локальний шлях, куди потрібно скопіювати файл або каталог

    sshpass -p "$REMOTE_PASSWORD_ROOT" rsync -avz -e "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10" "$REMOTE_USER@$REMOTE_IP_ADDRESS_SERVER:$1" "$2"

    if [ $? -ne 0 ]; then
        echo "Помилка під час копіювання файлу $remote_path"
        exit 1
    fi
}

function check_dependency() {
    local dependency_name=$1
    local package_name=$2

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

function vpnStartAndConect() {
    echo "Виконуємо функцію vpnStartAndConect"
    output=$(wg-quick down wg0 2>&1)

    if echo "$output" | grep -q "is not a WireGuard interface"; then
        echo "Помилка: wg0 не є інтерфейсом WireGuard."
    else
        echo "З'єднання WireGuard wg0 розірвано."
    fi

    while true; do
        ping -c 1 $REMOTE_IP_ADDRESS_SERVER >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            break # Вихід з цикла.
        else
            echo "Сервер $REMOTE_IP_ADDRESS_SERVER не пінгується, очікуємо 1хв"
            sleep 60
        fi
    done

    remote_ssh_command "wget -O wireguard.sh https://get.vpnsetup.net/wg"
    remote_ssh_command "ufw disable"
    # remote_ssh_command "apt remove --purge ufw -y"
    remote_ssh_command "bash wireguard.sh --auto"

    remote_rsync "/root/client.conf" "/etc/wireguard/wg0.conf"

    wg-quick up wg0

    #REMOTE_COMMAND_IPTABLES="iptables -t nat -A PREROUTING -p tcp ! --dport 22 -m multiport ! --dports 51821 -j DNAT --to-destination 10.7.0.2 && \
    #iptables -t nat -A POSTROUTING -d 10.7.0.2 -j SNAT --to-source $REMOTE_IP_ADDRESS_SERVER"
    
    #remote_ssh_command "$REMOTE_COMMAND_IPTABLES"
}

check_system_release

UPDATE_DONE=false

dependencies=(
    "sshpass sshpass"
    "wg wireguard"
    "resolvconf resolvconf"
)
for dependency in "${dependencies[@]}"; do
    check_dependency $dependency
done

while true; do # Авто відновлення тунеля.
    ping -c 1 10.7.0.1 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 10
    else
        echo "Сервер 10.7.0.1 не пінгується"
        vpnStartAndConect # Виконуємо налаштуваня на відаленому сервері
        echo "Функція vpnStartAndConect виконата. Запуск цикла"
    fi
done