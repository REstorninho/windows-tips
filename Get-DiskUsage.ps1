#Requires -Version 5.1
<#
.SYNOPSIS
    Explorador interativo de uso de disco com seleção de drive e navegação por teclado.

.DESCRIPTION
    Ao iniciar apresenta um seletor de drives (todas as partições disponíveis com info
    de espaço usado/livre). Após escolha, analisa e apresenta o Top 10 de pastas/ficheiros
    por tamanho. Permite navegar recursivamente com ↑↓, ENTER para entrar, BACKSPACE para
    recuar, e D para mudar de drive a qualquer momento.

.PARAMETER Path
    (Opcional) Caminho raiz a analisar diretamente, saltando o seletor de drives.

.EXAMPLE
    .\Get-DiskUsage.ps1              # Abre seletor de drives
    .\Get-DiskUsage.ps1 -Path "D:\" # Vai direto para D:\
#>

[CmdletBinding()]
param(
    [string]$Path = ""   # Se vazio, abre o seletor de drives
)

# ══════════════════════════════════════════════════════════════════
#  FUNÇÕES AUXILIARES
# ══════════════════════════════════════════════════════════════════

function Format-Size {
    param([long]$Bytes)
    switch ($Bytes) {
        { $_ -ge 1TB } { return "{0,8:N2} TB" -f ($_ / 1TB) }
        { $_ -ge 1GB } { return "{0,8:N2} GB" -f ($_ / 1GB) }
        { $_ -ge 1MB } { return "{0,8:N2} MB" -f ($_ / 1MB) }
        { $_ -ge 1KB } { return "{0,8:N2} KB" -f ($_ / 1KB) }
        default        { return "{0,8} B " -f $_ }
    }
}

function Get-SizeColor {
    param([long]$Bytes)
    if ($Bytes -ge 10GB) { return "Red" }
    if ($Bytes -ge 1GB)  { return "Yellow" }
    if ($Bytes -ge 100MB){ return "Cyan" }
    return "White"
}

function Get-SizeBar {
    param([long]$Bytes, [long]$MaxBytes, [int]$Width = 20)
    if ($MaxBytes -eq 0) { return " " * $Width }
    $filled = [Math]::Round(($Bytes / $MaxBytes) * $Width)
    $filled = [Math]::Max(0, [Math]::Min($filled, $Width))
    return ("█" * $filled) + ("░" * ($Width - $filled))
}

# Calcula tamanho total de uma pasta (recursivo, sem limite de profundidade)
function Get-FolderSize {
    param([string]$FolderPath)
    $size = 0
    try {
        $items = Get-ChildItem -LiteralPath $FolderPath -Force -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $items) { $size += $f.Length }
    } catch { }
    return $size
}

# Calcula tamanho apenas do nível direto (sem recursão)
function Get-DirectChildrenSizes {
    param([string]$FolderPath)
    $results = [System.Collections.Generic.List[PSObject]]::new()

    # Subpastas
    $dirs = Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction SilentlyContinue
    $total = $dirs.Count
    $i = 0
    foreach ($dir in $dirs) {
        $i++
        Write-Progress -Activity "A calcular..." -Status $dir.Name -PercentComplete (($i / [Math]::Max($total,1)) * 100)
        $sz = Get-FolderSize -FolderPath $dir.FullName
        $results.Add([PSCustomObject]@{
            Name      = $dir.Name
            FullPath  = $dir.FullName
            SizeBytes = $sz
            IsDir     = $true
            LastWrite = $dir.LastWriteTime
        })
    }
    Write-Progress -Activity "A calcular..." -Completed

    # Ficheiros diretos
    $files = Get-ChildItem -LiteralPath $FolderPath -File -Force -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $results.Add([PSCustomObject]@{
            Name      = $f.Name
            FullPath  = $f.FullName
            SizeBytes = $f.Length
            IsDir     = $false
            LastWrite = $f.LastWriteTime
        })
    }

    return $results | Sort-Object SizeBytes -Descending
}

