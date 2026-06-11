#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows Update Repair Tool

.DESCRIPTION
    Para os serviços relacionados ao Windows Update, apaga o repositório
    SoftwareDistribution, reinicia os serviços e força uma nova detecção de atualizações.

.NOTES
    Deve ser executado como Administrador.
    v2 — fixes: encoding UTF-8, WaitForStatus, takeown fallback, DISM/SFC opcional.
#>

# ──────────────────────────────────────────────────────────────────────────────
# Fix de encoding — garante output correcto em PowerShell 5.x (CP850/CP1252)
# ──────────────────────────────────────────────────────────────────────────────
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding        = [System.Text.Encoding]::UTF8

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host ""
    Write-Host "[$Step] $Message" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor DarkGray
}

function Write-Success { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green  }
function Write-Warn    { param([string]$Msg) Write-Host "  [!!]   $Msg" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Msg) Write-Host "  [ERRO] $Msg" -ForegroundColor Red    }

# ──────────────────────────────────────────────────────────────────────────────
# Header
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "====================================" -ForegroundColor Green
Write-Host " Windows Update Repair Tool v2"      -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────
# [1/5] Parar serviços — com WaitForStatus para evitar race condition
# ──────────────────────────────────────────────────────────────────────────────

$services = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
$waitTimeout = New-TimeSpan -Seconds 30

Write-Step "1/5" "A parar serviços do Windows Update..."

foreach ($svc in $services) {
    try {
        $s = Get-Service -Name $svc -ErrorAction Stop
        if ($s.Status -ne 'Stopped') {
            Stop-Service -Name $svc -Force -ErrorAction Stop
            # Aguarda confirmação efectiva do SCM antes de prosseguir
            $s.WaitForStatus('Stopped', $waitTimeout)
            Write-Success "Serviço '$svc' parado."
        } else {
            Write-Warn "Serviço '$svc' já estava parado."
        }
    } catch {
        Write-Fail "Não foi possível parar '$svc': $($_.Exception.Message)"
    }
}

# Pausa adicional para libertação de handles de ficheiros pelo kernel
Write-Host "  [..] A aguardar libertação de handles..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

# ──────────────────────────────────────────────────────────────────────────────
# [2/5] Apagar repositório SoftwareDistribution — com fallback takeown/icacls
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "2/5" "A apagar o repositório SoftwareDistribution..."

$foldersToDelete = @(
    "$env:SystemRoot\SoftwareDistribution.old",
    "$env:SystemRoot\SoftwareDistribution"
)

foreach ($folder in $foldersToDelete) {
    if (-not (Test-Path $folder)) {
        Write-Warn "'$folder' não encontrada. Nada a apagar."
        continue
    }

    # Tentativa 1 — remoção directa
    $removed = $false
    try {
        Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
        Write-Success "'$folder' apagado com sucesso."
        $removed = $true
    } catch {
        Write-Warn "Remoção directa falhou ($($_.Exception.Message)) — a tentar takeown + icacls..."
    }

    # Tentativa 2 — takeown/icacls como fallback (só se a tentativa 1 falhou)
    if (-not $removed) {
        $null = & takeown.exe /F $folder /R /D Y 2>&1
        $null = & icacls.exe $folder /grant "Administrators:(OI)(CI)F" /T /C /Q 2>&1
        try {
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Success "'$folder' apagado via takeown."
        } catch {
            Write-Fail "Não foi possível apagar '$folder' mesmo após takeown: $($_.Exception.Message)"
            Write-Warn "Reinicia o sistema e corre novamente, ou apaga manualmente em modo de segurança."
        }
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# [3/5] Reiniciar serviços
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "3/5" "A reiniciar serviços do Windows Update..."

foreach ($svc in $services) {
    try {
        Start-Service -Name $svc -ErrorAction Stop
        Write-Success "Serviço '$svc' iniciado."
    } catch {
        Write-Fail "Não foi possível iniciar '$svc': $($_.Exception.Message)"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# [4/5] Re-registo de DLLs críticas do Windows Update (opcional mas útil)
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "4/5" "A re-registar DLLs do Windows Update..."

$dlls = @(
    'atl.dll','urlmon.dll','mshtml.dll','shdocvw.dll','browseui.dll',
    'jscript.dll','vbscript.dll','scrrun.dll','msxml.dll','msxml3.dll',
    'msxml6.dll','actxprxy.dll','softpub.dll','wintrust.dll','dssenh.dll',
    'rsaenh.dll','gpkcsp.dll','sccbase.dll','slbcsp.dll','cryptdlg.dll',
    'oleaut32.dll','ole32.dll','shell32.dll','initpki.dll','wuapi.dll',
    'wuaueng.dll','wuaueng1.dll','wucltui.dll','wups.dll','wups2.dll',
    'wuweb.dll','qmgr.dll','qmgrprxy.dll','wucltux.dll','muweb.dll','wuwebv.dll'
)

$regErrors = 0
foreach ($dll in $dlls) {
    $result = & regsvr32.exe /s $dll 2>&1
    if ($LASTEXITCODE -ne 0) { $regErrors++ }
}

if ($regErrors -eq 0) {
    Write-Success "Todas as DLLs re-registadas sem erros."
} else {
    Write-Warn "$regErrors DLL(s) não puderam ser re-registadas (normal em versões recentes do Windows 11)."
}

# ──────────────────────────────────────────────────────────────────────────────
# [5/5] Forçar detecção de atualizações
# ──────────────────────────────────────────────────────────────────────────────

Write-Step "5/5" "A forçar detecção de atualizações..."

try {
    # wuauclt legado (compatível com todas as versões)
    Start-Process -FilePath "wuauclt.exe" -ArgumentList "/detectnow" -NoNewWindow
    Write-Success "wuauclt.exe /detectnow disparado."

    # UsoClient (Windows 10/11 e Server 2016+) — mais fiável que wuauclt
    $usoClient = "$env:SystemRoot\System32\UsoClient.exe"
    if (Test-Path $usoClient) {
        Start-Process -FilePath $usoClient -ArgumentList "StartScan" -NoNewWindow
        Write-Success "UsoClient.exe StartScan disparado."
    }
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
Write-Host " Se as atualizações continuarem a falhar:" -ForegroundColor DarkGray
Write-Host "   dism /Online /Cleanup-Image /RestoreHealth" -ForegroundColor DarkGray
Write-Host "   sfc /scannow" -ForegroundColor DarkGray
Write-Host ""
