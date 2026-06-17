#!/bin/bash
# ============================================================
# Script de validation Zabbix Agent2 - Déploiement Docker
# Compatible AWS EC2
# ============================================================
 
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
else
    echo "[ERREUR] Fichier .env introuvable !"
    exit 1
fi
 
CONTAINER_NAME="${CONTAINER_NAME:-zabbix-agent2}"
AGENT_PORT="${AGENT_PORT:-10050}"
ZABBIX_SERVER_PORT="${ZABBIX_SERVER_PORT:-10051}"
 
echo "============================================"
echo " Validation Zabbix Agent2 (Docker)"
echo " Serveur   : $ZABBIX_SERVER:$ZABBIX_SERVER_PORT"
echo " Hostname  : ${CUSTOM_HOSTNAME:-$(hostname)}"
echo " Conteneur : $CONTAINER_NAME"
echo "============================================"
 
ERRORS=0
WARNINGS=0
 
# ============================================================
# 1. Vérification que le conteneur existe et tourne
# ============================================================
echo ""
echo "[1/9] Vérification du conteneur Docker..."
 
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
 
if [ -z "$CONTAINER_STATUS" ]; then
    echo "[ERREUR] Conteneur '$CONTAINER_NAME' introuvable !"
    ERRORS=$((ERRORS+1))
elif [ "$CONTAINER_STATUS" == "running" ]; then
    echo "[OK] Conteneur '$CONTAINER_NAME' est running"
