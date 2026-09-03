# VEXY Optimizer - V6 prototype
# Windows PowerShell 5.1 / WPF
# Public build: activation keys are NOT stored in plaintext.

$ErrorActionPreference = 'Continue'
$script:VexyVersion = '6.2.0-hardware-suite'
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
$script:BaselineFile = Join-Path $script:LicenseDir 'baseline.json'
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
# HARDWARE / BASELINE / SETTINGS TOOLS
# Monitoring and launchers only. VEXY deliberately does NOT automate
# CPU/GPU voltage, clocks, PBO, Curve Optimizer, EXPO, BIOS or firmware.
# =====================================================================
function ConvertTo-VexySize([double]$Bytes) {
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Get-VexyActivePowerPlanText {
    try {
        $raw = (powercfg.exe /getactivescheme 2>$null | Out-String).Trim()
        if ($raw) { return $raw }
    } catch {}
    return 'Unavailable'
}

function Get-VexyMemoryIntegrityText {
    try {
        $v = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction Stop
        if ([int]$v.Enabled -eq 1) { return 'Enabled' }
        return 'Disabled'
    } catch { return 'Not reported' }
}

function Get-VexyCpuReport {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        @"
CPU
Name: $($cpu.Name)
Manufacturer: $($cpu.Manufacturer)
Physical cores: $($cpu.NumberOfCores)
Logical processors: $($cpu.NumberOfLogicalProcessors)
Current clock reported by Windows: $($cpu.CurrentClockSpeed) MHz
Maximum clock reported by Windows: $($cpu.MaxClockSpeed) MHz
Virtualization firmware enabled: $($cpu.VirtualizationFirmwareEnabled)

Notes:
• Windows-reported clock values are snapshots and may not match per-core boost clocks.
• Package temperature, voltage, PBO and Curve Optimizer values are not exposed reliably through standard Windows APIs.
• VEXY does not change CPU voltage, multiplier, PBO, Curve Optimizer or BIOS settings.
"@
    } catch { "CPU information unavailable: $($_.Exception.Message)" }
}

function Get-VexyGpuReport {
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object Name -NotMatch 'Remote|Basic')
        if (-not $gpus.Count) { return 'No supported graphics adapter was reported by Windows.' }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($g in $gpus) {
            $vram = if ($g.AdapterRAM) { ConvertTo-VexySize ([double]$g.AdapterRAM) } else { 'Not reported' }
            [void]$lines.Add("GPU: $($g.Name)")
            [void]$lines.Add("Driver: $($g.DriverVersion)")
            [void]$lines.Add("VRAM reported by Windows: $vram")
            [void]$lines.Add("Current mode: $($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution) @ $($g.CurrentRefreshRate) Hz")
            [void]$lines.Add('')
        }
        [void]$lines.Add('Notes:')
        [void]$lines.Add('• GPU core clock, hotspot temperature, voltage and board power are vendor-specific and are not read reliably through standard Windows APIs.')
        [void]$lines.Add('• VEXY does not apply GPU overclocks or voltage changes.')
        return ($lines -join "`r`n")
    } catch { "GPU information unavailable: $($_.Exception.Message)" }
}

function Get-VexyMemoryReport {
    try {
        $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop)
        $total = ($mods | Measure-Object Capacity -Sum).Sum
        $lines = New-Object System.Collections.Generic.List[string]
        [void]$lines.Add("Installed memory: $(ConvertTo-VexySize ([double]$total))")
        [void]$lines.Add("Modules detected: $($mods.Count)")
        [void]$lines.Add('')
        $i = 1
        foreach ($m in $mods) {
            $speed = if ($m.ConfiguredClockSpeed) { "$($m.ConfiguredClockSpeed) MT/s" } elseif ($m.Speed) { "$($m.Speed) MT/s" } else { 'Not reported' }
            [void]$lines.Add("DIMM $i: $(ConvertTo-VexySize ([double]$m.Capacity)) | $speed | $($m.Manufacturer) $($m.PartNumber)")
            $i++
        }
        [void]$lines.Add('')
        [void]$lines.Add('EXPO/XMP status is BIOS/vendor-specific and cannot be identified reliably from standard Windows memory classes.')
        [void]$lines.Add('VEXY does not change DRAM voltage, timings or EXPO/XMP settings.')
        return ($lines -join "`r`n")
    } catch { "Memory information unavailable: $($_.Exception.Message)" }
}

function Get-VexyBoardReport {
    try {
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        @"
SYSTEM / MOTHERBOARD
System: $($cs.Manufacturer) $($cs.Model)
Board: $($board.Manufacturer) $($board.Product)
Board version: $($board.Version)
BIOS: $($bios.SMBIOSBIOSVersion)
BIOS vendor: $($bios.Manufacturer)
BIOS date: $($bios.ReleaseDate)

Memory Integrity: $(Get-VexyMemoryIntegrityText)

VEXY does not flash BIOS/UEFI, alter firmware security, or write CPU/RAM tuning values.
"@
    } catch { "Board/BIOS information unavailable: $($_.Exception.Message)" }
}

function Get-VexyStorageReport {
    try {
        $vols = @(Get-Volume -ErrorAction Stop | Where-Object DriveLetter)
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($v in $vols) {
            $size = if ($v.Size) { ConvertTo-VexySize ([double]$v.Size) } else { 'Unknown' }
            $free = if ($v.SizeRemaining -ne $null) { ConvertTo-VexySize ([double]$v.SizeRemaining) } else { 'Unknown' }
            [void]$lines.Add("$($v.DriveLetter):  $($v.FileSystem)  Free $free / $size  [$($v.HealthStatus)]")
        }
        return ($lines -join "`r`n")
    } catch { "Storage information unavailable: $($_.Exception.Message)" }
}

function Get-VexyNetworkReport {
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop)
        if (-not $adapters.Count) { return 'No physical network adapters were reported.' }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($a in $adapters) {
            [void]$lines.Add("$($a.Name) | $($a.InterfaceDescription)")
            [void]$lines.Add("Status: $($a.Status) | Link: $($a.LinkSpeed) | MAC: $($a.MacAddress)")
            try {
                $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
                [void]$lines.Add("Power-off permission: $($pm.AllowComputerToTurnOffDevice)")
            } catch {}
            try {
                $rss = Get-NetAdapterRss -Name $a.Name -ErrorAction Stop
                [void]$lines.Add("RSS: $($rss.Enabled)")
            } catch {}
            [void]$lines.Add('')
        }
        [void]$lines.Add('Driver-specific settings such as interrupt moderation or energy-efficient Ethernet are shown only by the adapter vendor/driver and are not automatically changed by VEXY.')
        return ($lines -join "`r`n")
    } catch { "Network information unavailable: $($_.Exception.Message)" }
}

function Get-VexyStartupEntries {
    $items = New-Object System.Collections.Generic.List[object]
    $locations = @(
        @{Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Source='Current user Run'},
        @{Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Source='Machine Run'},
        @{Path='HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Source='Machine Run (32-bit)'}
    )
    foreach ($loc in $locations) {
        try {
            $p = Get-ItemProperty -Path $loc.Path -ErrorAction Stop
            foreach ($prop in $p.PSObject.Properties) {
                if ($prop.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$') {
                    [void]$items.Add([pscustomobject]@{ Name=$prop.Name; Source=$loc.Source; Command=[string]$prop.Value })
                }
            }
        } catch {}
    }
    $startupFolders = @(
        @{Path=[Environment]::GetFolderPath('Startup'); Source='Current user Startup folder'},
        @{Path=[Environment]::GetFolderPath('CommonStartup'); Source='All users Startup folder'}
    )
    foreach ($folder in $startupFolders) {
        if ($folder.Path -and (Test-Path $folder.Path)) {
            Get-ChildItem -LiteralPath $folder.Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                [void]$items.Add([pscustomobject]@{ Name=$_.Name; Source=$folder.Source; Command=$_.FullName })
            }
        }
    }
    return @($items)
}

function Get-VexyStartupReport {
    $items = @(Get-VexyStartupEntries)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("Startup entries detected: $($items.Count)")
    [void]$lines.Add('')
    foreach ($i in $items) {
        [void]$lines.Add("$($i.Name)  [$($i.Source)]")
        [void]$lines.Add("  $($i.Command)")
    }
    if (-not $items.Count) { [void]$lines.Add('No entries were found in the common Run keys or Startup folders.') }
    [void]$lines.Add('')
    [void]$lines.Add('VEXY does not auto-disable startup entries because driver utilities, security software and apps you rely on can appear here.')
    return ($lines -join "`r`n")
}

