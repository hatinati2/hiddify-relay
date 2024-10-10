#!/bin/bash

# Check if the user has sudo permissions
if sudo -n true 2>/dev/null; then
    echo "This User has sudo permissions"
else
    echo "This User does not have sudo permissions"
    exit 1
fi

# Detect OS and set package/service managers
if [ -f /etc/redhat-release ]; then
    if grep -q "Rocky" /etc/redhat-release; then
        OS="Rocky"
        PACKAGE_MANAGER="dnf"
        SERVICE_MANAGER="systemctl"
    elif grep -q "AlmaLinux" /etc/redhat-release; then
        OS="AlmaLinux"
        PACKAGE_MANAGER="dnf"
        SERVICE_MANAGER="systemctl"
    else
        OS="CentOS"
        PACKAGE_MANAGER="yum"
        SERVICE_MANAGER="systemctl"
    fi
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu)
            OS="Ubuntu"
            PACKAGE_MANAGER="apt"
            SERVICE_MANAGER="systemctl"
            ;;
        debian)
            OS="Debian"
            PACKAGE_MANAGER="apt"
            SERVICE_MANAGER="systemctl"
            ;;
        fedora)
            OS="Fedora"
            PACKAGE_MANAGER="dnf"
            SERVICE_MANAGER="systemctl"
            ;;
        *)
            echo "Unsupported OS"
            exit 1
            ;;
    esac
else
    echo "Unsupported OS"
    exit 1
fi

# Update
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    sudo apt update
else
    sudo $PACKAGE_MANAGER update -y
fi

# Install necessary packages
install_package() {
    package=$1
    if ! command -v $package &> /dev/null; then
        echo "Installing $package..."
        sudo $PACKAGE_MANAGER install $package -y
    fi
}

install_package dialog
install_package whiptail
install_package jq
install_package lsof
install_package tar 
install_package wget

# Check if the alias already exists in .bashrc
if ! grep -q "alias relay='bash -c \"\$(curl -L https://raw.githubusercontent.com/hiddify/hiddify-relay/main/install.sh)\"'" ~/.bashrc; then
    echo "alias relay='bash -c \"\$(curl -L https://raw.githubusercontent.com/hiddify/hiddify-relay/main/install.sh)\"'" >> ~/.bashrc
    echo "Alias added to .bashrc"
    source ~/.bashrc
else
    echo "Alias already exists in .bashrc"
    source ~/.bashrc
fi
clear


# Define partial functions
##############################
## Functions for iptables setup
install_iptables() {
    IP=$(whiptail --inputbox "Enter your main server IP like (1.1.1.1):" 8 60 3>&1 1>&2 2>&3)
    TCP_PORTS=$(whiptail --inputbox "Enter ports separated by commas (e.g., 80,443):" 8 60 80,443 3>&1 1>&2 2>&3)

    {
        echo "10" "Installing iptables..."
        sudo $PACKAGE_MANAGER install iptables -y > /dev/null 2>&1
        echo "30" "Enabling net.ipv4.ip_forward..."
        sudo sysctl net.ipv4.ip_forward=1 > /dev/null 2>&1
        echo "50" "Configuring iptables rules for TCP..."
        sudo iptables -t nat -A POSTROUTING -p tcp --match multiport --dports $TCP_PORTS -j MASQUERADE > /dev/null 2>&1
        echo "60" "Configuring iptables rules for TCP DNAT..."
        sudo iptables -t nat -A PREROUTING -p tcp --match multiport --dports $TCP_PORTS -j DNAT --to-destination $IP > /dev/null 2>&1
        echo "75" "Configuring iptables rules for UDP..."
        sudo iptables -t nat -A POSTROUTING -p udp --match multiport --dports $TCP_PORTS -j MASQUERADE > /dev/null 2>&1
        echo "85" "Configuring iptables rules for UDP DNAT..."
        sudo iptables -t nat -A PREROUTING -p udp --match multiport --dports $TCP_PORTS -j DNAT --to-destination $IP > /dev/null 2>&1
        echo "95" "Creating /etc/iptables/..."
        sudo mkdir -p /etc/iptables/ > /dev/null 2>&1
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
        echo "100" "Starting iptables service..."
        sudo systemctl start iptables
    } | dialog --title "IPTables Installation" --gauge "Installing IPTables..." 10 100 0
    clear
    whiptail --title "IPTables Installation" --msgbox "IPTables installation completed." 8 60
}

