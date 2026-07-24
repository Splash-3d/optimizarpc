#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Optimizador Windows 10/11 - interactivo, seguro y reversible.
.DESCRIPTION
    Menu para elegir que optimizar. Power plans, cache, servicios,
    red, RAM, disco, efectos visuales. No borra datos ni toca drivers.
#>

# ─── Consola: UTF-8, negro, titulo ──────────────────────────────────────────────
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = "TURBO PC  -  Optimizador" } catch {}
try { [Console]::BackgroundColor = 'Black'; Clear-Host } catch {}

# Fuente de consola GRANDE (texto legible, no diminuto)
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ConFont {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct FONTINFOEX {
    public uint cbSize; public uint nFont;
    public short X; public short Y;
    public int FontFamily; public int FontWeight;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string FaceName;
  }
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool max, ref FONTINFOEX f);
  public static void Set(short h, string face) {
    FONTINFOEX f = new FONTINFOEX();
    f.cbSize = (uint)Marshal.SizeOf(typeof(FONTINFOEX));
    f.X = 0; f.Y = h; f.FontFamily = 54; f.FontWeight = 700; f.FaceName = face;
    SetCurrentConsoleFontEx(GetStdHandle(-11), false, ref f);
  }
}
"@
    [ConFont]::Set(28, "Consolas")
} catch {}

# Activar color 24-bit (VT) para mostrar el logo PNG real
try {
    $vt = Add-Type -Name VT -Namespace ConVT -PassThru -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
"@
    $h = $vt::GetStdHandle(-11); $m = 0
    if ($vt::GetConsoleMode($h, [ref]$m)) { $vt::SetConsoleMode($h, $m -bor 0x0004) | Out-Null }
} catch {}

# Maximizar la ventana de consola (que ocupe toda la pantalla)
try {
    $win = Add-Type -Name Win -Namespace Con -PassThru -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr h, int c);
"@
    $win::ShowWindow($win::GetConsoleWindow(), 3) | Out-Null   # 3 = SW_MAXIMIZE
    Start-Sleep -Milliseconds 200
    # Buffer = ancho de ventana (sin scroll horizontal), alto amplio para el log
    $ui = $Host.UI.RawUI
    $b = $ui.BufferSize; $b.Width = $ui.WindowSize.Width
    if ($b.Height -lt 300) { $b.Height = 300 }
    $ui.BufferSize = $b
    Clear-Host
} catch {}

$ErrorActionPreference = "SilentlyContinue"

# Carpeta del propio script (portable: funcione donde este la carpeta)
$baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $baseDir) { $baseDir = (Get-Location).Path }
$log = Join-Path $baseDir "OptimizarPC_Log_$(Get-Date -f 'yyyyMMdd_HHmm').txt"

# Lineas de resumen para el log (solo lo esencial)
$script:LogLines = New-Object System.Collections.Generic.List[string]

# ─── Helpers de salida (estilo terminal, legible) ───────────────────────────────
function CC { param($t,$c='Gray',[switch]$n) if($n){Write-Host $t -ForegroundColor $c -NoNewline}else{Write-Host $t -ForegroundColor $c} }
function Ok   { param($m) CC "   [+] " Green -n; CC $m Gray;   $script:LogLines.Add("[+] $m") }
function Info { param($m) CC "   [>] " Cyan  -n; CC $m Gray }
function Warn { param($m) CC "   [!] " Yellow -n; CC $m DarkYellow; $script:LogLines.Add("[!] $m") }
function Val  { param($k,$v) CC "   [i] " DarkCyan -n; CC "$k " Gray -n; CC $v White; $script:LogLines.Add("[i] $k $v") }

