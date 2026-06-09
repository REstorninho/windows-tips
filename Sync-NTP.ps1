#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reconfigura o serviço Windows Time (W32Time) com servidores NTP portugueses.

.DESCRIPTION
    Para, desregista e volta a registar o serviço W32Time, configura peers NTP
    (OAL/UL + PT NTP Pool), força resync e apresenta o estado final.

.NOTES
    Requer execução como Administrador.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "    [ERRO] $Message" -ForegroundColor Red
}

# ── Verificar privilégios ──────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "O script não está a correr como Administrador. Abrir PowerShell elevado e repetir."
    exit 1
}

Write-Host "`n================================================" -ForegroundColor Yellow
Write-Host "   Reconfiguração do Windows Time Service (NTP)" -ForegroundColor Yellow
Write-Host "================================================`n" -ForegroundColor Yellow

# ── 1. Parar o serviço ────────────────────────────────────────────────────────
Write-Step "A parar o serviço W32Time..."
try {
    & net stop w32time 2>&1 | Out-Null
    Write-OK "Serviço parado."
} catch {
    Write-Fail "Falha ao parar o serviço: $_"
}

# ── 2. Desregistar ────────────────────────────────────────────────────────────
Write-Step "A desregistar o W32Time..."
try {
    & w32tm /unregister 2>&1 | Out-Null
    Write-OK "Desregisto concluído."
} catch {
    Write-Fail "Falha no desregisto: $_"
}

# ── 3. Registar de novo ───────────────────────────────────────────────────────
Write-Step "A registar o W32Time..."
try {
    & w32tm /register 2>&1 | Out-Null
    Write-OK "Registo concluído."
} catch {
    Write-Fail "Falha no registo: $_"
}

# ── 4. Iniciar o serviço ──────────────────────────────────────────────────────
Write-Step "A iniciar o serviço W32Time..."
try {
    & net start w32time 2>&1 | Out-Null
    Write-OK "Serviço iniciado."
} catch {
    Write-Fail "Falha ao iniciar o serviço: $_"
}

# ── 5. Configurar peers NTP ───────────────────────────────────────────────────
$ntpPeers = "ntp02.oal.ul.pt ntp04.oal.ul.pt 1.pt.pool.ntp.org"
Write-Step "A configurar peers NTP: $ntpPeers"
try {
    & w32tm /config /manualpeerlist:$ntpPeers /syncfromflags:manual /reliable:yes /update 2>&1 | Out-Null
    Write-OK "Peers configurados."
} catch {
    Write-Fail "Falha na configuração dos peers: $_"
}

# ── 6. Aplicar configuração ───────────────────────────────────────────────────
Write-Step "A aplicar configuração (/config /update)..."
try {
    & w32tm /config /update 2>&1 | Out-Null
    Write-OK "Configuração aplicada."
} catch {
    Write-Fail "Falha ao aplicar configuração: $_"
}

# ── 7. Forçar resync ──────────────────────────────────────────────────────────
Write-Step "A forçar ressincronização (/resync /rediscover)..."
try {
    & w32tm /resync /rediscover 2>&1 | Out-Null
    Write-OK "Resync iniciado."
} catch {
    Write-Fail "Falha no resync: $_"
}

# ── 8. Resultados ─────────────────────────────────────────────────────────────
Write-Host "`n------------------------------------------------" -ForegroundColor Yellow
Write-Host "   Fonte de sincronização actual:" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow
& w32tm /query /source

Write-Host "`n------------------------------------------------" -ForegroundColor Yellow
Write-Host "   Estado dos peers NTP:" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow
& w32tm /query /peers

Write-Host "`n================================================" -ForegroundColor Green
Write-Host "   Reconfiguração NTP concluída." -ForegroundColor Green
Write-Host "================================================`n" -ForegroundColor Green