check_port_iptables() {
    ip_ports=$(iptables-save | awk '/-A (PREROUTING|POSTROUTING)/ && /-p tcp -m multiport --dports/ {split($0, parts, "--to-destination "); split(parts[2], dest_port, "[:]"); split(parts[1], src_port, " --dports "); split(src_port[2], port_list, ","); for (i in port_list) { if(dest_port[1] != "") { if (index(port_list[i], " ")) { split(port_list[i], split_port, " "); print dest_port[1], split_port[1] } else print dest_port[1], port_list[i] }}}'
)
    status=$(sudo systemctl is-active iptables)
    service_status="iptables Service Status: $status"
    info="Service Status and Ports in Use:\n$ip_ports\n\n$service_status"
    whiptail --title "iptables Service Status and Ports" --msgbox "$info" 15 70
}

uninstall_iptables() {
    if whiptail --title "Confirm Uninstallation" --yesno "Are you sure you want to uninstall IPTables?" 8 60; then
        {
            echo "10" ; echo "Flushing iptables rules..."
            sudo iptables -F > /dev/null 2>&1
            sleep 1
            echo "20" ; echo "Deleting all user-defined chains..."
            sudo iptables -X > /dev/null 2>&1
            sleep 1
            echo "40" ; echo "Flushing NAT table..."
            sudo iptables -t nat -F > /dev/null 2>&1
            sleep 1
            echo "50" ; echo "Deleting user-defined chains in NAT table..."
            sudo iptables -t nat -X > /dev/null 2>&1
            sleep 1
            echo "70" ; echo "Removing /etc/iptables/rules.v4..."
            sudo rm /etc/iptables/rules.v4 > /dev/null 2>&1
            sleep 1
            echo "80" ; echo "Stopping iptables service..."
            sudo systemctl stop iptables > /dev/null 2>&1
            sleep 1
            echo "100" ; echo "IPTables Uninstallation completed!"
        } | whiptail --gauge "Uninstalling IPTables..." 10 70 0
        clear
        whiptail --title "IPTables Uninstallation" --msgbox "IPTables Uninstalled." 8 60
    else
        whiptail --title "IPTables Uninstallation" --msgbox "Uninstallation cancelled." 8 60
        clear
    fi
}
# Define the submenu for Other Options
function other_options_menu() {
    while true; do
        other_choice=$(whiptail --backtitle "Welcome to Hiddify Relay Builder" --title "Other Options" --menu "Please choose one of the following options:" 20 60 10 \
        "DNS" "Configure DNS" \
        "Update" "Update Server" \
        "Ping" "Ping to check internet connectivity" \
        "DeprecatedTunnel" "No longer supported"\
        "Back" "Return to Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $other_choice in
                DNS)
                    configure_dns
                    ;;
                Update)
                    update_server
                    ;;
                Ping)
                    ping_websites
                    ;;
                DeprecatedTunnel)
                    DeprecatedTunnel
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    ;;
            esac
        else
            exit 1
        fi
    done
}

#################################
# Define the main graphical menu
function DeprecatedTunnel() {
    while true; do
        choice=$(whiptail --backtitle "Welcome to Hiddify Relay Builder" --title "Choose Your Tunnel Mode" --menu "Please choose one of the following options:" 20 60 10 \
        "Socat" "Manage Socat Tunnel" \
        "WST" "Manage Web Socket Tunnel"\
        "Back" "Return to Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Socat)
                    socat_menu
                    ;;
                WST)
                    wstunnel_menu
                    ;;
                Back)
                    other_options_menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    ;;
            esac
        else
            exit 1
        fi
    done
}

#################################
# Define the main graphical menu
function menu() {
    while true; do
        choice=$(whiptail --backtitle "Welcome to Hiddify Relay Builder" --title "Choose Your Tunnel Mode" --menu "Please choose one of the following options:" 20 60 10 \
        "IP-Tables" "Manage IP-Tables Tunnel" \
        "GOST" "Manage GOST Tunnel" \
        "Dokodemo-Door" "Manage Dokodemo-Door Tunnel" \
        "HA-Proxy" "Manage HA-Proxy Tunnel" \
        "Options" "Additional Configuration Options" \
        "Quit" "Exit From The Script" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                IP-Tables)
                    iptables_menu
                    ;;
                GOST)
                    gost_menu
                    ;;
                Dokodemo-Door)
                    dokodemo_menu
                    ;;
                HA-Proxy)
                    haproxy_menu
                    ;;
                Options)
                    other_options_menu
                    ;;
                Quit)
                    exit 0
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Call the menu function
menu
