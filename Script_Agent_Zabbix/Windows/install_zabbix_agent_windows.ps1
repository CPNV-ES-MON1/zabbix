# ==============================
# Script d'installation Zabbix Agent 2 - Windows
# Avec enregistrement automatique via API Zabbix
# Compatible AWS EC2 Windows
# Executer en tant qu'Administrateur :
#   PowerShell -ExecutionPolicy Bypass -File install_zabbix_agent_windows.ps1
# ==============================

# ==============================
# Chargement du fichier .env
# ==============================
$EnvFile = ".\.env.windows.txt"
if (-Not (Test-Path $EnvFile)) {
    Write-Host "[ERREUR] Fichier .env.windows.txt introuvable !" -ForegroundColor Red
    exit 1
}

# Lecture et chargement des variables (ignore les commentaires et lignes vides)
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    $parts = $_ -split '=', 2
    if ($parts.Count -eq 2) {
        $key   = $parts[0].Trim()
        $value = $parts[1].Trim()
        Set-Variable -Name $key -Value $value -Scope Script
    }
}

Write-Host "===============================" -ForegroundColor Cyan
Write-Host " Installation Zabbix Agent 2 - Windows"
Write-Host " Serveur  : $ZABBIX_SERVER_IP"
Write-Host " Hostname : $ZABBIX_HOSTNAME"
Write-Host "===============================" -ForegroundColor Cyan

# ==============================
# Vérification droits administrateur
# ==============================
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERREUR] Ce script doit être exécuté en tant qu'Administrateur !" -ForegroundColor Red
    exit 1
}

# ==============================
# 1. Téléchargement de l'installeur Zabbix Agent 2
# ==============================
Write-Host "[1/6] Téléchargement de Zabbix Agent 2 v$ZABBIX_VERSION..."

$InstallerUrl  = "https://cdn.zabbix.com/zabbix/binaries/stable/$ZABBIX_VERSION/$ZABBIX_VERSION.0/zabbix_agent2-$ZABBIX_VERSION.0-windows-amd64-openssl.msi"
$InstallerPath = "$env:TEMP\zabbix_agent2.msi"

try {
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
    Write-Host "[OK] Installeur téléchargé" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Téléchargement échoué : $_" -ForegroundColor Red
    exit 1
}

# ==============================
# 2. Installation silencieuse via MSI
# ==============================
Write-Host "[2/6] Installation silencieuse de Zabbix Agent 2..."

$MsiArgs = @(
    "/i", $InstallerPath,
    "/qn",
    "SERVER=$ZABBIX_SERVER_IP",
    "SERVERACTIVE=$ZABBIX_SERVER_IP",
    "HOSTNAME=$ZABBIX_HOSTNAME",
    "LISTENPORT=$ZABBIX_AGENT_PORT"
)

$Install = Start-Process -FilePath "msiexec.exe" -ArgumentList $MsiArgs -Wait -PassThru

