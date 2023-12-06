![Proxmox](https://logovectorseek.com/wp-content/uploads/2021/10/proxmox-server-solutions-gmbh-logo-vector.png)

# 👨‍💻 Developed in:
![Shell Script](https://img.shields.io/badge/shell_script-%23121011.svg?style=for-the-badge&logo=gnu-bash&logoColor=white)

# 🗒️ Descritpion:

### French Version:

# Proxmox VE Network Configuration Script

Ce script Bash automatisé facilite la configuration avancée du réseau sur un serveur Proxmox VE. Il propose une gamme étendue de fonctionnalités, de la suppression des dépendances d'entreprise à la configuration d'un serveur DHCP et à l'ouverture spécifique de ports pour les machines avec des adresses IP statiques.

## Fonctionnalités Principales :

1. **Suppression des Dépendances d'Entreprise :**
   - Permet de retirer les dépendances d'entreprise de Proxmox VE.
   - Utilise un script externe pour effectuer cette opération.

2. **Configuration du Transfert IP :**
   - Demande à l'utilisateur d'entrer l'adresse IP du réseau avec le masque (par exemple : 192.168.10.0/24).
   - Active le transfert IP en ajoutant des règles iptables pour le masquerading.

3. **Configuration du Serveur DHCP :**
   - Guide l'utilisateur à travers la configuration du serveur DHCP.
   - Collecte des informations telles que l'interface réseau, l'adresse du routeur, la plage d'adresses IP, et les serveurs DNS.
   - Génère dynamiquement le fichier de configuration du serveur DHCP (`/etc/dhcp/dhcpd.conf`).

4. **Attribution d'Adresses IP Statiques :**
   - Permet à l'utilisateur d'attribuer des adresses IP statiques aux machines.
   - Récupère les adresses MAC des machines disponibles.

5. **Ouverture de Ports Spécifiques :**
   - Demande à l'utilisateur s'il souhaite ouvrir des ports pour une machine donnée.
   - Pour le port 22, commence à partir du port 222 et s'incrémente pour chaque machine ultérieure (port 223, port 224, etc.).

6. **Gestion des ICMP :**
   - Permet d'ajouter des règles ICMP pour chaque machine configurée.

7. **Redémarrage Automatique :**
   - Redémarre automatiquement Proxmox VE pour appliquer les modifications.

## Avertissements :

1. L'interface réseau `vmbr1` doit être configurée avant d'exécuter ce script.
2. Pour attribuer une adresse IP statique à une machine, celle-ci doit être installée et en cours d'exécution.
3. La première machine qui ouvre le port 22 utilise le port 222, la deuxième machine utilise le port 223, et ainsi de suite.

---

### English Version:

# Proxmox VE Network Configuration Script

This automated Bash script streamlines advanced network configuration on a Proxmox VE server. It offers a broad range of features, from removing enterprise dependencies to configuring a DHCP server and opening specific ports for machines with static IP addresses.

## Key Features:

1. **Removing Enterprise Dependencies:**
   - Allows the removal of Proxmox VE enterprise dependencies.
   - Utilizes an external script to perform this operation.

2. **IP Forwarding Configuration:**
   - Prompts the user to enter the network IP address with the mask (e.g., 192.168.10.0/24).
   - Enables IP forwarding by adding iptables rules for masquerading.

3. **DHCP Server Configuration:**
   - Guides the user through DHCP server configuration.
   - Collects information such as the network interface, router address, IP address range, and DNS servers.
   - Dynamically generates the DHCP server configuration file (`/etc/dhcp/dhcpd.conf`).

4. **Assignment of Static IP Addresses:**
   - Allows the user to assign static IP addresses to machines.
   - Retrieve MAC addresses of available machines.

5. **Opening Specific Ports:**
   - Asks the user if they want to open ports for a given machine.
   - For port 22, starts from port 222 and increments for each subsequent machine (port 223, port 224, etc.).

6. **ICMP Management:**
   - Enables the addition of ICMP rules for each configured machine.

7. **Automatic Restart:**
   - Automatically restarts Proxmox VE to apply changes.

## Warnings:

1. The `vmbr1` network interface must be configured before running this script.
2. To assign a static IP address to a machine, the machine must be installed and running.
3. The first machine opening port 22 uses port 222, the second machine uses port 223, and so on.

# ▶ How to use:
## No sudo mode and in the current folder

    sudo chmod +x config.sh
    sudo ./config.sh
## Sudo mode and in the current folder

    chmod +x config.sh
    ./config.sh

## IF port 22 opened for a machine
### On terminal (For the exemple PowerShell)
1. user = The user you want to be connected (User of the remote machine).
2. IP = IP of vmbr0, the interface exposed on the internet.
3. -p 222 = To precise the port (of the first machine in this exemple, if it's the second machine the -p will be 223 etc).

```bash
  ssh -p 222 user@IP
```
Enter the password of the remote user

And that's it ! 

## Authors
- [@CaiiTa7](https://www.github.com/CaiiTa7)

## Crédits
- [Original Author's name] https://github.com/tteck - Author of the Script to remove dependencies for Proxmox VE
- [Original Deposit] https://github.com/tteck/Proxmox/tree/main - Original Deposit for the script

## License
[MIT](https://choosealicense.com/licenses/mit/)