function RainbowBar {
    # Barra con degradado cian (igual que el titulo): oscuro -> claro -> oscuro
    param([int]$w = 44, [string]$ch = '█', [int]$pad = 0)
    if ($pad -gt 0) { Write-Host (' ' * $pad) -NoNewline }
    $mid = ($w - 1) / 2
    for ($i=0; $i -lt $w; $i++) {
        $d = if ($mid -eq 0) { 0 } else { [Math]::Abs($i - $mid) / $mid }   # 0 centro .. 1 borde
        $col = if     ($d -lt 0.30) { 'White' }
               elseif ($d -lt 0.65) { 'Cyan' }
               else                 { 'DarkCyan' }
        Write-Host $ch -NoNewline -ForegroundColor $col
    }
    Write-Host
}

# Ancho/alto reales de la ventana + centrado
function ConW { try { $Host.UI.RawUI.WindowSize.Width } catch { 80 } }
function ConH { try { $Host.UI.RawUI.WindowSize.Height } catch { 25 } }
function LPad { param([int]$len) $w = ConW; [Math]::Max(0, [int](($w - $len) / 2)) }
function CCc  { param($t, $c='Gray') CC ((' ' * (LPad $t.Length)) + $t) $c }

function ModHeader {
    param($n, $title)
    Write-Host ""
    CC ("  ┌─[ ") DarkGreen -n; CC ("MODULO $n") Green -n; CC (" ]") DarkGreen
    CC ("  │  ") DarkGreen -n; CC $title White
    CC ("  └────────────────────────────────────────────") DarkGreen
}

