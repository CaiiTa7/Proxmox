#!/bin/bash
# Copyrigth (c) 2023-2024
# Author: A.Matteo, ETU46744
# Henallux MASI
# License: MIT License

header_info() {
  clear
  cat <<"EOF"


██████  ██    ██        ██        ██████  ██   ██  ██████ ██████       ██████  ██████  ███    ██ ███████ ██  ██████            
██   ██ ██    ██        ██        ██   ██ ██   ██ ██      ██   ██     ██      ██    ██ ████   ██ ██      ██ ██                 
██████  ██    ██     ████████     ██   ██ ███████ ██      ██████      ██      ██    ██ ██ ██  ██ █████   ██ ██   ███           
██       ██  ██      ██  ██       ██   ██ ██   ██ ██      ██          ██      ██    ██ ██  ██ ██ ██      ██ ██    ██           
██        ████       ██████       ██████  ██   ██  ██████ ██           ██████  ██████  ██   ████ ██      ██  ██████            
                                                                                                                               
                                                                                                                               
███    ███  █████  ██████  ███████     ██████  ██    ██     ███████ ████████ ██    ██ ██   ██  ██████  ███████ ██   ██ ██   ██ 
████  ████ ██   ██ ██   ██ ██          ██   ██  ██  ██      ██         ██    ██    ██ ██   ██ ██            ██ ██   ██ ██   ██ 
██ ████ ██ ███████ ██   ██ █████       ██████    ████       █████      ██    ██    ██ ███████ ███████      ██  ███████ ███████ 
██  ██  ██ ██   ██ ██   ██ ██          ██   ██    ██        ██         ██    ██    ██      ██ ██    ██    ██        ██      ██ 
██      ██ ██   ██ ██████  ███████     ██████     ██        ███████    ██     ██████       ██  ██████     ██        ██      ██ 
                                                                                                       
Warning :

1) The vmbr1 network interface must be configured before running this script otherwise it will fail.

2) To assign a static IP address to a machine, the machine must be installed and running.

2.1) You must also know the MAC address of the machine. You can find it in the Proxmox VE web interface or with "ip a" command (on the machine).

3) If you want to open the port 22 for a machine the first one will have the specific port 222 the second machine will have the port 223 ...

---------------------------------------------------------------------------------------------------------------------------------------

EOF
}

header_info
function remove_enterprise_dependencies() {
    read -p "Do you want to remove enterprise dependencies? (y/n): " remove_enterprise
    if [ "$remove_enterprise" = "y" ]; then
        echo "Enterprise dependencies will be removed."
        bash -c "$(wget -qLO - https://github.com/tteck/Proxmox/raw/main/misc/post-pve-install.sh)"
    else
        echo -e "Enterprise dependencies will not be removed.\n"
    fi
}

function configure_ip_forwarding() {
    read -p "Please enter the network IP address with netmask (example: 192.168.10.0/24): " network_mask_ip
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
    echo "Information needed for DHCP server configuration."
    echo -e "---------------------------------------------------------------\n"

    read -p "Please enter the network interface to use for DHCP server (e.g., vmbr1): " interface
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

    read -p "Please enter the range of IP addresses to assign (e.g., 10 50): " ip_range
    read start_range end_range <<< "$ip_range"
    ip_range="$network_ip.$start_range $network_ip.$end_range"

    read -p "Please enter the DNS server IP address (e.g., 8.8.8.8, 8.8.4.4): " dns_ip

    read -p "Do you want to enter a domain name? (y/n): " domain_option

    if [ "$domain_option" == "y" ]; then
        read -p "Please enter a domain name (e.g., example.com): " domain_name
    fi

    apt-get update > /dev/null 2>&1
    apt-get install isc-dhcp-server -y > /dev/null 2>&1

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

    next_dport=222
    while true; do
        declare -A machine_configurations

        read -p "Do you want to assign a static IP to a machine? (y/n): " assign_ip_answer

        if [ "$assign_ip_answer" == "y" ]; then
            mac_addresses=$(ip neigh show dev "$interface" | awk '{print $3}' | sort -u)

            while true; do
                echo -e "Available MAC addresses:\n"
                select mac_address in $mac_addresses "Finish configuration"; do
                    case $mac_address in
                        "Finish configuration")
                            echo "Exiting static IP configuration."
                            break 2  # Break out of both loops
                            ;;
                        *)
                            echo "Selected MAC address: $mac_address"
                            read -p "Do you want to assign a static IP to this machine? (y/n): " answer

                            if [ "$answer" == "y" ]; then
                                read -p "Enter the static IP address: " static_ip
                                machine_configurations["$mac_address"]=$static_ip

                                cat <<EOL >> /etc/dhcp/dhcpd.conf
