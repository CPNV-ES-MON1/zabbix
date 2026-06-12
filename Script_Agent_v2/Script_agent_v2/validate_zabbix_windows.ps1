# ==============================
# Script de validation Zabbix Agent 2 - Windows Server 2025
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
Write-Host " Validation Zabbix Agent 2" -ForegroundColor Cyan
Write-Host " Serveur : $ZABBIX_SERVER_IP" -ForegroundColor Cyan
Write-Host " Hostname : $ZABBIX_HOSTNAME" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

$errors = 0

# ==============================
# 1. Vérification du service Zabbix Agent 2
# ==============================
Write-Host "[1/4] Vérification du service Zabbix Agent 2..." -ForegroundColor Yellow
$svc = Get-Service "Zabbix Agent 2" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host "[OK] Zabbix Agent 2 est running" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Zabbix Agent 2 n'est pas running !" -ForegroundColor Red
    $errors++
}

# ==============================
# 2. Vérification du port 10050
# ==============================
Write-Host "[2/4] Vérification du port $ZABBIX_AGENT_PORT..." -ForegroundColor Yellow
$port = netstat -an | findstr $ZABBIX_AGENT_PORT
if ($port) {
    Write-Host "[OK] Port $ZABBIX_AGENT_PORT est ouvert" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Port $ZABBIX_AGENT_PORT n'est pas ouvert !" -ForegroundColor Red
    $errors++
}

# ==============================
# 3. Vérification de la connexion vers le serveur
# ==============================
Write-Host "[3/4] Vérification de la connexion vers $ZABBIX_SERVER_IP..." -ForegroundColor Yellow
if (Test-Connection -ComputerName $ZABBIX_SERVER_IP -Count 1 -Quiet) {
    Write-Host "[OK] Serveur $ZABBIX_SERVER_IP accessible" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Serveur $ZABBIX_SERVER_IP inaccessible !" -ForegroundColor Red
    $errors++
}

# ==============================
# 4. Vérification du service surveillé W32Time
# ==============================
Write-Host "[4/4] Vérification du service $MONITORED_SERVICE..." -ForegroundColor Yellow
$monitored = Get-Service $MONITORED_SERVICE -ErrorAction SilentlyContinue
if ($monitored -and $monitored.Status -eq "Running") {
    Write-Host "[OK] $MONITORED_SERVICE est running" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] $MONITORED_SERVICE n'est pas running !" -ForegroundColor Red
    $errors++
}

# ==============================
# Résultat final
# ==============================
Write-Host ""
Write-Host "===============================" -ForegroundColor Cyan
if ($errors -eq 0) {
    Write-Host " Validation réussie ! Tous les services sont OK" -ForegroundColor Green
} else {
    Write-Host " Validation échouée ! $errors erreur(s) détectée(s)" -ForegroundColor Red
}
Write-Host "===============================" -ForegroundColor Cyan

exit $errors
