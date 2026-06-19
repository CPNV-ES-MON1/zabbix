#!/bin/bash
# ==============================
# Script d'installation Zabbix Agent 2 - Debian (détection auto)
# Avec enregistrement automatique via API Zabbix
# Compatible AWS EC2
# ==============================

# Chargement robuste du fichier .env (gère les espaces et caractères spéciaux)
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
else
    echo "[ERREUR] Fichier .env introuvable !"
    exit 1
fi

echo "==============================="
echo " Installation Zabbix Agent 2"
echo " Serveur : $ZABBIX_SERVER_IP"
echo " Hostname : $ZABBIX_HOSTNAME"
echo "==============================="

# Vérification root
if [ "$EUID" -ne 0 ]; then
    echo "[ERREUR] Ce script doit être exécuté en root !"
    exit 1
fi

# Correction du PATH
export PATH=/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin

# ==============================
# 1. Installation du repo Zabbix (détection automatique de la version Debian)
# ==============================
echo "[1/7] Téléchargement du repo Zabbix $ZABBIX_VERSION..."

# Détection automatique de la version Debian installée sur la machine
DEBIAN_VERSION=$(. /etc/os-release && echo "$VERSION_ID")
echo "[INFO] Version Debian détectée : $DEBIAN_VERSION"

DEB_PKG="zabbix-release_latest_${ZABBIX_VERSION}+debian${DEBIAN_VERSION}_all.deb"

wget -q "https://repo.zabbix.com/zabbix/$ZABBIX_VERSION/debian/pool/main/z/zabbix-release/$DEB_PKG" \
    || { echo "[ERREUR] Téléchargement du repo échoué ! Vérifie la version Zabbix ou Debian."; exit 1; }

dpkg -i "$DEB_PKG" \
    || { echo "[ERREUR] Installation du repo échouée !"; exit 1; }

apt update -q
echo "[OK] Repo Zabbix installé (Debian $DEBIAN_VERSION)"

# ==============================
# 2. Installation de l'agent et curl
# ==============================
echo "[2/7] Installation de zabbix-agent2 et curl..."
apt install -y zabbix-agent2 curl \
    || { echo "[ERREUR] Installation de zabbix-agent2 échouée !"; exit 1; }
echo "[OK] zabbix-agent2 installé"

# ==============================
# 3. Configuration de l'agent
# ==============================
echo "[3/7] Configuration de l'agent..."
sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agent2.conf
sed -i "s/^Hostname=.*/Hostname=$ZABBIX_HOSTNAME/" /etc/zabbix/zabbix_agent2.conf

# Ajout AllowKey pour les remote commands
if ! grep -q "^AllowKey=system.run" /etc/zabbix/zabbix_agent2.conf; then
    echo "AllowKey=system.run[*]" >> /etc/zabbix/zabbix_agent2.conf
fi
echo "[OK] Agent configuré"

# ==============================
# 4. Activation du DebugLevel
# ==============================
echo "[4/7] Activation du DebugLevel=4 pour les logs..."
sed -i "s/^# DebugLevel=.*/DebugLevel=4/" /etc/zabbix/zabbix_agent2.conf
if ! grep -q "^DebugLevel=" /etc/zabbix/zabbix_agent2.conf; then
    echo "DebugLevel=4" >> /etc/zabbix/zabbix_agent2.conf
fi
echo "[OK] DebugLevel=4 activé"

# ==============================
# 5. Configuration sudoers
# ==============================
echo "[5/7] Configuration sudoers pour $ZABBIX_USER..."
apt install -y sudo
echo "$ZABBIX_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart $MONITORED_SERVICE" >> /etc/sudoers
echo "[OK] Sudoers configuré"

# ==============================
# NOTE : Pare-feu (UFW) supprimé volontairement
# ==============================
# Sur AWS EC2, le firewall réseau est géré par les Security Groups.
# Ouvre le port 10050/tcp côté Security Group de ton instance EC2.
# Activer UFW en plus peut bloquer SSH ou créer des conflits.
echo "[INFO] Pare-feu UFW ignoré (géré par AWS Security Groups)"
echo "[INFO] Assure-toi que le port $ZABBIX_AGENT_PORT/tcp est ouvert dans ton Security Group EC2"