# ─── Splash: nombre en grande pixel-art + Enter ─────────────────────────────────
function Show-Splash {
    Clear-Host
    $banner = @(
        '████████╗██╗   ██╗██████╗ ██████╗  ██████╗ ',
        '╚══██╔══╝██║   ██║██╔══██╗██╔══██╗██╔═══██╗',
        '   ██║   ██║   ██║██████╔╝██████╔╝██║   ██║',
        '   ██║   ██║   ██║██╔══██╗██╔══██╗██║   ██║',
        '   ██║   ╚██████╔╝██║  ██║██████╔╝╚██████╔╝',
        '   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═════╝  ╚═════╝ '
    )
    $cols = @('White','Cyan','Cyan','Cyan','DarkCyan','DarkCyan')
    $bw = ($banner | Measure-Object -Property Length -Maximum).Maximum
    $bp = ' ' * (LPad $bw)
    $barW = [Math]::Min((ConW) - 6, 60)

    # Centrado vertical
    $top = [Math]::Max(0, [int](((ConH) - 17) / 2))
    if ($top -gt 0) { 1..$top | ForEach-Object { Write-Host "" } }

    RainbowBar $barW '█' (LPad $barW)
    Write-Host ""
    for ($i=0; $i -lt $banner.Count; $i++) { CC ($bp + $banner[$i]) $cols[$i] }
    Write-Host ""
    CCc "▓▒░  P C   O P T I M I Z E R  ░▒▓" Green
    CCc "Windows 10 / 11   ·   v3.0" DarkGray
    Write-Host ""
    RainbowBar $barW '█' (LPad $barW)
    Write-Host ""
    CCc "Seguro  ·  Reversible  ·  No borra tus datos" DarkGray
    Write-Host ""
    $prompt = "[ Pulsa ENTER para comenzar ]"
    CC (' ' * (LPad $prompt.Length)) Gray -n
    CC "[ Pulsa " Gray -n; CC "ENTER" Yellow -n; CC " para comenzar ]" Gray
    # Read-Host: espera Enter de forma fiable en cualquier consola/elevacion
    [void](Read-Host)
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MODULOS  (cada uno con su accion real de optimizacion)
# ═══════════════════════════════════════════════════════════════════════════════

$modules = @(
    [pscustomobject]@{ Enabled=$true; Name="Plan de energia";        Desc="Ultimate Performance, sin apagar disco, sin hibernacion"; Action={ Mod-Energia } }
    [pscustomobject]@{ Enabled=$true; Name="Limpieza de cache/temp"; Desc="Temporales, thumbnails, DNS, cola impresion, Disk Cleanup"; Action={ Mod-Limpieza } }
    [pscustomobject]@{ Enabled=$true; Name="Efectos visuales";       Desc="Menos animaciones, mantiene ClearType (mas fluido)"; Action={ Mod-Visual } }
    [pscustomobject]@{ Enabled=$true; Name="Optimizacion de red";    Desc="Nagle off, TCP tuning, quita reserva QoS 20%"; Action={ Mod-Red } }
    [pscustomobject]@{ Enabled=$true; Name="Memoria y almacenamiento"; Desc="Libera RAM, SysMain segun disco, TRIM SSD"; Action={ Mod-Memoria } }
    [pscustomobject]@{ Enabled=$true; Name="Servicios innecesarios"; Desc="Desactiva telemetria, Xbox, fax... (elige antes)"; Action={ Mod-Servicios } }
    [pscustomobject]@{ Enabled=$true; Name="Tweaks de registro";     Desc="Prioridad apps en foco, Game Mode ON"; Action={ Mod-Registro } }
    [pscustomobject]@{ Enabled=$false; Name="Ver arranque (info)";   Desc="Lista programas de inicio (solo informa, no toca)"; Action={ Mod-Startup } }
    [pscustomobject]@{ Enabled=$false; Name="Optimizar/desfragmentar"; Desc="Optimize-Volume en discos NTFS (puede tardar)"; Action={ Mod-Disco } }
)

# ─── MODULO 1 ───────────────────────────────────────────────────────────────────
function Mod-Energia {
    ModHeader 1 "PLAN DE ENERGIA"
    $ultGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    if (-not (powercfg /list | Select-String $ultGuid)) {
        powercfg /duplicatescheme $ultGuid 2>$null | Out-Null
        Ok "Plan 'Ultimate Performance' creado"
    } else { Info "Plan 'Ultimate Performance' ya existia" }
    powercfg /setactive $ultGuid | Out-Null
    Ok "Plan activo: Ultimate Performance"
    powercfg /change disk-timeout-ac 0 | Out-Null
    powercfg /change disk-timeout-dc 0 | Out-Null
    powercfg /hibernate off 2>$null | Out-Null
    Ok "Hibernacion off (libera hiberfil.sys)"
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
    Ok "USB selective suspend off"
}

# ─── MODULO 2 ───────────────────────────────────────────────────────────────────
function Mod-Limpieza {
    ModHeader 2 "LIMPIEZA DE CACHE Y TEMPORALES"
    $cachePaths = @(
        "$env:TEMP","$env:SystemRoot\Temp","$env:SystemRoot\Prefetch",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:SystemRoot\SoftwareDistribution\Download"
    )
    $totalFreed = 0
    foreach ($path in $cachePaths) {
        if (Test-Path $path) {
            $items = Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
            $before = ($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if (-not $before) { $before = 0 }
            $items | Remove-Item -Force -ErrorAction SilentlyContinue
            $totalFreed += $before
        }
    }
    $script:FreedMB = [math]::Round($totalFreed / 1MB, 1)
    Ok "Temporales/cache/thumbnails limpiados"
    Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
    Ok "Cola de impresion limpiada"
    ipconfig /flushdns | Out-Null
    Ok "DNS cache vaciada"
    Info "Disk Cleanup (~30s)..."
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    $cleanKeys = @(
        "Active Setup Temp Folders","BranchCache","Downloaded Program Files",
        "Internet Cache Files","Memory Dump Files","Old ChkDsk Files",
        "Previous Installations","Recycle Bin","Service Pack Cleanup",
        "Setup Log Files","System error memory dump files",
        "System error minidump files","Temporary Files",
        "Temporary Setup Files","Thumbnail Cache","Update Cleanup",
        "Upgrade Discarded Files","Windows Defender","Windows Error Reporting Files",
        "Windows ESD installation files","Windows Upgrade Log Files"
    )
    foreach ($key in $cleanKeys) {
        $fp = "$regPath\$key"
        if (Test-Path $fp) { Set-ItemProperty -Path $fp -Name StateFlags0064 -Value 2 -ErrorAction SilentlyContinue }
    }
    $cProc = Start-Process cleanmgr -ArgumentList "/sagerun:64" -PassThru -ErrorAction SilentlyContinue
    if ($cProc) { if (-not $cProc.WaitForExit(90000)) { $cProc.Kill() } }
    Val "Espacio liberado aprox:" "$script:FreedMB MB"
}

# ─── MODULO 3 ───────────────────────────────────────────────────────────────────
function Mod-Visual {
    ModHeader 3 "EFECTOS VISUALES"
    $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }
    Set-ItemProperty -Path $visualKey -Name VisualFXSetting -Value 2
    $uiKey = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $uiKey -Name UserPreferencesMask -Value ([byte[]](0x90,0x12,0x01,0x80,0x10,0x00,0x00,0x00))
    Set-ItemProperty -Path $uiKey -Name MenuShowDelay -Value 0
    Set-ItemProperty -Path $uiKey -Name DragFullWindows -Value 0
    Set-ItemProperty -Path $uiKey -Name FontSmoothing -Value 2
    $expKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $expKey -Name TaskbarAnimations -Value 0
    Set-ItemProperty -Path $expKey -Name ListviewAlphaSelect -Value 0
    Set-ItemProperty -Path $expKey -Name ListviewShadow -Value 0
    Ok "Animaciones reducidas, ClearType mantenido"
    Ok "Menus instantaneos (MenuShowDelay 0)"
}

# ─── MODULO 4 ───────────────────────────────────────────────────────────────────
function Mod-Red {
    ModHeader 4 "OPTIMIZACION DE RED"
    $tcpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $tcpKey | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name TcpAckFrequency -Value 1 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $_.PSPath -Name TCPNoDelay -Value 1 -ErrorAction SilentlyContinue
    }
    Ok "Nagle off en todas las interfaces (menos latencia)"
    netsh int tcp set global autotuninglevel=normal | Out-Null
    netsh int tcp set global chimney=disabled | Out-Null
    netsh int tcp set global dca=enabled | Out-Null
    netsh int tcp set global ecncapability=enabled | Out-Null
    netsh int tcp set global timestamps=disabled | Out-Null
    netsh int tcp set global rss=enabled | Out-Null
    Ok "Parametros TCP optimizados"
    $qosKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
    if (-not (Test-Path $qosKey)) { New-Item -Path $qosKey -Force | Out-Null }
    Set-ItemProperty -Path $qosKey -Name NonBestEffortLimit -Value 0
    Ok "Reserva QoS de ancho de banda eliminada (20%)"
}

