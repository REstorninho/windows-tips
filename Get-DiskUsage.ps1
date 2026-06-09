#Requires -Version 5.1
<#
.SYNOPSIS
    Explorador interativo de uso de disco com navegação por teclado.

.DESCRIPTION
    Analisa o disco, apresenta o Top 10 de pastas por tamanho e permite navegar
    recursivamente com as setas ↑↓, ENTER para entrar, BACKSPACE para voltar atrás,
    até aos ficheiros individuais. Interface TUI no terminal.

.PARAMETER Path
    Caminho raiz a analisar. Por defeito C:\

.EXAMPLE
    .\Get-DiskUsage.ps1
    .\Get-DiskUsage.ps1 -Path "D:\"
#>

[CmdletBinding()]
param(
    [string]$Path = "C:\"
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
    $controls = "  ↑↓ Navegar   ENTER Entrar/Abrir   BACKSPACE Voltar atrás   Q Sair"
    if ($displayItems.Count -gt 0 -and $displayItems[$SelectedIndex].IsDir) {
        $controls += "   [ENTER → ver subpastas]"
    }
    Write-Host $controls -ForegroundColor DarkGray
    Write-Host ("═" * $w) -ForegroundColor DarkCyan
}

# ══════════════════════════════════════════════════════════════════
#  LOOP PRINCIPAL DE NAVEGAÇÃO
# ══════════════════════════════════════════════════════════════════

# Info da unidade (drive letter)
$driveLetter = ($Path -replace '\\.*','')
$driveUsed   = 0L
$driveFree   = 0L
try {
    $drv = Get-PSDrive -Name ($driveLetter -replace ':','') -ErrorAction SilentlyContinue
    if ($drv) { $driveUsed = $drv.Used; $driveFree = $drv.Free }
} catch { }

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