# ==============================
# 6. Démarrage du service
# ==============================
echo "[6/7] Démarrage de zabbix-agent2..."
systemctl enable zabbix-agent2 --now \
    || { echo "[ERREUR] Démarrage de zabbix-agent2 échoué !"; exit 1; }
sleep 2
echo "[OK] Service démarré"

# ==============================
# 7. Enregistrement automatique de l'hôte via API Zabbix
# ==============================
echo "[7/7] Enregistrement de l'hôte '$ZABBIX_HOSTNAME' sur le serveur Zabbix via API..."

# Récupération de l'IP locale de la machine
LOCAL_IP=$(hostname -I | awk '{print $1}')

# Vérification si l'hôte existe déjà
EXISTING_HOST=$(curl -s -X POST "$ZABBIX_API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ZABBIX_API_TOKEN" \
    -d "{
        \"jsonrpc\": \"2.0\",
        \"method\": \"host.get\",
        \"params\": {
            \"filter\": { \"host\": [\"$ZABBIX_HOSTNAME\"] }
        },
        \"id\": 1
    }")

HOST_ID=$(echo "$EXISTING_HOST" | grep -o '"hostid":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$HOST_ID" ]; then
    echo "[INFO] Hôte '$ZABBIX_HOSTNAME' déjà présent (hostid=$HOST_ID), mise à jour..."

    curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ZABBIX_API_TOKEN" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"host.update\",
            \"params\": {
                \"hostid\": \"$HOST_ID\",
                \"interfaces\": [{
                    \"type\": 1,
                    \"main\": 1,
                    \"useip\": 1,
                    \"ip\": \"$LOCAL_IP\",
                    \"dns\": \"\",
                    \"port\": \"$ZABBIX_AGENT_PORT\"
                }],
                \"templates\": [{ \"templateid\": \"$ZABBIX_TEMPLATE_ID\" }],
                \"groups\": [{ \"groupid\": \"$ZABBIX_HOSTGROUP_ID\" }],
                \"status\": 0
            },
            \"id\": 2
        }" > /dev/null

    echo "[OK] Hôte mis à jour (IP: $LOCAL_IP)"
else
    echo "[INFO] Création de l'hôte '$ZABBIX_HOSTNAME' (IP: $LOCAL_IP)..."

    RESULT=$(curl -s -X POST "$ZABBIX_API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ZABBIX_API_TOKEN" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"host.create\",
            \"params\": {
                \"host\": \"$ZABBIX_HOSTNAME\",
                \"name\": \"$ZABBIX_HOSTNAME\",
                \"interfaces\": [{
                    \"type\": 1,
                    \"main\": 1,
                    \"useip\": 1,
                    \"ip\": \"$LOCAL_IP\",
                    \"dns\": \"\",
                    \"port\": \"$ZABBIX_AGENT_PORT\"
                }],
                \"groups\": [{ \"groupid\": \"$ZABBIX_HOSTGROUP_ID\" }],
                \"templates\": [{ \"templateid\": \"$ZABBIX_TEMPLATE_ID\" }],
                \"status\": 0
            },
            \"id\": 3
        }")

    NEW_HOST_ID=$(echo "$RESULT" | grep -o '"hostids":\["[^"]*"' | cut -d'"' -f3)

    if [ -n "$NEW_HOST_ID" ]; then
        echo "[OK] Hôte créé avec succès (hostid=$NEW_HOST_ID)"
    else
        echo "[AVERTISSEMENT] Réponse API : $RESULT"
        echo "[AVERTISSEMENT] L'hôte n'a pas pu être créé automatiquement."
        echo "    => Vérifiez ZABBIX_API_TOKEN, ZABBIX_HOSTGROUP_ID et ZABBIX_TEMPLATE_ID dans le .env"
    fi
fi

echo ""
echo "==============================="
echo " Installation terminée !"
echo " Agent connecté au serveur : $ZABBIX_SERVER_IP"
echo " Hôte enregistré            : $ZABBIX_HOSTNAME"
echo " IP de l'agent              : $LOCAL_IP"
echo "==============================="
