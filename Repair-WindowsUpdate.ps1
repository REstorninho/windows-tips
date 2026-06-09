#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows Update Repair Tool

.DESCRIPTION
    Para os serviços relacionados ao Windows Update, limpa o repositório
    SoftwareDistribution, reinicia os serviços e força uma nova detecção de atualizações.

.NOTES
    Deve ser executado como Administrador.
#>

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[$Step] $Message" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Write-Success { param([string]$Msg) Write-Host "  [OK] $Msg"    -ForegroundColor Green  }
function Write-Warn    { param([string]$Msg) Write-Host "  [!!] $Msg"    -ForegroundColor Yellow }
function Write-Fail    { param([string]$Msg) Write-Host "  [ERRO] $Msg"  -ForegroundColor Red    }

# ──────────────────────────────────────────────────────────────────────────────
# Header
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "====================================" -ForegroundColor Green
Write-Host " Windows Update Repair Tool"          -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────
# [1/4] Parar serviços
# ──────────────────────────────────────────────────────────────────────────────

$services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')

Write-Step "1/4" "A parar serviços do Windows Update..."

foreach ($svc in $services) {
    try {
        $s = Get-Service -Name $svc -ErrorAction Stop
        if ($s.Status -ne 'Stopped') {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            Write-Success "Serviço '$svc' parado."
        } else {
            Write-Warn "Serviço '$svc' já estava parado."
        }
    } catch {
        Write-Fail "Não foi possível parar '$svc': $($_.Exception.Message)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# [2/4] Limpar repositório SoftwareDistribution
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "2/4" "A limpar o repositório SoftwareDistribution..."

$sdPath    = "$env:SystemRoot\SoftwareDistribution"
$sdOldPath = "$env:SystemRoot\SoftwareDistribution.old"

# Remove backup antigo se existir
if (Test-Path $sdOldPath) {
    try {
        Remove-Item -Path $sdOldPath -Recurse -Force -ErrorAction Stop
        Write-Success "Backup antigo '$sdOldPath' removido."
    } catch {
        Write-Warn "Não foi possível remover o backup antigo: $($_.Exception.Message)"
    }
}

# Renomeia a pasta actual como backup
if (Test-Path $sdPath) {
    try {
        Rename-Item -Path $sdPath -NewName "SoftwareDistribution.old" -Force -ErrorAction Stop
        Write-Success "'$sdPath' renomeado para SoftwareDistribution.old."
    } catch {
        Write-Fail "Não foi possível renomear '$sdPath': $($_.Exception.Message)"

        # Fallback: tenta apagar directamente
        Write-Warn "A tentar remoção directa como fallback..."
        try {
            Remove-Item -Path $sdPath -Recurse -Force -ErrorAction Stop
            Write-Success "'$sdPath' removido directamente."
        } catch {
            Write-Fail "Falhou o fallback: $($_.Exception.Message)"
        }
    }
} else {
    Write-Warn "Pasta '$sdPath' não encontrada. Nada a limpar."
}

# ──────────────────────────────────────────────────────────────────────────────
# [3/4] Reiniciar serviços
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "3/4" "A reiniciar serviços do Windows Update..."

foreach ($svc in $services) {
    try {
        Start-Service -Name $svc -ErrorAction Stop
        Write-Success "Serviço '$svc' iniciado."
    } catch {
        Write-Fail "Não foi possível iniciar '$svc': $($_.Exception.Message)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# [4/4] Forçar detecção de atualizações
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "4/4" "A forçar detecção de atualizações..."

try {
    # wuauclt legado (funciona em todas as versões)
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow

    # UsoClient (Windows 10/11 e Server 2016+) — mais fiável
    $usoClient = "$env:SystemRoot\System32\UsoClient.exe"
    if (Test-Path $usoClient) {
        Start-Process -FilePath $usoClient -ArgumentList "StartScan" -NoNewWindow
        Write-Success "UsoClient.exe StartScan disparado."
    }

    Write-Success "wuauclt.exe /detectnow disparado."
} catch {
    Write-Fail "Erro ao forçar detecção: $($_.Exception.Message)"
}

# ──────────────────────────────────────────────────────────────────────────────
# Resumo final
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "====================================" -ForegroundColor Green
Write-Host " Reparação concluída."               -ForegroundColor Green
Write-Host " Aguarda alguns minutos e abre o"   -ForegroundColor Green
Write-Host " Windows Update para verificar."    -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host ""
