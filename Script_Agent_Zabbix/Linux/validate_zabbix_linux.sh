#!/bin/bash
# ==============================
# Script de validation Zabbix Agent 2 - Debian (détection auto)
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
    echo "[OK] Port $ZABBIX_AGENT_PORT est ouvert localement"
else
    echo "[ERREUR] Port $ZABBIX_AGENT_PORT n'est pas ouvert localement !"
    ERRORS=$((ERRORS+1))
fi

# ==============================
# 3. Vérification de la connexion vers le serveur Zabbix
# ==============================
# NOTE : Le ping ICMP est bloqué par défaut entre instances AWS EC2.
# On utilise nc (netcat) pour tester le port TCP 10051 (port serveur Zabbix)
echo "[3/4] Vérification de la connexion TCP vers $ZABBIX_SERVER_IP:10051..."
if nc -zw3 "$ZABBIX_SERVER_IP" 10051 2>/dev/null; then
    echo "[OK] Serveur $ZABBIX_SERVER_IP accessible sur le port 10051"
else
    echo "[ERREUR] Serveur $ZABBIX_SERVER_IP inaccessible sur le port 10051 !"
    echo "    => Vérifie le Security Group de ton instance serveur Zabbix (port 10051/tcp entrant)"
    ERRORS=$((ERRORS+1))
fi

# ==============================
# 4. Vérification du service surveillé
# ==============================
echo "[4/4] Vérification du service $MONITORED_SERVICE..."
if systemctl is-active --quiet "$MONITORED_SERVICE"; then
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