host static-$static_ip {
    hardware ethernet $mac_address;
    fixed-address $static_ip;
}
EOL
                                echo "Static IP address assigned to the machine."
                            else
                                echo "No static IP address assigned."
                            fi

                            read -p "Do you want to open ports for this machine? (y/n): " open_ports_answer

                            if [ "$open_ports_answer" == "y" ]; then
                                read -p "Please enter the port number(s) with protocols (separated by spaces, e.g., 80/tcp 53/udp): " port_numbers_and_protocols

                                # Initialize variables
                                transport_protocol=""
                                icmp_protocol=""

                                # Loop over the specified ports/protocols
                                for port_and_protocol in $port_numbers_and_protocols; do
                                    IFS='/' read -r port protocol <<< "$port_and_protocol"

                                    # Select the transport protocol (TCP or UDP)
                                    case $protocol in
                                        "tcp" | "udp")
                                            transport_protocol=$protocol
                                            ;;
                                        *)
                                            echo "Unsupported protocol: $protocol"
                                            ;;
                                    esac

                                    # Add iptables rules for each port/protocol
                                    if [ "$transport_protocol" != "" ]; then
                                        if [ "$port" == "22" ]; then
					    dport=$next_dport
					    next_dport=$((next_dport + 1))

					    # Add rules specific to port 22
                                            if ! grep -q "^\s*post-up iptables -t nat -A PREROUTING -i vmbr0 -p $protocol --dport $dport -j DNAT --to $static_ip:$port" /etc/network/interfaces ||
                                               ! grep -q "^\s*post-down iptables -t nat -D PREROUTING -i vmbr0 -p $protocol --dport $dport -j DNAT --to $static_ip:$port" /etc/network/interfaces
                                            then
                                                cat << EOF >> /etc/network/interfaces
	post-up iptables -t nat -A PREROUTING -i vmbr0 -p $protocol --dport $dport -j DNAT --to $static_ip:$port
	post-down iptables -t nat -D PREROUTING -i vmbr0 -p $protocol --dport $dport -j DNAT --to $static_ip:$port
EOF
                                                echo "Port $port opened in $protocol protocol for the machine with IP address: $static_ip"
                                            fi
                                        else
                                            # Add rules for other ports
                                            if ! grep -q "^\s*post-up iptables -t nat -A PREROUTING -i vmbr0 -p $protocol --dport $port -j DNAT --to $static_ip:$port" /etc/network/interfaces ||
                                               ! grep -q "^\s*post-down iptables -t nat -D PREROUTING -i vmbr0 -p $protocol --dport $port -j DNAT --to $static_ip:$port" /etc/network/interfaces
                                            then
                                                cat << EOF >> /etc/network/interfaces
	post-up iptables -t nat -A PREROUTING -i vmbr0 -p $protocol --dport $port -j DNAT --to $static_ip:$port
	post-down iptables -t nat -D PREROUTING -i vmbr0 -p $protocol --dport $port -j DNAT --to $static_ip:$port
EOF
                                                echo "Port $port opened in $protocol protocol for the machine with IP address: $static_ip"
                                            fi
                                        fi
                                    fi
                                done

                                # Ask if the user wants to add ICMP rules
                                read -p "Do you want to add ICMP rules? (y/n): " icmp_answer

                                if [ "$icmp_answer" == "y" ]; then
                                    if ! grep -q "^\s*post-up iptables -t nat -A PREROUTING -i vmbr0 -p icmp --icmp-type echo-request -j DNAT --to $static_ip" /etc/network/interfaces ||
                                       ! grep -q "^\s*post-down iptables -t nat -D PREROUTING -i vmbr0 -p icmp --icmp-type echo-request -j DNAT --to $static_ip" /etc/network/interfaces
                                    then
                                        cat << EOF >> /etc/network/interfaces
	post-up iptables -t nat -A PREROUTING -i vmbr0 -p icmp --icmp-type echo-request -j DNAT --to $static_ip
	post-down iptables -t nat -D PREROUTING -i vmbr0 -p icmp --icmp-type echo-request -j DNAT --to $static_ip
EOF
                                        echo "ICMP rule added for the machine with IP address: $static_ip"
                                    fi
                                else
                                    echo "No ICMP rules added."
                                fi

                                echo -e "Continuing to the next machine ...\n"
                                break 2
                            else
                                echo "No ports opened for the machine with IP address: $static_ip"
                                echo -e  "Continuing to the next machine ...\n"
                                break 2
                            fi
                            ;;
                    esac
                done
            done
        else
            echo "No action taken without assigning an IP."
            break
        fi
    done
}


function check_last_line() {
    last_line=$(tail -n 1 /etc/dhcp/dhcpd.conf)

    if [[ $last_line != }* ]]; then
        echo "The last line does not start with }, adding }"
        echo "}" >> /etc/dhcp/dhcpd.conf
    fi
}

function start_dhcp_server() {
    sed -i "s/^\(INTERFACESv4=\).*\$/\1\"$interface\"/" /etc/default/isc-dhcp-server
    systemctl start isc-dhcp-server
    systemctl enable isc-dhcp-server

    echo "The DHCP server has been installed and configured successfully."
    echo -e  "\nProxmox VE will restart in 5 seconds."
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
