#!/bin/bash
# Copyrigth (c) 2023-2024
# Author: ReCaIita7
# MASI
# License: MIT License
# Description: Script installation et de configuration serveur DHCP sur Proxmox VE

header_info() {
  clear
  cat <<"EOF"

______ _   _                    __ _                 ______ _   _ _____ ______                                                        
| ___ \ | | |                  / _(_)         ___    |  _  \ | | /  __ \| ___ \                                                       
| |_/ / | | |   ___ ___  _ __ | |_ _  __ _   ( _ )   | | | | |_| | /  \/| |_/ /                                                       
|  __/| | | |  / __/ _ \| '_ \|  _| |/ _` |  / _ \/\ | | | |  _  | |    |  __/                                                        
| |   \ \_/ / | (_| (_) | | | | | | | (_| | | (_>  < | |/ /| | | | \__/\| |                                                           
\_|    \___/   \___\___/|_| |_|_| |_|\__, |  \___/\/ |___/ \_| |_/\____/\_|                                                           
                                      __/ |                                                                                           
                                     |___/                                                                                            

___  ___          _       ______        ______     _____      _____ _ _         ______
|  \/  |         | |      | ___ \       | ___ \   /  __ \    |_   _(_) |       |___  /
| .  . | __ _  __| | ___  | |_/ /_   _  | |_/ /___| /  \/ __ _ | |  _| |_ __ _    / / 
| |\/| |/ _` |/ _` |/ _ \ | ___ \ | | | |    // _ \ |    / _` || | | | __/ _` |  / /  
| |  | | (_| | (_| |  __/ | |_/ / |_| | | |\ \  __/ \__/\ (_| || |_| | || (_| |./ /   
\_|  |_/\__,_|\__,_|\___| \____/ \__, | \_| \_\___|\____/\__,_\___/|_|\__\__,_|\_/    
                                  __/ |                                               
                                 |___/                                                

---------------------------------------------------------------------------------------------------------------------------------------
                                                                                                                                                                                                                                                   
EOF
}
echo -e "Avertissement : La création de l'interface réseau vmbr1 doit être faite manuellement avant l'exécution du script sinon le script va échouer.\n"
# Lancement du script pour enlever les dépendances entreprise
header_info
function remove_enterprise_dependencies() {
    read -p "Voulez-vous enlever les dépendances entreprise ? (y/n) : " remove_enterprise
    if [ "$remove_enterprise" = "y" ]; then
        echo "Les dépendances entreprise vont être enlevées."
        bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/post-pve-install.sh)"
    else
        echo -e "Les dépendances entreprise ne seront pas enlevées.\n"
    fi
}

function configure_ip_forwarding() {
    read -p "Veuillez entrer l'adresse IP du réseau avec le netmask (exemple: 192.168.10.0/24): " network_mask_ip
    if ! grep -q "^\s*post-up echo 1 > /proc/sys/net/ipv4/ip_forward" /etc/network/interfaces; then
        cat << EOL >> /etc/network/interfaces
        post-up echo 1 > /proc/sys/net/ipv4/ip_forward
EOL
    fi

    if ! grep -q "^\s*post-up iptables -t nat -A POSTROUTING -s '$network_mask_ip' -o vmbr0 -j MASQUERADE" /etc/network/interfaces || \
       ! grep -q "^\s*post-down iptables -t nat -D POSTROUTING -s '$network_mask_ip' -o vmbr0 -j MASQUERADE" /etc/network/interfaces
    then
        cat << EOF >> /etc/network/interfaces
        post-up iptables -t nat -A POSTROUTING -s '$network_mask_ip' -o vmbr0 -j MASQUERADE
        post-down iptables -t nat -D POSTROUTING -s '$network_mask_ip' -o vmbr0 -j MASQUERADE
EOF
    fi
}

function configure_dhcp_server() {
    echo -e "\n---------------------------------------------------------------"
    echo "Informations nécessaires pour la configuration du serveur DHCP."
    echo -e "---------------------------------------------------------------\n"

    read -p "Veuillez entrer l'interface réseau à utiliser pour le serveur DHCP (par exemple, vmbr1): " interface
    router_ip=$(ip addr show dev $interface | awk '/inet / {split($2, a, "/"); print a[1]}')
    network_ip_full=$(echo "$network_mask_ip" | awk -F/ '{print $1}')
    network_ip=$(echo "$network_mask_ip" | awk -F/ '{print $1}' | sed 's/\.[^.]*$//')
    prefix_length=$(echo "$network_mask_ip" | awk -F/ '{print $2}')

    netmask=$((0xFFFFFFFF << (32 - prefix_length) & 0xFFFFFFFF))
    parts=()
    for ((i = 0; i < 4; i++)); do
        parts[i]=$((netmask >> (24 - i * 8) & 0xFF))
    done
    netmask_dec=$(IFS=. ; echo "${parts[*]}")

    read -p "Veuillez entrer la plage d'adresses IP à attribuer (par exemple, 10 50): " ip_range
    read start_range end_range <<< "$ip_range"
    ip_range="$network_ip.$start_range $network_ip.$end_range"

    read -p "Veuillez entrer l'adresse IP du serveur DNS (exemple: 8.8.8.8, 8.8.4.4): " dns_ip

    read -p "Voulez-vous entrer un nom de domaine ? (y/n): " domain_option

    if [ "$domain_option" == "y" ]; then
        read -p "Veuillez entrer un nom de domaine (par exemple, example.com): " domain_name
    fi

    apt-get update
    apt-get install isc-dhcp-server -y

    cat <<EOL > /etc/dhcp/dhcpd.conf
subnet $network_ip_full netmask $netmask_dec {
    range $ip_range;
    option routers $router_ip;
    option domain-name-servers $dns_ip;
EOL

    if [ "$domain_option" == "y" ]; then
        echo "    option domain-name \"$domain_name\";" >> /etc/dhcp/dhcpd.conf
    fi

    cat <<EOL >> /etc/dhcp/dhcpd.conf
    default-lease-time 600;
    max-lease-time 7200;
}
EOL

    while true; do
        declare -A machine_configurations

        read -p "Voulez-vous assigner une IP statique à une machine ? (y/n): " assign_ip_answer

        if [ "$assign_ip_answer" == "y" ]; then
            mac_addresses=$(ip neigh show dev "$interface" | awk '{print $3}' | sort -u)

            while true; do
                echo "Adresses MAC disponibles :"
                select mac_address in $mac_addresses "Terminer la configuration"; do
                    case $mac_address in
                        "Terminer la configuration")
                            echo "Sortie de la configuration d'adresse IP statique."
                            break 2  # Break hors des deux boucles
                            ;;
                        *)
                            echo "Adresse MAC sélectionnée : $mac_address"
                            break
                            ;;
                    esac
                done

                read -p "Voulez-vous assigner une IP statique à cette machine ? (y/n): " answer

                if [ "$answer" == "y" ]; then
                    read -p "Entrez l'adresse IP statique : " static_ip
                    machine_configurations["$mac_address"]=$static_ip

                    cat <<EOL >> /etc/dhcp/dhcpd.conf
host static-$static_ip {
    hardware ethernet $mac_address;
    fixed-address $static_ip;
}
EOL
                else
                    echo "Aucune action effectuée pour l'adresse MAC $mac_address."
                fi
            done
        else
            echo "Aucune action effectuée sans assigner d'IP."
            break
        fi
    done
}

function check_last_line() {
    last_line=$(tail -n 1 /etc/dhcp/dhcpd.conf)

    if [[ $last_line != }* ]]; then
        echo "La dernière ligne ne commence pas par }, ajout de }"
        echo "}" >> /etc/dhcp/dhcpd.conf
    fi
}

function start_dhcp_server() {
    sed -i "s/^\(INTERFACESv4=\).*\$/\1\"$interface\"/" /etc/default/isc-dhcp-server
    systemctl start isc-dhcp-server
    systemctl enable isc-dhcp-server

    echo "Le serveur DHCP a été installé et configuré avec succès."
    echo "Proxmox VE va redémarrer dans 5 secondes."
    sleep 5
    shutdown -r now
}

function main() {
    remove_enterprise_dependencies
    configure_ip_forwarding
    configure_dhcp_server
    check_last_line
    start_dhcp_server
}

main