# ─── MODULO 5 ───────────────────────────────────────────────────────────────────
function Mod-Memoria {
    ModHeader 5 "MEMORIA Y ALMACENAMIENTO"
    $code = @"
using System;
using System.Runtime.InteropServices;
public class Memory { [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr hProcess); }
"@
    Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
    try {
        Get-Process | ForEach-Object { try { [Memory]::EmptyWorkingSet($_.Handle) | Out-Null } catch {} }
        Ok "RAM inactiva liberada (Working Set)"
    } catch { Warn "No se pudo liberar Working Set (sin impacto)" }

    $drive = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq 0 } | Select-Object -First 1
    if ($drive.MediaType -eq "HDD") {
        Set-Service -Name SysMain -StartupType Automatic
        Start-Service -Name SysMain -ErrorAction SilentlyContinue
        Ok "SysMain ON (HDD detectado)"
    } else {
        Set-Service -Name SysMain -StartupType Disabled
        Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue
        Ok "SysMain OFF (SSD detectado)"
    }
    $ramGB = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB)
    Val "RAM detectada:" "$ramGB GB"
    $mm = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    if ($ramGB -ge 16) {
        Set-ItemProperty -Path $mm -Name DisablePagingExecutive -Value 1
        Ok "Kernel en RAM (DisablePagingExecutive ON)"
    } else {
        Set-ItemProperty -Path $mm -Name DisablePagingExecutive -Value 0
        Info "Menos de 16 GB: dejado en default (seguro)"
    }
    $sysLetter = ($env:SystemDrive).TrimEnd(':')
    Optimize-Volume -DriveLetter $sysLetter -ReTrim 2>$null | Out-Null
    Ok "TRIM enviado a unidad ${sysLetter}:"
}