else
    echo "[ERREUR] Conteneur '$CONTAINER_NAME' est en état : $CONTAINER_STATUS"
    RESTART_COUNT=$(docker inspect --format='{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null)
    echo "         Nombre de restarts : $RESTART_COUNT"
    echo "         => docker logs $CONTAINER_NAME"
    ERRORS=$((ERRORS+1))
fi
 
# ============================================================
# 2. Vérification des crash loops
# ============================================================
echo ""
echo "[2/9] Vérification des crash loops..."
 
RESTART_COUNT=$(docker inspect --format='{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null || echo "0")
 
if [ "$RESTART_COUNT" -eq 0 ]; then
    echo "[OK] Aucun restart détecté"
elif [ "$RESTART_COUNT" -lt 3 ]; then
    echo "[WARN] $RESTART_COUNT restart(s) détecté(s) (acceptable)"
    WARNINGS=$((WARNINGS+1))
else
    echo "[ERREUR] $RESTART_COUNT restarts détectés - le conteneur crash en boucle !"
    echo "         => docker logs $CONTAINER_NAME"
    ERRORS=$((ERRORS+1))
fi
 
# ============================================================
# 3. Vérification du port 10050 (écoute locale)
# ============================================================
echo ""
echo "[3/9] Vérification du port $AGENT_PORT (écoute locale)..."
 
if ss -tlnp | grep -q ":$AGENT_PORT"; then
    echo "[OK] Port $AGENT_PORT est ouvert localement"
else
    echo "[ERREUR] Port $AGENT_PORT n'est pas ouvert localement !"
    echo "         => Vérifie que --network host est bien utilisé"
    echo "         => ou que le port est exposé dans le docker run"
    ERRORS=$((ERRORS+1))
fi
 
# ============================================================
# 4. Vérification de la config dans le conteneur (doublon Server=)
# ============================================================
echo ""
echo "[4/9] Vérification de la configuration de l'agent..."
 
if [ "$CONTAINER_STATUS" == "running" ]; then
    SERVER_LINE=$(docker exec "$CONTAINER_NAME" grep -i "^Server=" /etc/zabbix/zabbix_agent2.conf 2>/dev/null || echo "")
    ACTIVE_LINE=$(docker exec "$CONTAINER_NAME" grep -i "^ServerActive=" /etc/zabbix/zabbix_agent2.conf 2>/dev/null || echo "")
    HOSTNAME_LINE=$(docker exec "$CONTAINER_NAME" grep -i "^Hostname=" /etc/zabbix/zabbix_agent2.conf 2>/dev/null || echo "")
 
    echo "    $SERVER_LINE"
    echo "    $ACTIVE_LINE"
    echo "    $HOSTNAME_LINE"
 
    # Détection doublon
    SERVER_VALUE=$(echo "$SERVER_LINE" | cut -d'=' -f2)
    FIRST=$(echo "$SERVER_VALUE" | cut -d',' -f1)
    SECOND=$(echo "$SERVER_VALUE" | cut -d',' -f2)
 
    if [ -n "$SECOND" ] && [ "$FIRST" == "$SECOND" ]; then
        echo "[ERREUR] IP dupliquée dans Server= : '$SERVER_VALUE'"
        echo "         => Supprimer ZBX_PASSIVESERVERS de la commande docker run"
        ERRORS=$((ERRORS+1))
    else
        echo "[OK] Configuration Server= valide"
    fi
else
    echo "[SKIP] Conteneur non running, vérification config ignorée"
fi
 
# ============================================================
# 5. Vérification de la connexion TCP vers le serveur Zabbix
# ============================================================
echo ""
echo "[5/9] Vérification de la connexion TCP vers $ZABBIX_SERVER:$ZABBIX_SERVER_PORT..."
 
if command -v nc &>/dev/null; then
    if nc -zw3 "$ZABBIX_SERVER" "$ZABBIX_SERVER_PORT" 2>/dev/null; then
        echo "[OK] Serveur $ZABBIX_SERVER accessible sur le port $ZABBIX_SERVER_PORT"
    else
        echo "[ERREUR] Serveur $ZABBIX_SERVER inaccessible sur le port $ZABBIX_SERVER_PORT !"
        echo "         => Vérifie le Security Group / firewall côté serveur Zabbix"
        ERRORS=$((ERRORS+1))
    fi
else
    echo "[SKIP] nc (netcat) non disponible - test TCP ignoré"
    echo "       => apt install netcat-openbsd pour activer ce test"
fi
 
# ============================================================
# 6. Vérification des permissions du socket Docker (hôte)
# ============================================================
echo ""
echo "[6/9] Vérification des permissions du socket Docker (hôte)..."
 
SOCK_PATH="/var/run/docker.sock"
 
if [ ! -S "$SOCK_PATH" ]; then
    echo "[ERREUR] Socket $SOCK_PATH introuvable sur l'hôte !"
    ERRORS=$((ERRORS+1))
else
    SOCK_PERMS=$(stat -c "%a" "$SOCK_PATH")
    SOCK_GROUP=$(stat -c "%G" "$SOCK_PATH")
    SOCK_OWNER=$(stat -c "%U" "$SOCK_PATH")
    echo "[OK] Socket présent : $SOCK_PATH"
    echo "     Propriétaire : $SOCK_OWNER | Groupe : $SOCK_GROUP | Permissions : $SOCK_PERMS"
 
    # Vérifier que le groupe a accès en écriture (permissions 660 ou 666)
    if [[ "$SOCK_PERMS" == "660" || "$SOCK_PERMS" == "666" || "$SOCK_PERMS" == "670" || "$SOCK_PERMS" == "676" ]]; then
        echo "[OK] Permissions du socket correctes ($SOCK_PERMS)"
    else
        echo "[WARN] Permissions inhabituelles sur le socket : $SOCK_PERMS"
        echo "       => Attendu : 660 (root:docker)"
        WARNINGS=$((WARNINGS+1))
    fi
 
    # Vérifier que l'utilisateur courant est dans le groupe docker
    CURRENT_USER=$(whoami)
    if id -nG "$CURRENT_USER" | grep -qw "$SOCK_GROUP"; then
        echo "[OK] L'utilisateur '$CURRENT_USER' est dans le groupe '$SOCK_GROUP'"
    else
        echo "[WARN] L'utilisateur '$CURRENT_USER' n'est PAS dans le groupe '$SOCK_GROUP'"
        echo "       => sudo usermod -aG $SOCK_GROUP $CURRENT_USER && newgrp $SOCK_GROUP"
        WARNINGS=$((WARNINGS+1))
    fi
fi
 
# ============================================================
# 7. Vérification des droits socket Docker dans le conteneur
# ============================================================
echo ""
echo "[7/9] Vérification de l'accès au socket Docker dans le conteneur..."
 
if [ "$CONTAINER_STATUS" == "running" ]; then
    DOCKER_SOCK_BIND=$(docker inspect --format='{{range .HostConfig.Binds}}{{.}} {{end}}' "$CONTAINER_NAME" 2>/dev/null \
        | tr ' ' '\n' | grep "docker.sock" || echo "")
 
    if [ -z "$DOCKER_SOCK_BIND" ]; then
        echo "[WARN] /var/run/docker.sock non monté dans le conteneur"
        echo "       => Certaines métriques Docker ne seront pas disponibles"
        WARNINGS=$((WARNINGS+1))
    else
        echo "[OK] docker.sock monté : $DOCKER_SOCK_BIND"
 
        # Vérifier que le socket est visible dans le conteneur
        # FIX: on redirige aussi stdout (>/dev/null 2>&1) pour ne tester
        # que le code de sortie de `ls`, sans polluer la variable avec
        # le chemin affiché par `ls` en cas de succès.
        if docker exec "$CONTAINER_NAME" ls /var/run/docker.sock >/dev/null 2>&1; then
            SOCK_IN_CONTAINER="ok"
        else
            SOCK_IN_CONTAINER="fail"
        fi
 
        if [ "$SOCK_IN_CONTAINER" == "ok" ]; then
            echo "[OK] Socket visible dans le conteneur"
        else
            echo "[ERREUR] Socket monté mais invisible dans le conteneur !"
            ERRORS=$((ERRORS+1))
        fi
 
        # Vérifier que l'utilisateur zabbix peut lire le socket (test via docker exec)
        SOCK_READABLE=$(docker exec --user zabbix "$CONTAINER_NAME" \
            sh -c 'test -r /var/run/docker.sock && echo ok || echo fail' 2>/dev/null || echo "fail")
        if [ "$SOCK_READABLE" == "ok" ]; then
            echo "[OK] L'utilisateur 'zabbix' peut lire le socket Docker"
        else
            echo "[WARN] L'utilisateur 'zabbix' ne peut PAS lire le socket Docker"
            echo "       => Le GID du groupe docker sur l'hôte doit correspondre dans le conteneur"
            echo "       => Solution : docker run --group-add \$(getent group docker | cut -d: -f3) ..."
            WARNINGS=$((WARNINGS+1))
        fi
    fi
else
    echo "[SKIP] Conteneur non running, vérification socket ignorée"
fi
 
# ============================================================
# 8. Vérification du mode privileged et des volumes système
# ============================================================
echo ""
echo "[8/9] Vérification du mode privileged et des volumes système..."
 
PRIVILEGED=$(docker inspect --format='{{.HostConfig.Privileged}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")
 
if [ "$PRIVILEGED" == "true" ]; then
    echo "[OK] Conteneur en mode --privileged"
else
    echo "[WARN] Conteneur NON privileged"
    echo "       => Certaines métriques système (/proc, /sys) peuvent être inaccessibles"
    WARNINGS=$((WARNINGS+1))
fi
 
REQUIRED_VOLUMES=("/proc:/proc:ro" "/sys:/sys:ro" "/run:/run:ro" "/etc/hostname:/etc/hostname:ro")
BINDS=$(docker inspect --format='{{range .HostConfig.Binds}}{{.}}|{{end}}' "$CONTAINER_NAME" 2>/dev/null)
 
for VOL in "${REQUIRED_VOLUMES[@]}"; do
    VOL_NAME=$(echo "$VOL" | cut -d: -f1)
    if echo "$BINDS" | grep -q "$VOL_NAME"; then
        echo "[OK] Volume monté : $VOL"
    else
        echo "[WARN] Volume manquant : $VOL"
        WARNINGS=$((WARNINGS+1))
    fi
done
 
# ============================================================
# 9. Test fonctionnel agent.ping via zabbix_get
# ============================================================
echo ""
echo "[9/9] Test fonctionnel agent.ping..."
 
if command -v zabbix_get &>/dev/null; then
    PING_RESULT=$(zabbix_get -s 127.0.0.1 -p "$AGENT_PORT" -k agent.ping 2>/dev/null || echo "fail")
    if [ "$PING_RESULT" == "1" ]; then
        echo "[OK] agent.ping retourne 1 - l'agent répond correctement"
    else
        echo "[ERREUR] agent.ping a échoué (résultat : $PING_RESULT)"
        echo "         => L'agent ne répond pas aux checks passifs"
        ERRORS=$((ERRORS+1))
    fi
else
    echo "[SKIP] zabbix_get non installé - test fonctionnel ignoré"
    echo "       => apt install zabbix-get pour activer ce test"
fi
 
# ============================================================
# Résultat final
# ============================================================
echo ""
echo "============================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo " Validation réussie ! Tout est OK."
elif [ $ERRORS -eq 0 ]; then
    echo " Validation OK avec $WARNINGS avertissement(s)."
    echo " Consultez les [WARN] ci-dessus."
else
    echo " Validation échouée !"
    echo " $ERRORS erreur(s) | $WARNINGS avertissement(s)"
    echo " Consultez les [ERREUR] ci-dessus pour corriger."
fi
echo "============================================"
 