#Requires -Version 5.1
<#
.SYNOPSIS
    Analisa o uso de disco e identifica as pastas com maior consumo de espaço.

.DESCRIPTION
    Percorre recursivamente uma unidade/pasta e calcula o tamanho de cada diretório,
    apresentando um relatório ordenado por tamanho (do maior para o menor).
    Suporta exportação para CSV e filtragem por tamanho mínimo.

.PARAMETER Path
    Caminho raiz a analisar. Por defeito usa C:\

.PARAMETER TopN
    Número de pastas a mostrar no relatório. Por defeito 30.

.PARAMETER MinSizeGB
    Tamanho mínimo em GB para incluir no relatório. Por defeito 0.1 (100 MB).

.PARAMETER Depth
    Profundidade máxima de recursão. Por defeito 4.

.PARAMETER ExportCSV
    Caminho para exportar os resultados em CSV (opcional).

.EXAMPLE
    .\Get-DiskUsage.ps1 -Path "C:\" -TopN 20 -MinSizeGB 0.5

.EXAMPLE
    .\Get-DiskUsage.ps1 -Path "D:\" -ExportCSV "C:\Temp\disk_report.csv"
#>

[CmdletBinding()]
param(
    [string]$Path       = "C:\",
    [int]$TopN          = 30,
    [double]$MinSizeGB  = 0.1,
    [int]$Depth         = 4,
    [string]$ExportCSV  = ""
)

# ─────────────────────────────────────────────
#  Funções auxiliares
# ─────────────────────────────────────────────

function Format-Size {
    param([long]$Bytes)
    switch ($Bytes) {
        { $_ -ge 1TB } { return "{0:N2} TB" -f ($_ / 1TB) }
        { $_ -ge 1GB } { return "{0:N2} GB" -f ($_ / 1GB) }
        { $_ -ge 1MB } { return "{0:N2} MB" -f ($_ / 1MB) }
        { $_ -ge 1KB } { return "{0:N2} KB" -f ($_ / 1KB) }
        default        { return "$_ B" }
    }
}

function Get-FolderSize {
    param(
        [string]$FolderPath,
        [int]$CurrentDepth,
        [int]$MaxDepth
    )

    $size = 0

    try {
        # Soma ficheiros diretos nesta pasta
        $files = Get-ChildItem -LiteralPath $FolderPath -File -Force -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $size += $f.Length
        }

        # Recursão para subpastas
        if ($CurrentDepth -lt $MaxDepth) {
            $subDirs = Get-ChildItem -LiteralPath $FolderPath -Directory -Force -ErrorAction SilentlyContinue
            foreach ($dir in $subDirs) {
                $size += Get-FolderSize -FolderPath $dir.FullName -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
            }
        }
    }
    catch {
        Write-Verbose "Acesso negado ou erro em: $FolderPath — $_"
    }

    return $size
}

# ─────────────────────────────────────────────
#  Informação geral da unidade
# ─────────────────────────────────────────────

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  DISK USAGE ANALYZER — $Path" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

$driveLetter = ($Path -replace '\\.*', '')
try {
    $drive = Get-PSDrive -Name ($driveLetter -replace ':','') -ErrorAction SilentlyContinue
    if ($drive) {
        $totalBytes = ($drive.Used + $drive.Free)
        Write-Host ("  Unidade : {0}" -f $driveLetter) -ForegroundColor White
        Write-Host ("  Total   : {0}" -f (Format-Size $totalBytes)) -ForegroundColor White
        Write-Host ("  Usado   : {0}  ({1:N1}%)" -f (Format-Size $drive.Used), ($drive.Used / $totalBytes * 100)) -ForegroundColor Yellow
        Write-Host ("  Livre   : {0}  ({1:N1}%)" -f (Format-Size $drive.Free), ($drive.Free / $totalBytes * 100)) -ForegroundColor Green
        Write-Host ""
    }
}
catch { }

# ─────────────────────────────────────────────
#  Varredura das pastas de nível 1
# ─────────────────────────────────────────────

Write-Host "  A analisar pastas (profundidade máx: $Depth)..." -ForegroundColor DarkGray

$results    = [System.Collections.Generic.List[PSObject]]::new()
$minBytes   = [long]($MinSizeGB * 1GB)
$startTime  = Get-Date

try {
    $topLevelDirs = Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Error "Não foi possível aceder ao caminho: $Path"
    exit 1
}