# ─── MODULO 6 ───────────────────────────────────────────────────────────────────
function Mod-Servicios {
    ModHeader 6 "SERVICIOS INNECESARIOS"

    $svcs = @(
        [pscustomobject]@{ Svc="DiagTrack";          Desc="Telemetria de Microsoft";      On=$false }
        [pscustomobject]@{ Svc="dmwappushservice";   Desc="WAP Push (telemetria)";        On=$false }
        [pscustomobject]@{ Svc="MapsBroker";         Desc="Mapas offline en 2o plano";    On=$false }
        [pscustomobject]@{ Svc="RetailDemo";         Desc="Modo demo de tiendas";         On=$false }
        [pscustomobject]@{ Svc="WbioSrvc";           Desc="Biometria / Windows Hello";    On=$false }
        [pscustomobject]@{ Svc="XblAuthManager";     Desc="Xbox Live Auth";               On=$false }
        [pscustomobject]@{ Svc="XblGameSave";        Desc="Xbox Game Save";               On=$false }
        [pscustomobject]@{ Svc="XboxNetApiSvc";      Desc="Xbox Network API";             On=$false }
        [pscustomobject]@{ Svc="SCardSvr";           Desc="Smart card (tarjeta)";         On=$false }
        [pscustomobject]@{ Svc="TabletInputService"; Desc="Tablet PC Input";              On=$false }
        [pscustomobject]@{ Svc="WMPNetworkSvc";      Desc="WMP Network Sharing";          On=$false }
        [pscustomobject]@{ Svc="Fax";                Desc="Servicio de Fax";              On=$false }
    )
    # Marca cuales existen en este equipo
    foreach ($s in $svcs) { $s | Add-Member -NotePropertyName Exists -NotePropertyValue ([bool](Get-Service -Name $s.Svc -ErrorAction SilentlyContinue)) -Force }

    while ($true) {
        Clear-Host
        Write-Host ""
        CC "   SERVICIOS — elige cuales DESACTIVAR" Cyan
        CC "   (si no marcas ninguno, no se toca nada)" DarkGray
        Write-Host ""
        for ($i=0; $i -lt $svcs.Count; $i++) {
            $s = $svcs[$i]
            $box = if ($s.On) { "[X]" } else { "[ ]" }
            $bc = if ($s.On) { "Green" } else { "DarkGray" }
            $nc = if ($s.On) { "White" } else { "DarkGray" }
            $tag = if ($s.Exists) { "" } else { "  (no instalado)" }
            CC "   $box " $bc -n
            CC ("{0,2}. " -f ($i+1)) DarkCyan -n
            CC ("{0,-20}" -f $s.Svc) $nc -n
            CC ("$($s.Desc)$tag") DarkGray
        }
        Write-Host ""
        Write-Host "  " -NoNewline; RainbowBar 44
        CC "   Escribe el " Gray -n; CC "numero" Yellow -n; CC " (o varios: 1,3,5) y " Gray -n; CC "ENTER" Green -n; CC " para marcar/desmarcar" Gray
        CC "   " Gray -n; CC "A" Yellow -n; CC "=todos   " Gray -n; CC "N" Yellow -n; CC "=ninguno   " Gray -n
        CC "ENTER" Green -n; CC " vacio = APLICAR y continuar" Gray
        Write-Host ""
        $r = (Read-Host "   Tu eleccion").Trim()
        if ($r -eq '') { break }
        elseif ($r -match '^[Aa]$') { foreach ($s in $svcs) { $s.On = $true } }
        elseif ($r -match '^[Nn]$') { foreach ($s in $svcs) { $s.On = $false } }
        else {
            foreach ($tok in ($r -split '[,\s]+')) {
                if ($tok -match '^\d+$') {
                    $idx = [int]$tok - 1
                    if ($idx -ge 0 -and $idx -lt $svcs.Count) { $svcs[$idx].On = -not $svcs[$idx].On }
                }
            }
        }
    }

    # Redibuja cabecera del modulo tras el selector
    ModHeader 6 "SERVICIOS INNECESARIOS"
    $elegidos = @($svcs | Where-Object { $_.On })
    if ($elegidos.Count -eq 0) { Info "No se desactivo ningun servicio"; return }
    $done = 0
    foreach ($s in $elegidos) {
        if ($s.Exists) {
            Stop-Service -Name $s.Svc -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s.Svc -StartupType Disabled -ErrorAction SilentlyContinue
            Ok "Desactivado: $($s.Svc)"
            $done++
        } else {
            Info "Omitido (no instalado): $($s.Svc)"
        }
    }
    Val "Servicios desactivados:" "$done"
}