function Get-VexyFullHardwareReport {
    $os = try { Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1 } catch { $null }
    $header = @"
VEXY HARDWARE / SYSTEM REPORT
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Windows: $($os.Caption)
Version: $($os.Version)
Build: $($os.BuildNumber)
Active power plan:
$(Get-VexyActivePowerPlanText)

"@
    return $header + "`r`n" + (Get-VexyCpuReport) + "`r`n`r`n" + (Get-VexyGpuReport) + "`r`n`r`n" + (Get-VexyMemoryReport) + "`r`n`r`n" + (Get-VexyBoardReport) + "`r`n`r`nSTORAGE`r`n" + (Get-VexyStorageReport) + "`r`n`r`nNETWORK`r`n" + (Get-VexyNetworkReport)
}

function Show-VexyReport([string]$Title,[string]$Text) {
    try {
        $reportWindow = New-Object System.Windows.Window
        $reportWindow.Title = "VEXY // $Title"
        $reportWindow.Width = 820
        $reportWindow.Height = 650
        $reportWindow.MinWidth = 620
        $reportWindow.MinHeight = 440
        $reportWindow.WindowStartupLocation = 'CenterOwner'
        if ($window) { $reportWindow.Owner = $window }
        $reportWindow.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#09050D')
        $reportWindow.Foreground = [System.Windows.Media.Brushes]::White

        $grid = New-Object System.Windows.Controls.Grid
        $r1 = New-Object System.Windows.Controls.RowDefinition
        $r1.Height = [System.Windows.GridLength]::Auto
        $r2 = New-Object System.Windows.Controls.RowDefinition
        $r2.Height = New-Object System.Windows.GridLength(1,[System.Windows.GridUnitType]::Star)
        $r3 = New-Object System.Windows.Controls.RowDefinition
        $r3.Height = [System.Windows.GridLength]::Auto
        [void]$grid.RowDefinitions.Add($r1); [void]$grid.RowDefinitions.Add($r2); [void]$grid.RowDefinitions.Add($r3)

        $head = New-Object System.Windows.Controls.TextBlock
        $head.Text = $Title
        $head.FontSize = 22
        $head.FontWeight = 'Light'
        $head.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#DDA5FF')
        $head.Margin = '18,16,18,12'
        [System.Windows.Controls.Grid]::SetRow($head,0)
        [void]$grid.Children.Add($head)

        $box = New-Object System.Windows.Controls.TextBox
        $box.Text = $Text
        $box.IsReadOnly = $true
        $box.TextWrapping = 'Wrap'
        $box.AcceptsReturn = $true
        $box.VerticalScrollBarVisibility = 'Auto'
        $box.HorizontalScrollBarVisibility = 'Disabled'
        $box.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E60B0711')
        $box.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E8DFF0')
        $box.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#57326D')
        $box.BorderThickness = '1'
        $box.FontFamily = 'Consolas'
        $box.FontSize = 12
        $box.Padding = '14'
        $box.Margin = '18,0,18,12'
        [System.Windows.Controls.Grid]::SetRow($box,1)
        [void]$grid.Children.Add($box)

        $close = New-Object System.Windows.Controls.Button
        $close.Content = 'CLOSE'
        $close.Width = 110
        $close.Height = 36
        $close.HorizontalAlignment = 'Right'
        $close.Margin = '18,0,18,16'
        $close.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#6E1FC4')
        $close.Foreground = [System.Windows.Media.Brushes]::White
        $close.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C45AFF')
        $close.BorderThickness = '1'
        $close.Cursor = 'Hand'
        $close.Add_Click({ $reportWindow.Close() })
        [System.Windows.Controls.Grid]::SetRow($close,2)
        [void]$grid.Children.Add($close)

        $reportWindow.Content = $grid
        [void]$reportWindow.ShowDialog()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($Text,$Title) | Out-Null
    }
}

function Open-VexySettingsUri([string]$Uri,[string]$Label) {
    try {
        Start-Process $Uri
        return "$Label opened."
    } catch { return "Could not open $Label`: $($_.Exception.Message)" }
}

function Get-VexyBaselineSnapshot {
    $m = New-Object VexyNative.MEMORYSTATUSEX
    [VexyNative.Memory]::GlobalMemoryStatusEx($m) | Out-Null
    $drive = $null
    try { $drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $env:SystemDrive) -ErrorAction Stop } catch {}
    [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        RamPercent = [int]$m.dwMemoryLoad
        RamUsedGB = [Math]::Round(($m.ullTotalPhys-$m.ullAvailPhys)/1GB,1)
        FreeSystemDriveGB = if($drive){ [Math]::Round([double]$drive.FreeSpace/1GB,1) } else { $null }
        StartupEntries = @(Get-VexyStartupEntries).Count
        PowerPlan = Get-VexyActivePowerPlanText
    }
}

function Save-VexyBaseline {
    try {
        $snap = Get-VexyBaselineSnapshot
        $snap | ConvertTo-Json -Depth 4 | Set-Content -Path $script:BaselineFile -Encoding UTF8 -Force
        return "Baseline snapshot saved at $($snap.Timestamp). This is a configuration snapshot, not a benchmark score."
    } catch { return "Could not save baseline: $($_.Exception.Message)" }
}

function Compare-VexyBaseline {
    if (-not (Test-Path $script:BaselineFile)) { return 'No VEXY baseline exists yet. Use SAVE BASELINE first.' }
    try {
        $old = Get-Content -Path $script:BaselineFile -Raw -ErrorAction Stop | ConvertFrom-Json
        $now = Get-VexyBaselineSnapshot
        $lines = @(
            'VEXY BASELINE COMPARISON',
            "Baseline: $($old.Timestamp)",
            "Current:  $($now.Timestamp)",
            '',
            "RAM load: $($old.RamPercent)% -> $($now.RamPercent)%  (snapshot; background activity changes this)",
            "RAM used: $($old.RamUsedGB) GB -> $($now.RamUsedGB) GB",
            "System drive free: $($old.FreeSystemDriveGB) GB -> $($now.FreeSystemDriveGB) GB",
            "Startup entries: $($old.StartupEntries) -> $($now.StartupEntries)",
            '',
            'Baseline power plan:',
            "$($old.PowerPlan)",
            '',
            'Current power plan:',
            "$($now.PowerPlan)",
            '',
            'This comparison does not claim an FPS or latency gain; it shows observable configuration/resource changes.'
        )
        return ($lines -join "`r`n")
    } catch { return "Could not compare baseline: $($_.Exception.Message)" }
}

function Get-VexyTuningSafetyText {
@"
HARDWARE TUNING / OVERCLOCKING

VEXY intentionally keeps this section monitoring-only.

VEXY WILL NOT automatically:
• raise CPU or GPU voltage
• set CPU multipliers or GPU core/memory offsets
• apply Precision Boost Overdrive or Curve Optimizer values
• enable EXPO/XMP or change RAM timings/voltage
• flash or modify BIOS/UEFI firmware

Why:
Hardware tuning is dependent on the exact processor, motherboard, cooling, firmware, power supply and silicon quality. A setting that is stable on one PC can crash or corrupt work on another, and higher voltage/power can increase heat and component stress.

Use the HARDWARE page to identify components, clocks reported by Windows, memory speed, drivers, board/BIOS details and current Windows power settings. For deeper temperature/voltage/clock telemetry, use the monitoring features supplied by your hardware manufacturer.

VEXY can still optimize reversible Windows settings around the hardware without changing the hardware's operating limits.
"@
}


# =====================================================================
# VEXY TOGGLE ENGINE
# These functions expose reversible on/off states for the switch UI.
# Advanced items intentionally have visible warnings and do not disable
# Windows security, recovery, Defender, or boot safeguards.
# =====================================================================
function Get-VexyRegValue {
    param([string]$Path,[string]$Name,$Default=$null)
    try {
        $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $p.$Name
    } catch { return $Default }
}

function Test-VexyGameModeEnabled {
    return ([int](Get-VexyRegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0) -eq 1)
}
function Set-VexyGameModeState([bool]$Enabled) {
    New-Item 'HKCU:\Software\Microsoft\GameBar' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Type DWord -Value $(if($Enabled){1}else{0}) -Force
    if($Enabled){ 'Game Mode enabled.' } else { 'Game Mode disabled.' }
}

function Test-VexyGameCaptureDisabled {
    $a = [int](Get-VexyRegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1)
    $b = [int](Get-VexyRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1)
    return ($a -eq 0 -and $b -eq 0)
}
function Set-VexyGameCaptureDisabledState([bool]$Disabled) {
    New-Item 'HKCU:\System\GameConfigStore' -Force | Out-Null
    New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Force | Out-Null
    $v = if($Disabled){0}else{1}
    Set-ItemProperty 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Type DWord -Value $v -Force
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Type DWord -Value $v -Force
    if($Disabled){ 'Background game capture disabled.' } else { 'Background game capture enabled.' }
}

function Test-VexyHighPerformanceEnabled {
    try {
        $active = (powercfg.exe /getactivescheme 2>$null | Out-String)
        return ($active -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -or $active -match 'e9a42b02-d5df-448d-aa00-03f14749eb61')
    } catch { return $false }
}
function Set-VexyHighPerformanceState([bool]$Enabled) {
    if($Enabled){
        powercfg.exe /setactive SCHEME_MIN | Out-Null
        'High Performance power plan selected. Expect higher power use and possibly more heat/fan noise.'
    } else {
        powercfg.exe /setactive SCHEME_BALANCED | Out-Null
        'Balanced power plan restored.'
    }
}

function Test-VexyMouseAccelOff {
    $s=[string](Get-VexyRegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '1')
    $t1=[string](Get-VexyRegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '6')
    $t2=[string](Get-VexyRegValue 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '10')
    return ($s -eq '0' -and $t1 -eq '0' -and $t2 -eq '0')
}
function Set-VexyMouseAccelOffState([bool]$Disabled) {
    if($Disabled){
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -Value '0' -Force
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1 -Value '0' -Force
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2 -Value '0' -Force
        'Mouse acceleration disabled.'
    } else {
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -Value '1' -Force
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1 -Value '6' -Force
        Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2 -Value '10' -Force
        'Standard Windows mouse acceleration values restored.'
    }
}

function Test-VexyHagsEnabled {
    return ([int](Get-VexyRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 1) -eq 2)
}
function Set-VexyHagsState([bool]$Enabled) {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Force | Out-Null
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -Type DWord -Value $(if($Enabled){2}else{1}) -Force
    if($Enabled){ 'HAGS enabled in the registry. Reboot required.' } else { 'HAGS disabled in the registry. Reboot required.' }
}

function Test-VexyNetworkPowerSaveOff {
    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop)
        if(-not $adapters.Count){ return $false }
        $supported = 0
        foreach($a in $adapters){
            try {
                $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
                if($null -ne $pm.AllowComputerToTurnOffDevice){
                    $supported++
                    if([string]$pm.AllowComputerToTurnOffDevice -notmatch 'Disabled'){ return $false }
                }
            } catch {}
        }
        return ($supported -gt 0)
    } catch { return $false }
}
function Set-VexyNetworkPowerSaveOffState([bool]$Disabled) {
    $changed=0
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice $(if($Disabled){'Disabled'}else{'Enabled'}) -ErrorAction Stop
            $changed++
        } catch {}
    }
    if($Disabled){
        "Network adapter power-off permission disabled on $changed adapter(s). This can increase power use."
    } else {
        "Network adapter power-off permission restored on $changed adapter(s)."
    }
}

function Test-VexyCloudflareDns {
    try {
        $up = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq 'Up')
        if(-not $up.Count){ return $false }
        foreach($a in $up){
            $servers = @((Get-DnsClientServerAddress -InterfaceIndex $a.IfIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
            if(-not ($servers -contains '1.1.1.1')){ return $false }
        }
        return $true
    } catch { return $false }
}
function Set-VexyCloudflareDnsState([bool]$Enabled) {
    $changed=0
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
        try {
            if($Enabled){
                Set-DnsClientServerAddress -InterfaceIndex $_.IfIndex -ServerAddresses @('1.1.1.1','1.0.0.1') -ErrorAction Stop
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $_.IfIndex -ResetServerAddresses -ErrorAction Stop
            }
            $changed++
        } catch {}
    }
    if($Enabled){ "Cloudflare DNS enabled on $changed active adapter(s)." } else { "DNS restored to automatic/DHCP on $changed active adapter(s)." }
}

function Test-VexyVisualPerformance {
    return ([int](Get-VexyRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0) -eq 2)
}
function Set-VexyVisualPerformanceState([bool]$Enabled) {
    New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -Type DWord -Value $(if($Enabled){2}else{0}) -Force
    if($Enabled){ 'Best Performance visual-effects preference enabled. Sign out/restart Explorer may be needed.' } else { 'Visual-effects preference returned to Let Windows choose.' }
}

function Test-VexyTransparencyOff {
    return ([int](Get-VexyRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1) -eq 0)
}
function Set-VexyTransparencyOffState([bool]$Disabled) {
    New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Force | Out-Null
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -Type DWord -Value $(if($Disabled){0}else{1}) -Force
    if($Disabled){ 'Windows transparency effects disabled.' } else { 'Windows transparency effects enabled.' }
}

function Test-VexyPowerThrottlingOff {
    return ([int](Get-VexyRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 0) -eq 1)
}
function Set-VexyPowerThrottlingOffState([bool]$Disabled) {
    $p='HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
    New-Item $p -Force | Out-Null
    if($Disabled){
        Set-ItemProperty $p -Name PowerThrottlingOff -Type DWord -Value 1 -Force
        'Windows power throttling disabled. This can increase power use, heat and battery drain.'
    } else {
        Remove-ItemProperty $p -Name PowerThrottlingOff -ErrorAction SilentlyContinue
        'Windows default power-throttling control restored.'
    }
}

function Test-VexyDeliveryP2POff {
    $v = Get-VexyRegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' $null
    return ($null -ne $v -and [int]$v -eq 0)
}
function Set-VexyDeliveryP2POffState([bool]$Disabled) {
    $p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    New-Item $p -Force | Out-Null
    if($Disabled){
        Set-ItemProperty $p -Name DODownloadMode -Type DWord -Value 0 -Force
        'Delivery Optimization peer-to-peer sharing disabled; Microsoft downloads still work over HTTP/CDN.'
    } else {
        Remove-ItemProperty $p -Name DODownloadMode -ErrorAction SilentlyContinue
        'Delivery Optimization policy returned to the Windows default.'
    }
}

$script:ToggleHandlers = @{
    GameMode = @{
        Get = { Test-VexyGameModeEnabled }
        Set = { param($state) Set-VexyGameModeState $state }
    }
    GameCaptureOff = @{
        Get = { Test-VexyGameCaptureDisabled }
        Set = { param($state) Set-VexyGameCaptureDisabledState $state }
    }
    HighPerformance = @{
        Get = { Test-VexyHighPerformanceEnabled }
        Set = { param($state) Set-VexyHighPerformanceState $state }
    }
    MouseAccelOff = @{
        Get = { Test-VexyMouseAccelOff }
        Set = { param($state) Set-VexyMouseAccelOffState $state }
    }
    Hags = @{
        Get = { Test-VexyHagsEnabled }
        Set = { param($state) Set-VexyHagsState $state }
    }
    NetworkPowerSaveOff = @{
        Get = { Test-VexyNetworkPowerSaveOff }
        Set = { param($state) Set-VexyNetworkPowerSaveOffState $state }
    }
    CloudflareDns = @{
        Get = { Test-VexyCloudflareDns }
        Set = { param($state) Set-VexyCloudflareDnsState $state }
    }
    VisualPerformance = @{
        Get = { Test-VexyVisualPerformance }
        Set = { param($state) Set-VexyVisualPerformanceState $state }
    }
    TransparencyOff = @{
        Get = { Test-VexyTransparencyOff }
        Set = { param($state) Set-VexyTransparencyOffState $state }
    }
    PowerThrottlingOff = @{
        Get = { Test-VexyPowerThrottlingOff }
        Set = { param($state) Set-VexyPowerThrottlingOffState $state }
    }
    DeliveryP2POff = @{
        Get = { Test-VexyDeliveryP2POff }
        Set = { param($state) Set-VexyDeliveryP2POffState $state }
    }
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
        <Style x:Key="CardButton" TargetType="Button">
            <Setter Property="Background" Value="#D70A0710"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#3F2450"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="CardBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="12" Padding="14">
                            <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CardBorder" Property="Background" Value="#E2140A20"/>
                                <Setter TargetName="CardBorder" Property="BorderBrush" Value="#A23BFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="CardBorder" Property="Background" Value="#F11C0E2B"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ToggleSwitch" TargetType="{x:Type ToggleButton}">
            <Setter Property="Width" Value="66"/>
            <Setter Property="Height" Value="30"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ToggleButton}">
                        <Grid Width="{TemplateBinding Width}" Height="{TemplateBinding Height}">
                            <Border x:Name="Track" CornerRadius="15" Background="#4A4650" BorderBrush="#6A6470" BorderThickness="1"/>
                            <Ellipse x:Name="Knob" Width="22" Height="22" Fill="#ECE8F0" HorizontalAlignment="Left" Margin="4,0,0,0"/>
                            <TextBlock x:Name="StateText" Text="OFF" Foreground="#C8C1CD" FontSize="8" FontWeight="Bold"
                                       VerticalAlignment="Center" HorizontalAlignment="Right" Margin="0,0,8,0"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Track" Property="Background" Value="#159447"/>
                                <Setter TargetName="Track" Property="BorderBrush" Value="#47E884"/>
                                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="Knob" Property="Margin" Value="0,0,4,0"/>
                                <Setter TargetName="StateText" Property="Text" Value="ON"/>
                                <Setter TargetName="StateText" Property="Foreground" Value="White"/>
                                <Setter TargetName="StateText" Property="HorizontalAlignment" Value="Left"/>
                                <Setter TargetName="StateText" Property="Margin" Value="9,0,0,0"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Track" Property="BorderBrush" Value="#C56CFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
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
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="145"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" VerticalAlignment="Center">
                        <Image x:Name="SidebarLogo" Height="100" Stretch="Uniform"/>
                        <TextBlock Text="OPTIMIZER" HorizontalAlignment="Center" Foreground="#A06DBE" FontSize="10"/>
                    </StackPanel>
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="0,0,0,4">
                        <StackPanel x:Name="NavPanel"/>
                    </ScrollViewer>
                    <StackPanel Grid.Row="2" Margin="14,6,14,14">
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
        @{Title='QUICK OPTIMIZE'; Desc='Run the recommended reversible VEXY preset.'; Info='Creates a restore point, enables Game Mode, disables Windows background game capture, switches to High Performance, cleans user TEMP files and flushes DNS. It does not disable Windows security or recovery features.'; Icon='optimize'; Action='QuickOptimize'; Kind='Action'; Risk='Normal'},
        @{Title='RESTORE POINT'; Desc='Create a Windows restore point before changes.'; Info='Asks Windows System Restore to create a checkpoint before optimization changes. Windows can limit how often restore points are created, so the request can occasionally be skipped by the operating system.'; Icon='backup'; Action='RestorePoint'; Kind='Action'; Risk='Normal'},
        @{Title='GAME MODE'; Desc='Prioritize gaming behavior in Windows.'; Info='Turns Windows Game Mode on or off. Game Mode can reduce some background activity while a game is running. Results vary by game and hardware; it is not an FPS guarantee.'; Icon='game_mode'; Toggle='GameMode'; Kind='Toggle'; Risk='Normal'},
        @{Title='GAME CAPTURE OFF'; Desc='Stop Windows background game recording.'; Info='When ON, disables Windows Game DVR/background capture for the current user. This can reduce background recording activity, but Xbox/Windows capture shortcuts and background clips will no longer work until switched back OFF.'; Icon='gpu'; Toggle='GameCaptureOff'; Kind='Toggle'; Risk='Warning'},
        @{Title='HIGH PERFORMANCE'; Desc='Use Windows High Performance power plan.'; Info='When ON, selects the Windows High Performance power plan. It can improve responsiveness on some systems, but it increases power consumption and may increase temperatures, battery drain and fan noise. OFF restores Balanced.'; Icon='boost'; Toggle='HighPerformance'; Kind='Toggle'; Risk='Warning'},
        @{Title='HARDWARE'; Desc='Open hardware monitoring and system information.'; Info='Opens the VEXY Hardware page. It reads CPU, GPU, RAM, motherboard, BIOS, storage and network information without changing CPU/GPU voltage, clocks or firmware.'; Icon='cpu'; Action='OpenHardware'; Kind='Action'; Risk='Normal'},
        @{Title='TEMP CLEAN'; Desc='Clear deletable files from your user TEMP folder.'; Info='Deletes files Windows and apps have placed in your current user TEMP folder. Locked/in-use files are skipped. It does not intentionally delete Documents, Downloads, Desktop or game saves.'; Icon='temp_clean'; Action='TempClean'; Kind='Action'; Risk='Normal'},
        @{Title='DISK TRIM'; Desc='Request Windows retrim on eligible fixed drives.'; Info='Uses Windows Optimize-Volume with ReTrim on eligible fixed volumes. This is intended for SSD/TRIM maintenance and lets Windows decide what is supported.'; Icon='disk'; Action='DiskTrim'; Kind='Action'; Risk='Normal'},
        @{Title='ADVANCED'; Desc='Open experimental options with clear trade-offs.'; Info='Opens VEXY Advanced / Experimental. These settings are reversible but can increase power use, change networking behavior, or require a reboot. Read each information tooltip before switching one on.'; Icon='advanced'; Action='OpenAdvanced'; Kind='Action'; Risk='Advanced'}
    )
    optimize = @(
        @{Title='GAME MODE'; Desc='Toggle Windows Game Mode.'; Info='Game Mode changes how Windows prioritizes gaming workloads and some background activity. Benefit depends on the game, driver and hardware.'; Icon='game_mode'; Toggle='GameMode'; Kind='Toggle'; Risk='Normal'},
        @{Title='GAME CAPTURE OFF'; Desc='Disable background game recording.'; Info='When ON, disables Windows background capture/Game DVR. This may reduce background work, but background recording features stop working.'; Icon='gpu'; Toggle='GameCaptureOff'; Kind='Toggle'; Risk='Warning'},
        @{Title='HIGH PERFORMANCE'; Desc='Toggle the High Performance power plan.'; Info='When ON, prioritizes performance over energy savings. Expect higher electricity/battery use and possibly more heat. OFF restores Balanced.'; Icon='boost'; Toggle='HighPerformance'; Kind='Toggle'; Risk='Warning'},
        @{Title='MOUSE ACCEL OFF'; Desc='Toggle standard Windows mouse acceleration values.'; Info='When ON, sets MouseSpeed, MouseThreshold1 and MouseThreshold2 to zero for the current user. This makes pointer movement more direct for many gaming setups. OFF restores common Windows acceleration values (1/6/10).'; Icon='tools'; Toggle='MouseAccelOff'; Kind='Toggle'; Risk='Normal'},
        @{Title='VISUAL PERFORMANCE'; Desc='Prefer performance over Windows visual effects.'; Info='When ON, requests Windows Best Performance visual-effects preference. Some animations and effects may be reduced. OFF returns the preference to Let Windows choose. A sign-out or Explorer restart can be needed.'; Icon='windows'; Toggle='VisualPerformance'; Kind='Toggle'; Risk='Warning'},
        @{Title='TRANSPARENCY OFF'; Desc='Disable Windows transparency effects.'; Info='When ON, disables acrylic/transparency effects in Windows. This is mostly a visual preference and may slightly reduce compositing work on weaker systems. OFF re-enables transparency.'; Icon='windows'; Toggle='TransparencyOff'; Kind='Toggle'; Risk='Normal'},
        @{Title='GRAPHICS SETTINGS'; Desc='Open Windows per-app GPU preferences.'; Info='Opens the official Windows Graphics Settings page so you can choose GPU preferences per application and review supported default graphics options.'; Icon='gpu'; Action='OpenGraphicsSettings'; Kind='Action'; Risk='Normal'},
        @{Title='SAVE BASELINE'; Desc='Save a before/after system snapshot.'; Info='Stores RAM use, free system-drive space, startup-entry count and active power plan. It is a configuration snapshot, not an FPS benchmark.'; Icon='diagnostics'; Action='SaveBaseline'; Kind='Action'; Risk='Normal'},
        @{Title='COMPARE BASELINE'; Desc='Compare current state with your saved snapshot.'; Info='Shows how RAM use, disk free space, startup-entry count and power plan changed since SAVE BASELINE. Values such as RAM use naturally move as apps open and close.'; Icon='diagnostics'; Action='CompareBaseline'; Kind='Action'; Risk='Normal'}
    )
    cleaner = @(
        @{Title='USER TEMP'; Desc='Remove deletable files from your user TEMP folder.'; Info='Deletes items in the current user temporary folder. Locked files are skipped. Personal folders are not targeted.'; Icon='temp_clean'; Action='TempClean'; Kind='Action'; Risk='Normal'},
        @{Title='DNS CACHE'; Desc='Flush cached DNS resolver entries.'; Info='Runs the Windows DNS cache flush command. This removes cached name lookups; Windows rebuilds them as sites and apps are used.'; Icon='dns_network'; Action='FlushDns'; Kind='Action'; Risk='Normal'},
        @{Title='DISK TRIM'; Desc='Run Windows retrim on eligible drives.'; Info='Requests Windows to issue retrim/optimization for fixed volumes that support it. Windows handles unsupported volumes safely.'; Icon='disk'; Action='DiskTrim'; Kind='Action'; Risk='Normal'},
        @{Title='STORAGE SENSE'; Desc='Open Windows automatic cleanup controls.'; Info='Opens the official Windows Storage Sense page. VEXY does not force automatic deletion settings because Storage Sense can be configured to clean temporary, Recycle Bin or cloud content on a schedule.'; Icon='cleaner'; Action='OpenStorageSense'; Kind='Action'; Risk='Warning'},
        @{Title='STORAGE REPORT'; Desc='See free space and health reported by Windows.'; Info='Reads mounted volumes, file systems, free space and Windows health status without writing to the drives.'; Icon='disk'; Action='StorageReport'; Kind='Action'; Risk='Normal'}
    )
    boost = @(
        @{Title='HIGH PERFORMANCE'; Desc='Prioritize performance over power savings.'; Info='ON selects High Performance. It can improve responsiveness but raises power use and can increase heat/fan noise. OFF restores Balanced.'; Icon='boost'; Toggle='HighPerformance'; Kind='Toggle'; Risk='Warning'},
        @{Title='GAME MODE'; Desc='Enable Windows Game Mode behavior.'; Info='Game Mode is a Windows gaming feature. It may help some systems by reducing competing background activity; results vary.'; Icon='game_mode'; Toggle='GameMode'; Kind='Toggle'; Risk='Normal'},
        @{Title='GAME CAPTURE OFF'; Desc='Disable background game recording.'; Info='ON disables Game DVR/background capture. Useful if you do not use background clips. OFF re-enables capture.'; Icon='gpu'; Toggle='GameCaptureOff'; Kind='Toggle'; Risk='Warning'},
        @{Title='POWER THROTTLING OFF'; Desc='Experimental: stop Windows power throttling.'; Info='When ON, sets the Windows PowerThrottlingOff policy. Background tasks may stay more responsive, but this can increase CPU power use, battery drain and heat. It is not recommended as a universal FPS tweak. OFF restores Windows control.'; Icon='cpu'; Toggle='PowerThrottlingOff'; Kind='Toggle'; Risk='Advanced'},
        @{Title='POWER SETTINGS'; Desc='Open Windows power and energy controls.'; Info='Opens the official Windows Power & sleep settings page. Use it to review power mode and energy settings that VEXY does not force automatically.'; Icon='boost'; Action='OpenPowerSettings'; Kind='Action'; Risk='Normal'},
        @{Title='HARDWARE REPORT'; Desc='Check clocks and component information.'; Info='Shows Windows-reported CPU clock, GPU driver/VRAM, RAM speed, motherboard/BIOS, storage and network information. It does not alter hardware limits.'; Icon='cpu'; Action='HardwareReport'; Kind='Action'; Risk='Normal'}
    )
    tools = @(
        @{Title='DIAGNOSTICS'; Desc='Display a quick system hardware summary.'; Info='Reads basic OS/CPU/GPU/RAM information and writes it to the VEXY event log.'; Icon='diagnostics'; Action='Diagnostics'; Kind='Action'; Risk='Normal'},
        @{Title='STARTUP SCAN'; Desc='List common startup entries without disabling them.'; Info='Reads common Run registry keys and Startup folders. VEXY lists the entries but does not auto-disable them because driver, security and utility software can appear there.'; Icon='startup'; Action='StartupScan'; Kind='Action'; Risk='Normal'},
        @{Title='STARTUP MANAGER'; Desc='Open Windows startup-app control.'; Info='Opens Task Manager so you can review startup applications yourself. VEXY does not automatically disable startup entries because some are important to drivers or software you use.'; Icon='startup'; Action='Startup'; Kind='Action'; Risk='Normal'},
        @{Title='SAVE BASELINE'; Desc='Save a before/after configuration snapshot.'; Info='Stores RAM usage, free system-drive space, startup-entry count and active power plan so you can compare later. It does not stress-test the PC.'; Icon='diagnostics'; Action='SaveBaseline'; Kind='Action'; Risk='Normal'},
        @{Title='COMPARE BASELINE'; Desc='Compare against the saved VEXY snapshot.'; Info='Displays observable changes since the saved baseline. It does not convert the result into a fake FPS or latency score.'; Icon='diagnostics'; Action='CompareBaseline'; Kind='Action'; Risk='Normal'},
        @{Title='CREATE RESTORE POINT'; Desc='Create a Windows System Restore checkpoint.'; Info='Creates a recovery checkpoint before you experiment with advanced Windows settings. Windows may rate-limit restore point creation.'; Icon='backup'; Action='RestorePoint'; Kind='Action'; Risk='Normal'},
        @{Title='SYSTEM RESTORE'; Desc='Open the Windows System Restore interface.'; Info='Launches the built-in Windows System Restore interface. VEXY does not select or apply a restore point automatically.'; Icon='windows'; Action='OpenRestore'; Kind='Action'; Risk='Normal'},
        @{Title='INSTALLED APPS'; Desc='Open Windows app management.'; Info='Opens Windows Installed Apps so you can review software yourself. VEXY does not automatically uninstall programs.'; Icon='settings'; Action='OpenAppsSettings'; Kind='Action'; Risk='Normal'}
    )
    tweaks = @(
        @{Title='MOUSE ACCEL OFF'; Desc='Direct pointer movement for gaming setups.'; Info='ON sets the current user mouse acceleration registry values to zero. OFF restores common Windows acceleration values.'; Icon='tools'; Toggle='MouseAccelOff'; Kind='Toggle'; Risk='Normal'},
        @{Title='VISUAL PERFORMANCE'; Desc='Reduce some Windows visual effects.'; Info='ON asks Windows to favor performance over appearance. OFF returns to Let Windows choose. This affects appearance more than raw game FPS.'; Icon='windows'; Toggle='VisualPerformance'; Kind='Toggle'; Risk='Warning'},
        @{Title='TRANSPARENCY OFF'; Desc='Disable acrylic/transparency effects.'; Info='ON disables Windows transparency effects. OFF re-enables them. This is a small, reversible visual/compositor tweak.'; Icon='windows'; Toggle='TransparencyOff'; Kind='Toggle'; Risk='Normal'},
        @{Title='DELIVERY P2P OFF'; Desc='Stop Windows update peer-to-peer sharing.'; Info='ON sets Delivery Optimization to HTTP/CDN only (DownloadMode 0), disabling peer-to-peer update sharing while still allowing Microsoft downloads. This can reduce peer upload/download activity but may use more internet bandwidth from Microsoft servers. OFF returns the policy to Windows default.'; Icon='network'; Toggle='DeliveryP2POff'; Kind='Toggle'; Risk='Warning'},
        @{Title='CLOUDFLARE DNS'; Desc='Use 1.1.1.1 / 1.0.0.1 for active adapters.'; Info='ON changes IPv4 DNS servers on active physical adapters to Cloudflare. This can change DNS lookup routing but does not guarantee lower game ping. OFF resets DNS server addresses to automatic/DHCP.'; Icon='dns_network'; Toggle='CloudflareDns'; Kind='Toggle'; Risk='Warning'},
        @{Title='GRAPHICS SETTINGS'; Desc='Open Windows graphics controls.'; Info='Opens the official Windows Graphics Settings page. VEXY does not force a GPU preference for every application because laptops and multi-GPU systems can have different needs.'; Icon='gpu'; Action='OpenGraphicsSettings'; Kind='Action'; Risk='Normal'},
        @{Title='STORAGE SENSE'; Desc='Review automatic cleanup schedules.'; Info='Opens Windows Storage Sense so you can decide whether automatic cleanup should be enabled and what it is allowed to remove.'; Icon='cleaner'; Action='OpenStorageSense'; Kind='Action'; Risk='Warning'}
    )
    backup = @(
        @{Title='RESTORE POINT'; Desc='Create a Windows restore point now.'; Info='Requests a Windows System Restore checkpoint. Use this before Advanced / Experimental changes.'; Icon='backup'; Action='RestorePoint'; Kind='Action'; Risk='Normal'},
        @{Title='SYSTEM RESTORE'; Desc='Open the Windows System Restore interface.'; Info='Opens the built-in Windows restore tool. Nothing is restored until you choose it in Windows.'; Icon='windows'; Action='OpenRestore'; Kind='Action'; Risk='Normal'},
        @{Title='SAVE BASELINE'; Desc='Save current configuration/resource snapshot.'; Info='Stores a lightweight before-state to compare later. It is useful before testing a group of tweaks.'; Icon='diagnostics'; Action='SaveBaseline'; Kind='Action'; Risk='Normal'},
        @{Title='COMPARE BASELINE'; Desc='Compare against your saved snapshot.'; Info='Shows resource/configuration differences without claiming they equal a performance gain.'; Icon='diagnostics'; Action='CompareBaseline'; Kind='Action'; Risk='Normal'}
    )
    advanced = @(
        @{Title='HAGS'; Desc='Hardware-Accelerated GPU Scheduling.'; Info='ON requests Hardware-Accelerated GPU Scheduling through the Windows graphics-driver setting. A reboot is required. Depending on GPU, driver and game it may help, hurt, or make no measurable difference. OFF disables HAGS and also requires a reboot.'; Icon='gpu'; Toggle='Hags'; Kind='Toggle'; Risk='Advanced'},
        @{Title='NETWORK POWER SAVE OFF'; Desc='Keep physical network adapters awake.'; Info='ON prevents Windows from powering off supported physical network adapters to save energy. This may avoid some resume/power-management issues, but it increases power use and is usually unnecessary on stable systems. OFF restores permission to power the adapters down.'; Icon='network'; Toggle='NetworkPowerSaveOff'; Kind='Toggle'; Risk='Advanced'},
        @{Title='POWER THROTTLING OFF'; Desc='Let background work avoid Windows throttling.'; Info='ON turns off Windows Power Throttling system-wide. This may keep background workloads more responsive but can substantially increase battery use, CPU activity and heat. It is not a guaranteed gaming improvement. OFF restores Windows control.'; Icon='cpu'; Toggle='PowerThrottlingOff'; Kind='Toggle'; Risk='Advanced'},
        @{Title='CLOUDFLARE DNS'; Desc='Change active adapter DNS servers.'; Info='ON sets active physical adapters to Cloudflare DNS. DNS affects name resolution, not the route your game packets take, so lower game ping is not guaranteed. OFF resets DNS to automatic/DHCP.'; Icon='dns_network'; Toggle='CloudflareDns'; Kind='Toggle'; Risk='Advanced'},
        @{Title='DELIVERY P2P OFF'; Desc='Disable update peer sharing.'; Info='ON disables Delivery Optimization peer-to-peer sharing while keeping normal Microsoft HTTP/CDN downloads. This can reduce background peer traffic. OFF removes the VEXY policy and lets Windows use its normal configuration.'; Icon='network'; Toggle='DeliveryP2POff'; Kind='Toggle'; Risk='Advanced'},
        @{Title='VISUAL PERFORMANCE'; Desc='Reduce Windows visual polish.'; Info='ON selects the Best Performance visual-effects preference. It can make Windows feel snappier on slower hardware but removes visual effects. OFF returns to Let Windows choose.'; Icon='windows'; Toggle='VisualPerformance'; Kind='Toggle'; Risk='Advanced'},
        @{Title='NETWORK CAPABILITIES'; Desc='Read adapter RSS/power/link information.'; Info='Shows current physical network adapter state and selected capabilities. VEXY does not automatically alter driver-specific interrupt moderation, EEE or vendor advanced properties because the correct setting depends on the adapter and driver.'; Icon='network'; Action='NetworkReport'; Kind='Action'; Risk='Advanced'},
        @{Title='HARDWARE TUNING INFO'; Desc='See what VEXY will not auto-overclock.'; Info='Explains why VEXY keeps CPU/GPU voltage, clocks, PBO, Curve Optimizer, EXPO/XMP and firmware controls monitoring-only.'; Icon='cpu'; Action='TuningSafety'; Kind='Action'; Risk='Advanced'}
    )
    hardware = @(
        @{Title='FULL HARDWARE REPORT'; Desc='CPU, GPU, RAM, board, BIOS, storage and network.'; Info='Builds a read-only system report from standard Windows hardware classes. No clocks, voltages, firmware or drivers are changed.'; Icon='diagnostics'; Action='HardwareReport'; Kind='Action'; Risk='Normal'},
        @{Title='CPU SNAPSHOT'; Desc='Read CPU model, cores and Windows-reported clocks.'; Info='Shows the processor model, core/thread counts and current/max clock values reported by Windows. Per-core boost, temperature and voltage require vendor-specific telemetry and are not guessed.'; Icon='cpu'; Action='CpuReport'; Kind='Action'; Risk='Normal'},
        @{Title='GPU SNAPSHOT'; Desc='Read graphics adapters and driver information.'; Info='Shows GPU name, driver version, Windows-reported VRAM and display mode. GPU core clock, hotspot temperature and voltage are vendor-specific and are not modified.'; Icon='gpu'; Action='GpuReport'; Kind='Action'; Risk='Normal'},
        @{Title='RAM SNAPSHOT'; Desc='Read installed capacity and configured speed.'; Info='Shows detected memory modules, size and configured speed reported by Windows. EXPO/XMP status and memory voltages/timings are not changed by VEXY.'; Icon='memory'; Action='MemoryReport'; Kind='Action'; Risk='Normal'},
        @{Title='BOARD / BIOS'; Desc='Read motherboard and BIOS information.'; Info='Shows system model, motherboard, BIOS version/date and Memory Integrity status. VEXY never flashes firmware or disables security protections.'; Icon='windows'; Action='BoardReport'; Kind='Action'; Risk='Normal'},
        @{Title='STORAGE'; Desc='Read volume space and health.'; Info='Shows mounted volumes, file systems, free space and the health state Windows reports. This card is read-only.'; Icon='disk'; Action='StorageReport'; Kind='Action'; Risk='Normal'},
        @{Title='NETWORK'; Desc='Read physical adapter state and link speed.'; Info='Shows physical adapters, link speed, power-off permission and RSS when available. Driver-specific advanced properties are not changed automatically.'; Icon='network'; Action='NetworkReport'; Kind='Action'; Risk='Normal'},
        @{Title='GRAPHICS SETTINGS'; Desc='Open Windows graphics preferences.'; Info='Opens the official Windows Graphics Settings page for per-app GPU selection and supported default graphics options.'; Icon='gpu'; Action='OpenGraphicsSettings'; Kind='Action'; Risk='Normal'},
        @{Title='POWER SETTINGS'; Desc='Open Windows power controls.'; Info='Opens Windows Power & sleep settings so power mode and energy options can be reviewed without VEXY forcing hardware tuning.'; Icon='boost'; Action='OpenPowerSettings'; Kind='Action'; Risk='Normal'},
        @{Title='TASK MANAGER'; Desc='Open Windows live performance graphs.'; Info='Opens Task Manager, where Windows exposes CPU, memory, disk, network and GPU utilization graphs.'; Icon='diagnostics'; Action='OpenTaskManager'; Kind='Action'; Risk='Normal'},
        @{Title='OVERCLOCKING SAFETY'; Desc='Read why hardware tuning stays monitoring-only.'; Info='VEXY does not automatically set CPU/GPU clocks, voltages, PBO, Curve Optimizer, EXPO/XMP or firmware values because stability and safe limits depend on the exact hardware and cooling.'; Icon='advanced'; Action='TuningSafety'; Kind='Action'; Risk='Advanced'}
    )
    settings = @(
        @{Title='MUSIC ON / OFF'; Desc='Toggle the VEXY background track.'; Info='Pauses or resumes the VEXY background music only. This does not affect Windows audio settings.'; Icon='settings'; Action='ToggleMusic'; Kind='Action'; Risk='Normal'},
        @{Title='LICENSE INFO'; Desc='Show current license duration and remaining time.'; Info='Displays the active VEXY license label and remaining time stored for this Windows user.'; Icon='about'; Action='LicenseInfo'; Kind='Action'; Risk='Normal'},
        @{Title='GRAPHICS SETTINGS'; Desc='Open Windows graphics preferences.'; Info='Opens the official Windows graphics configuration page.'; Icon='gpu'; Action='OpenGraphicsSettings'; Kind='Action'; Risk='Normal'},
        @{Title='POWER SETTINGS'; Desc='Open Windows power controls.'; Info='Opens Windows Power & sleep settings.'; Icon='boost'; Action='OpenPowerSettings'; Kind='Action'; Risk='Normal'},
        @{Title='STORAGE SENSE'; Desc='Open Windows automatic cleanup controls.'; Info='Opens Storage Sense so cleanup behavior and schedules remain under your control.'; Icon='cleaner'; Action='OpenStorageSense'; Kind='Action'; Risk='Warning'}
    )
    about = @(
        @{Title='VEXY VERSION'; Desc='Show build information.'; Info='Displays the current VEXY build/version identifier.'; Icon='about'; Action='Version'; Kind='Action'; Risk='Normal'},
        @{Title='SAFETY MODEL'; Desc='See which system areas VEXY deliberately avoids.'; Info='VEXY does not disable Defender, Windows Recovery, Ctrl+Alt+Delete, Task Manager, Memory Integrity or other security protections, and does not modify firmware/BIOS or apply hardware voltage/clock changes.'; Icon='security'; Action='SafetyInfo'; Kind='Action'; Risk='Normal'},
        @{Title='HARDWARE TUNING'; Desc='Read the hardware-tuning boundary.'; Info='Explains why overclocking controls stay monitoring-only in VEXY.'; Icon='cpu'; Action='TuningSafety'; Kind='Action'; Risk='Normal'}
    )
}

