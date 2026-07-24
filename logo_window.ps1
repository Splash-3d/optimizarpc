# Ventana flotante con el logo PNG real. Sigue a la ventana de la consola.
param([int]$ParentPid = 0, [long]$ConsoleHwnd = 0)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class NoActForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE (no roba foco)
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW (fuera de alt-tab)
            return cp;
        }
    }
}
public struct RECT { public int Left, Top, Right, Bottom; }
public static class Win {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@

$png = Join-Path $PSScriptRoot 'logo-reven.png'
if (-not (Test-Path $png)) { return }
$img = [System.Drawing.Image]::FromFile($png)

$form = New-Object NoActForm
$form.FormBorderStyle = 'None'
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.StartPosition = 'Manual'
$form.BackColor = [System.Drawing.Color]::FromArgb(9, 13, 38)

$pb = New-Object System.Windows.Forms.PictureBox
$pb.Dock = 'Fill'
$pb.SizeMode = 'Zoom'
$pb.Image = $img
$form.Controls.Add($pb)

$hwnd    = [IntPtr]$ConsoleHwnd
$screenH = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
$maxSz   = [int]([Math]::Min($screenH * 0.55, 620))
$margin  = 24

# Posicion inicial (por si no hay handle valido)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Size = New-Object System.Drawing.Size($maxSz, $maxSz)
$form.Location = New-Object System.Drawing.Point(($wa.Right - $maxSz - $margin), ($wa.Top + [int](($wa.Height - $maxSz) / 2)))

# Seguir a la consola
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
    # Cerrar si el optimizador ya no existe
    if ($ParentPid -gt 0 -and -not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { $form.Close(); return }

    if ($hwnd -ne [IntPtr]::Zero -and [Win]::IsWindow($hwnd)) {
        # Oculta el logo si la consola esta minimizada o no visible
        if ([Win]::IsIconic($hwnd) -or -not [Win]::IsWindowVisible($hwnd)) {
            if ($form.Visible) { $form.Hide() }
            return
        }
        $r = New-Object RECT
        if ([Win]::GetWindowRect($hwnd, [ref]$r)) {
            $ch = $r.Bottom - $r.Top
            $sz = [int]([Math]::Min($maxSz, $ch - 20))
            if ($sz -lt 60) { if ($form.Visible) { $form.Hide() }; return }
            $scr  = [System.Windows.Forms.Screen]::FromHandle($hwnd).WorkingArea
            $offL = 140   # desplazamiento a la izquierda
            # Preferido: FUERA de la consola, pegado a su derecha (no tapa texto)
            $x = $r.Right + 8
            # Si no cabe fuera (consola maximizada), pegar cerca del borde derecho (mas a la izquierda)
            if ($x + $sz -gt $scr.Right) { $x = $scr.Right - $sz - $offL }
            if ($x -lt $scr.Left) { $x = $scr.Left }
            $y = $r.Top + [int](($ch - $sz) / 2)
            if ($y -lt $scr.Top) { $y = $scr.Top }
            if ($y + $sz -gt $scr.Bottom) { $y = $scr.Bottom - $sz }
            if ($form.Width -ne $sz) { $form.Size = New-Object System.Drawing.Size($sz, $sz) }
            $form.Location = New-Object System.Drawing.Point($x, $y)
            if (-not $form.Visible) { $form.Show() }
            $form.TopMost = $true
        }
    }
})
$timer.Start()

[System.Windows.Forms.Application]::Run($form)