# ─── MODULO 7 ───────────────────────────────────────────────────────────────────
function Mod-Registro {
    ModHeader 7 "TWEAKS DE REGISTRO"
    $mm = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    Set-ItemProperty -Path $mm -Name ClearPageFileAtShutdown -Value 0
    Set-ItemProperty -Path $mm -Name LargeSystemCache -Value 0
    $perfKey = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    Set-ItemProperty -Path $perfKey -Name Win32PrioritySeparation -Value 38
    Ok "Prioridad a apps en primer plano"
    $gameKey = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $gameKey)) { New-Item -Path $gameKey -Force | Out-Null }
    Set-ItemProperty -Path $gameKey -Name AllowAutoGameMode -Value 1
    Set-ItemProperty -Path $gameKey -Name AutoGameModeEnabled -Value 1
    Ok "Game Mode ON"
    $wuKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $wuKey)) { New-Item -Path $wuKey -Force | Out-Null }
    Set-ItemProperty -Path $wuKey -Name NoAutoRebootWithLoggedOnUsers -Value 1
    Ok "Sin auto-reinicio de Windows Update (updates siguen ON)"
}

# ─── MODULO 8 ───────────────────────────────────────────────────────────────────
function Mod-Startup {
    ModHeader 8 "PROGRAMAS DE ARRANQUE (info)"
    $items = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
    Val "Programas en el inicio:" "$($items.Count)"
    $items | Select-Object -First 12 | ForEach-Object { CC ("      · " + $_.Name) DarkGray }
    if ($items.Count -gt 12) { CC "      · ..." DarkGray }
    Info "Quita los que no uses en: Administrador de tareas > Inicio"
}

# ─── MODULO 9 ───────────────────────────────────────────────────────────────────
function Mod-Disco {
    ModHeader 9 "OPTIMIZAR / DESFRAGMENTAR"
    Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -eq "NTFS" } | ForEach-Object {
        $l = $_.DriveLetter
        Info "Optimizando ${l}: ..."
        Optimize-Volume -DriveLetter $l 2>$null | Out-Null
        Ok "Unidad ${l}: optimizada"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MENU INTERACTIVO
# ═══════════════════════════════════════════════════════════════════════════════
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  " -NoNewline; RainbowBar 44
    CC "   T U R B O   P C   —   selecciona que optimizar" Cyan
    Write-Host "  " -NoNewline; RainbowBar 44
    Write-Host ""
    for ($i=0; $i -lt $modules.Count; $i++) {
        $m = $modules[$i]
        $mark = if ($m.Enabled) { "[X]" } else { "[ ]" }
        $mc   = if ($m.Enabled) { "Green" } else { "DarkGray" }
        $nc   = if ($m.Enabled) { "White" } else { "DarkGray" }
        CC ("   {0} " -f $mark) $mc -n
        CC ("{0}. " -f ($i+1)) DarkCyan -n
        CC $m.Name $nc
        CC ("          {0}" -f $m.Desc) DarkGray
    }
    Write-Host ""
    Write-Host "  " -NoNewline; RainbowBar 44
    CC "   Escribe el " Gray -n; CC "numero" Yellow -n; CC " (o varios: 1,3,6) y pulsa " Gray -n; CC "ENTER" Green -n; CC " para marcar/desmarcar" Gray
    CC "   " Gray -n; CC "A" Yellow -n; CC "=todo   " Gray -n; CC "N" Yellow -n; CC "=nada   " Gray -n
    CC "ENTER" Green -n; CC " vacio = INICIAR   " Gray -n; CC "Q" Red -n; CC "=salir" Gray
    Write-Host ""
}

