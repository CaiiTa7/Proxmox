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


interface=""
function select_interface() {
    local PS3="Enter the vmbr interface number: "
    # List all vmbr interfaces
    vmbr_interfaces=$(ip -o link show | awk -F': ' '$2 ~ /^vmbr[1-9]+$/ {print $2}')

    if [ -z "$vmbr_interfaces" ]; then
        echo "No vmbr interfaces found. Please configure vmbr interfaces first."
        exit 1
    fi

    # Prompt user to select a vmbr interface
    echo "Available vmbr interfaces:"
    select selected_interface in $vmbr_interfaces; do
        case $selected_interface in
            *)
                interface="$selected_interface"
                echo "Selected vmbr interface: $interface"
                break
                ;;
        esac
    done
}


function vm_information() {
    select_interface
    vm_interface="$interface"
    all_vm_ids=($(qm list | awk 'NR>1 {print $1}'))

    echo -e "Available machines for interface $vm_interface:\n"

    for vm_id in "${all_vm_ids[@]}"; do
        
        # Extract network interface from the virtual machine configuration file
        vm_config_file="/etc/pve/qemu-server/${vm_id}.conf"

        vm_net0=$(grep -Po '(?<=net0: ).*' "$vm_config_file" | awk -F, '{print $2}' | awk -F= '{print $2}')

        # Check if the network interface matches the specified interface
        if [ "$vm_net0" == "$vm_interface" ]; then
            vm_name=$(qm config "$vm_id" | awk -F'[=,[:space:]]*' '/name:/ {print $2}')
            vm_mac=$(qm config "$vm_id" | awk -F'[=,[:space:]]*' '/net0:/ {print tolower($3)}')
            vm_full_info="${vm_name} with MAC Address ${vm_mac}"
            vm_ip=$(ip neigh show dev "$vm_interface" | awk '{print $1,$3}' | grep "$vm_mac" | awk '{print $1}')
            network_ip_prefix=$(echo $vm_ip | sed 's/\.[0-255]*$//')

        fi
    done
}


function select_vm() {
    local PS3="Enter the machine number: "
    select vm_info in "${vm_name[@]}" "Finish configuration"; do
        case $vm_info in
            "Finish configuration")
                echo "Exiting port configuration."
                break 2  # Break out of both loops
                ;;
            *)
                echo "Selected machine: $vm_name with MAC address: $vm_mac and IP : $vm_ip"
                break
                ;;
        esac
    done
}


function find_network_with_netmask(){
    select_interface
    router_ip=$(ip addr show dev $interface | awk '/inet / {split($2, a, "/"); print a[1]}')
    network_ip=$(echo $router_ip | awk 'BEGIN{FS=OFS="."} {$4="0"; print}')
    network_ip_prefix=$(echo $network_ip | sed 's/\.[0-255]*$//')
    prefix_length=$(ip addr show dev $interface | awk '/inet / {split($2, a, "/"); print a[2]}')
    network_mask_ip="$network_ip/$prefix_length"
    netmask=$((0xFFFFFFFF << (32 - prefix_length) & 0xFFFFFFFF))
    parts=()
    for ((i = 0; i < 4; i++)); do
        parts[i]=$((netmask >> (24 - i * 8) & 0xFF))
    done
    netmask_dec=$(IFS=. ; echo "${parts[*]}")
}


function is_dhcp_server_present() {
    # Check if the dhcpd.conf file contains a subnet configuration for the selected interface
    grep -q "subnet $network_ip netmask $netmask_dec {" /etc/dhcp/dhcpd.conf
}

function has_static_hosts() {
    # Check if the dhcpd.conf file contains host entries
    if_is_present=$(grep -n -m 1 "^host " /etc/dhcp/dhcpd.conf | cut -d: -f1)
    echo $if_is_present
}

function check_listenning_interface() {
    # Check if INTERFACESv4 is already defined
    if grep -w "^INTERFACESv4=\".*$interface.*\"" /etc/default/isc-dhcp-server; then
	echo "Interface $interface already present."
    elif grep -q "^INTERFACESv4=\"\"" /etc/default/isc-dhcp-server; then
        # If not defined, set INTERFACESv4 to the new interface
        sed -i "s/^\(INTERFACESv4=\).*\$/\1\"$interface\"/" /etc/default/isc-dhcp-server
    else
		# If defined, add the new interface with a space before it
        sed -i "/^INTERFACESv4=/ s/\"$/ $interface\"/" /etc/default/isc-dhcp-server
    fi
}


function configure_dhcp() {
    echo -e "\n---------------------------------------------------------------"
    echo "Information needed for DHCP server configuration."
    echo -e "---------------------------------------------------------------\n"

    find_network_with_netmask

    if is_dhcp_server_present; then
        echo "DHCP server configuration already exists for the selected interface."
        exit 0
    fi

    check_listenning_interface
    
    read -p "Please enter the range of IP addresses to assign (e.g., 10 50): " ip_range
    read start_range end_range <<< "$ip_range"
    ip_range="$network_ip_prefix.$start_range $network_ip_prefix.$end_range"

    read -p "Please enter the DNS server IP address (e.g., 8.8.8.8, 8.8.4.4): " dns_ip
    # Check if dns_ip contains multiple IPs with commas
    if echo "$dns_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(, ([0-9]{1,3}\.){3}[0-9]{1,3})*$'; then
        # DNS configuration already contains commas between multiple IPs
        echo "OK good format."
    else
        # Add commas between multiple IPs using awk
        dns_ip=$(echo "$dns_ip" | awk '{gsub(/, /, ","); gsub(/ /, ", "); gsub(/,/, ", "); gsub(/  /, " "); print}')
	echo $dns_ip
  	echo "Added commas between multiple DNS servers."
    fi

    read -p "Do you want to enter a domain name? (y/n): " domain_option

    if [ "$domain_option" == "y" ]; then
        read -p "Please enter a domain name (e.g., example.com): " domain_name
    fi

    apt-get update > /dev/null 2>&1
    apt-get install isc-dhcp-server -y > /dev/null 2>&1

    # Find the first host line
    first_host_line=$(grep -n -m 1 "^host " /etc/dhcp/dhcpd.conf | cut -d: -f1)
    has_static_hosts_result=$(has_static_hosts)

    # If host exists in the DHCP configuration, add DHCP configuration above them.
    if [ "$has_static_hosts_result" ] && [ "$domain_option" == "y" ]; then
        awk -v first_line="$first_host_line" -v network_ip="$network_ip" -v netmask_dec="$netmask_dec" -v ip_range="$ip_range" -v router_ip="$router_ip" -v dns_ip="$dns_ip" -v domain_name="$domain_name" '
            NR == first_line {
                print "subnet " network_ip " netmask " netmask_dec " {";
                print "    range " ip_range ";";
                print "    option routers " router_ip ";";
                print "    option domain-name-servers " dns_ip ";";
                print "    option domain-name \"" domain_name "\";";
                print "    default-lease-time 600;";
                print "    max-lease-time 7200;";
                print "}";
		print ""
            }
            {print}' /etc/dhcp/dhcpd.conf > temp_file
    mv temp_file /etc/dhcp/dhcpd.conf 

    elif [ "$has_static_hosts_result" ] && [ "$domain_option" == "n" ]; then
          awk -v first_line="$first_host_line" -v network_ip="$network_ip" -v netmask_dec="$netmask_dec" -v ip_range="$ip_range" -v router_ip="$router_ip" -v dns_ip="$dns_ip" '
              NR == first_line {
                print "subnet " network_ip " netmask " netmask_dec " {";
                print "    range " ip_range ";";
                print "    option routers " router_ip ";";
                print "    option domain-name-servers " dns_ip ";";
                print "    default-lease-time 600;";
                print "    max-lease-time 7200;";
                print "}";
		print ""
            }
            {print}' /etc/dhcp/dhcpd.conf > temp_file
    mv temp_file /etc/dhcp/dhcpd.conf

    else
        cat <<EOL > /etc/dhcp/dhcpd.conf
subnet $network_ip netmask $netmask_dec {
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

fi
}

function add_dhcp_server() {
    echo -e "\n---------------------------------------------------------------"
    echo "Information needed to add another DHCP server configuration."
    echo -e "---------------------------------------------------------------\n"

    find_network_with_netmask
    if is_dhcp_server_present; then
        echo "DHCP server configuration already exists for the selected interface."
        exit 0
    fi
    
    check_listenning_interface
    
    read -p "Please enter the range of IP addresses to assign (e.g., 10 50): " ip_range
    read start_range end_range <<< "$ip_range"
    ip_range="$network_ip_prefix.$start_range $network_ip_prefix.$end_range"

    read -p "Please enter the DNS server IP address (e.g., 8.8.8.8, 8.8.4.4): " dns_ip
    # Check if dns_ip contains multiple IPs with commas
    if echo "$dns_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(, ([0-9]{1,3}\.){3}[0-9]{1,3})*$'; then
        # DNS configuration already contains commas between multiple IPs
        echo "OK good format."
    else
        # Add commas between multiple IPs using awk
        dns_ip=$(echo "$dns_ip" | awk '{gsub(/, /, ","); gsub(/ /, ", "); gsub(/,/, ", "); gsub(/  /, " "); print}')
	echo $dns_ip
  	echo "Added commas between multiple DNS servers."
    fi

    read -p "Do you want to enter a domain name? (y/n): " domain_option

    if [ "$domain_option" == "y" ]; then
        read -p "Please enter a domain name (e.g., example.com): " domain_name
    fi

    apt-get update > /dev/null 2>&1
    apt-get install isc-dhcp-server -y > /dev/null 2>&1

    # Find the first host line
    first_host_line=$(grep -n -m 1 "^host " /etc/dhcp/dhcpd.conf | cut -d: -f1)
    has_static_hosts_result=$(has_static_hosts)

    # If host exists in the DHCP configuration, add DHCP configuration above them.
    if [ "$has_static_hosts_result" ] && [ "$domain_option" == "y" ]; then
        awk -v first_line="$first_host_line" -v network_ip="$network_ip" -v netmask_dec="$netmask_dec" -v ip_range="$ip_range" -v router_ip="$router_ip" -v dns_ip="$dns_ip" -v domain_name="$domain_name" '
            NR == first_line {
                print "subnet " network_ip " netmask " netmask_dec " {";
                print "    range " ip_range ";";
                print "    option routers " router_ip ";";
                print "    option domain-name-servers " dns_ip ";";
                print "    option domain-name \"" domain_name "\";";
                print "    default-lease-time 600;";
                print "    max-lease-time 7200;";
                print "}";
		print ""
            }
            {print}' /etc/dhcp/dhcpd.conf > temp_file
    mv temp_file /etc/dhcp/dhcpd.conf 

    elif [ "$has_static_hosts_result" ] && [ "$domain_option" == "n" ]; then
          awk -v first_line="$first_host_line" -v network_ip="$network_ip" -v netmask_dec="$netmask_dec" -v ip_range="$ip_range" -v router_ip="$router_ip" -v dns_ip="$dns_ip" '
              NR == first_line {
                print "subnet " network_ip " netmask " netmask_dec " {";
                print "    range " ip_range ";";
                print "    option routers " router_ip ";";
                print "    option domain-name-servers " dns_ip ";";
                print "    default-lease-time 600;";
                print "    max-lease-time 7200;";
                print "}";
		print ""
            }
            {print}' /etc/dhcp/dhcpd.conf > temp_file
    mv temp_file /etc/dhcp/dhcpd.conf

    else
        cat <<EOL >> /etc/dhcp/dhcpd.conf
subnet $network_ip netmask $netmask_dec {
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

fi
}


function assign_static_ip() {

    declare -A machine_configurations
    vm_information
    select_vm
    mac_address=$vm_mac
    if grep -q "$mac_address" /etc/dhcp/dhcpd.conf; then
        echo "This machine already has a static IP assigned in dhcpd.conf."

    else                           
    read -p "Enter the end of the IP address (e.g 10): " end_ip
    static_ip="$network_ip_prefix.$end_ip"
    machine_configurations["$mac_address"]=$static_ip
    cat <<EOL >> /etc/dhcp/dhcpd.conf
host static-$static_ip {
    hardware ethernet $mac_address;
    fixed-address $static_ip;
}
EOL
    echo "Static IP $static_ip  assigned to the machine $vm_name."
    fi
}

function configure_ports() {
    # Get the IP address of the selected machine
    static_ip=$vm_ip
    echo "IP Address : $static_ip"

    # Ask the user to enter the ports to open
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

        if [ "$port" == "22" ]; then
            # If the port is 22, find the next available destination port in the range 222-250
            for ((dport = 222; dport <= 250; dport++)); do
                if ! grep -q " --dport $dport" /etc/network/interfaces; then
                    break
                fi
            done
        else
            # For other ports, use the specified port as the destination port
            dport=$port
        fi

        # Add iptables rules
        if ! grep -q "^\s*post-up iptables -t nat -A PREROUTING -i vmbr0 -p $transport_protocol --dport $dport -j DNAT --to $static_ip:$port" /etc/network/interfaces ||
        ! grep -q "^\s*post-down iptables -t nat -D PREROUTING -i vmbr0 -p $transport_protocol --dport $dport -j DNAT --to $static_ip:$port" /etc/network/interfaces
        then
            cat << EOF >> /etc/network/interfaces
        post-up iptables -t nat -A PREROUTING -i vmbr0 -p $transport_protocol --dport $dport -j DNAT --to $static_ip:$port
        post-down iptables -t nat -D PREROUTING -i vmbr0 -p $transport_protocol --dport $dport -j DNAT --to $static_ip:$port
EOF
            echo "Port $dport opened in $transport_protocol protocol for the machine with IP address: $static_ip"
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
}


function remove_iptables_rules() {

    target_ip=$vm_ip
       # Ask the user to enter the ports to open
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

        # Confirmation of the operation
        read -p "This will remove iptables rules for IP $target_ip and ports $port. Are you sure? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            echo "Operation aborted."
            return
        fi

        if [[ "$port" -ge 222 && "$port" -le 250 ]]; then
            if grep -q " --dport $port" /etc/network/interfaces; then
                ssh_port=22
                sed -i "/post-up iptables -t nat -A PREROUTING -i vmbr0 -p $transport_protocol --dport $port -j DNAT --to $target_ip:$ssh_port/d" /etc/network/interfaces
                sed -i "/post-down iptables -t nat -D PREROUTING -i vmbr0 -p $transport_protocol --dport $port -j DNAT --to $target_ip:$ssh_port/d" /etc/network/interfaces
                echo "Iptables rules for IP $target_ip and port $port have been removed."
            fi
        else
            dport=$port
            sed -i "/post-up iptables -t nat -A PREROUTING -i vmbr0 -p $transport_protocol --dport $dport -j DNAT --to $target_ip:$port/d" /etc/network/interfaces
            sed -i "/post-down iptables -t nat -D PREROUTING -i vmbr0 -p $transport_protocol --dport $dport -j DNAT --to $target_ip:$port/d" /etc/network/interfaces
            echo "Iptables rules for IP $target_ip and port $port have been removed."
        fi

    done
}


function assign_ports() {
    declare -A opened_ports

    vm_information
    select_vm
    configure_ports           
}


function remove_ports(){ 
    list_ports_vm
    remove_iptables_rules
}


function list_ports_vm() {
    vm_information
    select_vm

    found_rules=false
    # Check if iptables rules exist for the specified IP address
    while IFS= read -r line; do
        # Check for iptables rules
        if [[ $line =~ ^[[:space:]]*post-up && $line == *"--to $vm_ip"* ]]; then
            # Extraire le protocole et le port
            protocol=$(echo "$line" | awk -F '-p ' '{print $2}' | awk '{print $1}')
            port=$(echo "$line" | awk -F '--dport ' '{print $2}' | awk '{print $1}')

            echo "Port opened for the machine $vm_name with IP $vm_ip: $port/$protocol"
            found_rules=true

        fi
        
    done < /etc/network/interfaces 

    if ! $found_rules; then
        echo "No iptables rules found for the machine $vm_name with IP $vm_ip."
    fi
}


function start_dhcp_server() {
    systemctl start isc-dhcp-server
    systemctl enable isc-dhcp-server

    echo "The DHCP server has been installed and configured successfully."
}


function reboot_script() {
    echo -e  "\nExiting script....Proxmox VE will restart in 5 seconds."
    sleep 5
    shutdown -r now
}

function exit_script(){
    read -p "Do you want to exit the script (y/n) : " response
    if [ "$response" != "y" ]; then
        echo "Operation aborted."
        return
    else
        read -p "Do you want to reboot dhcp configuration to take effect, reboot the server, abort the operation or exit (1/2/3/4) : " confirmation
        if [ "$confirmation" == "1" ]; then
            restart_dhcp_server
        elif [ "$confirmation" == "2" ]; then
            if systemctl status isc-dhcp-server &> /dev/null; then
                read -p "DHCP present do you want to restart the service before rebooting the server ? (y/n) : " DHCP_confirmation
                if [ "$DHCP_confirmation" != "y" ]; then
                    reboot_script

                else
                    restart_dhcp_server
                    reboot_script

                fi
            else
                reboot_script

            fi

        elif [ "$confirmation" == "3" ]; then
            echo "Operation aborted."
            return
        elif [ "$confirmation" == "4" ]; then
            read -p "You'll exit the script without anny effect on the configuration do you want to continue (y/n) ? : " exit_response
            if [ "$exit_response" == "y" ]; then
                exit 0
            else
                echo "Operation aborted."
                return
            fi
        fi
    fi
}


function clear_screen(){
    printf "\x1Bc"
}

function remove_ip_forwarding() {
    read -p "Enter the network IP address with netmask (example: 192.168.10.0/24): " network_mask_ip

    # Remove ip_forwarding rules
#    sed -i -e "\|post-up echo 1 > /proc/sys/net/ipv4/ip_forward|d" /etc/network/interfaces
    sed -i -e "\|post-up iptables -t nat -A POSTROUTING -s '$network_mask_ip' -o vmbr0 -j MASQUERADE|d" /etc/network/interfaces
    sed -i -e "\|post-down iptables -t nat -D POSTROUTING -s '$network_mask_ip' -o vmbr0 -j MASQUERADE|d" /etc/network/interfaces

    echo "IP forwarding rules for network $network_mask_ip have been removed."
}


function remove_static_ip() {
    vm_information
    select_vm
    static_ip=$vm_ip
    # Remove static IP entry
    sed -i "/host static-$static_ip {/,/}/d" /etc/dhcp/dhcpd.conf

    echo "Static IP entry for $static_ip has been removed from dhcpd.conf."
}

function restart_dhcp_server() {
    echo -e "The DHCP server restart ...."
    systemctl restart isc-dhcp-server
    sleep 3
    echo "The DHCP server restarting operation is good"

}


function remove_dhcp_server() {
    
    find_network_with_netmask
    # Check if the DHCP server and the network exist
    if grep -q "subnet $network_ip " /etc/dhcp/dhcpd.conf; then
        # Utiliser sed pour supprimer la configuration du serveur DHCP du fichier
        sed -i "/subnet $network_ip /,/^}/{/^\$/!d}" /etc/dhcp/dhcpd.conf
        echo "DHCP server configuration for subnet $network_ip removed."

        # Remove the interface associate in the /etc/default/isc-dhcp-server
#       sed -i "/^INTERFACESv4=.*$interface/ s/$interface//" /etc/default/isc-dhcp-server
#	sed -i "/^INTERFACESv4=.*$interface/ s/[[:space:]]*$interface[[:space:]]*//" /etc/default/isc-dhcp-server
	sed -i "/^INTERFACESv4=.*$interface/ s/\s*$interface\s*//" /etc/default/isc-dhcp-server

        echo "Interface for subnet $network_ip removed from /etc/default/isc-dhcp-server."
    else
        echo "No DHCP server configuration found for subnet $subnet_ip."
    fi
}


function list_config_dhcp() {
	cat /etc/dhcp/dhcpd.conf
	is_interface_remove=$(grep -w "^INTERFACESv4" /etc/default/isc-dhcp-server)
	echo -e "\nListenning interface : $is_interface_remove\n"
}


function add_vmbr_interface() {
    read -p "Enter the number for the new vmbr interface (e.g., 4 for vmbr4): " vmbr_number

    # Form the vmbr interface name
    vmbr_interface="vmbr$vmbr_number"

    # Check if vmbr interface already exists in /etc/network/interfaces
    if grep -q "iface $vmbr_interface" /etc/network/interfaces; then
        echo "vmbr interface $vmbr_interface already exists in /etc/network/interfaces. Not adding again."
        return
    fi

    read -p "Enter the IP address to assign with netmask (e.g., 192.168.1.1/24): " ip_address

    # Temporary file for modified interfaces file
    tmp_file=$(mktemp)

    # Flag to determine if new interface added
    new_iface_added=0

    # Flag to determine if iptables rules exist
    iptables_rules_exist=0

    # Process each line in /etc/network/interfaces
    while IFS= read -r line; do
        # Check for iptables rules
        if [[ $line =~ ^[[:space:]]*post-up ]]; then
            iptables_rules_exist=1
        fi

        # If iptables rules exist and new interface not added, add it before the rules
        if [[ $iptables_rules_exist -eq 1 && $new_iface_added -eq 0 ]]; then
            echo -e "\nauto $vmbr_interface" >> "$tmp_file"
            echo "iface $vmbr_interface inet static" >> "$tmp_file"
            echo "        address $ip_address" >> "$tmp_file"
            echo "        bridge-ports none" >> "$tmp_file"
            echo "        bridge-stp off" >> "$tmp_file"
            echo -e "        bridge-fd 0\n" >> "$tmp_file"
            new_iface_added=1
        fi

        # Print the line
        echo "$line" >> "$tmp_file"

    done < /etc/network/interfaces

    # If no iptables rules, add new interface at the end
    if [[ $iptables_rules_exist -eq 0 && $new_iface_added -eq 0 ]]; then
        echo -e "\nauto $vmbr_interface" >> "$tmp_file"
        echo "iface $vmbr_interface inet static" >> "$tmp_file"
        echo "        address $ip_address" >> "$tmp_file"
        echo "        bridge-ports none" >> "$tmp_file"
        echo "        bridge-stp off" >> "$tmp_file"
        echo -e "        bridge-fd 0\n" >> "$tmp_file"
    fi

    # Move the modified file back to /etc/network/interfaces
    mv /etc/network/interfaces /etc/network/interfaces.backup
    cp $tmp_file /etc/network/interfaces
    chmod 0644 /etc/network/interfaces

    echo "Bridge Interface $vmbr_interface added with IP address and netmask $ip_address"
}


function remove_vmbr_interface() {
    select_interface
    read -p "This will remove the interface $interface. Are you sure? (y/n): " vmbr_confirmation
    if [ "$vmbr_confirmation" != "y" ]; then
        echo "Operation aborted."
        return
    fi
    # Remove the selected interface from /etc/network/interfaces
    sed -i "/iface $interface/,/bridge-fd/d" /etc/network/interfaces
    sed -i "/auto $interface/d" /etc/network/interfaces
    echo "Bridge Interface $interface removed."
                
}


function select_task() {
    echo -e "\nSelect a task: \n"
    local PS3="Enter the task number (15 for menu) : "
    options=("Remove enterprise dependencies" "Add Bridge interface" "Remove Bridge interface" "Configure IP forwarding" "Remove IP forwarding" "Configure DHCP server" "Add other DHCP server" "Remove DHCP server" "Restart DHCP server" "List DHCP configuration" "Configure static IP" "Remove static IP" "Assign ports" "Remove ports" "Show Menu" "Reboot" "Exit")
    select opt in "${options[@]}"; do
        case $opt in
            "Remove enterprise dependencies")
                remove_enterprise_dependencies
                ;;
            "Add Bridge interface")
                add_vmbr_interface
                ;;
            "Remove Bridge interface")
                remove_vmbr_interface
                ;;
            "Configure IP forwarding")
                configure_ip_forwarding
                ;;
            "Remove IP forwarding")
                remove_ip_forwarding
                ;;
            "Configure DHCP server")
                configure_dhcp
	        start_dhcp_server
		;;
            "Add other DHCP server")
		add_dhcp_server
		restart_dhcp_server		
		;;
            "Remove DHCP server")
		remove_dhcp_server
		restart_dhcp_server		
		;;
            "List DHCP configuration")
		list_config_dhcp		
		;;
	    "Restart DHCP server")
		restart_dhcp_server
		;;
            "Configure static IP")
                assign_static_ip
                restart_dhcp_server
                ;;
            "Remove static IP")
                remove_static_ip
		restart_dhcp_server
                ;;
            "Assign ports")
                assign_ports
                ;;
            "Remove ports")
                remove_ports
                ;;
            "Exit")
                exit_script
                ;;
	    "Reboot")
                reboot_script
                ;;
            "Show Menu")
                clear_screen
                select_task
                ;;
            *) echo "Invalid option";;
        esac
    done
}

function main() {
    select_task
}

main
