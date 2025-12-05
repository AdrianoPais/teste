#!/bin/bash
# Script de instalação do servidor Web (Prestashop + WordPress)
# Para Ubuntu Server 24.04.2 LTS em ambiente DMZ.
# Inclui: Apache, PHP 7.4, MariaDB, VirtualHosts e correções completas.
set -e

########################################
# 1. Verificações iniciais
########################################
if [ "$EUID" -ne 0 ]; then
  echo "⚠️  Este script tem de ser corrido como root (sudo)."
  exit 1
fi

echo "=== CONFIGURAÇÃO DO SERVIDOR DMZ ==="
echo

########################################
# 2. Inputs
########################################

# Interface de rede
read -rp "Nome da interface de rede (ex: ens33): " NET_IFACE
if [ -z "$NET_IFACE" ]; then
  echo "Interface inválida."
  exit 1
fi

# IP e gateway
read -rp "IP do servidor (ex: 192.168.0.17): " SERVER_IP
read -rp "Gateway (ex: 192.168.0.22): " GATEWAY_IP

# Domínios
read -rp "Domínio Prestashop (ex: loja.paca.cloud): " PRESTA_DOMAIN
read -rp "Domínio WordPress (ex: blog.paca.cloud): " WP_DOMAIN

if [ -z "$PRESTA_DOMAIN" ] || [ -z "$WP_DOMAIN" ]; then
  echo "Ambos os domínios têm de ser preenchidos."
  exit 1
fi

# Base de dados
read -rp "Nome BD Prestashop [prestashopdb]: " PRESTA_DB
PRESTA_DB=${PRESTA_DB:-prestashopdb}

read -rp "Utilizador BD Prestashop [prestashop]: " PRESTA_USER
PRESTA_USER=${PRESTA_USER:-prestashop}

read -rp "Password BD Prestashop: " PRESTA_PASS

read -rp "Nome BD WordPress [wordpressdb]: " WP_DB
WP_DB=${WP_DB:-wordpressdb}

read -rp "Utilizador BD WordPress [wordpress]: " WP_USER
WP_USER=${WP_USER:-wordpress}

read -rp "Password BD WordPress: " WP_PASS

########################################
# 3. Configurar rede Netplan
########################################

NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"

echo "A configurar Netplan..."
cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${NET_IFACE}:
      optional: true
      dhcp4: false
      addresses:
        - ${SERVER_IP}/29
      routes:
        - to: default
          via: ${GATEWAY_IP}
      nameservers:
        addresses: [8.8.8.8,1.1.1.1]
EOF

netplan apply
echo "Rede configurada."
echo

########################################
# 4. Instalar Apache
########################################

echo "=== 4) Instalar Apache ==="
apt update
apt -y install apache2 unzip curl

systemctl enable apache2
systemctl restart apache2
echo

########################################
# 5. Instalar MariaDB
########################################

echo "=== 5) Instalar MariaDB ==="
apt -y install mariadb-server mariadb-client

systemctl enable mariadb
systemctl restart mariadb

# Criar bases de dados e utilizadores
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${PRESTA_DB};
CREATE USER IF NOT EXISTS '${PRESTA_USER}'@'localhost' IDENTIFIED BY '${PRESTA_PASS}';
GRANT ALL PRIVILEGES ON ${PRESTA_DB}.* TO '${PRESTA_USER}'@'localhost';

CREATE DATABASE IF NOT EXISTS ${WP_DB};
CREATE USER IF NOT EXISTS '${WP_USER}'@'localhost' IDENTIFIED BY '${WP_PASS}';
GRANT ALL PRIVILEGES ON ${WP_DB}.* TO '${WP_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF

echo "Bases de dados criadas."
echo

########################################
# 6. Instalar PHP 7.4 (PPA corrigido)
########################################

echo "=== 6) Instalar PHP 7.4 ==="

apt -y install lsb-release ca-certificates apt-transport-https software-properties-common gnupg2

add-apt-repository ppa:ondrej/php -y
apt update

apt -y install php7.4 php7.4-cli php7.4-common php7.4-mysql php7.4-gd \
               php7.4-xml php7.4-curl php7.4-mbstring php7.4-zip \
               php7.4-intl php7.4-bcmath php7.4-soap php7.4-imagick

PHP_INI="/etc/php/7.4/apache2/php.ini"
sed -i "s/^memory_limit = .*/memory_limit = 512M/" "${PHP_INI}"
sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "${PHP_INI}"
sed -i "s/^post_max_size = .*/post_max_size = 64M/" "${PHP_INI}"
sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "${PHP_INI}"

systemctl restart apache2
echo

########################################
# 7. Download e instalação do Prestashop (CORRIGIDO)
########################################

echo "=== 7) Instalar Prestashop ==="
cd /var/www

rm -f prestashop.zip
rm -rf prestashop

wget -O prestashop.zip https://github.com/PrestaShop/PrestaShop/releases/download/8.1.7/prestashop_8.1.7.zip

# Validar ZIP
if ! file prestashop.zip | grep -qi 'Zip archive'; then
  echo "❌ ERRO: O ficheiro descarregado NÃO é um ZIP válido!"
  exit 1
fi

unzip prestashop.zip -d prestashop
rm prestashop.zip

chown -R www-data:www-data prestashop
echo

########################################
# 8. Download e instalação do WordPress
########################################

echo "=== 8) Instalar WordPress ==="
rm -rf wordpress
wget -O wordpress.tar.gz https://wordpress.org/latest.tar.gz
tar -xvf wordpress.tar.gz
rm wordpress.tar.gz

chown -R www-data:www-data wordpress
echo

########################################
# 9. VirtualHosts
########################################

echo "=== 9) Configurar VirtualHosts ==="

cat > /etc/apache2/sites-available/prestashop.conf <<EOF
<VirtualHost *:80>
  ServerName ${PRESTA_DOMAIN}
  DocumentRoot /var/www/prestashop
  <Directory /var/www/prestashop>
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF

cat > /etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost *:80>
  ServerName ${WP_DOMAIN}
  DocumentRoot /var/www/wordpress
  <Directory /var/www/wordpress>
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF

a2ensite prestashop.conf
a2ensite wordpress.conf
a2enmod rewrite
systemctl reload apache2

echo
echo "========================================"
echo " INSTALAÇÃO CONCLUÍDA COM SUCESSO! "
echo "========================================"
echo "Prestashop: http://${PRESTA_DOMAIN}"
echo "WordPress:  http://${WP_DOMAIN}"
echo "IP Servidor: ${SERVER_IP}"
echo "========================================"
