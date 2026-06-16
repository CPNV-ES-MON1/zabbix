# ==============================
# Script de validation Zabbix Agent 2 - Windows
# Compatible AWS EC2 Windows
# Executer en tant qu'Administrateur :
#   PowerShell -ExecutionPolicy Bypass -File validate_zabbix_windows.ps1
# ==============================

# ==============================
# Chargement du fichier .env
# ==============================
$EnvFile = ".\.env.windows.txt"
if (-Not (Test-Path $EnvFile)) {
    Write-Host "[ERREUR] Fichier .env.windows.txt introuvable !" -ForegroundColor Red
    exit 1
}

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
Write-Host " Validation Zabbix Agent 2 - Windows"
Write-Host " Serveur  : $ZABBIX_SERVER_IP"
Write-Host " Hostname : $ZABBIX_HOSTNAME"
Write-Host "===============================" -ForegroundColor Cyan

$ERRORS = 0

# ==============================
# 1. Vérification du service Zabbix Agent 2
# ==============================
Write-Host "[1/4] Vérification du service Zabbix Agent 2..."

$Service = Get-Service -Name "Zabbix Agent 2" -ErrorAction SilentlyContinue

if ($Service -and $Service.Status -eq "Running") {
    Write-Host "[OK] Zabbix Agent 2 est running" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Zabbix Agent 2 n'est pas running !" -ForegroundColor Red
    $ERRORS++
}

# ==============================
# 2. Vérification du port local 10050
# ==============================
Write-Host "[2/4] Vérification du port $ZABBIX_AGENT_PORT en écoute..."

$PortOpen = Get-NetTCPConnection -LocalPort $ZABBIX_AGENT_PORT -State Listen -ErrorAction SilentlyContinue

if ($PortOpen) {
    Write-Host "[OK] Port $ZABBIX_AGENT_PORT est en écoute localement" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Port $ZABBIX_AGENT_PORT n'est pas en écoute !" -ForegroundColor Red
    $ERRORS++
}

# ==============================
# 3. Vérification de la connexion TCP vers le serveur Zabbix
# ==============================
# NOTE : Le ping ICMP est bloqué par défaut entre instances AWS EC2.
# On teste directement le port TCP 10051 (port d'écoute du serveur Zabbix).
Write-Host "[3/4] Vérification de la connexion TCP vers $ZABBIX_SERVER_IP`:10051..."

try {
    $TcpClient = New-Object System.Net.Sockets.TcpClient
    $Connect   = $TcpClient.BeginConnect($ZABBIX_SERVER_IP, 10051, $null, $null)
    $Wait      = $Connect.AsyncWaitHandle.WaitOne(3000, $false)

    if ($Wait -and $TcpClient.Connected) {
        Write-Host "[OK] Serveur $ZABBIX_SERVER_IP accessible sur le port 10051" -ForegroundColor Green
    } else {
        Write-Host "[ERREUR] Serveur $ZABBIX_SERVER_IP inaccessible sur le port 10051 !" -ForegroundColor Red
        Write-Host "    => Vérifie le Security Group du serveur Zabbix (port 10051/tcp entrant)" -ForegroundColor Yellow
        $ERRORS++
    }
    $TcpClient.Close()
} catch {
    Write-Host "[ERREUR] Test de connexion échoué : $_" -ForegroundColor Red
    $ERRORS++
}

# ==============================
# 4. Vérification du service Windows surveillé
# ==============================
Write-Host "[4/4] Vérification du service Windows '$MONITORED_SERVICE'..."

$MonitoredSvc = Get-Service -Name $MONITORED_SERVICE -ErrorAction SilentlyContinue

if ($MonitoredSvc -and $MonitoredSvc.Status -eq "Running") {
    Write-Host "[OK] $MONITORED_SERVICE est running" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] $MONITORED_SERVICE n'est pas running !" -ForegroundColor Red
    $ERRORS++
}

# ==============================
# Résultat final
# ==============================
Write-Host ""
Write-Host "===============================" -ForegroundColor Cyan
if ($ERRORS -eq 0) {
    Write-Host " Validation réussie ! Tous les services sont OK" -ForegroundColor Green
} else {
    Write-Host " Validation échouée ! $ERRORS erreur(s) détectée(s)" -ForegroundColor Red
}
Write-Host "===============================" -ForegroundColor Cyan

exit $ERRORS
