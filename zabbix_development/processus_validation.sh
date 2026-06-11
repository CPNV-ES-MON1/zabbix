#!/bin/bash
# Ce script vérifie que l'installation de Zabbix est correcte.
# Il contrôle les versions, les services, la base de données, l'interface web et les logs.
# Usage : sudo bash validate_zabbix.sh

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "=== Validation de installation Zabbix ==="

# Versions des dépendances installées
echo "--- Versions ---"
mariadb --version 2>/dev/null | grep -q '10\.11' && ok "MariaDB 10.11" || fail "MariaDB 10.11 non trouvée"
apache2 -v 2>/dev/null | grep -q '2\.4'          && ok "Apache 2.4"   || fail "Apache 2.4 non trouvée"
php -v 2>/dev/null | grep -q '8\.2'              && ok "PHP 8.2"      || fail "PHP 8.2 non trouvée"
zabbix_server --version 2>/dev/null | grep -q '7\.0' && ok "Zabbix 7.0" || fail "Zabbix 7.0 non trouvée"
echo ""

# Services démarrés et activés au démarrage
echo "--- Services ---"
for service in zabbix-server zabbix-agent2 apache2 mariadb; do
    systemctl is-active --quiet $service  && ok "$service démarré"            || fail "$service non démarré"
    systemctl is-enabled --quiet $service && ok "$service actif au démarrage" || fail "$service inactif au démarrage"
done
echo ""

# Connexion à la base de données
echo "--- Base de données ---"
read -s -p "Mot de passe MariaDB (utilisateur zabbix) : " DB_PASSWORD
echo ""
mysql -uzabbix -p${DB_PASSWORD} zabbix -e "SELECT 1;" &>/dev/null && ok "Connexion MariaDB OK" || fail "Connexion MariaDB échouée"
echo ""

# Accessibilité de l'interface web
echo "--- Interface web ---"
for url in http://localhost/zabbix http://MON-SRV-LIN/zabbix; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" $url)
    [ "$CODE" = "200" ] || [ "$CODE" = "301" ] || [ "$CODE" = "302" ] && ok "$url accessible" || fail "$url inaccessible (HTTP $CODE)"
done
echo ""

# Présence des fichiers de logs
echo "--- Logs ---"
for log in \
    /var/log/zabbix/zabbix_server.log \
    /var/log/zabbix/zabbix_agent2.log \
    /var/log/apache2/access.log \
    /var/log/apache2/error.log; do
    [ -f "$log" ] && ok "$log" || fail "$log manquant"
done

echo "C'est bon"