# ══════════════════════════════════════════════════════════════════
#  FUNÇÃO DE ELIMINAÇÃO COM CONFIRMAÇÃO
# ══════════════════════════════════════════════════════════════════

function Invoke-DeleteConfirmation {
    param([PSCustomObject]$Item)

    $w = [Console]::WindowWidth
    if ($w -lt 80) { $w = 80 }

    # ── Proteção contra paths de sistema críticos ──────────────────
    $protectedPaths = @(
        "$env:SystemRoot",                          # C:\Windows
        "$env:SystemRoot\System32",
        "$env:SystemRoot\SysWOW64",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}",
        "$env:ProgramData",
        "$env:SystemDrive\",                        # C:\
        "$env:USERPROFILE",
        "$env:APPDATA",
        "$env:LOCALAPPDATA"
    )

    foreach ($p in $protectedPaths) {
        if ($p -and $Item.FullPath.TrimEnd('\') -ieq $p.TrimEnd('\')) {
            [Console]::Clear()
            Write-Host ""
            Write-Host ("  " + "═" * ($w - 4)) -ForegroundColor Red
            Write-Host "  ⛔  ELIMINAÇÃO BLOQUEADA" -ForegroundColor Red
            Write-Host ("  " + "═" * ($w - 4)) -ForegroundColor Red
            Write-Host ""
            Write-Host ("  O caminho '{0}' é uma localização de sistema protegida." -f $Item.FullPath) -ForegroundColor Yellow
            Write-Host "  Este script não permite eliminar directorias críticas do Windows." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Prima qualquer tecla para voltar..." -ForegroundColor DarkGray
            [Console]::ReadKey($true) | Out-Null
            return $false
        }
    }

    # ── Ecrã de confirmação — nível 1 ─────────────────────────────
    [Console]::Clear()
    $typeLabel = if ($Item.IsDir) { "PASTA" } else { "FICHEIRO" }
    $icon      = if ($Item.IsDir) { "📁" } else { "📄" }

    Write-Host ""
    Write-Host ("  " + "═" * ($w - 4)) -ForegroundColor Red
    Write-Host ("  ⚠   CONFIRMAR ELIMINAÇÃO DE $typeLabel") -ForegroundColor Red
    Write-Host ("  " + "═" * ($w - 4)) -ForegroundColor Red
    Write-Host ""
    Write-Host ("  $icon  Nome     : {0}" -f $Item.Name) -ForegroundColor White
    Write-Host ("      Caminho  : {0}" -f $Item.FullPath) -ForegroundColor White
    Write-Host ("      Tamanho  : {0}" -f (Format-Size $Item.SizeBytes)) -ForegroundColor Yellow

    if ($Item.IsDir) {
        # Conta itens dentro da pasta
        try {
            $childCount = (Get-ChildItem -LiteralPath $Item.FullPath -Recurse -Force -ErrorAction SilentlyContinue).Count
            Write-Host ("      Conteúdo : {0} item(ns) no total (incluindo subpastas)" -f $childCount) -ForegroundColor Yellow
        } catch { }
        Write-Host ""
        Write-Host "  ⚠  ATENÇÃO: Esta operação eliminará a pasta e TODO o seu conteúdo!" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host ("  " + "─" * ($w - 4)) -ForegroundColor DarkGray
    Write-Host "  Tem a certeza que quer eliminar? Escreva  SIM  e prima ENTER para confirmar." -ForegroundColor White
    Write-Host "  (qualquer outra entrada cancela a operação)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  > " -ForegroundColor Yellow -NoNewline

    [Console]::CursorVisible = $true
    $resposta = Read-Host
    [Console]::CursorVisible = $false

    if ($resposta.Trim() -ne "SIM") {
        [Console]::Clear()
        Write-Host ""
        Write-Host "  ✔  Operação cancelada. Nenhum ficheiro foi eliminado." -ForegroundColor Green
        Write-Host ""
        Start-Sleep -Milliseconds 1200
        return $false
    }

    # ── Ecrã de confirmação — nível 2 (segunda barreira) ──────────
    [Console]::Clear()
    Write-Host ""
    Write-Host ("  " + "═" * ($w - 4)) -ForegroundColor Red
    Write-Host "  🔴  CONFIRMAÇÃO FINAL — ESTA AÇÃO É IRREVERSÍVEL" -ForegroundColor Red
    Write-Host ("  " + "═" * ($w - 4)) -ForegroundColor Red
    Write-Host ""
    Write-Host ("  Vai ser eliminado permanentemente:") -ForegroundColor White
    Write-Host ("  $icon  {0}  [{1}]" -f $Item.FullPath, (Format-Size $Item.SizeBytes)) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Prima  S  para CONFIRMAR definitivamente." -ForegroundColor Red
    Write-Host "  Prima qualquer outra tecla para CANCELAR." -ForegroundColor DarkGray
    Write-Host ""

    $finalKey = [Console]::ReadKey($true)

    if ($finalKey.Key -ne "S" -and $finalKey.KeyChar -ne 's') {
        [Console]::Clear()
        Write-Host ""
        Write-Host "  ✔  Operação cancelada na segunda confirmação." -ForegroundColor Green
        Write-Host ""
        Start-Sleep -Milliseconds 1200
        return $false
    }

    # ── Execução da eliminação ─────────────────────────────────────
    [Console]::Clear()
    Write-Host ""
    Write-Host "  🗑  A eliminar: $($Item.FullPath)" -ForegroundColor Yellow
    Write-Host ""

    $success = $false
    $errMsg  = ""

    try {
        if ($Item.IsDir) {
            Remove-Item -LiteralPath $Item.FullPath -Recurse -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $Item.FullPath -Force -ErrorAction Stop
        }
        $success = $true
    } catch {
        $errMsg = $_.Exception.Message
    }

    if ($success) {
        Write-Host ("  ✅  Eliminado com sucesso: {0}" -f $Item.Name) -ForegroundColor Green
        Write-Host ("      Espaço libertado: {0}" -f (Format-Size $Item.SizeBytes)) -ForegroundColor Green
    } else {
        Write-Host "  ❌  Erro ao eliminar:" -ForegroundColor Red
        Write-Host ("      {0}" -f $errMsg) -ForegroundColor Red
        Write-Host ""
        Write-Host "  Dica: executa o script como Administrador se o acesso for negado." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Prima qualquer tecla para voltar..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null

    return $success
}

# ══════════════════════════════════════════════════════════════════
#  RENDERIZAÇÃO DO ECRÃ (TUI)
# ══════════════════════════════════════════════════════════════════

function Draw-Screen {
    param(
        [object[]]$Items,
        [int]$SelectedIndex,
        [string]$CurrentPath,
        [string[]]$BreadCrumb,
        [long]$TotalUsed,
        [long]$TotalFree
    )

    [Console]::Clear()
    $w = [Console]::WindowWidth
    if ($w -lt 80) { $w = 80 }

    # ── Cabeçalho ──────────────────────────────────────────────────
    $title = " DISK USAGE EXPLORER "
    $pad   = [Math]::Max(0, [Math]::Floor(($w - $title.Length) / 2))
    Write-Host ("═" * $w) -ForegroundColor DarkCyan
    Write-Host (" " * $pad + $title) -ForegroundColor Cyan
    Write-Host ("═" * $w) -ForegroundColor DarkCyan

    # ── Info da unidade ────────────────────────────────────────────
    $totalDrive = $TotalUsed + $TotalFree
    if ($totalDrive -gt 0) {
        $pct     = ($TotalUsed / $totalDrive * 100)
        $barW    = $w - 30
        $filled  = [Math]::Round($pct / 100 * $barW)
        $barColor = if ($pct -ge 90) { "Red" } elseif ($pct -ge 70) { "Yellow" } else { "Green" }
        $bar = ("█" * $filled) + ("░" * ($barW - $filled))
        Write-Host (" Usado: $(Format-Size $TotalUsed)  Livre: $(Format-Size $TotalFree)  [{0:N1}%]" -f $pct) -ForegroundColor $barColor
        Write-Host (" [$bar]") -ForegroundColor $barColor
    }

    # ── Breadcrumb ─────────────────────────────────────────────────
    $crumb = " 📁 " + ($BreadCrumb -join " › ")
    if ($crumb.Length -gt $w - 2) { $crumb = " …" + $crumb.Substring($crumb.Length - ($w - 4)) }
    Write-Host ("─" * $w) -ForegroundColor DarkGray
    Write-Host $crumb -ForegroundColor White
    Write-Host ("─" * $w) -ForegroundColor DarkGray

    # ── Cabeçalho da lista ─────────────────────────────────────────
    Write-Host ("  {0,-3}  {1,-38}  {2,12}  {3,20}  {4}" -f `
        "   ", "NOME", "TAMANHO", "MODIFICADO", "GRÁFICO") -ForegroundColor DarkGray

    # ── Itens ──────────────────────────────────────────────────────
    $displayItems = $Items | Select-Object -First 10
    $maxSize = if ($displayItems.Count -gt 0) { ($displayItems | Measure-Object SizeBytes -Maximum).Maximum } else { 1 }

    for ($i = 0; $i -lt $displayItems.Count; $i++) {
        $item     = $displayItems[$i]
        $isSelected = ($i -eq $SelectedIndex)
        $sizeColor  = Get-SizeColor -Bytes $item.SizeBytes
        $bar        = Get-SizeBar -Bytes $item.SizeBytes -MaxBytes $maxSize -Width 18

        # Ícone
        $icon = if ($item.IsDir) { "📁" } else {
            switch ([System.IO.Path]::GetExtension($item.Name).ToLower()) {
                ".exe"  { "⚙ " }
                ".msi"  { "📦" }
                ".zip"  { "🗜 " }
                ".rar"  { "🗜 " }
                ".7z"   { "🗜 " }
                ".log"  { "📋" }
                ".evtx" { "📋" }
                ".vhd"  { "💽" }
                ".vhdx" { "💽" }
                ".iso"  { "💿" }
                ".mp4"  { "🎬" }
                ".mkv"  { "🎬" }
                ".bak"  { "💾" }
                default { "📄" }
            }
        }

        # Nome truncado
        $nameMax  = 36
        $dispName = if ($item.Name.Length -gt $nameMax) { $item.Name.Substring(0, $nameMax - 1) + "…" } else { $item.Name }
        $rank     = "{0,2}." -f ($i + 1)
        $dateStr  = $item.LastWrite.ToString("yyyy-MM-dd HH:mm")
        $line     = "  {0}  {1} {2,-38}  {3}  {4,20}  {5}" -f `
            $rank, $icon, $dispName, (Format-Size $item.SizeBytes), $dateStr, $bar

        if ($isSelected) {
            Write-Host $line -BackgroundColor DarkCyan -ForegroundColor White
        } else {
            Write-Host $line -ForegroundColor $sizeColor
        }
    }

    # Aviso se há mais de 10 itens
    $extra = $Items.Count - 10
    if ($extra -gt 0) {
        Write-Host ("  … mais {0} item(ns) não mostrado(s)" -f $extra) -ForegroundColor DarkGray
    }

    # ── Rodapé / Controlos ─────────────────────────────────────────
    Write-Host ("─" * $w) -ForegroundColor DarkGray
    $controls = "  ↑↓ Navegar   ENTER Entrar   BACKSPACE Voltar   DEL Eliminar   D Drive   Q Sair"
    if ($displayItems.Count -gt 0 -and $displayItems[$SelectedIndex].IsDir) {
        $controls += "   [ENTER → ver subpastas]"
    }
    Write-Host $controls -ForegroundColor DarkGray
    Write-Host ("═" * $w) -ForegroundColor DarkCyan
}

# ══════════════════════════════════════════════════════════════════
#  ECRÃ DE SELEÇÃO DE DRIVE
# ══════════════════════════════════════════════════════════════════

function Show-DrivePicker {
    # Recolhe todas as drives fixas, removíveis e de rede
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object {
        $_.Root -ne "" -and (Test-Path $_.Root -ErrorAction SilentlyContinue)
    }

    # Enriquece com info do WMI (label, tipo)
    $driveList = foreach ($drv in $drives) {
        $letter = $drv.Name                          # ex: C
        $root   = $drv.Root                          # ex: C:\
        $used   = $drv.Used
        $free   = $drv.Free
        $total  = $used + $free

        # Tenta obter label e tipo via WMI
        $wmi = $null
        try {
            $wmi = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='${letter}:'" -ErrorAction SilentlyContinue
        } catch { }

        $label    = if ($wmi -and $wmi.VolumeName) { $wmi.VolumeName } else { "(sem rótulo)" }
        $driveType = switch ($wmi.DriveType) {
            2  { "Amovível  " }
            3  { "Disco Local" }
            4  { "Rede      " }
            5  { "CD/DVD    " }
            6  { "Disco RAM " }
            default { "Desconhecido" }
        }

        [PSCustomObject]@{
            Letter    = $letter
            Root      = $root
            Label     = $label
            DriveType = $driveType
            Used      = $used
            Free      = $free
            Total     = $total
        }
    }

    $driveArr = @($driveList)
    $sel      = 0

    [Console]::CursorVisible = $false

    while ($true) {
        [Console]::Clear()
        $w = [Console]::WindowWidth
        if ($w -lt 80) { $w = 80 }

        # Cabeçalho
        $title = " DISK USAGE EXPLORER — Selecionar Drive "
        $pad   = [Math]::Max(0, [Math]::Floor(($w - $title.Length) / 2))
        Write-Host ("═" * $w) -ForegroundColor DarkCyan
        Write-Host (" " * $pad + $title) -ForegroundColor Cyan
        Write-Host ("═" * $w) -ForegroundColor DarkCyan
        Write-Host ""

        # Coluna header
        Write-Host ("  {0,-4}  {1,-14}  {2,-16}  {3,12}  {4,12}  {5,12}  {6}" -f `
            "DRV", "TIPO", "RÓTULO", "TOTAL", "USADO", "LIVRE", "UTILIZAÇÃO") -ForegroundColor DarkGray
        Write-Host ("  " + "─" * ($w - 4)) -ForegroundColor DarkGray

        for ($i = 0; $i -lt $driveArr.Count; $i++) {
            $d        = $driveArr[$i]
            $isActive = ($i -eq $sel)

            # Barra de utilização (20 chars)
            $pct    = if ($d.Total -gt 0) { $d.Used / $d.Total * 100 } else { 0 }
            $barW   = 20
            $filled = [Math]::Round($pct / 100 * $barW)
            $bar    = ("█" * $filled) + ("░" * ($barW - $filled))
            $pctStr = "{0:N0}%" -f $pct

            $barColor = if ($pct -ge 90) { "Red" } elseif ($pct -ge 70) { "Yellow" } else { "Green" }

            $line = "  {0,-4}  {1,-14}  {2,-16}  {3,12}  {4,12}  {5,12}  " -f `
                ($d.Letter + ":\"),
                $d.DriveType,
                $d.Label,
                (Format-Size $d.Total),
                (Format-Size $d.Used),
                (Format-Size $d.Free)

            if ($isActive) {
                Write-Host $line -BackgroundColor DarkCyan -ForegroundColor White -NoNewline
                Write-Host ("[{0}] {1,4}" -f $bar, $pctStr) -BackgroundColor DarkCyan -ForegroundColor $barColor
            } else {
                Write-Host $line -ForegroundColor White -NoNewline
                Write-Host ("[{0}] {1,4}" -f $bar, $pctStr) -ForegroundColor $barColor
            }
        }

        Write-Host ""
        Write-Host ("  " + "─" * ($w - 4)) -ForegroundColor DarkGray
        Write-Host "  ↑↓ Selecionar   ENTER Confirmar   Q Sair" -ForegroundColor DarkGray
        Write-Host ("═" * $w) -ForegroundColor DarkCyan

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "DownArrow" { if ($sel -lt ($driveArr.Count - 1)) { $sel++ } }
            "UpArrow"   { if ($sel -gt 0) { $sel-- } }
            "Enter"     {
                [Console]::CursorVisible = $false
                return $driveArr[$sel]
            }
            { $_ -eq "Q" -or $_ -eq "Escape" } {
                [Console]::CursorVisible = $true
                [Console]::Clear()
                exit 0
            }
        }
    }
}

# ══════════════════════════════════════════════════════════════════
#  LOOP PRINCIPAL DE NAVEGAÇÃO
# ══════════════════════════════════════════════════════════════════

# Se não foi passado -Path, abre o seletor de drives
if ($Path -eq "") {
    $chosenDrive = Show-DrivePicker
    $Path        = $chosenDrive.Root
    $driveUsed   = $chosenDrive.Used
    $driveFree   = $chosenDrive.Free
} else {
    # Path fornecido via parâmetro — obtém info da drive normalmente
    $driveLetter = ($Path -replace '\\.*','')
    $driveUsed   = 0L
    $driveFree   = 0L
    try {
        $drv = Get-PSDrive -Name ($driveLetter -replace ':','') -ErrorAction SilentlyContinue
        if ($drv) { $driveUsed = $drv.Used; $driveFree = $drv.Free }
    } catch { }
}

# Stack de navegação: cada entrada tem @{ Path; Items; SelectedIndex }
$navStack  = [System.Collections.Generic.Stack[hashtable]]::new()
$crumbs    = [System.Collections.Generic.List[string]]::new()
$crumbs.Add($Path.TrimEnd('\'))

# Scan inicial
[Console]::Clear()
Write-Host "`n  A analisar $Path — aguarde...`n" -ForegroundColor Cyan
$currentItems    = Get-DirectChildrenSizes -FolderPath $Path
$currentSelected = 0

# Esconde o cursor durante a navegação
[Console]::CursorVisible = $false

try {
    while ($true) {
        $topN = $currentItems | Select-Object -First 10

        Draw-Screen `
            -Items $currentItems `
            -SelectedIndex $currentSelected `
            -CurrentPath $Path `
            -BreadCrumb $crumbs.ToArray() `
            -TotalUsed $driveUsed `
            -TotalFree $driveFree

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {

            # ── Navegar para baixo ──────────────────────────────────
            "DownArrow" {
                $max = [Math]::Min($currentItems.Count, 10) - 1
                if ($currentSelected -lt $max) { $currentSelected++ }
            }

            # ── Navegar para cima ───────────────────────────────────
            "UpArrow" {
                if ($currentSelected -gt 0) { $currentSelected-- }
            }

            # ── Entrar na pasta / mostrar ficheiro ──────────────────
            "Enter" {
                $selected = ($currentItems | Select-Object -First 10)[$currentSelected]
                if ($selected.IsDir) {
                    # Guarda estado atual na stack
                    $navStack.Push(@{
                        Items    = $currentItems
                        Selected = $currentSelected
                        Crumbs   = $crumbs.ToArray()
                    })
                    $crumbs.Add($selected.Name)

                    [Console]::Clear()
                    Write-Host "`n  A analisar $($selected.FullPath) — aguarde...`n" -ForegroundColor Cyan

                    $currentItems    = Get-DirectChildrenSizes -FolderPath $selected.FullPath
                    $currentSelected = 0
                } else {
                    # Ficheiro — mostrar detalhes
                    [Console]::Clear()
                    $f = Get-Item -LiteralPath $selected.FullPath -Force -ErrorAction SilentlyContinue
                    Write-Host "`n  DETALHES DO FICHEIRO" -ForegroundColor Cyan
                    Write-Host ("  " + "─" * 50) -ForegroundColor DarkGray
                    if ($f) {
                        Write-Host ("  Nome       : {0}" -f $f.Name)
                        Write-Host ("  Caminho    : {0}" -f $f.FullName)
                        Write-Host ("  Tamanho    : {0}" -f (Format-Size $f.Length))
                        Write-Host ("  Criado     : {0}" -f $f.CreationTime.ToString("yyyy-MM-dd HH:mm:ss"))
                        Write-Host ("  Modificado : {0}" -f $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
                        Write-Host ("  Atributos  : {0}" -f $f.Attributes)
                    }
                    Write-Host "`n  Prima qualquer tecla para voltar..." -ForegroundColor DarkGray
                    [Console]::ReadKey($true) | Out-Null
                }
            }

            # ── Voltar atrás ────────────────────────────────────────
            { $_ -eq "Backspace" -or $_ -eq "LeftArrow" } {
                if ($navStack.Count -gt 0) {
                    $prev = $navStack.Pop()
                    $currentItems    = $prev.Items
                    $currentSelected = $prev.Selected
                    $crumbs.Clear()
                    foreach ($c in $prev.Crumbs) { $crumbs.Add($c) }
                } else {
                    # Já no topo — nada a fazer
                }
            }

            # ── Eliminar item selecionado ───────────────────────────
            "Delete" {
                $target = ($currentItems | Select-Object -First 10)[$currentSelected]
                $deleted = Invoke-DeleteConfirmation -Item $target
                if ($deleted) {
                    # Atualiza a lista removendo o item eliminado e refresca tamanhos
                    $parentPath = if ($navStack.Count -gt 0) {
                        # Path atual = último crumb completo
                        $crumbs[$crumbs.Count - 1]
                    } else { $Path }

                    # Reconstrói o path completo do nível atual a partir dos crumbs
                    $scanPath = $crumbs[0]
                    for ($ci = 1; $ci -lt $crumbs.Count; $ci++) {
                        $scanPath = Join-Path $scanPath $crumbs[$ci]
                    }

                    [Console]::Clear()
                    Write-Host "`n  A atualizar lista...`n" -ForegroundColor Cyan
                    $currentItems = Get-DirectChildrenSizes -FolderPath $scanPath

                    # Atualiza também o espaço da drive
                    $driveLtr = ($Path -replace '\\.*','')
                    try {
                        $drv2 = Get-PSDrive -Name ($driveLtr -replace ':','') -ErrorAction SilentlyContinue
                        if ($drv2) { $driveUsed = $drv2.Used; $driveFree = $drv2.Free }
                    } catch { }

                    # Ajusta índice se necessário
                    $maxIdx = [Math]::Min($currentItems.Count, 10) - 1
                    if ($currentSelected -gt $maxIdx) {
                        $currentSelected = [Math]::Max(0, $maxIdx)
                    }
                }
            }

            # ── Mudar de drive ──────────────────────────────────────
            { $_ -eq "D" } {
                $chosenDrive  = Show-DrivePicker
                $Path         = $chosenDrive.Root
                $driveUsed    = $chosenDrive.Used
                $driveFree    = $chosenDrive.Free

                $navStack.Clear()
                $crumbs.Clear()
                $crumbs.Add($Path.TrimEnd('\'))

                [Console]::Clear()
                Write-Host "`n  A analisar $Path — aguarde...`n" -ForegroundColor Cyan
                $currentItems    = Get-DirectChildrenSizes -FolderPath $Path
                $currentSelected = 0
            }

            # ── Sair ────────────────────────────────────────────────
            { $_ -eq "Q" -or $_ -eq "Escape" } {
                [Console]::Clear()
                Write-Host "`n  Saindo do Disk Usage Explorer.`n" -ForegroundColor Cyan
                return
            }
        }
    }
}
finally {
    [Console]::CursorVisible = $true
    [Console]::Clear()
}
