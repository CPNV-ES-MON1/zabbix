#!/bin/bash
# ============================================================
# Installation Zabbix Agent2 en Docker + Enregistrement auto
# Zabbix 7.0 - Authentification par API Token permanent
# ============================================================
set -e

# ---- Chargement de la configuration depuis .env ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "[ERREUR] Fichier .env introuvable dans $SCRIPT_DIR"
    echo "  Copiez .env.example vers .env et renseignez vos valeurs."
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

# ---- Vérification des variables obligatoires ----
REQUIRED_VARS=(ZABBIX_SERVER ZABBIX_SERVER_PORT ZABBIX_API_TOKEN AGENT_PORT CONTAINER_NAME ZBX_IMAGE HOST_GROUP_NAME TEMPLATE_NAME)
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "[ERREUR] Variable '$var' manquante dans le fichier .env"
        exit 1
    fi
done

ZABBIX_API_URL="http://$ZABBIX_SERVER/zabbix/api_jsonrpc.php"
HOSTNAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')

echo "============================================"
echo " Installation Zabbix Agent2 Docker"
echo " Serveur  : $ZABBIX_SERVER"
echo " Hostname : $HOSTNAME"
echo " IP       : $HOST_IP"
echo "============================================"

# ---- Vérifications préalables ----
if ! command -v docker &> /dev/null; then
    echo "[ERREUR] Docker n'est pas installé."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "[ERREUR] jq n'est pas installé : apt install jq"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "[ERREUR] curl n'est pas installé."
    exit 1
fi

# ---- Fonctions helper API ----
# Sans auth (apiinfo.version uniquement)
zabbix_api_noauth() {
  curl -s -X POST "$ZABBIX_API_URL" \
    -H "Content-Type: application/json" \
    -d "$1"
}

# Avec auth (tous les autres appels)
zabbix_api() {
  curl -s -X POST "$ZABBIX_API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ZABBIX_API_TOKEN" \
    -d "$1"
}

# ---- Test de connectivité API (sans Authorization) ----
echo "[INFO] Test de connexion à l'API Zabbix..."
API_VERSION=$(zabbix_api_noauth '{"jsonrpc":"2.0","method":"apiinfo.version","params":[],"id":1}' \
  | jq -r '.result' 2>/dev/null) || true

if [ -z "$API_VERSION" ] || [ "$API_VERSION" == "null" ]; then
    echo "[ERREUR] Impossible de joindre l'API Zabbix ($ZABBIX_API_URL)"
    exit 1
fi

echo "[OK] API Zabbix $API_VERSION accessible."

# ---- Suppression d'un éventuel conteneur existant ----
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[INFO] Suppression de l'ancien conteneur $CONTAINER_NAME..."
    docker rm -f "$CONTAINER_NAME"
fi

# ---- Lancement du conteneur Zabbix Agent2 ----
echo "[INFO] Démarrage du conteneur $CONTAINER_NAME..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --privileged \
    --network host \
    \
    -v /proc:/proc:ro \
    -v /sys:/sys:ro \
    -v /dev:/dev:ro \
    -v /run:/run:ro \
    -v /etc/hostname:/etc/hostname:ro \
    -v /etc/os-release:/etc/os-release:ro \
    \
    -v /var/run/docker.sock:/var/run/docker.sock \
    \
    -e ZBX_SERVER_HOST="$ZABBIX_SERVER" \
    -e ZBX_SERVER_PORT="$ZABBIX_SERVER_PORT" \
    -e ZBX_ACTIVE_ALLOW=true \
    -e ZBX_HOSTNAME="$HOSTNAME" \
    -e ZBX_PASSIVESERVERS="$ZABBIX_SERVER" \
    -e ZBX_LISTENPORT="$AGENT_PORT" \
    -e ZBX_ENABLEPERSISTENTBUFFER=true \
    -e ZBX_PERSISTENTBUFFERFILE=/var/lib/zabbix/buffer \
    \
    "$ZBX_IMAGE"

# ---- Vérification du conteneur ----
echo "[INFO] Attente du démarrage de l'agent (5s)..."
sleep 5

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[ERREUR] Le conteneur n'a pas démarré."
    echo "  docker logs $CONTAINER_NAME"
    exit 1
fi

echo "[OK] Conteneur démarré."

# ============================================================
# Enregistrement automatique via l'API Zabbix 7.0
# ============================================================

