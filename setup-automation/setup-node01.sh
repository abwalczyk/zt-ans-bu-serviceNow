#!/bin/bash

# Network Configuration - Mirror roadshow02 logic
nmcli connection add type ethernet con-name enp2s0 ifname enp2s0 ipv4.addresses 192.168.1.11/24 ipv4.method manual connection.autoconnect yes
nmcli connection up enp2s0

# Hosts file configuration - Mirror roadshow02 logic
echo "192.168.1.10 control.lab control" >> /etc/hosts
echo "192.168.1.11 node01.lab node01" >> /etc/hosts
echo "192.168.1.12 node02.lab node02" >> /etc/hosts

# Satellite Registration - Mirror roadshow02 logic
curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm

subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}

# Package Installation - Mirror roadshow02 logic with additional packages for ServiceNow
dnf install samba-common-tools realmd oddjob oddjob-mkhomedir sssd adcli krb5-workstation httpd nano -y

# SELinux Configuration - Mirror roadshow02 logic
setenforce 0

# Backup resolv.conf - Mirror roadshow02 logic
cp /etc/resolv.conf /tmp/resolv.conf

# Web Server Configuration - Mirror roadshow02 logic with ServiceNow branding
cat <<EOF | tee /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ServiceNow Lab Environment</title>
    <style>
        body {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            font-family: Arial, sans-serif;
            background-color: #f4f4f9;
            color: #333;
        }
        h1 {
            font-size: 3em;
            text-align: center;
        }
        .container {
            text-align: center;
            padding: 20px;
        }
        .status {
            color: #28a745;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>ServiceNow Lab Environment</h1>
        <p class="status">Node01 is ready for ServiceNow automation</p>
        <p>This server is configured for ServiceNow ITSM integration</p>
    </div>
</body>
</html>
EOF

# Start and enable services - Mirror roadshow02 logic
systemctl enable httpd
systemctl start httpd

# Create backup directory for ServiceNow
mkdir -p /backup
chmod -R 777 /backup

# Create servicenow project directory
mkdir -p /home/rhel/servicenow_project
chown -R rhel:rhel /home/rhel/servicenow_project

# Additional ServiceNow-specific configurations
echo "ServiceNow Node01 setup completed successfully"
