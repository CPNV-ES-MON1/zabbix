# ==============================
# Script d'installation Zabbix Agent 2 - Windows Server 2025
# Avec enregistrement automatique via API Zabbix
# ==============================

# Chargement du fichier .env
$envFile = ".\.env.windows"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*#') { return }
        if ($_ -match '^\s*$') { return }
        $key, $value = $_ -split '=', 2
        Set-Variable -Name $key.Trim() -Value $value.Trim() -Scope Script
    }
} else {
    Write-Host "[ERREUR] Fichier .env.windows introuvable !" -ForegroundColor Red
    exit 1
}

Write-Host "===============================" -ForegroundColor Cyan
Write-Host " Installation Zabbix Agent 2" -ForegroundColor Cyan
Write-Host " Serveur : $ZABBIX_SERVER_IP" -ForegroundColor Cyan
Write-Host " Hostname : $ZABBIX_HOSTNAME" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# ==============================
# 1. Téléchargement du MSI
# ==============================
Write-Host "[1/6] Téléchargement du MSI Zabbix $ZABBIX_VERSION..." -ForegroundColor Yellow
$msiPath = "$env:TEMP\zabbix_agent2.msi"
Invoke-WebRequest -Uri $ZABBIX_MSI_URL -OutFile $msiPath
Write-Host "[OK] MSI téléchargé" -ForegroundColor Green

# ==============================
# 2. Installation silencieuse
# ==============================
Write-Host "[2/6] Installation de l'agent..." -ForegroundColor Yellow
Start-Process msiexec -ArgumentList "/i `"$msiPath`" /qn SERVER=$ZABBIX_SERVER_IP SERVERACTIVE=$ZABBIX_SERVER_IP HOSTNAME=$ZABBIX_HOSTNAME" -Wait
Write-Host "[OK] Agent installé" -ForegroundColor Green

# ==============================
# 3. Démarrage du service
# ==============================
Write-Host "[3/6] Démarrage du service Zabbix Agent 2..." -ForegroundColor Yellow
Start-Service "Zabbix Agent 2"
Set-Service "Zabbix Agent 2" -StartupType Automatic
Write-Host "[OK] Service démarré" -ForegroundColor Green

# ==============================
# 4. Ouverture du pare-feu
# ==============================
Write-Host "[4/6] Ouverture du port $ZABBIX_AGENT_PORT dans le pare-feu..." -ForegroundColor Yellow
New-NetFirewallRule -DisplayName "Zabbix Agent" -Direction Inbound -Protocol TCP -LocalPort $ZABBIX_AGENT_PORT -Action Allow -ErrorAction SilentlyContinue
Write-Host "[OK] Port $ZABBIX_AGENT_PORT ouvert" -ForegroundColor Green

# ==============================
# 5. Démarrage du service surveillé
# ==============================
Write-Host "[5/6] Vérification du service $MONITORED_SERVICE..." -ForegroundColor Yellow
Start-Service $MONITORED_SERVICE -ErrorAction SilentlyContinue
Set-Service $MONITORED_SERVICE -StartupType Automatic -ErrorAction SilentlyContinue
Write-Host "[OK] Service $MONITORED_SERVICE configuré" -ForegroundColor Green

# ==============================
# 6. Enregistrement automatique de l'hôte via API Zabbix
# ==============================
Write-Host "[6/6] Enregistrement de l'hôte '$ZABBIX_HOSTNAME' sur le serveur Zabbix via API..." -ForegroundColor Yellow

# Récupération de l'IP locale
$LOCAL_IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1).IPAddress

$headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $ZABBIX_API_TOKEN"
}

# Vérification si l'hôte existe déjà
$checkBody = @{
    jsonrpc = "2.0"
    method  = "host.get"
    params  = @{
        filter = @{ host = @($ZABBIX_HOSTNAME) }
    }
    id      = 1
} | ConvertTo-Json -Depth 5

$checkResult = Invoke-RestMethod -Uri $ZABBIX_API_URL -Method Post -Headers $headers -Body $checkBody
$existingHostId = $checkResult.result[0].hostid

if ($existingHostId) {
    Write-Host "[INFO] Hôte '$ZABBIX_HOSTNAME' déjà présent (hostid=$existingHostId), mise à jour..." -ForegroundColor Yellow

    $updateBody = @{
        jsonrpc = "2.0"
        method  = "host.update"
        params  = @{
            hostid     = $existingHostId
            interfaces = @(@{
                type   = 1
                main   = 1
                useip  = 1
                ip     = $LOCAL_IP
                dns    = ""
                port   = $ZABBIX_AGENT_PORT
            })
            templates  = @(@{ templateid = $ZABBIX_TEMPLATE_ID })
            groups     = @(@{ groupid = $ZABBIX_HOSTGROUP_ID })
            status     = 0
        }
        id      = 2
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $ZABBIX_API_URL -Method Post -Headers $headers -Body $updateBody | Out-Null
    Write-Host "[OK] Hôte mis à jour (IP: $LOCAL_IP)" -ForegroundColor Green

} else {
    Write-Host "[INFO] Création de l'hôte '$ZABBIX_HOSTNAME' (IP: $LOCAL_IP)..." -ForegroundColor Yellow

    $createBody = @{
        jsonrpc = "2.0"
        method  = "host.create"
        params  = @{
            host       = $ZABBIX_HOSTNAME
            name       = $ZABBIX_HOSTNAME
            interfaces = @(@{
                type   = 1
                main   = 1
                useip  = 1
                ip     = $LOCAL_IP
                dns    = ""
                port   = $ZABBIX_AGENT_PORT
            })
            groups     = @(@{ groupid = $ZABBIX_HOSTGROUP_ID })
            templates  = @(@{ templateid = $ZABBIX_TEMPLATE_ID })
            status     = 0
        }
        id      = 3
    } | ConvertTo-Json -Depth 5

    $createResult = Invoke-RestMethod -Uri $ZABBIX_API_URL -Method Post -Headers $headers -Body $createBody

    if ($createResult.result.hostids) {
        $newId = $createResult.result.hostids[0]
        Write-Host "[OK] Hôte créé avec succès (hostid=$newId)" -ForegroundColor Green
    } else {
        Write-Host "[AVERTISSEMENT] Réponse API : $($createResult | ConvertTo-Json)" -ForegroundColor Red
        Write-Host "[AVERTISSEMENT] L'hôte n'a pas pu être créé automatiquement." -ForegroundColor Red
        Write-Host "    => Vérifiez ZABBIX_API_TOKEN, ZABBIX_HOSTGROUP_ID et ZABBIX_TEMPLATE_ID dans le .env.windows" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===============================" -ForegroundColor Cyan
Write-Host " Installation terminée !" -ForegroundColor Cyan
Write-Host " Agent connecté au serveur : $ZABBIX_SERVER_IP" -ForegroundColor Cyan
Write-Host " Hôte enregistré            : $ZABBIX_HOSTNAME" -ForegroundColor Cyan
Write-Host " IP de l'agent              : $LOCAL_IP" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan
