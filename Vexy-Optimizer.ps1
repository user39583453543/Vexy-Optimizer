# VEXY Optimizer - V6 prototype
# Windows PowerShell 5.1 / WPF
# Public build: activation keys are NOT stored in plaintext.

$ErrorActionPreference = 'Continue'
$script:VexyVersion = '6.0.2-enterfix'
$script:RepoBase = 'https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/main'
$script:ScriptUrl = "$script:RepoBase/Vexy-Optimizer.ps1"

# ---------- Robust elevation (works both as a local .ps1 and via irm | iex) ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    try {
        if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath)
            )
        }
        else {
            $elevatedCopy = Join-Path $env:TEMP 'Vexy-Optimizer-Elevated.ps1'
            Invoke-WebRequest -Uri $script:ScriptUrl -OutFile $elevatedCopy -UseBasicParsing -ErrorAction Stop
            Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $elevatedCopy)
            )
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show('VEXY needs administrator permission to apply system optimizations.','VEXY') | Out-Null
    }
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Security
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# ---------- Fast native memory status ----------
if (-not ([System.Management.Automation.PSTypeName]'VexyNative.Memory').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace VexyNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public class MEMORYSTATUSEX {
        public uint dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }
    public static class Memory {
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);
    }
}
'@
}

# =====================================================================
# ASSETS
# Upload these paths to the GitHub repository:
#   vexy_logo.png
#   vexy_background.png
#   vexy_music.mp3
#   assets/icons/*.png
# =====================================================================
$script:AssetDir = Join-Path $env:LOCALAPPDATA 'VexyOptimizer\Assets'
$script:IconDir = Join-Path $script:AssetDir 'icons'
New-Item -ItemType Directory -Path $script:IconDir -Force | Out-Null

function Get-VexyAsset {
    param(
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [Parameter(Mandatory=$true)][string]$CacheName
    )
    $target = Join-Path $script:AssetDir $CacheName
    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

    # Local file beside the script wins when available.
    if ($PSCommandPath) {
        $scriptFolder = Split-Path -Parent $PSCommandPath
        if ($scriptFolder) {
            $local = Join-Path $scriptFolder $RelativePath
            if (Test-Path $local) { return $local }
        }
    }

    if (Test-Path $target) { return $target }
    try {
        $url = "$script:RepoBase/$($RelativePath.Replace('\\','/'))"
        Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing -ErrorAction Stop
        if (Test-Path $target) { return $target }
    } catch {}
    return $null
}

$script:LogoPath = Get-VexyAsset 'vexy_logo.png' 'vexy_logo.png'
$script:BackgroundPath = Get-VexyAsset 'vexy_background.png' 'vexy_background.png'
$script:MusicPath = Get-VexyAsset 'vexy_music.mp3' 'vexy_music.mp3'

function Get-VexyIconPath([string]$Name) {
    return Get-VexyAsset ("assets/icons/{0}.png" -f $Name) ("icons\{0}.png" -f $Name)
}

function New-VexyBitmap([string]$Path) {
    if (-not $Path -or -not (Test-Path $Path)) { return $null }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.UriSource = New-Object System.Uri($Path, [System.UriKind]::Absolute)
        $bmp.EndInit()
        $bmp.Freeze()
        return $bmp
    } catch { return $null }
}

# =====================================================================
# UI SOUNDS - tiny generated WAV files, so no extra sound files required.
# =====================================================================
$script:SoundDir = Join-Path $env:LOCALAPPDATA 'VexyOptimizer\Sounds'
New-Item -ItemType Directory -Path $script:SoundDir -Force | Out-Null

function New-VexyToneWav {
    param([string]$Path,[double]$Frequency,[int]$Milliseconds,[double]$Volume)
    if (Test-Path $Path) { return }
    try {
        $sampleRate = 44100
        $samples = [int]($sampleRate * ($Milliseconds / 1000.0))
        $dataSize = $samples * 2
        $fs = [System.IO.File]::Open($Path,[System.IO.FileMode]::Create)
        $bw = New-Object System.IO.BinaryWriter($fs)
        $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
        $bw.Write([int](36 + $dataSize))
        $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
        $bw.Write([Text.Encoding]::ASCII.GetBytes('fmt '))
        $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
        $bw.Write([int]$sampleRate); $bw.Write([int]($sampleRate * 2)); $bw.Write([int16]2); $bw.Write([int16]16)
        $bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]$dataSize)
        for ($i=0; $i -lt $samples; $i++) {
            $fade = 1.0 - ($i / [double]$samples)
            $s = [Math]::Sin(2 * [Math]::PI * $Frequency * $i / $sampleRate)
            $value = [int16]([Math]::Max([int16]::MinValue,[Math]::Min([int16]::MaxValue,32767 * $Volume * $fade * $s)))
            $bw.Write($value)
        }
        $bw.Close(); $fs.Close()
    } catch {}
}

$script:HoverSound = Join-Path $script:SoundDir 'hover.wav'
$script:ClickSound = Join-Path $script:SoundDir 'click.wav'
$script:SuccessSound = Join-Path $script:SoundDir 'success.wav'
$script:WarningSound = Join-Path $script:SoundDir 'warning.wav'
New-VexyToneWav $script:HoverSound 520 28 0.08
New-VexyToneWav $script:ClickSound 760 45 0.14
New-VexyToneWav $script:SuccessSound 920 90 0.12
New-VexyToneWav $script:WarningSound 260 110 0.12

function Play-VexySound([string]$Kind) {
    $path = switch ($Kind) {
        'Hover'   { $script:HoverSound }
        'Click'   { $script:ClickSound }
        'Success' { $script:SuccessSound }
        'Warning' { $script:WarningSound }
        default   { $null }
    }
    if ($path -and (Test-Path $path)) {
        try { (New-Object System.Media.SoundPlayer $path).Play() } catch {}
    }
}

# =====================================================================
# ACTIVATION - public script contains only SHA-256 hashes.
# The plaintext keys are kept in VEXY_KEYS_PRIVATE.txt and should NOT be
# uploaded to the public repository.
# =====================================================================
$script:LicenseTable = @{
    '425748BA523DB65D036F782B7E742911936193FCFB8931856465D5B26C4F7AEF' = @{ Days = 1;   Label = '1 DAY' }
    '4A099E5B1B4377C7D4CE5BB15C4745D6CEE37C2E6EB8DB8FDBFA481B3394DA7D' = @{ Days = 3;   Label = '3 DAYS' }
    '7A49A2BA8F2E7AF370EBBC30E28779C91566F1DDE089B81EC53443808E83C985' = @{ Days = 7;   Label = '7 DAYS' }
    '9633EE8F32B37A281ACE55A90AB3E5D361823510F6836A027245CF4D354AA34E' = @{ Days = 14;  Label = '2 WEEKS' }
    '7875480DDDA0C70A6FDC6F6F400342DDBA2DC21915D2F9400E6B14063725BEDF' = @{ Days = 30;  Label = '1 MONTH' }
    '4E0270CC988A6C7F929DE04ED8F1B77BA79B5728A75FDA337A90E0CACF3E72B1' = @{ Days = 365; Label = '1 YEAR' }
    '06A851A6AD14CE852FCE85F8ECF8AC37AA125DA658E958C62516EC53A3220D78' = @{ Days = -1;  Label = 'LIFETIME' }
}

$script:LicenseDir = Join-Path $env:APPDATA 'VexyOptimizer'
$script:LicenseFile = Join-Path $script:LicenseDir 'license.dat'
New-Item -ItemType Directory -Path $script:LicenseDir -Force | Out-Null

function Get-VexyHash([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text.Trim().ToUpperInvariant())
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
    } finally { $sha.Dispose() }
}

function New-EmptyLicenseStore { return @{ ActiveHash = ''; History = @{} } }

function Load-VexyLicenseStore {
    if (-not (Test-Path $script:LicenseFile)) { return (New-EmptyLicenseStore) }
    try {
        $cipher = [Convert]::FromBase64String([IO.File]::ReadAllText($script:LicenseFile))
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $raw = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
        $store = New-EmptyLicenseStore
        if ($raw.ActiveHash) { $store.ActiveHash = [string]$raw.ActiveHash }
        if ($raw.History) {
            $raw.History.PSObject.Properties | ForEach-Object { $store.History[$_.Name] = [string]$_.Value }
        }
        return $store
    } catch { return (New-EmptyLicenseStore) }
}

function Save-VexyLicenseStore($Store) {
    try {
        $json = (@{ ActiveHash = $Store.ActiveHash; History = $Store.History } | ConvertTo-Json -Depth 5 -Compress)
        $plain = [Text.Encoding]::UTF8.GetBytes($json)
        $cipher = [Security.Cryptography.ProtectedData]::Protect($plain,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllText($script:LicenseFile,[Convert]::ToBase64String($cipher))
    } catch {}
}

function Test-VexyLicenseHash([string]$Hash,[hashtable]$Store,[switch]$StartIfNew) {
    if (-not $script:LicenseTable.ContainsKey($Hash)) {
        return [pscustomobject]@{ Valid=$false; Reason='Key not recognized.'; Label=''; Remaining='' }
    }
    $entry = $script:LicenseTable[$Hash]
    if (-not $Store.History.ContainsKey($Hash)) {
        if (-not $StartIfNew) { return [pscustomobject]@{ Valid=$false; Reason='License has not been activated on this Windows account.'; Label=$entry.Label; Remaining='' } }
        $Store.History[$Hash] = (Get-Date).ToString('o')
    }
    $start = [datetime]$Store.History[$Hash]
    if ([int]$entry.Days -lt 0) {
        return [pscustomobject]@{ Valid=$true; Reason=''; Label=$entry.Label; Remaining='LIFETIME' }
    }
    $expiry = $start.AddDays([int]$entry.Days)
    $span = $expiry - (Get-Date)
    if ($span.TotalSeconds -le 0) {
        return [pscustomobject]@{ Valid=$false; Reason=('License expired on {0}.' -f $expiry.ToString('dd MMM yyyy HH:mm')); Label=$entry.Label; Remaining='EXPIRED' }
    }
    $remaining = if ($span.TotalDays -ge 1) { '{0}d {1}h' -f [Math]::Floor($span.TotalDays),$span.Hours } else { '{0}h {1}m' -f [Math]::Floor($span.TotalHours),$span.Minutes }
    return [pscustomobject]@{ Valid=$true; Reason=''; Label=$entry.Label; Remaining=$remaining }
}

$script:LicenseStore = Load-VexyLicenseStore
$script:CurrentLicense = $null
if ($script:LicenseStore.ActiveHash) {
    $script:CurrentLicense = Test-VexyLicenseHash $script:LicenseStore.ActiveHash $script:LicenseStore
}

# =====================================================================
# OPTIMIZATION ACTIONS
# Deliberately reversible / standard Windows settings. Advanced actions
# are shown with warnings before execution.
# =====================================================================
function New-VexyRestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'VEXY - Before Optimization' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        'Restore point created.'
    } catch { "Restore point could not be created: $($_.Exception.Message)" }
}

function Set-VexyGameMode {
    try {
        New-Item 'HKCU:\Software\Microsoft\GameBar' -Force | Out-Null
        Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Type DWord -Value 1 -Force
        'Windows Game Mode enabled.'
    } catch { "Game Mode error: $($_.Exception.Message)" }
}

function Set-VexyGameDvrOff {
    try {
        New-Item 'HKCU:\System\GameConfigStore' -Force | Out-Null
        Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Type DWord -Value 0 -Force
        New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Force | Out-Null
        Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Type DWord -Value 0 -Force
        'Background game capture disabled.'
    } catch { "Game capture error: $($_.Exception.Message)" }
}

function Set-VexyHighPerformance {
    try {
        powercfg.exe /setactive SCHEME_MIN | Out-Null
        'High Performance power plan selected. This can increase power use and heat.'
    } catch { "Power plan error: $($_.Exception.Message)" }
}

function Clear-VexyUserTemp {
    $removed = 0
    try {
        Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $removed++ } catch {}
        }
        "User temporary files cleaned ($removed item(s) removed; locked files skipped)."
    } catch { "Cleanup error: $($_.Exception.Message)" }
}

function Clear-VexyDnsCache {
    try { ipconfig.exe /flushdns | Out-Null; 'Windows DNS resolver cache flushed.' }
    catch { "DNS flush error: $($_.Exception.Message)" }
}

function Set-VexyMouseAccelOff {
    try {
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -Value '0' -Force
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1 -Value '0' -Force
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2 -Value '0' -Force
        'Enhance Pointer Precision / mouse acceleration disabled for the current user.'
    } catch { "Mouse setting error: $($_.Exception.Message)" }
}

function Set-VexyHags {
    try {
        New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Force | Out-Null
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -Type DWord -Value 2 -Force
        'Hardware-accelerated GPU scheduling requested. Reboot required; effect depends on GPU/driver.'
    } catch { "HAGS error: $($_.Exception.Message)" }
}

function Set-VexyNetworkPower {
    $changed = 0
    try {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
                $changed++
            } catch {}
        }
        "Disabled Windows power-off permission on $changed physical network adapter(s)."
    } catch { "Network adapter power error: $($_.Exception.Message)" }
}

function Set-VexyCloudflareDns {
    $changed = 0
    try {
        Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $_.IfIndex -ServerAddresses @('1.1.1.1','1.0.0.1') -ErrorAction Stop
                $changed++
            } catch {}
        }
        "Cloudflare DNS set on $changed active physical adapter(s)."
    } catch { "DNS change error: $($_.Exception.Message)" }
}

function Set-VexyVisualPerformance {
    try {
        New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Force | Out-Null
        Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Type DWord -Value 2 -Force
        'Windows visual effects preference set to Best Performance. Sign-out/restart Explorer may be required.'
    } catch { "Visual effects error: $($_.Exception.Message)" }
}

function Invoke-VexyDiskOptimize {
    $done = @()
    try {
        Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
            try { Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction Stop; $done += "$($_.DriveLetter):" } catch {}
        }
        if ($done.Count) { 'Requested Windows TRIM/retrim on: ' + ($done -join ', ') } else { 'No eligible fixed volume was optimized.' }
    } catch { "Disk optimization error: $($_.Exception.Message)" }
}

function Open-VexyStartupManager {
    try { Start-Process 'taskmgr.exe'; 'Task Manager opened. Select Startup apps to manage startup programs.' }
    catch { "Could not open Task Manager: $($_.Exception.Message)" }
}

function Get-VexyDiagnosticsText {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object Name -NotMatch 'Remote|Basic' | Select-Object -First 1
        $ram = New-Object VexyNative.MEMORYSTATUSEX
        [VexyNative.Memory]::GlobalMemoryStatusEx($ram) | Out-Null
        $gb = [Math]::Round($ram.ullTotalPhys / 1GB,1)
        "Windows: $($os.Caption) | CPU: $($cpu.Name) | GPU: $($gpu.Name) | RAM: $gb GB"
    } catch { 'Diagnostics completed with limited hardware information.' }
}

# =====================================================================
# MAIN WINDOW
# =====================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="VEXY Optimizer" WindowStyle="None" WindowState="Maximized"
        ResizeMode="NoResize" Background="#020104" Foreground="White"
        ShowInTaskbar="True" Topmost="False" FontFamily="Segoe UI">
    <Window.Resources>
        <SolidColorBrush x:Key="Purple" Color="#A23BFF"/>
        <SolidColorBrush x:Key="Purple2" Color="#6B1ED7"/>
        <SolidColorBrush x:Key="Panel" Color="#D9080710"/>
        <SolidColorBrush x:Key="Panel2" Color="#E40C0913"/>
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Height" Value="48"/><Setter Property="Margin" Value="10,3"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Padding" Value="16,0"/>
            <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#CBB9DD"/>
            <Setter Property="BorderBrush" Value="Transparent"/><Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="14"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
                <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                    <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#47215F78"/><Setter TargetName="bd" Property="BorderBrush" Value="#7135B4"/><Setter Property="Foreground" Value="White"/></Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate></Setter.Value></Setter>
        </Style>
        <Style x:Key="PurpleButton" TargetType="Button">
            <Setter Property="Background" Value="#6E1FC4"/><Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#C45AFF"/><Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="20,10"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
                <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                </Border>
                <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#8E2FE8"/><Setter TargetName="bd" Property="BorderBrush" Value="#E8A8FF"/></Trigger></ControlTemplate.Triggers>
            </ControlTemplate></Setter.Value></Setter>
        </Style>
        <Style x:Key="TextInput" TargetType="TextBox">
            <Setter Property="Background" Value="#C40B0711"/><Setter Property="Foreground" Value="White"/><Setter Property="CaretBrush" Value="#C45AFF"/>
            <Setter Property="BorderBrush" Value="#7135B4"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="14,11"/><Setter Property="FontSize" Value="15"/>
        </Style>
    </Window.Resources>

    <Grid x:Name="Root">
        <Image x:Name="BackgroundImage" Stretch="UniformToFill" Opacity="0.72"/>
        <Rectangle Fill="#8A000000"/>
        <Rectangle>
            <Rectangle.Fill>
                <RadialGradientBrush Center="0.5,0.42" RadiusX="0.8" RadiusY="0.75">
                    <GradientStop Color="#00110022" Offset="0"/>
                    <GradientStop Color="#500A0015" Offset="0.55"/>
                    <GradientStop Color="#D9000000" Offset="1"/>
                </RadialGradientBrush>
            </Rectangle.Fill>
        </Rectangle>
        <Canvas x:Name="StarCanvas" IsHitTestVisible="False"/>

        <!-- LOADING -->
        <Grid x:Name="LoadingView">
            <StackPanel Width="620" HorizontalAlignment="Center" VerticalAlignment="Center">
                <Image x:Name="LoadingLogo" Height="310" Stretch="Uniform"/>
                <TextBlock Text="V E X Y" HorizontalAlignment="Center" Foreground="#F0D8FF" FontSize="42" FontWeight="Light" Margin="0,14,0,0"/>
                <TextBlock x:Name="LoadingStatus" Text="INITIALIZING VEXY CORE..." HorizontalAlignment="Center" Foreground="#A98EBB" FontSize="13" Margin="0,22,0,12"/>
                <ProgressBar x:Name="LoadingProgress" Height="3" Minimum="0" Maximum="100" Value="4" Foreground="#A23BFF" Background="#35203F" BorderThickness="0"/>
            </StackPanel>
        </Grid>

        <!-- ACTIVATION -->
        <Grid x:Name="ActivationView" Visibility="Collapsed">
            <Border Width="570" Background="#E50A0710" BorderBrush="#7135B4" BorderThickness="1" CornerRadius="16" Padding="34" HorizontalAlignment="Center" VerticalAlignment="Center">
                <Border.Effect><DropShadowEffect Color="#A23BFF" BlurRadius="40" ShadowDepth="0" Opacity="0.32"/></Border.Effect>
                <StackPanel>
                    <Image x:Name="ActivationLogo" Height="205" Stretch="Uniform" Margin="0,-16,0,2"/>
                    <TextBlock Text="ACTIVATE VEXY" HorizontalAlignment="Center" FontSize="29" FontWeight="Light" Foreground="#F3E8FF"/>
                    <TextBlock Text="ENTER YOUR ACCESS KEY TO CONTINUE" HorizontalAlignment="Center" FontSize="11" Foreground="#8E7E9E" Margin="0,7,0,23"/>
                    <TextBox x:Name="ActivationKeyBox" Style="{StaticResource TextInput}" Height="46"/>
                    <TextBlock x:Name="ActivationStatus" Text="" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Foreground="#BCA6CC" Margin="0,13,0,13"/>
                    <Button x:Name="ActivationButton" Style="{StaticResource PurpleButton}" Content="ACTIVATE" Height="48"/>
                    <TextBlock Text="VEXY // PERFORMANCE • STABILITY • CONTROL" HorizontalAlignment="Center" Foreground="#695777" FontSize="10" Margin="0,22,0,0"/>
                </StackPanel>
            </Border>
        </Grid>

        <!-- MAIN DASHBOARD -->
        <Grid x:Name="MainView" Visibility="Collapsed" Margin="12">
            <Grid.ColumnDefinitions><ColumnDefinition Width="235"/><ColumnDefinition Width="*"/><ColumnDefinition Width="290"/></Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="#E5090710" BorderBrush="#47215F" BorderThickness="1" CornerRadius="12" Margin="0,0,12,0">
                <Grid><Grid.RowDefinitions><RowDefinition Height="160"/><RowDefinition Height="*"/><RowDefinition Height="145"/></Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" VerticalAlignment="Center">
                        <Image x:Name="SidebarLogo" Height="105" Stretch="Uniform"/>
                        <TextBlock Text="OPTIMIZER" HorizontalAlignment="Center" Foreground="#A06DBE" FontSize="10"/>
                    </StackPanel>
                    <StackPanel x:Name="NavPanel" Grid.Row="1"/>
                    <StackPanel Grid.Row="2" Margin="14" VerticalAlignment="Bottom">
                        <Border Background="#500E0716" BorderBrush="#3F2450" BorderThickness="1" CornerRadius="8" Padding="12">
                            <StackPanel>
                                <TextBlock Text="STATUS" Foreground="#B95CFF" FontWeight="SemiBold"/>
                                <TextBlock x:Name="ReadyText" Text="● READY" Foreground="#4EE89A" FontSize="12" Margin="0,8,0,3"/>
                                <TextBlock x:Name="LicenseMini" Text="LICENSE" Foreground="#8E7E9E" FontSize="10" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                        <Button x:Name="ExitButton" Content="EXIT VEXY" Style="{StaticResource NavButton}" Foreground="#FF8FA6" Margin="0,8,0,0"/>
                    </StackPanel>
                </Grid>
            </Border>

            <Grid Grid.Column="1" Margin="0,0,12,0">
                <Grid.RowDefinitions><RowDefinition Height="115"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <Grid Grid.Row="0">
                    <StackPanel VerticalAlignment="Center" Margin="14,0">
                        <TextBlock x:Name="PageTitle" Text="WELCOME TO VEXY OPTIMIZER" FontSize="30" FontWeight="Light" Foreground="#F0E7F8"/>
                        <TextBlock x:Name="PageSubtitle" Text="MAXIMIZE PERFORMANCE. MINIMIZE LATENCY. KEEP CONTROL." FontSize="11" Foreground="#9985A8" Margin="1,8,0,0"/>
                    </StackPanel>
                </Grid>
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <WrapPanel x:Name="ActionGrid" Margin="8,4,0,20"/>
                </ScrollViewer>
            </Grid>

            <Grid Grid.Column="2">
                <Grid.RowDefinitions><RowDefinition Height="280"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                <Border Grid.Row="0" Background="#E5090710" BorderBrush="#47215F" BorderThickness="1" CornerRadius="12" Padding="16">
                    <StackPanel>
                        <TextBlock Text="SYSTEM OVERVIEW" Foreground="#B95CFF" FontSize="14" FontWeight="SemiBold"/>
                        <TextBlock x:Name="CpuText" Text="CPU     --%" Foreground="#DDD2E6" FontSize="13" Margin="0,20,0,3"/>
                        <ProgressBar x:Name="CpuBar" Height="5" Maximum="100" Foreground="#9B35F0" Background="#2A1832" BorderThickness="0"/>
                        <TextBlock x:Name="RamText" Text="RAM     --%" Foreground="#DDD2E6" FontSize="13" Margin="0,17,0,3"/>
                        <ProgressBar x:Name="RamBar" Height="5" Maximum="100" Foreground="#9B35F0" Background="#2A1832" BorderThickness="0"/>
                        <TextBlock x:Name="SystemInfoText" Text="Detecting hardware..." TextWrapping="Wrap" Foreground="#8F809C" FontSize="11" Margin="0,20,0,0"/>
                    </StackPanel>
                </Border>
                <Border Grid.Row="1" Background="#E5090710" BorderBrush="#47215F" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,12,0,0">
                    <Grid><Grid.RowDefinitions><RowDefinition Height="36"/><RowDefinition Height="*"/></Grid.RowDefinitions>
                        <TextBlock Text="VEXY EVENT LOG" Foreground="#B95CFF" FontSize="14" FontWeight="SemiBold"/>
                        <ListBox x:Name="EventLog" Grid.Row="1" Background="Transparent" BorderThickness="0" Foreground="#AFA0B9" FontSize="11"/>
                    </Grid>
                </Border>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
}
catch {
    $msg = "VEXY UI failed to load.\n\n$($_.Exception.Message)"
    try { [System.Windows.Forms.MessageBox]::Show($msg,'VEXY STARTUP ERROR',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null } catch { Write-Host $msg -ForegroundColor Red }
    return
}
if (-not $window) {
    $msg = 'VEXY UI could not be created.'
    try { [System.Windows.Forms.MessageBox]::Show($msg,'VEXY STARTUP ERROR') | Out-Null } catch { Write-Host $msg -ForegroundColor Red }
    return
}

# Controls
$backgroundImage = $window.FindName('BackgroundImage')
$starCanvas = $window.FindName('StarCanvas')
$loadingView = $window.FindName('LoadingView'); $loadingLogo = $window.FindName('LoadingLogo'); $loadingStatus = $window.FindName('LoadingStatus'); $loadingProgress = $window.FindName('LoadingProgress')
$activationView = $window.FindName('ActivationView'); $activationLogo = $window.FindName('ActivationLogo'); $activationKeyBox = $window.FindName('ActivationKeyBox'); $activationStatus = $window.FindName('ActivationStatus'); $activationButton = $window.FindName('ActivationButton')
$mainView = $window.FindName('MainView'); $sidebarLogo = $window.FindName('SidebarLogo'); $navPanel = $window.FindName('NavPanel'); $actionGrid = $window.FindName('ActionGrid')
$pageTitle = $window.FindName('PageTitle'); $pageSubtitle = $window.FindName('PageSubtitle'); $cpuText = $window.FindName('CpuText'); $cpuBar = $window.FindName('CpuBar'); $ramText = $window.FindName('RamText'); $ramBar = $window.FindName('RamBar'); $systemInfoText = $window.FindName('SystemInfoText'); $eventLog = $window.FindName('EventLog'); $licenseMini = $window.FindName('LicenseMini'); $exitButton = $window.FindName('ExitButton')

# Assets into UI
$bgBmp = New-VexyBitmap $script:BackgroundPath
if ($bgBmp) { $backgroundImage.Source = $bgBmp }
$logoBmp = New-VexyBitmap $script:LogoPath
if ($logoBmp) { $loadingLogo.Source = $logoBmp; $activationLogo.Source = $logoBmp; $sidebarLogo.Source = $logoBmp }

# ---------- Music ----------
$script:MusicEnabled = $true
$script:MusicPlayer = New-Object System.Windows.Media.MediaPlayer
if ($script:MusicPath -and (Test-Path $script:MusicPath)) {
    try {
        $script:MusicPlayer.Open((New-Object Uri($script:MusicPath,[UriKind]::Absolute)))
        $script:MusicPlayer.Volume = 0.18
        $script:MusicPlayer.Add_MediaEnded({ $script:MusicPlayer.Position = [TimeSpan]::Zero; $script:MusicPlayer.Play() })
    } catch {}
}

# PowerShell 5.1 note: use fully-qualified System.Windows.* WPF type names.
# ---------- Stars ----------
$script:Stars = New-Object System.Collections.ArrayList
$rand = New-Object System.Random
function Initialize-VexyStars {
    param([int]$Count = 90)
    $w = [Math]::Max(1280,[System.Windows.SystemParameters]::PrimaryScreenWidth)
    $h = [Math]::Max(720,[System.Windows.SystemParameters]::PrimaryScreenHeight)
    1..$Count | ForEach-Object {
        $size = 0.7 + ($rand.NextDouble() * 2.2)
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size; $dot.Height = $size
        $dot.Fill = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb([byte](120 + $rand.Next(120)),[byte](170 + $rand.Next(80)),[byte](90 + $rand.Next(90)),[byte]255))
        $dot.IsHitTestVisible = $false
        [System.Windows.Controls.Canvas]::SetLeft($dot,$rand.NextDouble()*$w); [System.Windows.Controls.Canvas]::SetTop($dot,$rand.NextDouble()*$h)
        $starCanvas.Children.Add($dot) | Out-Null
        [void]$script:Stars.Add([pscustomobject]@{ Shape=$dot; Speed=0.10+($rand.NextDouble()*0.42); Phase=$rand.NextDouble()*6.283; Twinkle=0.025+($rand.NextDouble()*0.055) })
    }
}
try {
    Initialize-VexyStars 95
}
catch {
    # Stars are cosmetic; never let the particle layer stop VEXY from launching.
}
$script:StarTick = 0.0
$starTimer = New-Object System.Windows.Threading.DispatcherTimer
$starTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$starTimer.Add_Tick({
    try {
        if (-not $window -or -not $starCanvas) { return }
        $script:StarTick += 0.05
        $w = [Math]::Max(1,$window.ActualWidth); $h = [Math]::Max(1,$window.ActualHeight)
        foreach ($s in $script:Stars) {
            $x = [System.Windows.Controls.Canvas]::GetLeft($s.Shape) - $s.Speed
            if ($x -lt -4) { $x = $w + 3; [System.Windows.Controls.Canvas]::SetTop($s.Shape,$rand.NextDouble()*$h) }
            [System.Windows.Controls.Canvas]::SetLeft($s.Shape,$x)
            $s.Shape.Opacity = [Math]::Max(0.15,[Math]::Min(0.95,0.52 + 0.38*[Math]::Sin($script:StarTick/$s.Twinkle + $s.Phase)))
        }
    } catch {}
})
$starTimer.Start()