$script:PageTitles = @{
    dashboard=@('WELCOME TO VEXY OPTIMIZER','LIVE SWITCHES, CLEAR TRADE-OFFS, AND REVERSIBLE WINDOWS TUNING.')
    optimize=@('OPTIMIZATION SUITE','GREEN = ENABLED. GRAY = DISABLED. HOVER THE ⓘ FOR EXACT DETAILS.')
    cleaner=@('SYSTEM CLEANER','SAFE MAINTENANCE ACTIONS — PERSONAL FILES ARE NOT TARGETED.')
    boost=@('PERFORMANCE BOOST','PERFORMANCE OPTIONS WITH POWER, HEAT AND FEATURE TRADE-OFFS SHOWN CLEARLY.')
    tools=@('VEXY TOOLS','STARTUP SCAN, BASELINE SNAPSHOTS, DIAGNOSTICS AND WINDOWS RECOVERY.')
    tweaks=@('WINDOWS TWEAKS','REVERSIBLE SETTINGS — NO MAGIC FPS CLAIMS.')
    backup=@('BACKUP / RESTORE','CREATE A RECOVERY POINT OR SAVE A CONFIGURATION BASELINE BEFORE CHANGES.')
    advanced=@('ADVANCED / EXPERIMENTAL','THESE CAN HELP SOME SYSTEMS AND HURT OTHERS. READ THE ⓘ BEFORE SWITCHING THEM ON.')
    hardware=@('HARDWARE / MONITORING','READ-ONLY COMPONENT DATA. VEXY DOES NOT AUTOMATE VOLTAGE, CLOCK OR BIOS TUNING.')
    settings=@('VEXY SETTINGS','CONTROL MUSIC AND OPEN OFFICIAL WINDOWS CONFIGURATION PAGES.')
    about=@('ABOUT VEXY','VEXY OPTIMIZER • WINDOWS PERFORMANCE UTILITY.')
}