if ($Install.ExitCode -ne 0) {
    Write-Host "[ERREUR] Installation MSI échouée (code : $($Install.ExitCode))" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Zabbix Agent 2 installé" -ForegroundColor Green

# ==============================
# 3. Configuration de l'agent (zabbix_agent2.conf)
# ==============================
Write-Host "[3/6] Configuration de l'agent..."

$ConfPath = "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf"

if (-Not (Test-Path $ConfPath)) {
    Write-Host "[ERREUR] Fichier de config introuvable : $ConfPath" -ForegroundColor Red
    exit 1
}

# Remplacement des directives clés
(Get-Content $ConfPath) | ForEach-Object {
    $_ -replace '^Server=.*',       "Server=$ZABBIX_SERVER_IP" `
       -replace '^ServerActive=.*', "ServerActive=$ZABBIX_SERVER_IP" `
       -replace '^Hostname=.*',     "Hostname=$ZABBIX_HOSTNAME" `
       -replace '^ListenPort=.*',   "ListenPort=$ZABBIX_AGENT_PORT"
} | Set-Content $ConfPath

# Ajout AllowKey et DebugLevel si absents
$ConfContent = Get-Content $ConfPath -Raw
if ($ConfContent -notmatch 'AllowKey=system\.run') {
    Add-Content $ConfPath "`nAllowKey=system.run[*]"
}
if ($ConfContent -notmatch '^DebugLevel=') {
    Add-Content $ConfPath "`nDebugLevel=4"
}

Write-Host "[OK] Agent configuré" -ForegroundColor Green

# ==============================
# 4. Ouverture du port pare-feu Windows
# ==============================
# NOTE : Sur AWS EC2 Windows, le pare-feu réseau est géré par les Security Groups.
# Cette règle ouvre le pare-feu LOCAL de Windows (nécessaire quand même).
# Pense à ouvrir le port 10050/tcp entrant dans ton Security Group EC2 aussi.
Write-Host "[4/6] Ouverture du port $ZABBIX_AGENT_PORT/tcp dans le pare-feu Windows..."

$RuleName = "Zabbix Agent 2"
$ExistingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

if ($ExistingRule) {
    Write-Host "[INFO] Règle pare-feu déjà présente, mise à jour..." -ForegroundColor Yellow
    Set-NetFirewallRule -DisplayName $RuleName -LocalPort $ZABBIX_AGENT_PORT
} else {
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $ZABBIX_AGENT_PORT `
        -Action Allow | Out-Null
}
Write-Host "[OK] Pare-feu configuré (port $ZABBIX_AGENT_PORT/tcp)" -ForegroundColor Green
Write-Host "[INFO] N'oublie pas d'ouvrir le port $ZABBIX_AGENT_PORT/tcp dans ton Security Group AWS" -ForegroundColor Yellow

# ==============================
# 5. Démarrage du service Zabbix Agent 2
# ==============================
Write-Host "[5/6] Démarrage du service Zabbix Agent 2..."

try {
    Set-Service -Name "Zabbix Agent 2" -StartupType Automatic
    Start-Service -Name "Zabbix Agent 2"
    Start-Sleep -Seconds 2
    Write-Host "[OK] Service démarré" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] Démarrage du service échoué : $_" -ForegroundColor Red
    exit 1
}

# ==============================
# 6. Enregistrement automatique via API Zabbix
# ==============================
Write-Host "[6/6] Enregistrement de l'hôte '$ZABBIX_HOSTNAME' sur le serveur Zabbix via API..."

# Récupération de l'IP locale
$LOCAL_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169'
} | Select-Object -First 1).IPAddress

$Headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $ZABBIX_API_TOKEN"
}

# Vérification si l'hôte existe déjà
$CheckBody = @{
    jsonrpc = "2.0"
    method  = "host.get"
    params  = @{ filter = @{ host = @($ZABBIX_HOSTNAME) } }
    id      = 1
} | ConvertTo-Json -Depth 5

try {
    $CheckResponse = Invoke-RestMethod -Uri $ZABBIX_API_URL -Method POST -Headers $Headers -Body $CheckBody
    $HOST_ID = $CheckResponse.result[0].hostid
} catch {
    Write-Host "[AVERTISSEMENT] Impossible de contacter l'API Zabbix : $_" -ForegroundColor Yellow
    $HOST_ID = $null
}

if ($HOST_ID) {
    Write-Host "[INFO] Hôte '$ZABBIX_HOSTNAME' déjà présent (hostid=$HOST_ID), mise à jour..." -ForegroundColor Yellow

    $UpdateBody = @{
        jsonrpc = "2.0"
        method  = "host.update"
        params  = @{
            hostid     = $HOST_ID
            interfaces = @(@{
                type   = 1; main = 1; useip = 1
                ip     = $LOCAL_IP; dns = ""; port = $ZABBIX_AGENT_PORT
            })
            templates  = @(@{ templateid = $ZABBIX_TEMPLATE_ID })
            groups     = @(@{ groupid = $ZABBIX_HOSTGROUP_ID })
            status     = 0
        }
        id = 2
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $ZABBIX_API_URL -Method POST -Headers $Headers -Body $UpdateBody | Out-Null
    Write-Host "[OK] Hôte mis à jour (IP: $LOCAL_IP)" -ForegroundColor Green

} else {
    Write-Host "[INFO] Création de l'hôte '$ZABBIX_HOSTNAME' (IP: $LOCAL_IP)..."

    $CreateBody = @{
        jsonrpc = "2.0"
        method  = "host.create"
        params  = @{
            host       = $ZABBIX_HOSTNAME
            name       = $ZABBIX_HOSTNAME
            interfaces = @(@{
                type   = 1; main = 1; useip = 1
                ip     = $LOCAL_IP; dns = ""; port = $ZABBIX_AGENT_PORT
            })
            groups     = @(@{ groupid = $ZABBIX_HOSTGROUP_ID })
            templates  = @(@{ templateid = $ZABBIX_TEMPLATE_ID })
            status     = 0
        }
        id = 3
    } | ConvertTo-Json -Depth 10

    try {
        $CreateResponse = Invoke-RestMethod -Uri $ZABBIX_API_URL -Method POST -Headers $Headers -Body $CreateBody
        $NEW_HOST_ID = $CreateResponse.result.hostids[0]

        if ($NEW_HOST_ID) {
            Write-Host "[OK] Hôte créé avec succès (hostid=$NEW_HOST_ID)" -ForegroundColor Green
        } else {
            Write-Host "[AVERTISSEMENT] Réponse API : $($CreateResponse | ConvertTo-Json)" -ForegroundColor Yellow
            Write-Host "[AVERTISSEMENT] L'hôte n'a pas pu être créé automatiquement." -ForegroundColor Yellow
            Write-Host "    => Vérifiez ZABBIX_API_TOKEN, ZABBIX_HOSTGROUP_ID et ZABBIX_TEMPLATE_ID dans le .env" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[ERREUR] Appel API échoué : $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===============================" -ForegroundColor Cyan
Write-Host " Installation terminée !"
Write-Host " Agent connecté au serveur : $ZABBIX_SERVER_IP"
Write-Host " Hôte enregistré            : $ZABBIX_HOSTNAME"
Write-Host " IP de l'agent              : $LOCAL_IP"
Write-Host "===============================" -ForegroundColor Cyan
