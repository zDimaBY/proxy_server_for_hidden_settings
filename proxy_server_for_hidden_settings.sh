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

    # Перевірка наявності залежності
    if ! command -v $dependency_name &>/dev/null; then
        echo -e "${RED}$dependency_name не встановлено. Встановлюємо...${RESET}"

        # Перевірка чи вже було виконано оновлення системи
        if ! "$UPDATE_DONE"; then
            # Встановлення залежності залежно від операційної системи
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
    # Генерація rsa SSH ключа
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
    fi
    if ssh-keygen -F "$REMOTE_ADDRESS_CHECK" -l &>/dev/null; then
        echo "Ключі для сервера $REMOTE_ADDRESS_CHECK вже існують. Видаляємо їх..."
        ssh-keygen -R "$REMOTE_ADDRESS_CHECK" -f ~/.ssh/known_hosts # Видалення старих ключів
        ssh-keyscan -H "$REMOTE_ADDRESS_CHECK" >>~/.ssh/known_hosts
    else
        echo "Додаємо ключі для сервера $REMOTE_ADDRESS_CHECK..."
        ssh-keyscan -H "$REMOTE_ADDRESS_CHECK" >>~/.ssh/known_hosts # Додавання нових ключів
    fi
    if sshpass -p "$REMOTE_PASSWORD" ssh-copy-id -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_ADDRESS_CHECK"; then
        echo "Ключі успішно скопійовано на віддалений сервер."
    else
        echo "Сталася помилка під час копіювання ключів на віддалений сервер. Спробуємо виправити."
        if sshpass -p "$REMOTE_PASSWORD" ssh-copy-id -f -i ~/.ssh/id_rsa.pub -o StrictHostKeyChecking=no "$REMOTE_USER"@"$REMOTE_ADDRESS_CHECK"; then
            echo "Ключі успішно скопійовано на віддалений сервер із використанням опції -f."
        else
            echo "Сталася помилка під час копіювання ключів на віддалений сервер із використанням опції -f."
        fi
    fi
}
vpnStartAndConect() {
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

    REMOTE_COMMAND="wget -O 5_VPN.sh https://raw.githubusercontent.com/zDimaBY/setting_up_control_panels/main/scripts/5_VPN.sh && \
        sed -i '/s|CLIENT_NAME=/d' ./5_VPN.sh && \
        source /etc/os-release && \
        operating_system=\"\$ID\" && \
        if [[ -e /etc/wireguard/params ]]; then echo -e \"4\\ny\" | /root/VPN/wireguard-install.sh; fi && \
        source /root/5_VPN.sh && \
        mkdir -p /root/VPN/wireguard && \
        install_wireguard_scriptLocal"

    sshpass -p "$REMOTE_PASSWORD" ssh -o PasswordAuthentication=no -x "$REMOTE_USER"@"$REMOTE_ADDRESS" "$REMOTE_COMMAND"

    sshpass -p "$REMOTE_PASSWORD" rsync -e "ssh -o StrictHostKeyChecking=no" -avz "$REMOTE_USER"@"$REMOTE_ADDRESS":/root/VPN/wireguard/* /root

    cp /root/wg0-client-proxy.conf /etc/wireguard/wg0.conf && wg-quick up wg0

    check_ssh_keys "10.0.0.1"

    #REMOTE_COMMAND_IPTABLES="iptables -t nat -A PREROUTING -p tcp ! --dport 51820 -j DNAT --to-destination 10.0.0.2 && \
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

vpnStartAndConect # Виконуємо налаштуваня на відаленому сервері

while true; do # Авто відновлення тунеля.
    ping -c 1 10.0.0.1 >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 10
    else
        echo "Сервер 10.0.0.1 не пінгується"
        vpnStartAndConect
    fi
done