$counter = 0
foreach ($dir in $topLevelDirs) {
    $counter++
    Write-Progress -Activity "A calcular tamanhos..." `
                   -Status $dir.FullName `
                   -PercentComplete (($counter / [Math]::Max($topLevelDirs.Count, 1)) * 100)

    $dirSize = Get-FolderSize -FolderPath $dir.FullName -CurrentDepth 1 -MaxDepth $Depth

    if ($dirSize -ge $minBytes) {
        $results.Add([PSCustomObject]@{
            Path       = $dir.FullName
            SizeBytes  = $dirSize
            SizeHuman  = Format-Size $dirSize
            LastWrite  = $dir.LastWriteTime
        })
    }
}

Write-Progress -Activity "A calcular tamanhos..." -Completed

$elapsed = (Get-Date) - $startTime
Write-Host ("  Concluído em {0:N1}s — {1} pasta(s) encontrada(s) acima de {2}`n" -f `
    $elapsed.TotalSeconds, $results.Count, (Format-Size $minBytes)) -ForegroundColor DarkGray

# ─────────────────────────────────────────────
#  Apresentação dos resultados
# ─────────────────────────────────────────────

$sorted = $results | Sort-Object SizeBytes -Descending | Select-Object -First $TopN

Write-Host ("  {'TOP {0} PASTAS POR TAMANHO',-55} {'TAMANHO',12}  ÚLTIMA MODIFICAÇÃO" -f $TopN) -ForegroundColor Cyan
Write-Host ("  {0}" -f ("─" * 95)) -ForegroundColor DarkGray

$rank = 1
foreach ($item in $sorted) {
    # Cor baseada no tamanho
    $color = if ($item.SizeBytes -ge 10GB) { "Red" }
             elseif ($item.SizeBytes -ge 1GB) { "Yellow" }
             else { "White" }

    Write-Host ("  {0,3}. {1,-55} {2,10}   {3}" -f `
        $rank,
        ($item.Path.Substring([Math]::Max(0, $item.Path.Length - 55))),
        $item.SizeHuman,
        $item.LastWrite.ToString("yyyy-MM-dd HH:mm")) -ForegroundColor $color

    $rank++
}

Write-Host ("  {0}" -f ("─" * 95)) -ForegroundColor DarkGray

# ─────────────────────────────────────────────
#  Exportação CSV (opcional)
# ─────────────────────────────────────────────

if ($ExportCSV -ne "") {
    try {
        $sorted | Select-Object Path, SizeHuman, SizeBytes, LastWrite |
            Export-Csv -Path $ExportCSV -NoTypeInformation -Encoding UTF8
        Write-Host ("`n  Relatório exportado para: $ExportCSV") -ForegroundColor Green
    }
    catch {
        Write-Warning "Não foi possível exportar o CSV: $_"
    }
}

# ─────────────────────────────────────────────
#  Sugestões de limpeza comuns
# ─────────────────────────────────────────────

Write-Host "`n  LOCAIS DE LIMPEZA RÁPIDA RECOMENDADOS:`n" -ForegroundColor Magenta

$cleanupTargets = @(
    @{ Path = "$env:SystemRoot\Temp";                         Label = "Windows Temp" }
    @{ Path = "$env:TEMP";                                    Label = "User Temp" }
    @{ Path = "$env:SystemRoot\SoftwareDistribution\Download"; Label = "Windows Update Cache" }
    @{ Path = "$env:SystemRoot\Logs\CBS";                     Label = "CBS Logs" }
    @{ Path = "$env:LOCALAPPDATA\Temp";                       Label = "AppData Temp" }
    @{ Path = "C:\Windows\Minidump";                          Label = "Minidumps" }
)

foreach ($target in $cleanupTargets) {
    if (Test-Path $target.Path) {
        try {
            $sz = (Get-ChildItem -LiteralPath $target.Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
            if ($sz -gt 0) {
                Write-Host ("  ► {0,-40} {1,10}" -f $target.Label, (Format-Size $sz)) -ForegroundColor Yellow
            }
        }
        catch { }
    }
}

Write-Host "`n  Dica: usa 'cleanmgr /sageset:1' e 'cleanmgr /sagerun:1' para limpeza avançada." -ForegroundColor DarkGray
Write-Host "  Para WinSxS: 'Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase'`n" -ForegroundColor DarkGray