function New-VexyToolTip([string]$Title,[string]$Text,[string]$Risk) {
    $tip = New-Object System.Windows.Controls.ToolTip
    $tip.Placement = 'Mouse'
    $tip.StaysOpen = $true
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($tip,180)
    [System.Windows.Controls.ToolTipService]::SetShowDuration($tip,45000)

    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F20A0710')
    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if($Risk -eq 'Advanced'){'#D15BFF'}elseif($Risk -eq 'Warning'){'#A76A5B'}else{'#7135B4'}))
    $border.BorderThickness = '1'
    $border.CornerRadius = '9'
    $border.Padding = '14'
    $border.MaxWidth = 430

    $stack = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.TextBlock
    $head.Text = "$Title  •  $($Risk.ToUpperInvariant())"
    $head.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D998FF')
    $head.FontWeight = 'SemiBold'
    $head.FontSize = 12
    $head.Margin = '0,0,0,7'
    $body = New-Object System.Windows.Controls.TextBlock
    $body.Text = $Text
    $body.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E4D9EA')
    $body.TextWrapping = 'Wrap'
    $body.FontSize = 11
    $body.LineHeight = 17
    $stack.Children.Add($head) | Out-Null
    $stack.Children.Add($body) | Out-Null
    $border.Child = $stack
    $tip.Content = $border
    return $tip
}

