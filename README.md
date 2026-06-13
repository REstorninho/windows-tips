# windows-tips

Coleção de scripts e ferramentas para diagnóstico, manutenção e reparação de sistemas Windows.

## Conteúdo

### `Repair-WindowsUpdate.ps1`

Ferramenta de reparação do Windows Update. Para os serviços relacionados (`wuauserv`, `cryptSvc`, `bits`, `msiserver`), apaga os repositórios `SoftwareDistribution` (com fallback via `takeown`/`icacls` em caso de acesso negado), reinicia os serviços, re-regista as DLLs críticas do Windows Update e força uma nova detecção de atualizações.

**Requisitos:** PowerShell, executar como Administrador.

```powershell
.\Repair-WindowsUpdate.ps1
```

### `Get-DiskUsage.ps1`

Explorador interativo de uso de disco (TUI) em PowerShell. Apresenta um seletor de drives com informação de espaço usado/livre e permite navegar recursivamente pelas pastas, mostrando o Top 10 de pastas/ficheiros por tamanho com barras de utilização. Suporta eliminação de ficheiros/pastas com dupla confirmação e proteção contra paths de sistema críticos.

**Requisitos:** PowerShell 5.1+

```powershell
.\Get-DiskUsage.ps1              # Abre seletor de drives
.\Get-DiskUsage.ps1 -Path "D:\"  # Vai direto para D:\
.\Get-DiskUsage.ps1 -DebugMode   # Ativa overlay de debug de teclas
```

**Controlos:** `↑↓` navegar · `ENTER` entrar/ver detalhes · `BACKSPACE` voltar · `DEL` eliminar · `D` mudar de drive · `Q` sair

### `Sync-NTP.ps1`

Reconfigura o serviço Windows Time (W32Time): para, desregista e regista novamente o serviço, configura servidores NTP portugueses (`ntp02.oal.ul.pt`, `ntp04.oal.ul.pt`, `1.pt.pool.ntp.org`), força a resincronização e mostra o estado final da fonte de tempo e dos peers.

**Requisitos:** PowerShell, executar como Administrador.

```powershell
.\Sync-NTP.ps1
```

### `win-boot-fix.bat`

Script batch de reparação geral do Windows: corre `sfc /scannow`, `DISM` (RestoreHealth, ScanHealth, StartComponentCleanup), `chkdsk`, reinicia a stack de rede (`ipconfig /flushdns`, `netsh winsock reset`, `netsh int ip reset`), gera um relatório do sistema (`System_Report.txt`) e inclui os comandos de reparação de arranque (`bootrec /fixmbr`, `/fixboot`, `/rebuildbcd`) — estes últimos normalmente requerem o Ambiente de Recuperação do Windows (WinRE).

**Requisitos:** Prompt de Comando como Administrador.

```cmd
win-boot-fix.bat
```

## Aviso

Estes scripts efetuam alterações a serviços, registo e ficheiros do sistema. Usa-os com cuidado e, sempre que possível, cria um ponto de restauro do sistema antes de os executar.