function Add-VexyLog([string]$Message) {
    if (-not $eventLog) { return }
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $eventLog.Items.Insert(0,"[$stamp] $Message")
    while ($eventLog.Items.Count -gt 80) { $eventLog.Items.RemoveAt($eventLog.Items.Count-1) }
}

# ---------- Views ----------
function Show-VexyActivation {
    $loadingView.Visibility = 'Collapsed'; $mainView.Visibility = 'Collapsed'; $activationView.Visibility = 'Visible'
    $script:CurrentLicense = $null
    if ($script:LicenseStore.ActiveHash) { $script:CurrentLicense = Test-VexyLicenseHash $script:LicenseStore.ActiveHash $script:LicenseStore }
    if ($script:CurrentLicense -and $script:CurrentLicense.Valid) {
        $activationKeyBox.Visibility = 'Collapsed'
        $activationStatus.Foreground = '#66E6A2'
        $activationStatus.Text = "ACTIVE $($script:CurrentLicense.Label) LICENSE  •  $($script:CurrentLicense.Remaining) REMAINING"
        $activationButton.Content = 'ENTER VEXY'
    } else {
        $activationKeyBox.Visibility = 'Visible'
        $activationKeyBox.Text = ''
        $activationStatus.Foreground = '#BCA6CC'
        $activationStatus.Text = if ($script:CurrentLicense -and $script:CurrentLicense.Reason) { $script:CurrentLicense.Reason } else { 'ENTER A VALID VEXY ACCESS KEY' }
        $activationButton.Content = 'ACTIVATE'
    }
}