function Add-VexyCardHeader($Stack,$Item) {
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = 168
    $grid.Margin = '0,0,0,8'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    $c2 = New-Object System.Windows.Controls.ColumnDefinition
    $c2.Width = [System.Windows.GridLength]::new(24)
    $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2)

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = $Item.Title
    $title.FontSize = 14
    $title.FontWeight = 'SemiBold'
    $title.Foreground = 'White'
    $title.TextAlignment = 'Center'
    $title.VerticalAlignment = 'Center'
    $title.TextWrapping = 'Wrap'
    [System.Windows.Controls.Grid]::SetColumn($title,0)

    $info = New-Object System.Windows.Controls.TextBlock
    $info.Text = 'ⓘ'
    $info.FontSize = 15
    $info.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C56CFF')
    $info.HorizontalAlignment = 'Right'
    $info.VerticalAlignment = 'Top'
    $info.Cursor = 'Help'
    $info.ToolTip = New-VexyToolTip $Item.Title $(if($Item.Info){$Item.Info}else{$Item.Desc}) $Item.Risk
    [System.Windows.Controls.Grid]::SetColumn($info,1)

    $grid.Children.Add($title) | Out-Null
    $grid.Children.Add($info) | Out-Null
    $Stack.Children.Add($grid) | Out-Null
}

function Add-VexyCardIcon($Stack,$Item,[int]$Height=92) {
    $iconPath = Get-VexyIconPath $Item.Icon
    $bmp = New-VexyBitmap $iconPath
    if ($bmp) {
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $bmp
        $img.Height = $Height
        $img.Stretch = 'Uniform'
        $img.Margin = '0,0,0,8'
        $Stack.Children.Add($img) | Out-Null
    } else {
        $fallback = New-Object System.Windows.Controls.TextBlock
        $fallback.Text = '✦'
        $fallback.FontSize = 48
        $fallback.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#A23BFF')
        $fallback.HorizontalAlignment = 'Center'
        $fallback.Margin = '0,0,0,10'
        $Stack.Children.Add($fallback) | Out-Null
    }
}

function Add-VexyDescription($Stack,$Item) {
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $Item.Desc
    $desc.FontSize = 10.5
    $desc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#A696B1')
    $desc.TextWrapping = 'Wrap'
    $desc.TextAlignment = 'Center'
    $desc.HorizontalAlignment = 'Center'
    $desc.MaxWidth = 175
    $desc.MinHeight = 34
    $Stack.Children.Add($desc) | Out-Null
}

