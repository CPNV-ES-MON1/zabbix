#!/bin/bash
# ==============================
# Script de validation Zabbix Agent 2 - Debian 13
# ==============================

# Chargement du fichier .env
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "[ERREUR] Fichier .env introuvable !"
    exit 1
fi

echo "==============================="
echo " Validation Zabbix Agent 2"
echo " Serveur : $ZABBIX_SERVER_IP"
echo " Hostname : $ZABBIX_HOSTNAME"
echo "==============================="

ERRORS=0

# ==============================
# 1. Vérification du service zabbix-agent2
# ==============================
echo "[1/4] Vérification du service zabbix-agent2..."
if systemctl is-active --quiet zabbix-agent2; then
    echo "[OK] zabbix-agent2 est running"
else
    echo "[ERREUR] zabbix-agent2 n'est pas running !"
    ERRORS=$((ERRORS+1))
fi

# ==============================
# 2. Vérification du port 10050
# ==============================
echo "[2/4] Vérification du port $ZABBIX_AGENT_PORT..."
if ss -tlnp | grep -q "$ZABBIX_AGENT_PORT"; then
    echo "[OK] Port $ZABBIX_AGENT_PORT est ouvert"
else
    echo "[ERREUR] Port $ZABBIX_AGENT_PORT n'est pas ouvert !"
    ERRORS=$((ERRORS+1))
fi

# ==============================
# 3. Vérification de la connexion vers le serveur
# ==============================
echo "[3/4] Vérification de la connexion vers $ZABBIX_SERVER_IP..."
if ping -c 1 -W 2 $ZABBIX_SERVER_IP > /dev/null 2>&1; then
    echo "[OK] Serveur $ZABBIX_SERVER_IP accessible"
else
    echo "[ERREUR] Serveur $ZABBIX_SERVER_IP inaccessible !"
    ERRORS=$((ERRORS+1))
fi

# ==============================
# 4. Vérification du service surveillé
# ==============================
echo "[4/4] Vérification du service $MONITORED_SERVICE..."
if systemctl is-active --quiet $MONITORED_SERVICE; then
    echo "[OK] $MONITORED_SERVICE est running"
else
    echo "[ERREUR] $MONITORED_SERVICE n'est pas running !"
    ERRORS=$((ERRORS+1))
fi

# ==============================
# Résultat final
# ==============================
echo ""
echo "==============================="
if [ $ERRORS -eq 0 ]; then
    echo " Validation réussie ! Tous les services sont OK"
else
    echo " Validation échouée ! $ERRORS erreur(s) détectée(s)"
fi
echo "==============================="

exit $ERRORS