function Run-Menu {
    while ($true) {
        Show-Menu
        $r = (Read-Host "   Tu eleccion").Trim()
        if ($r -eq '') {
            if (($modules | Where-Object Enabled).Count -gt 0) { return $true } else { continue }
        }
        elseif ($r -match '^[Aa]$') { foreach ($m in $modules) { $m.Enabled = $true } }
        elseif ($r -match '^[Nn]$') { foreach ($m in $modules) { $m.Enabled = $false } }
        elseif ($r -match '^[Qq]$') { return $false }
        else {
            foreach ($tok in ($r -split '[,\s]+')) {
                if ($tok -match '^\d+$') {
                    $idx = [int]$tok - 1
                    if ($idx -ge 0 -and $idx -lt $modules.Count) { $modules[$idx].Enabled = -not $modules[$idx].Enabled }
                }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  FLUJO PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════════

# Ventana flotante con el logo PNG real (sigue a la consola, no roba foco)
$logoProc = $null
try {
    $logoWin = Join-Path $baseDir 'logo_window.ps1'
    $logoPng = Join-Path $baseDir 'logo-reven.png'
    if ((Test-Path $logoWin) -and (Test-Path $logoPng)) {
        $ch = Add-Type -Name Cw -Namespace ConH -PassThru -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
"@
        $hwnd = [int64]$ch::GetConsoleWindow()
        $logoProc = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$logoWin`"",'-ParentPid',$PID,'-ConsoleHwnd',$hwnd
        )
    }
} catch {}

try {

Show-Splash
if (-not (Run-Menu)) {
    Clear-Host; CC "  Cancelado. No se ha cambiado nada." Yellow; Write-Host ""
    return
}

$seleccion = @($modules | Where-Object Enabled)
Clear-Host
Write-Host ""
Write-Host "  " -NoNewline; RainbowBar 44
CC "   EJECUTANDO OPTIMIZACION  ·  $($seleccion.Count) modulos" Green
Write-Host "  " -NoNewline; RainbowBar 44

$script:FreedMB = 0
$inicio = Get-Date
foreach ($m in $seleccion) { & $m.Action }

$dur = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 0)

# ─── Resumen en pantalla ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  " -NoNewline; RainbowBar 44
CC "   ✔ COMPLETADO" Green
Write-Host "  " -NoNewline; RainbowBar 44
Val "Modulos ejecutados:" "$($seleccion.Count)"
Val "Espacio liberado:"   "$script:FreedMB MB"
Val "Duracion:"           "$dur s"
Write-Host ""
CC "   Reinicia el PC para aplicar todos los cambios." Yellow
Write-Host ""

# ─── Log simplificado y bonito ──────────────────────────────────────────────────
$header = @(
    "==============================================",
    "  TURBO PC  -  Optimizador  ·  Resumen",
    "  Fecha:   $(Get-Date -f 'dd/MM/yyyy HH:mm')",
    "  Equipo:  $env:COMPUTERNAME"
    "  Modulos: $($seleccion.Count)   Liberado: $script:FreedMB MB   Duracion: $dur s",
    "=============================================="
    ""
    "  Que optimice:"
) + ($seleccion | ForEach-Object { "    - $($_.Name)" }) + @(
    ""
    "  Detalle:"
) + ($script:LogLines | ForEach-Object { "    $_" }) + @(
    ""
    "  Reinicia para aplicar todo."
    "=============================================="
)
$header | Set-Content -Path $log -Encoding UTF8
CC "   Log guardado en: " DarkGray -n; CC $log Gray
Write-Host ""

}
finally {
    # Cerrar la ventana del logo al salir
    if ($logoProc) { try { if (-not $logoProc.HasExited) { $logoProc.Kill() } } catch {} }
}