function New-VexyToggleCard($Item) {
    $border = New-Object System.Windows.Controls.Border
    $border.Width = 205
    $border.Height = 255
    $border.Margin = '8'
    $border.Padding = '14'
    $border.CornerRadius = '12'
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D70A0710')
    $border.BorderThickness = '1'
    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if($Item.Risk -eq 'Advanced'){'#A353E6'}elseif($Item.Risk -eq 'Warning'){'#6F385D'}else{'#3F2450'}))
    $border.Add_MouseEnter({
        param($s,$e)
        $s.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#E2140A20')
        $s.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#A23BFF')
        Play-VexySound 'Hover'
    })
    $border.Add_MouseLeave({
        param($s,$e)
        $item = $s.Tag
        $s.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D70A0710')
        $s.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if($item.Risk -eq 'Advanced'){'#A353E6'}elseif($item.Risk -eq 'Warning'){'#6F385D'}else{'#3F2450'}))
    })
    $border.Tag = $Item

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = 'Center'
    Add-VexyCardHeader $stack $Item
    Add-VexyCardIcon $stack $Item 82
    Add-VexyDescription $stack $Item

    $toggle = New-Object System.Windows.Controls.Primitives.ToggleButton
    $toggle.Style = $window.Resources['ToggleSwitch']
    $toggle.Margin = '0,13,0,0'
    $toggle.HorizontalAlignment = 'Center'
    $toggle.Tag = $Item

    $handler = $script:ToggleHandlers[$Item.Toggle]
    $initial = $false
    if($handler){
        try { $initial = [bool](& $handler.Get) } catch { $initial = $false }
    }
    $toggle.IsChecked = $initial

    $toggle.Add_Click({
        param($s,$e)
        Play-VexySound 'Click'
        $item = $s.Tag
        $spec = $script:ToggleHandlers[$item.Toggle]
        if(-not $spec){ Add-VexyLog "No toggle handler for $($item.Toggle)."; return }

        $wanted = [bool]$s.IsChecked
        $before = $false
        try { $before = [bool](& $spec.Get) } catch {}

        if($item.Risk -eq 'Advanced'){
            $verb = if($wanted){'ENABLE'}else{'DISABLE'}
            $msg = "$verb $($item.Title)?`n`n$($item.Info)`n`nThis is an Advanced / Experimental setting. Create a restore point first if you want an easy rollback."
            if(-not (Confirm-Vexy "ADVANCED: $($item.Title)" $msg)){
                $s.IsChecked = $before
                return
            }
        } elseif($item.Risk -eq 'Warning'){
            $verb = if($wanted){'TURN ON'}else{'TURN OFF'}
            if(-not (Confirm-Vexy $item.Title "$verb $($item.Title)?`n`n$($item.Info)")){
                $s.IsChecked = $before
                return
            }
        }

        try {
            Add-VexyLog "$($item.Title): applying..."
            $result = & $spec.Set $wanted
            if($result){ Add-VexyLog $result }
            $actual = [bool](& $spec.Get)
            $s.IsChecked = $actual
            if($actual -eq $wanted){
                Play-VexySound 'Success'
            } else {
                Add-VexyLog "$($item.Title): Windows did not report the requested state. The setting may be unsupported or require a reboot."
                Play-VexySound 'Warning'
            }
        } catch {
            $s.IsChecked = $before
            Add-VexyLog "$($item.Title) failed: $($_.Exception.Message)"
            Play-VexySound 'Warning'
        }
    })

    $stack.Children.Add($toggle) | Out-Null

    if($Item.Risk -eq 'Advanced'){
        $badge = New-Object System.Windows.Controls.TextBlock
        $badge.Text='⚠ EXPERIMENTAL'
        $badge.Foreground=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#D78CFF')
        $badge.FontSize=8.5
        $badge.HorizontalAlignment='Center'
        $badge.Margin='0,7,0,0'
        $stack.Children.Add($badge)|Out-Null
    }

    $border.Child = $stack
    return $border
}

function New-VexyCard($Item) {
    if($Item.Kind -eq 'Toggle'){
        return New-VexyToggleCard $Item
    }

    $button = New-Object System.Windows.Controls.Button
    $button.Width = 205
    $button.Height = 255
    $button.Margin = '8'
    $button.Tag = $Item
    $button.Style = $window.Resources['CardButton']

    $borderColor = if ($Item.Risk -eq 'Advanced') { '#A353E6' } elseif ($Item.Risk -eq 'Warning') { '#6F385D' } else { '#3F2450' }
    $button.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($borderColor)

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = 'Center'
    Add-VexyCardHeader $stack $Item
    Add-VexyCardIcon $stack $Item 88
    Add-VexyDescription $stack $Item

    $actionText = New-Object System.Windows.Controls.TextBlock
    $actionText.Text = 'CLICK TO RUN'
    $actionText.FontSize = 9
    $actionText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#C56CFF')
    $actionText.HorizontalAlignment = 'Center'
    $actionText.Margin = '0,12,0,0'
    $stack.Children.Add($actionText) | Out-Null

    if ($Item.Risk -eq 'Advanced') {
        $badge = New-Object System.Windows.Controls.TextBlock
        $badge.Text = '⚠ ADVANCED'
        $badge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#D78CFF')
        $badge.FontSize = 8.5
        $badge.HorizontalAlignment = 'Center'
        $badge.Margin = '0,6,0,0'
        $stack.Children.Add($badge) | Out-Null
    }

    $button.Content = $stack
    $button.Add_MouseEnter({ Play-VexySound 'Hover' })
    $button.Add_Click({
        param($s,$e)
        try {
            Play-VexySound 'Click'
            Invoke-VexyAction $s.Tag
        } catch {
            Add-VexyLog ("Action error: {0}" -f $_.Exception.Message)
            Play-VexySound 'Warning'
        }
    })
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
        } catch {
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
        'OpenHardware' { Render-VexyPage 'hardware' }
        'HardwareReport' { Show-VexyReport 'FULL HARDWARE REPORT' (Get-VexyFullHardwareReport); Add-VexyLog 'Hardware report opened.' }
        'CpuReport' { Show-VexyReport 'CPU SNAPSHOT' (Get-VexyCpuReport); Add-VexyLog 'CPU snapshot opened.' }
        'GpuReport' { Show-VexyReport 'GPU SNAPSHOT' (Get-VexyGpuReport); Add-VexyLog 'GPU snapshot opened.' }
        'MemoryReport' { Show-VexyReport 'RAM SNAPSHOT' (Get-VexyMemoryReport); Add-VexyLog 'RAM snapshot opened.' }
        'BoardReport' { Show-VexyReport 'BOARD / BIOS' (Get-VexyBoardReport); Add-VexyLog 'Board/BIOS report opened.' }
        'StorageReport' { Show-VexyReport 'STORAGE REPORT' (Get-VexyStorageReport); Add-VexyLog 'Storage report opened.' }
        'NetworkReport' { Show-VexyReport 'NETWORK REPORT' (Get-VexyNetworkReport); Add-VexyLog 'Network report opened.' }
        'StartupScan' { Show-VexyReport 'STARTUP SCAN' (Get-VexyStartupReport); Add-VexyLog 'Startup scan opened.' }
        'SaveBaseline' { Run-VexyResult 'Baseline' { Save-VexyBaseline } }
        'CompareBaseline' { Show-VexyReport 'BASELINE COMPARISON' (Compare-VexyBaseline); Add-VexyLog 'Baseline comparison opened.' }
        'OpenGraphicsSettings' { Add-VexyLog (Open-VexySettingsUri 'ms-settings:display-advancedgraphics' 'Windows Graphics Settings') }
        'OpenPowerSettings' { Add-VexyLog (Open-VexySettingsUri 'ms-settings:powersleep' 'Windows Power settings') }
        'OpenStorageSense' { Add-VexyLog (Open-VexySettingsUri 'ms-settings:storagepolicies' 'Windows Storage Sense') }
        'OpenAppsSettings' { Add-VexyLog (Open-VexySettingsUri 'ms-settings:appsfeatures' 'Windows Installed Apps') }
        'OpenTaskManager' { try { Start-Process 'taskmgr.exe'; Add-VexyLog 'Task Manager opened.' } catch { Add-VexyLog "Task Manager failed: $($_.Exception.Message)" } }
        'TuningSafety' { Show-VexyReport 'HARDWARE TUNING / OVERCLOCKING' (Get-VexyTuningSafetyText); Add-VexyLog 'Hardware tuning safety info opened.' }
        'OpenRestore' { Start-Process 'rstrui.exe'; Add-VexyLog 'Windows System Restore opened.' }
        'ToggleMusic' { $script:MusicEnabled = -not $script:MusicEnabled; if($script:MusicEnabled){$script:MusicPlayer.Play();Add-VexyLog 'Music enabled.'}else{$script:MusicPlayer.Pause();Add-VexyLog 'Music paused.'} }
        'LicenseInfo' { [System.Windows.MessageBox]::Show($window,("License: {0}`nRemaining: {1}" -f $script:CurrentLicense.Label,$script:CurrentLicense.Remaining),'VEXY LICENSE') | Out-Null }
        'Version' { [System.Windows.MessageBox]::Show($window,"VEXY Optimizer`nBuild $script:VexyVersion",'ABOUT VEXY') | Out-Null }
        'SafetyInfo' { [System.Windows.MessageBox]::Show($window,'VEXY keeps Windows recovery and security controls available. It does not disable Defender, Memory Integrity, Windows Recovery, Task Manager or Ctrl+Alt+Delete, and it does not automate CPU/GPU voltage, clocks, PBO, Curve Optimizer, EXPO/XMP or BIOS/firmware tuning.','VEXY SAFETY') | Out-Null }
    }
}

# Navigation
$navItems = @(
    @('⌂  DASHBOARD','dashboard'),@('🚀  OPTIMIZE','optimize'),@('▱  CLEANER','cleaner'),@('ϟ  BOOST','boost'),
    @('◈  HARDWARE','hardware'),@('🛠  TOOLS','tools'),@('≡  TWEAKS','tweaks'),@('◇  BACKUP','backup'),
    @('⚠  ADVANCED','advanced'),@('⚙  SETTINGS','settings'),@('ⓘ  ABOUT','about')
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