# ---- Récupération du groupid ----
echo "[INFO] Recherche du groupe '$HOST_GROUP_NAME'..."

GROUP_ID=$(zabbix_api "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"hostgroup.get\",
  \"params\": {
    \"output\": [\"groupid\", \"name\"],
    \"filter\": {\"name\": [\"$HOST_GROUP_NAME\"]}
  },
  \"id\": 2
}" | jq -r '.result[0].groupid') || true

if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
    echo "[ERREUR] Groupe '$HOST_GROUP_NAME' introuvable. Groupes disponibles :"
    zabbix_api '{"jsonrpc":"2.0","method":"hostgroup.get","params":{"output":["groupid","name"]},"id":2}' \
      | jq -r '.result[] | "  - \(.groupid) : \(.name)"'
    exit 1
fi

echo "[OK] Groupe : '$HOST_GROUP_NAME' (ID=$GROUP_ID)"

# ---- Récupération du templateid ----
echo "[INFO] Recherche du template '$TEMPLATE_NAME'..."

TEMPLATE_ID=$(zabbix_api "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"template.get\",
  \"params\": {
    \"output\": [\"templateid\", \"name\"],
    \"filter\": {\"name\": [\"$TEMPLATE_NAME\"]}
  },
  \"id\": 3
}" | jq -r '.result[0].templateid') || true

if [ -z "$TEMPLATE_ID" ] || [ "$TEMPLATE_ID" == "null" ]; then
    echo "[ERREUR] Template '$TEMPLATE_NAME' introuvable. Templates disponibles :"
    zabbix_api '{"jsonrpc":"2.0","method":"template.get","params":{"output":["templateid","name"]},"id":3}' \
      | jq -r '.result[] | "  - \(.templateid) : \(.name)"'
    exit 1
fi

echo "[OK] Template : '$TEMPLATE_NAME' (ID=$TEMPLATE_ID)"

# ---- Vérification si l'hôte existe déjà ----
echo "[INFO] Vérification si '$HOSTNAME' existe déjà..."

EXISTING_HOST=$(zabbix_api "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"host.get\",
  \"params\": {
    \"output\": [\"hostid\"],
    \"filter\": {\"host\": [\"$HOSTNAME\"]}
  },
  \"id\": 4
}" | jq -r '.result[0].hostid') || true

if [ -n "$EXISTING_HOST" ] && [ "$EXISTING_HOST" != "null" ]; then
    echo "[WARN] L'hôte '$HOSTNAME' existe déjà (ID=$EXISTING_HOST). Pas de création."
else
    echo "[INFO] Création de l'hôte '$HOSTNAME'..."

    CREATE_RESULT=$(zabbix_api "{
      \"jsonrpc\": \"2.0\",
      \"method\": \"host.create\",
      \"params\": {
        \"host\": \"$HOSTNAME\",
        \"interfaces\": [{
          \"type\": 1,
          \"main\": 1,
          \"useip\": 1,
          \"ip\": \"$HOST_IP\",
          \"dns\": \"\",
          \"port\": \"$AGENT_PORT\"
        }],
        \"groups\": [{\"groupid\": \"$GROUP_ID\"}],
        \"templates\": [{\"templateid\": \"$TEMPLATE_ID\"}]
      },
      \"id\": 5
    }")

    HOST_ID=$(echo "$CREATE_RESULT" | jq -r '.result.hostids[0]') || true

    if [ -z "$HOST_ID" ] || [ "$HOST_ID" == "null" ]; then
        echo "[ERREUR] Création de l'hôte échouée :"
        echo "$CREATE_RESULT" | jq .
        exit 1
    fi

    echo "[OK] Hôte créé ! ID=$HOST_ID"
fi

# ---- Résumé final ----
echo ""
echo "============================================"
echo " Déploiement terminé avec succès !"
echo "============================================"
echo " Conteneur : $CONTAINER_NAME"
echo " Hostname  : $HOSTNAME"
echo " IP        : $HOST_IP"
echo " Serveur   : $ZABBIX_SERVER:$ZABBIX_SERVER_PORT"
echo " Groupe    : $HOST_GROUP_NAME (ID=$GROUP_ID)"
echo " Template  : $TEMPLATE_NAME (ID=$TEMPLATE_ID)"
echo ""
echo " Logs du conteneur :"
echo "   docker logs -f $CONTAINER_NAME"
echo "============================================"