function Show-VexyMain {
    try {
        $activationView.Visibility='Collapsed'
        $loadingView.Visibility='Collapsed'
        $mainView.Visibility='Visible'
        $lic = if ($script:CurrentLicense) { "$($script:CurrentLicense.Label) • $($script:CurrentLicense.Remaining)" } else { 'LICENSE ACTIVE' }
        $licenseMini.Text = $lic
        Render-VexyPage 'dashboard'
        Add-VexyLog 'VEXY session ready.'
    }
    catch {
        # Never let a dashboard-render problem terminate the entire app.
        try { $mainView.Visibility='Collapsed'; $activationView.Visibility='Visible' } catch {}
        $msg = "VEXY could not open the dashboard.`r`n`r`n$($_.Exception.Message)`r`n`r`nLine: $($_.InvocationInfo.ScriptLineNumber)"
        try { [System.Windows.Forms.MessageBox]::Show($msg,'VEXY DASHBOARD ERROR',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null } catch { Write-Host $msg -ForegroundColor Red }
    }
}

# ---------- Page/card model ----------
$script:Pages = @{
    dashboard = @(
        @{Title='QUICK OPTIMIZE'; Desc='Run the recommended reversible VEXY preset.'; Icon='optimize'; Action='QuickOptimize'; Risk='Normal'},
        @{Title='RESTORE POINT'; Desc='Create a Windows restore point before changes.'; Icon='backup'; Action='RestorePoint'; Risk='Normal'},
        @{Title='GAME MODE'; Desc='Enable Windows Game Mode.'; Icon='game_mode'; Action='GameMode'; Risk='Normal'},
        @{Title='TEMP CLEAN'; Desc='Clear your user temporary folder; locked files are skipped.'; Icon='temp_clean'; Action='TempClean'; Risk='Normal'},
        @{Title='HIGH PERFORMANCE'; Desc='Switch Windows to its High Performance power plan.'; Icon='boost'; Action='HighPerformance'; Risk='Warning'},
        @{Title='STARTUP APPS'; Desc='Open Windows startup-app management.'; Icon='startup'; Action='Startup'; Risk='Normal'},
        @{Title='DISK TRIM'; Desc='Ask Windows to retrim eligible fixed volumes.'; Icon='disk'; Action='DiskTrim'; Risk='Normal'},
        @{Title='FLUSH DNS'; Desc='Clear the Windows DNS resolver cache.'; Icon='dns_network'; Action='FlushDns'; Risk='Normal'},
        @{Title='DIAGNOSTICS'; Desc='Read basic Windows and hardware information.'; Icon='diagnostics'; Action='Diagnostics'; Risk='Normal'},
        @{Title='ADVANCED'; Desc='Open experimental options with warnings.'; Icon='advanced'; Action='OpenAdvanced'; Risk='Warning'}
    )
    optimize = @(
        @{Title='GAME MODE'; Desc='Enable Windows Game Mode.'; Icon='game_mode'; Action='GameMode'; Risk='Normal'},
        @{Title='GAME CAPTURE OFF'; Desc='Disable Windows background game capture.'; Icon='gpu'; Action='GameDvrOff'; Risk='Warning'},
        @{Title='HIGH PERFORMANCE'; Desc='Use the High Performance power plan.'; Icon='boost'; Action='HighPerformance'; Risk='Warning'},
        @{Title='MOUSE ACCEL OFF'; Desc='Disable Enhance Pointer Precision style acceleration.'; Icon='tools'; Action='MouseAccel'; Risk='Normal'},
        @{Title='DISK TRIM'; Desc='Run Windows retrim on eligible fixed drives.'; Icon='disk'; Action='DiskTrim'; Risk='Normal'}
    )
    cleaner = @(
        @{Title='USER TEMP'; Desc='Remove deletable files from your user TEMP folder.'; Icon='temp_clean'; Action='TempClean'; Risk='Normal'},
        @{Title='DNS CACHE'; Desc='Flush cached DNS resolver entries.'; Icon='dns_network'; Action='FlushDns'; Risk='Normal'}
    )
    boost = @(
        @{Title='HIGH PERFORMANCE'; Desc='Prioritize performance over power savings.'; Icon='boost'; Action='HighPerformance'; Risk='Warning'},
        @{Title='GAME MODE'; Desc='Enable Windows Game Mode.'; Icon='game_mode'; Action='GameMode'; Risk='Normal'},
        @{Title='GAME CAPTURE OFF'; Desc='Disable background game recording.'; Icon='gpu'; Action='GameDvrOff'; Risk='Warning'}
    )
    tools = @(
        @{Title='DIAGNOSTICS'; Desc='Display a quick system hardware summary.'; Icon='diagnostics'; Action='Diagnostics'; Risk='Normal'},
        @{Title='STARTUP MANAGER'; Desc='Open Task Manager for startup-app control.'; Icon='startup'; Action='Startup'; Risk='Normal'},
        @{Title='CREATE RESTORE POINT'; Desc='Create a Windows System Restore checkpoint.'; Icon='backup'; Action='RestorePoint'; Risk='Normal'}
    )
    tweaks = @(
        @{Title='MOUSE ACCEL OFF'; Desc='Set standard no-acceleration mouse values.'; Icon='tools'; Action='MouseAccel'; Risk='Normal'},
        @{Title='VISUAL PERFORMANCE'; Desc='Request Windows Best Performance visual-effects preset.'; Icon='windows'; Action='VisualPerformance'; Risk='Warning'},
        @{Title='GAME CAPTURE OFF'; Desc='Disable Windows background game capture.'; Icon='game_mode'; Action='GameDvrOff'; Risk='Warning'}
    )
    backup = @(
        @{Title='RESTORE POINT'; Desc='Create a Windows restore point now.'; Icon='backup'; Action='RestorePoint'; Risk='Normal'},
        @{Title='SYSTEM RESTORE'; Desc='Open the Windows System Restore interface.'; Icon='windows'; Action='OpenRestore'; Risk='Normal'}
    )
    advanced = @(
        @{Title='HAGS'; Desc='Request Hardware-Accelerated GPU Scheduling. Driver dependent; reboot required.'; Icon='gpu'; Action='Hags'; Risk='Advanced'},
        @{Title='NETWORK POWER'; Desc='Stop Windows powering off physical network adapters.'; Icon='network'; Action='NetworkPower'; Risk='Advanced'},
        @{Title='CLOUDFLARE DNS'; Desc='Set active physical adapters to 1.1.1.1 / 1.0.0.1.'; Icon='dns_network'; Action='CloudflareDns'; Risk='Advanced'},
        @{Title='VISUAL PERFORMANCE'; Desc='Reduce Windows visual effects for responsiveness.'; Icon='windows'; Action='VisualPerformance'; Risk='Advanced'}
    )
    settings = @(
        @{Title='MUSIC ON / OFF'; Desc='Toggle the VEXY background track.'; Icon='settings'; Action='ToggleMusic'; Risk='Normal'},
        @{Title='LICENSE INFO'; Desc='Show current license duration and remaining time.'; Icon='about'; Action='LicenseInfo'; Risk='Normal'}
    )
    about = @(
        @{Title='VEXY VERSION'; Desc='Show build information.'; Icon='about'; Action='Version'; Risk='Normal'},
        @{Title='SAFETY MODEL'; Desc='VEXY keeps Windows recovery controls available.'; Icon='security'; Action='SafetyInfo'; Risk='Normal'}
    )
}

$script:PageTitles = @{
    dashboard=@('WELCOME TO VEXY OPTIMIZER','MAXIMIZE PERFORMANCE. MINIMIZE LATENCY. KEEP CONTROL.')
    optimize=@('OPTIMIZATION SUITE','WINDOWS PERFORMANCE SETTINGS AND GAMING OPTIONS.')
    cleaner=@('SYSTEM CLEANER','REMOVE SAFE TEMPORARY DATA WITHOUT DELETING PERSONAL FILES.')
    boost=@('PERFORMANCE BOOST','POWER AND GAMING OPTIONS WITH CLEAR TRADEOFFS.')
    tools=@('VEXY TOOLS','DIAGNOSTICS, STARTUP CONTROL AND RECOVERY.')
    tweaks=@('WINDOWS TWEAKS','REVERSIBLE SETTINGS — NO MAGIC FPS CLAIMS.')
    backup=@('BACKUP / RESTORE','CREATE A RECOVERY POINT BEFORE IMPORTANT CHANGES.')
    advanced=@('ADVANCED / EXPERIMENTAL','READ EACH WARNING BEFORE APPLYING DRIVER OR NETWORK-LEVEL SETTINGS.')
    settings=@('VEXY SETTINGS','CONTROL MUSIC AND VIEW LICENSE INFORMATION.')
    about=@('ABOUT VEXY','VEXY OPTIMIZER • WINDOWS PERFORMANCE UTILITY.')
}

function New-VexyCard($Item) {
    $button = New-Object System.Windows.Controls.Button
    $button.Width=205; $button.Height=250; $button.Margin='8'; $button.Padding='0'; $button.Cursor='Hand'; $button.Tag=$Item
    $button.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D70A0710')
    $button.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if($Item.Risk -eq 'Advanced'){'#A353E6'}elseif($Item.Risk -eq 'Warning'){'#6F385D'}else{'#3F2450'}))
    $button.BorderThickness='1'
    $template = [System.Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12" Padding="14">
    <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#E2140A20"/><Setter TargetName="bd" Property="BorderBrush" Value="#A23BFF"/></Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
'@)
    $button.Template=$template
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment='Center'
    $iconPath = Get-VexyIconPath $Item.Icon
    $bmp = New-VexyBitmap $iconPath
    if ($bmp) {
        $img=New-Object System.Windows.Controls.Image; $img.Source=$bmp; $img.Height=105; $img.Stretch='Uniform'; $img.Margin='0,0,0,8'; $stack.Children.Add($img)|Out-Null
    } else {
        $fallback=New-Object System.Windows.Controls.TextBlock; $fallback.Text='✦'; $fallback.FontSize=58; $fallback.Foreground=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#A23BFF'); $fallback.HorizontalAlignment='Center'; $fallback.Margin='0,0,0,10'; $stack.Children.Add($fallback)|Out-Null
    }
    $title=New-Object System.Windows.Controls.TextBlock; $title.Text=$Item.Title; $title.FontSize=15; $title.FontWeight='SemiBold'; $title.Foreground='White'; $title.HorizontalAlignment='Center'; $title.TextAlignment='Center'; $title.Margin='0,0,0,8'; $stack.Children.Add($title)|Out-Null
    $desc=New-Object System.Windows.Controls.TextBlock; $desc.Text=$Item.Desc; $desc.FontSize=11; $desc.Foreground=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#A696B1'); $desc.TextWrapping='Wrap'; $desc.TextAlignment='Center'; $desc.HorizontalAlignment='Center'; $stack.Children.Add($desc)|Out-Null
    if ($Item.Risk -eq 'Advanced') { $badge=New-Object System.Windows.Controls.TextBlock; $badge.Text='⚠ ADVANCED'; $badge.Foreground=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#D78CFF'); $badge.FontSize=9; $badge.HorizontalAlignment='Center'; $badge.Margin='0,11,0,0'; $stack.Children.Add($badge)|Out-Null }
    $button.Content=$stack
    $button.Add_MouseEnter({ Play-VexySound 'Hover' })
    $button.Add_Click({ param($s,$e) try { Play-VexySound 'Click'; Invoke-VexyAction $s.Tag } catch { Add-VexyLog ("Action error: {0}" -f $_.Exception.Message); Play-VexySound 'Warning' } })
    return $button
}

function Render-VexyPage([string]$Page) {
    if (-not $script:Pages.ContainsKey($Page)) { $Page='dashboard' }
    $pair=$script:PageTitles[$Page]
    $pageTitle.Text=$pair[0]
    $pageSubtitle.Text=$pair[1]
    $actionGrid.Children.Clear()
    foreach($item in $script:Pages[$Page]) {
        try {
            $card = New-VexyCard $item
            if ($card) { $actionGrid.Children.Add($card) | Out-Null }
        }
        catch {
            # Keep rendering the rest of the dashboard if one card has a problem.
            Add-VexyLog ("Card render failed: {0} - {1}" -f $item.Title,$_.Exception.Message)
        }
    }
}

function Confirm-Vexy([string]$Title,[string]$Text) {
    Play-VexySound 'Warning'
    $r=[System.Windows.MessageBox]::Show($window,$Text,$Title,[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Warning)
    return ($r -eq [System.Windows.MessageBoxResult]::Yes)
}

function Run-VexyResult([string]$Name,[scriptblock]$Code) {
    Add-VexyLog "$Name started..."
    try { $result=& $Code; Add-VexyLog $result; Play-VexySound 'Success' }
    catch { Add-VexyLog "$Name failed: $($_.Exception.Message)"; Play-VexySound 'Warning' }
}

function Invoke-VexyAction($Item) {
    switch ($Item.Action) {
        'QuickOptimize' {
            if (Confirm-Vexy 'VEXY QUICK OPTIMIZE' "VEXY will create a restore point, enable Game Mode, disable background game capture, switch to High Performance, clean user TEMP files and flush DNS.`n`nContinue?") {
                Run-VexyResult 'Restore point' { New-VexyRestorePoint }
                Run-VexyResult 'Game Mode' { Set-VexyGameMode }
                Run-VexyResult 'Game capture' { Set-VexyGameDvrOff }
                Run-VexyResult 'Power plan' { Set-VexyHighPerformance }
                Run-VexyResult 'Temp clean' { Clear-VexyUserTemp }
                Run-VexyResult 'DNS flush' { Clear-VexyDnsCache }
            }
        }
        'RestorePoint' { Run-VexyResult 'Restore point' { New-VexyRestorePoint } }
        'GameMode' { Run-VexyResult 'Game Mode' { Set-VexyGameMode } }
        'GameDvrOff' { if(Confirm-Vexy 'BACKGROUND GAME CAPTURE' 'This disables Windows background game capture for the current user. Continue?'){ Run-VexyResult 'Game capture' { Set-VexyGameDvrOff } } }
        'HighPerformance' { if(Confirm-Vexy 'HIGH PERFORMANCE POWER PLAN' 'This can increase power consumption, fan noise and heat, especially on laptops. Continue?'){ Run-VexyResult 'Power plan' { Set-VexyHighPerformance } } }
        'TempClean' { Run-VexyResult 'Temp clean' { Clear-VexyUserTemp } }
        'FlushDns' { Run-VexyResult 'DNS flush' { Clear-VexyDnsCache } }
        'MouseAccel' { Run-VexyResult 'Mouse setting' { Set-VexyMouseAccelOff } }
        'DiskTrim' { Run-VexyResult 'Disk optimize' { Invoke-VexyDiskOptimize } }
        'Startup' { Run-VexyResult 'Startup manager' { Open-VexyStartupManager } }
        'Diagnostics' { Run-VexyResult 'Diagnostics' { Get-VexyDiagnosticsText } }
        'OpenAdvanced' { Render-VexyPage 'advanced' }
        'Hags' { if(Confirm-Vexy 'ADVANCED: HAGS' 'Hardware-Accelerated GPU Scheduling is driver-dependent and may help, hurt, or make no difference. A reboot is required. Continue?'){ Run-VexyResult 'HAGS' { Set-VexyHags } } }
        'NetworkPower' { if(Confirm-Vexy 'ADVANCED: NETWORK POWER' 'This prevents Windows from powering off physical network adapters. It can increase power use. Continue?'){ Run-VexyResult 'Network power' { Set-VexyNetworkPower } } }
        'CloudflareDns' { if(Confirm-Vexy 'ADVANCED: CHANGE DNS' 'This replaces DNS servers on active physical adapters with Cloudflare 1.1.1.1 / 1.0.0.1 until you set DNS back to Automatic or another provider. Continue?'){ Run-VexyResult 'DNS change' { Set-VexyCloudflareDns } } }
        'VisualPerformance' { if(Confirm-Vexy 'VISUAL PERFORMANCE' 'This requests Windows Best Performance visual effects and may reduce animations/visual polish. Continue?'){ Run-VexyResult 'Visual effects' { Set-VexyVisualPerformance } } }
        'OpenRestore' { Start-Process 'rstrui.exe'; Add-VexyLog 'Windows System Restore opened.' }
        'ToggleMusic' { $script:MusicEnabled = -not $script:MusicEnabled; if($script:MusicEnabled){$script:MusicPlayer.Play();Add-VexyLog 'Music enabled.'}else{$script:MusicPlayer.Pause();Add-VexyLog 'Music paused.'} }
        'LicenseInfo' { [System.Windows.MessageBox]::Show($window,("License: {0}`nRemaining: {1}" -f $script:CurrentLicense.Label,$script:CurrentLicense.Remaining),'VEXY LICENSE') | Out-Null }
        'Version' { [System.Windows.MessageBox]::Show($window,"VEXY Optimizer`nBuild $script:VexyVersion",'ABOUT VEXY') | Out-Null }
        'SafetyInfo' { [System.Windows.MessageBox]::Show($window,'VEXY does not disable Alt+Tab, Task Manager, Ctrl+Alt+Delete, Windows Recovery, Defender, or other emergency/security controls.','VEXY SAFETY') | Out-Null }
    }
}

# Navigation
$navItems = @(
    @('⌂  DASHBOARD','dashboard'),@('🚀  OPTIMIZE','optimize'),@('▱  CLEANER','cleaner'),@('ϟ  BOOST','boost'),
    @('🛠  TOOLS','tools'),@('≡  TWEAKS','tweaks'),@('◇  BACKUP','backup'),@('⚠  ADVANCED','advanced'),
    @('⚙  SETTINGS','settings'),@('ⓘ  ABOUT','about')
)
foreach($n in $navItems){
    $b=New-Object System.Windows.Controls.Button; $b.Style=$window.Resources['NavButton']; $b.Content=$n[0]; $b.Tag=$n[1]
    $b.Add_MouseEnter({Play-VexySound 'Hover'}); $b.Add_Click({param($s,$e) Play-VexySound 'Click'; Render-VexyPage $s.Tag})
    $navPanel.Children.Add($b)|Out-Null
}

# Activation button
$activationButton.Add_MouseEnter({Play-VexySound 'Hover'})
$activationButton.Add_Click({
    try {
        Play-VexySound 'Click'
        if ($script:CurrentLicense -and $script:CurrentLicense.Valid -and $activationKeyBox.Visibility -eq 'Collapsed') { Show-VexyMain; return }
        $hash=Get-VexyHash $activationKeyBox.Text
        if (-not $script:LicenseTable.ContainsKey($hash)) { Play-VexySound 'Warning'; $activationStatus.Foreground='#FF7796'; $activationStatus.Text='INVALID ACTIVATION KEY'; return }
        $state=Test-VexyLicenseHash $hash $script:LicenseStore -StartIfNew
        if (-not $state.Valid) { Play-VexySound 'Warning'; $activationStatus.Foreground='#FF7796'; $activationStatus.Text=$state.Reason; Save-VexyLicenseStore $script:LicenseStore; return }
        $script:LicenseStore.ActiveHash=$hash; Save-VexyLicenseStore $script:LicenseStore; $script:CurrentLicense=$state
        $activationStatus.Foreground='#66E6A2'; $activationStatus.Text="ACTIVATED • $($state.Label) • $($state.Remaining)"; Play-VexySound 'Success'
        $activationKeyBox.Visibility='Collapsed'; $activationButton.Content='ENTER VEXY'
    }
    catch {
        $msg = "Activation UI error: $($_.Exception.Message)`r`nLine: $($_.InvocationInfo.ScriptLineNumber)"
        try { [System.Windows.Forms.MessageBox]::Show($msg,'VEXY ACTIVATION ERROR') | Out-Null } catch { Write-Host $msg -ForegroundColor Red }
    }
})

# Exit behavior: dedicated button + normal Windows close route remains available.
$script:ExitRequested=$false
$exitButton.Add_MouseEnter({Play-VexySound 'Hover'})
$exitButton.Add_Click({
    Play-VexySound 'Click'
    if([System.Windows.MessageBox]::Show($window,'Exit VEXY?','VEXY',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question) -eq [System.Windows.MessageBoxResult]::Yes){$script:ExitRequested=$true;$window.Close()}
})
$window.Add_Closing({param($s,$e)
    if(-not $script:ExitRequested){
        $r=[System.Windows.MessageBox]::Show($window,'Exit VEXY?','VEXY',[System.Windows.MessageBoxButton]::YesNo,[System.Windows.MessageBoxImage]::Question)
        if($r -ne [System.Windows.MessageBoxResult]::Yes){$e.Cancel=$true}else{$script:ExitRequested=$true}
    }
})

# Telemetry - lightweight PerformanceCounter + native RAM API.
$script:CpuCounter=$null
try { $script:CpuCounter=New-Object System.Diagnostics.PerformanceCounter('Processor','% Processor Time','_Total'); $null=$script:CpuCounter.NextValue() } catch {}
$telemetryTimer=New-Object System.Windows.Threading.DispatcherTimer
$telemetryTimer.Interval=[TimeSpan]::FromMilliseconds(1200)
$telemetryTimer.Add_Tick({
    if($mainView.Visibility -ne 'Visible'){return}
    try{ if($script:CpuCounter){$cpu=[Math]::Max(0,[Math]::Min(100,[Math]::Round($script:CpuCounter.NextValue())));$cpuText.Text="CPU     $cpu%";$cpuBar.Value=$cpu} }catch{}
    try{ $m=New-Object VexyNative.MEMORYSTATUSEX; if([VexyNative.Memory]::GlobalMemoryStatusEx($m)){$ram=[int]$m.dwMemoryLoad;$used=[Math]::Round(($m.ullTotalPhys-$m.ullAvailPhys)/1GB,1);$total=[Math]::Round($m.ullTotalPhys/1GB,1);$ramText.Text="RAM     $ram%   •   $used / $total GB";$ramBar.Value=$ram} }catch{}
})
$telemetryTimer.Start()

# One-time hardware identity read after main window appears (not every second).
$window.Add_ContentRendered({
    try {
        $cpu=(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue|Select-Object -First 1).Name
        $gpu=(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue|Where-Object Name -NotMatch 'Remote|Basic'|Select-Object -First 1).Name
        $os=(Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        $systemInfoText.Text="$os`n$cpu`n$gpu"
    } catch { $systemInfoText.Text='Windows system detected.' }
})

# Loading sequence
$loadSteps=@('PREPARING ENVIRONMENT...','LOADING VEXY CORE...','INITIALIZING VISUAL ENGINE...','READING SYSTEM CAPABILITIES...','LOADING OPTIMIZATION MODULES...','VERIFYING LOCAL LICENSE STORE...','ESTABLISHING VEXY SESSION...','SYSTEM READY')
$script:LoadIndex=0
$loadingTimer=New-Object System.Windows.Threading.DispatcherTimer
$loadingTimer.Interval=[TimeSpan]::FromMilliseconds(520)
$loadingTimer.Add_Tick({
    if($script:LoadIndex -lt $loadSteps.Count){
        $loadingStatus.Text=$loadSteps[$script:LoadIndex]
        $loadingProgress.Value=[Math]::Round((($script:LoadIndex+1)/$loadSteps.Count)*100)
        $script:LoadIndex++
    } else { $loadingTimer.Stop(); Show-VexyActivation }
})

$window.Add_Loaded({
    if($script:MusicPath -and (Test-Path $script:MusicPath)){try{$script:MusicPlayer.Play()}catch{}}
    $loadingTimer.Start()
})

try { $null=$window.ShowDialog() }
finally {
    try{$loadingTimer.Stop();$telemetryTimer.Stop();$starTimer.Stop()}catch{}
    try{$script:MusicPlayer.Stop();$script:MusicPlayer.Close()}catch{}
    try{if($script:CpuCounter){$script:CpuCounter.Dispose()}}catch{}
}
