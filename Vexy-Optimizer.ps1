#Requires -Version 5.0
# =====================================================================
#  Vexy PC Optimizer - GUI edition
#  Self-elevates, shows a checkbox menu, runs selected tweaks,
#  pops a branded splash with a live status feed while it works.
# =====================================================================

# ---------- Self-elevate if not already admin ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'VexyNative.MemTrim').Type) {
    Add-Type -Name MemTrim -Namespace VexyNative -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("psapi.dll")]
public static extern bool EmptyWorkingSet(System.IntPtr hProcess);
'@
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { try { Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue } catch { $null } }
if (-not $scriptDir) { $scriptDir = "" }

# ---------- Asset locations: prefer local files next to the script, fall back to download ----------
$logoUrl  = "https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/main/vexy_logo_gray.png"
$musicUrl = "https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/main/vexy_music%20(2).mp3"

$assetDir = Join-Path $env:TEMP "VexyOptimizerAssets"
if (-not (Test-Path $assetDir)) { New-Item -Path $assetDir -ItemType Directory -Force | Out-Null }

function Resolve-Asset {
    param($LocalName, $Url, $CachedName)
    if ($scriptDir) {
        $localCandidate = Join-Path $scriptDir $LocalName
        if (Test-Path $localCandidate) { return $localCandidate }
    }

    $cached = Join-Path $assetDir $CachedName
    if (Test-Path $cached) { return $cached }

    try {
        Invoke-WebRequest -Uri $Url -OutFile $cached -UseBasicParsing -ErrorAction Stop
        if (Test-Path $cached) { return $cached }
    } catch {
        return $null
    }
    return $null
}

$logoPath  = Resolve-Asset -LocalName "vexy_logo.png"  -Url $logoUrl  -CachedName "vexy_logo_gray_v3.png"
$musicPath = Resolve-Asset -LocalName "vexy_music.mp3" -Url $musicUrl -CachedName "vexy_music_v2.mp3"
if (-not $logoPath)  { $logoPath  = "" }
if (-not $musicPath) { $musicPath = "" }

# =====================================================================
#  ACTIVATION / LICENSE SYSTEM
#  Edit the $validKeys table below to add/remove/adjust keys.
#  Value = number of days the key stays valid, counted from first use.
# =====================================================================
$validKeys = @{
    "VEXY-DEMO-0001" = 7
    "VEXY-DEMO-0002" = 30
    "VEXY-DEMO-0003" = 365
}

$licenseDir  = Join-Path $env:APPDATA "VexyOptimizer"
$licenseFile = Join-Path $licenseDir "activation.json"
if (-not (Test-Path $licenseDir)) { New-Item -Path $licenseDir -ItemType Directory -Force | Out-Null }

function Load-License {
    $result = @{ History = @{}; LastKey = $null }
    if (Test-Path $licenseFile) {
        try {
            $raw = Get-Content $licenseFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($raw.History) {
                $raw.History.PSObject.Properties | ForEach-Object { $result.History[$_.Name] = $_.Value }
            }
            if ($raw.LastKey) { $result.LastKey = $raw.LastKey }
        } catch {}
    }
    return $result
}

function Save-License {
    param($License)
    $obj = @{ History = $License.History; LastKey = $License.LastKey }
    try { $obj | ConvertTo-Json | Set-Content -Path $licenseFile -Force -ErrorAction Stop } catch {}
}

function Test-KeyStatus {
    param($Key, $License)
    # Returns @{ Valid=bool; DaysUsed=int; DaysAllowed=int; Reason=string }
    if (-not $validKeys.ContainsKey($Key)) {
        return @{ Valid = $false; DaysUsed = 0; DaysAllowed = 0; Reason = "Key not recognized." }
    }
    $daysAllowed = $validKeys[$Key]
    if (-not $License.History.ContainsKey($Key)) {
        $License.History[$Key] = (Get-Date).ToString("o")
    }
    $firstDate = [datetime]$License.History[$Key]
    $daysUsed = [Math]::Floor(((Get-Date) - $firstDate).TotalDays)
    if ($daysUsed -ge $daysAllowed) {
        return @{ Valid = $false; DaysUsed = $daysUsed; DaysAllowed = $daysAllowed; Reason = "Key expired ($daysUsed/$daysAllowed days used)." }
    }
    return @{ Valid = $true; DaysUsed = $daysUsed; DaysAllowed = $daysAllowed; Reason = "" }
}

$script:license = Load-License
$script:activationDaysUsed = 0
$script:activationDaysAllowed = 0
$script:activeLicenseKey = $null


# =====================================================================

function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Vexy Optimizer - Pre-optimization" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        return "Restore point created."
    } catch {
        return "Restore point skipped (Windows may limit one per 24h): $($_.Exception.Message)"
    }
}

function Set-PowerPlan {
    try {
        # Ultimate Performance plan GUID (built into Win10/11); falls back to High Performance
        $ultimate = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $existing = powercfg /list | Select-String $ultimate
        if (-not $existing) {
            powercfg -duplicatescheme $ultimate | Out-Null
        }
        powercfg /setactive $ultimate 2>$null
        if ($LASTEXITCODE -ne 0) {
            powercfg /setactive SCHEME_MIN   # High Performance
        }
        powercfg /change monitor-timeout-ac 0
        powercfg /change standby-timeout-ac 0
        # Disable USB selective suspend
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /setactive SCHEME_CURRENT
        return "Power plan set to Ultimate/High Performance; USB selective suspend disabled."
    } catch {
        return "Power plan: error - $($_.Exception.Message)"
    }
}

function Set-GraphicsTweaks {
    try {
        # Hardware-Accelerated GPU Scheduling
        New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Type DWord -Value 2 -Force

        # Game Mode on
        New-Item -Path "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Type DWord -Value 1 -Force

        # Disable Xbox Game Bar / Game DVR (background recording overhead)
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "ShowStartupPanel" -Type DWord -Value 0 -Force
        New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Type DWord -Value 0 -Force
        Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Type DWord -Value 2 -Force
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Type DWord -Value 0 -Force

        # Disable fullscreen optimizations globally (default layer key)
        New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Type DWord -Value 1 -Force

        # MMCSS priority boost for games
        $gamesKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        New-Item -Path $gamesKey -Force | Out-Null
        Set-ItemProperty -Path $gamesKey -Name "GPU Priority" -Type DWord -Value 8 -Force
        Set-ItemProperty -Path $gamesKey -Name "Priority" -Type DWord -Value 6 -Force
        Set-ItemProperty -Path $gamesKey -Name "Scheduling Category" -Type String -Value "High" -Force
        Set-ItemProperty -Path $gamesKey -Name "SFIO Priority" -Type String -Value "High" -Force

        return "GPU scheduling (HAGS), Game Mode, Game Bar/DVR, fullscreen opts, MMCSS boost applied. (HAGS needs a reboot.)"
    } catch {
        return "Graphics: error - $($_.Exception.Message)"
    }
}

function Set-InputTweaks {
    try {
        # Disable mouse acceleration / "enhance pointer precision"
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Force

        # Max keyboard repeat rate / min delay
        Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardSpeed" -Value "31" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Value "0" -Force

        # Disable USB power-saving (selective suspend) on HID/USB hubs
        $usbHubs = Get-WmiObject Win32_USBHub -ErrorAction SilentlyContinue
        Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | ForEach-Object {
            $dev = $_
            try {
                $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters"
                if (Test-Path $powerKey) {
                    Set-ItemProperty -Path $powerKey -Name "EnhancedPowerManagementEnabled" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue
                }
            } catch {}
        }

        return "Mouse acceleration disabled, keyboard repeat maxed, USB power-saving disabled on HID devices."
    } catch {
        return "Input: error - $($_.Exception.Message)"
    }
}

function Set-NetworkTweaks {
    try {
        # Disable Nagle's algorithm on all network interfaces
        $ifacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        Get-ChildItem $ifacesKey -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PsPath -Name "TcpAckFrequency" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PsPath -Name "TCPNoDelay" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
        }

        # Remove the 20% reserved bandwidth for QoS
        $qosKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
        New-Item -Path $qosKey -Force | Out-Null
        Set-ItemProperty -Path $qosKey -Name "NonBestEffortLimit" -Type DWord -Value 0 -Force

        return "Nagle's algorithm disabled; QoS bandwidth reservation removed."
    } catch {
        return "Network: error - $($_.Exception.Message)"
    }
}

function Set-VisualEffects {
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 2 -Force -ErrorAction SilentlyContinue
        New-Item -Path "HKCU:\Control Panel\Desktop" -Force | Out-Null
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue
        return "Visual effects switched to 'Best Performance'."
    } catch {
        return "Visual effects: error - $($_.Exception.Message)"
    }
}

function Set-BackgroundApps {
    try {
        # Stop UWP apps running in background
        Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.PsPath -Name "Disabled" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PsPath -Name "DisabledByUser" -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
        }

        # Set non-critical services to Manual (not disabled/deleted)
        $services = @("DiagTrack", "dmwappushservice", "SysMain", "WSearch")
        foreach ($svc in $services) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
                if ($s.Status -eq 'Running') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
            }
        }
        return "Background UWP apps stopped; telemetry/Superfetch/Search indexing set to Manual (not removed)."
    } catch {
        return "Background apps: error - $($_.Exception.Message)"
    }
}

function Set-CpuScheduling {
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Type DWord -Value 38 -Force
        $sysProfKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-ItemProperty -Path $sysProfKey -Name "SystemResponsiveness" -Type DWord -Value 0 -Force
        Set-ItemProperty -Path $sysProfKey -Name "NetworkThrottlingIndex" -Type DWord -Value 0xffffffff -Force
        return "CPU scheduling tuned for foreground app / game responsiveness."
    } catch {
        return "CPU scheduling: error - $($_.Exception.Message)"
    }
}

function Invoke-Cleanup {
    try {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Prefetch\*" -Force -ErrorAction SilentlyContinue
        return "Temp and prefetch junk cleared."
    } catch {
        return "Cleanup: error - $($_.Exception.Message)"
    }
}

function Set-ChromeMemoryLimits {
    try {
        $chromePolicyKey = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        New-Item -Path $chromePolicyKey -Force | Out-Null
        # Chrome's built-in Memory Saver mode: aggressively discards background tabs
        Set-ItemProperty -Path $chromePolicyKey -Name "HighEfficiencyModeEnabled" -Type DWord -Value 1 -Force
        # Cap Chrome's on-disk cache to ~250MB instead of growing unbounded
        Set-ItemProperty -Path $chromePolicyKey -Name "DiskCacheSize" -Type DWord -Value 262144000 -Force
        # Stop Chrome lingering in the background/system tray after you close all windows
        Set-ItemProperty -Path $chromePolicyKey -Name "BackgroundModeEnabled" -Type DWord -Value 0 -Force
        return "Chrome Memory Saver enabled, disk cache capped ~250MB, background mode off. (Restart Chrome to apply - these are official Chrome enterprise policies.)"
    } catch {
        return "Chrome tweaks: error - $($_.Exception.Message)"
    }
}

function Set-NetworkAdapterPower {
    try {
        $count = 0
        Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction SilentlyContinue
                $count++
            } catch {}
        }
        return "Disabled power-saving on $count network adapter(s) (prevents mid-session drops/lag)."
    } catch {
        return "Network adapter power: error - $($_.Exception.Message)"
    }
}

function Optimize-Disks {
    try {
        $results = @()
        Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
            try {
                Optimize-Volume -DriveLetter $_.DriveLetter -ReTrim -ErrorAction Stop
                $results += "$($_.DriveLetter):"
            } catch {}
        }
        if ($results.Count -eq 0) { return "No fixed drives were optimized." }
        return "TRIM/optimize run on: $($results -join ', ')"
    } catch {
        return "Disk optimize: error - $($_.Exception.Message)"
    }
}

function Set-FastDns {
    try {
        $count = 0
        Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
            try {
                Set-DnsClientServerAddress -InterfaceIndex $_.IfIndex -ServerAddresses ("1.1.1.1","1.0.0.1") -ErrorAction Stop
                $count++
            } catch {}
        }
        return "Set $count active adapter(s) to Cloudflare DNS (1.1.1.1/1.0.0.1). Revert anytime: Network Settings -> DNS -> Automatic (DHCP)."
    } catch {
        return "DNS: error - $($_.Exception.Message)"
    }
}

function Invoke-FreeRam {
    try {
        $before = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory
        $trimmed = 0
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ([VexyNative.MemTrim]::EmptyWorkingSet($_.Handle)) { $trimmed++ }
            } catch {}
        }
        Start-Sleep -Milliseconds 500
        $after = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory
        $freedMB = 0
        if ($before -and $after) { $freedMB = [Math]::Max(0, [Math]::Round(($after - $before) / 1024)) }
        return "Trimmed working set on $trimmed process(es). ~$freedMB MB freed (estimate - actual RAM use can bounce back as apps are used)."
    } catch {
        return "Free RAM: error - $($_.Exception.Message)"
    }
}

# =====================================================================
#  TWEAK REGISTRY -- maps checkbox names to functions
# =====================================================================
$tweakMap = [ordered]@{
    "ChkRestore"    = @{ Label = "System restore point";      Fn = { New-RestorePoint };     ImpactMin = 0; ImpactMax = 0 }
    "ChkPower"      = @{ Label = "Power plan";                Fn = { Set-PowerPlan };         ImpactMin = 2; ImpactMax = 5 }
    "ChkGraphics"   = @{ Label = "Graphics / GPU scheduling"; Fn = { Set-GraphicsTweaks };    ImpactMin = 3; ImpactMax = 8 }
    "ChkInput"      = @{ Label = "Input (mouse/keyboard)";    Fn = { Set-InputTweaks };       ImpactMin = 0; ImpactMax = 1 }
    "ChkNetwork"    = @{ Label = "Network latency";           Fn = { Set-NetworkTweaks };     ImpactMin = 0; ImpactMax = 1 }
    "ChkVisual"     = @{ Label = "Visual effects";            Fn = { Set-VisualEffects };     ImpactMin = 1; ImpactMax = 3 }
    "ChkBackground" = @{ Label = "Background apps/services";  Fn = { Set-BackgroundApps };    ImpactMin = 2; ImpactMax = 5 }
    "ChkCpu"        = @{ Label = "CPU scheduling";            Fn = { Set-CpuScheduling };     ImpactMin = 1; ImpactMax = 3 }
    "ChkCleanup"    = @{ Label = "Temp/prefetch cleanup";     Fn = { Invoke-Cleanup };        ImpactMin = 0; ImpactMax = 1 }
    "ChkChrome"     = @{ Label = "Chrome memory limiter";     Fn = { Set-ChromeMemoryLimits }; ImpactMin = 1; ImpactMax = 4 }
    "ChkNetPower"   = @{ Label = "Network adapter power";     Fn = { Set-NetworkAdapterPower }; ImpactMin = 0; ImpactMax = 1 }
    "ChkDisk"       = @{ Label = "Disk TRIM/optimize";        Fn = { Optimize-Disks };        ImpactMin = 0; ImpactMax = 2 }
    "ChkDns"        = @{ Label = "Fast DNS (Cloudflare)";     Fn = { Set-FastDns };           ImpactMin = 0; ImpactMax = 1 }
}
# NOTE: ImpactMin/Max are rough, indicative ranges based on commonly reported community
# benchmarks for these tweak categories. They are NOT measured on the user's own hardware
# and should not be read as a guaranteed or precise result.

# =====================================================================
#  MAIN DASHBOARD WINDOW XAML
# =====================================================================
[xml]$mainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Vexy" WindowState="Maximized" WindowStyle="None"
        Background="#050810" ResizeMode="NoResize" Opacity="0" ShowInTaskbar="True" Topmost="True">
    <Window.Triggers>
        <EventTrigger RoutedEvent="Window.Loaded">
            <BeginStoryboard>
                <Storyboard>
                    <DoubleAnimation Storyboard.TargetProperty="Opacity" From="0" To="1" Duration="0:0:0.5"/>
                </Storyboard>
            </BeginStoryboard>
        </EventTrigger>
    </Window.Triggers>
    <Window.Resources>
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#9FB3D9"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="Margin" Value="10,2"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#2A2438"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ActionCard" TargetType="Button">
            <Setter Property="Background" Value="#0E1730"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#4A3E66"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="16,14">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#9A5CFF"/>
                                <Setter TargetName="Bd" Property="Background" Value="#122040"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#D8E4FF"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Margin" Value="4,8"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Foreground" Value="#8FD0FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="Button" x:Key="PrimaryButton">
            <Setter Property="Background" Value="#5A3AA8"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="7">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="70"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- GLOBAL DRIFTING PARTICLE FIELD (behind everything) -->
        <Canvas x:Name="GlobalParticleCanvas" Grid.Row="0" Grid.RowSpan="2" IsHitTestVisible="False" ClipToBounds="True"/>

        <!-- TOP BAR -->
        <Border x:Name="TopBarBorder" Grid.Row="0" Background="#080C18" BorderBrush="#9A5CFF" BorderThickness="0,0,0,2">
            <Border.Effect>
                <DropShadowEffect x:Name="TopBarGlow" Color="#9A5CFF" BlurRadius="16" ShadowDepth="2" Direction="270" Opacity="0.8"/>
            </Border.Effect>
            <Grid Margin="20,0">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image x:Name="TopLogoImg" Height="30" Margin="0,0,10,0"/>
                    <TextBlock x:Name="TitleText" Text="VEXY" Foreground="White" FontWeight="Bold" FontSize="20" VerticalAlignment="Center" FontFamily="Segoe UI"
                               RenderTransformOrigin="0.5,0.5">
                        <TextBlock.RenderTransform>
                            <TransformGroup>
                                <SkewTransform x:Name="TitleSkew" AngleX="0" AngleY="0"/>
                                <TranslateTransform x:Name="TitleShift" X="0" Y="0"/>
                            </TransformGroup>
                        </TextBlock.RenderTransform>
                        <TextBlock.Effect>
                            <DropShadowEffect x:Name="TitleGlow" Color="#9A5CFF" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/>
                        </TextBlock.Effect>
                    </TextBlock>
                    <TextBlock Text="OPTIMIZATION TOOL" Foreground="#4C7AC9" FontSize="11" VerticalAlignment="Center" Margin="14,4,0,0" FontFamily="Consolas"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="BtnMinimize" Content="—" Width="34" Height="30" Background="Transparent" Foreground="#9FB3D9" BorderThickness="0" Margin="0,0,2,0"/>
                    <Button x:Name="BtnClose" Content="✕" Width="34" Height="30" Background="Transparent" Foreground="#9FB3D9" BorderThickness="0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- BODY -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="230"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- SIDEBAR -->
            <Border Grid.Column="0" Background="#080C18" BorderBrush="#2A2438" BorderThickness="0,0,1,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Margin="0,16,0,0">
                        <Button x:Name="NavDashboard" Style="{StaticResource NavButton}" Content="🏠  Dashboard" Background="#2A2438" Foreground="White" BorderBrush="#9A5CFF"/>
                        <Button x:Name="NavTweaks" Style="{StaticResource NavButton}" Content="🚀  Optimization"/>
                        <Button x:Name="NavGaming" Style="{StaticResource NavButton}" Content="🎮  Gaming"/>
                        <Button x:Name="NavNetwork" Style="{StaticResource NavButton}" Content="🌐  Network"/>
                        <Button x:Name="NavBrowser" Style="{StaticResource NavButton}" Content="🧭  Browser"/>
                        <Button x:Name="NavStartup" Style="{StaticResource NavButton}" Content="🧩  Startup Apps"/>
                        <Button x:Name="NavWindows" Style="{StaticResource NavButton}" Content="🪟  Windows"/>
                        <Button x:Name="NavServices" Style="{StaticResource NavButton}" Content="⚙️  Services"/>
                        <Button x:Name="NavCleanup" Style="{StaticResource NavButton}" Content="🗑️  Cleanup"/>
                        <Button x:Name="NavPowerPlan" Style="{StaticResource NavButton}" Content="⚡  Power Plan"/>
                        <Button x:Name="NavRestore" Style="{StaticResource NavButton}" Content="↺  Restore"/>
                    </StackPanel>
                    <StackPanel Grid.Row="1" Margin="16,0,16,18">
                        <StackPanel Orientation="Horizontal">
                            <Ellipse Width="8" Height="8" Fill="#33D17A" Margin="0,0,8,0"/>
                            <TextBlock Text="VEXY v1.0.0" Foreground="#9FB3D9" FontSize="11"/>
                        </StackPanel>
                        <TextBlock x:Name="LicenseStatusText" Text="Not activated" Foreground="#4C5C7A" FontSize="10" Margin="16,2,0,0"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- CONTENT AREA -->
            <Grid Grid.Column="1">
                <!-- DASHBOARD VIEW -->
                <ScrollViewer x:Name="DashboardView" VerticalScrollBarVisibility="Auto" Visibility="Visible">
                <Grid Margin="20">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="290"/>
                    </Grid.ColumnDefinitions>

                    <StackPanel Grid.Column="0" Margin="0,0,16,0">
                        <!-- HERO -->
                        <Border x:Name="HeroBorder" Background="#080C18" BorderBrush="#9A5CFF" BorderThickness="1.5" CornerRadius="12" Height="220" Margin="0,0,0,16">
                            <Border.Effect>
                                <DropShadowEffect x:Name="HeroGlow" Color="#9A5CFF" BlurRadius="30" ShadowDepth="0" Opacity="0.65"/>
                            </Border.Effect>
                            <Grid>
                                <Canvas x:Name="HeroStarCanvas" ClipToBounds="True" IsHitTestVisible="False"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="HeroLogoImg" Height="120" Stretch="Uniform"/>
                                    <TextBlock Text="OPTIMIZE   •   TWEAK   •   DOMINATE" Foreground="#9A8CB0" FontSize="13"
                                               FontFamily="Consolas" HorizontalAlignment="Center" Margin="0,14,0,0"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- STATUS + PERFORMANCE ROW -->
                        <Grid Margin="0,0,0,16">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="16"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <Border Grid.Column="0" Background="#080C18" BorderBrush="#2A2438" BorderThickness="1" CornerRadius="12" Padding="18">
                                <StackPanel>
                                    <TextBlock Text="SYSTEM STATUS" Foreground="#9A8CB0" FontSize="12" FontWeight="Bold" Margin="0,0,0,14"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="120"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid x:Name="RingGrid" Width="110" Height="110" HorizontalAlignment="Left">
                                            <Grid.Effect>
                                                <DropShadowEffect x:Name="RingGlow" Color="#9A5CFF" BlurRadius="20" ShadowDepth="0" Opacity="0.7"/>
                                            </Grid.Effect>
                                            <Ellipse Width="110" Height="110" Stroke="#1A2C4E" StrokeThickness="12"/>
                                            <Path x:Name="RingPath" Stroke="#9A5CFF" StrokeThickness="12" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                                            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                                                <TextBlock x:Name="RingPercentText" Text="0%" Foreground="White" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Optimized" Foreground="#7FA0D9" FontSize="10" HorizontalAlignment="Center"/>
                                            </StackPanel>
                                        </Grid>
                                        <StackPanel Grid.Column="1" Margin="14,0,0,0" x:Name="StatusListPanel" VerticalAlignment="Center">
                                        </StackPanel>
                                    </Grid>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="2" Background="#080C18" BorderBrush="#2A2438" BorderThickness="1" CornerRadius="12" Padding="18">
                                <StackPanel>
                                    <TextBlock Text="PERFORMANCE" Foreground="#9A8CB0" FontSize="12" FontWeight="Bold" Margin="0,0,0,14"/>
                                    <UniformGrid Columns="2" Rows="2">
                                        <Border Background="#0E1730" CornerRadius="8" Margin="0,0,8,8" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="CPU" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="CpuValueText" Text="--%" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <Polyline x:Name="CpuSpark" Stroke="#9A5CFF" StrokeThickness="1.5" Height="24"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#0E1730" CornerRadius="8" Margin="0,0,0,8" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="GPU" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="GpuValueText" Text="--%" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <Polyline x:Name="GpuSpark" Stroke="#9A5CFF" StrokeThickness="1.5" Height="24"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#0E1730" CornerRadius="8" Margin="0,0,8,0" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="RAM" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="RamValueText" Text="-- GB" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <ProgressBar x:Name="RamBar" Height="6" Minimum="0" Maximum="100" Value="0" Foreground="#9A5CFF" Background="#1A2C4E" BorderThickness="0" Margin="0,4,0,0"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#0E1730" CornerRadius="8" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="PING" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="PingValueText" Text="-- ms" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <Polyline x:Name="PingSpark" Stroke="#9A5CFF" StrokeThickness="1.5" Height="24"/>
                                            </StackPanel>
                                        </Border>
                                    </UniformGrid>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <!-- ACTIVITY + MEMORY + TEMP ROW -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="16"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="16"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <Border Grid.Column="0" Background="#080C18" BorderBrush="#2A2438" BorderThickness="1" CornerRadius="12" Padding="16" MinHeight="200">
                                <StackPanel>
                                    <TextBlock Text="RECENT ACTIVITY" Foreground="#9A8CB0" FontSize="12" FontWeight="Bold" Margin="0,0,0,10"/>
                                    <StackPanel x:Name="ActivityPanel"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="2" Background="#080C18" BorderBrush="#2A2438" BorderThickness="1" CornerRadius="12" Padding="16" MinHeight="200">
                                <StackPanel>
                                    <Grid>
                                        <TextBlock Text="MEMORY USAGE" Foreground="#9A8CB0" FontSize="12" FontWeight="Bold" HorizontalAlignment="Left"/>
                                        <TextBlock x:Name="MemUsageText" Text="-- / -- GB" Foreground="#9FB3D9" FontSize="11" HorizontalAlignment="Right"/>
                                    </Grid>
                                    <Canvas x:Name="MemGraphCanvas" Height="130" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="4" Background="#080C18" BorderBrush="#2A2438" BorderThickness="1" CornerRadius="12" Padding="16" MinHeight="200">
                                <StackPanel>
                                    <TextBlock Text="TEMPERATURES" Foreground="#9A8CB0" FontSize="12" FontWeight="Bold" Margin="0,0,0,10"/>
                                    <TextBlock x:Name="TempInfoText" Text="Checking sensors..." Foreground="#7FA0D9" FontSize="12" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                    </StackPanel>

                    <!-- QUICK ACTIONS -->
                    <StackPanel Grid.Column="1">
                        <TextBlock Text="QUICK ACTIONS" Foreground="#9A8CB0" FontSize="12" FontWeight="Bold" Margin="4,0,0,10"/>
                        <Button x:Name="QaOptimizeNow" Style="{StaticResource ActionCard}" BorderBrush="#9A5CFF">
                            <Button.Effect>
                                <DropShadowEffect x:Name="QaGlow" Color="#9A5CFF" BlurRadius="18" ShadowDepth="0" Opacity="0.6"/>
                            </Button.Effect>
                            <StackPanel>
                                <TextBlock Text="🚀  OPTIMIZE NOW" FontWeight="Bold" FontSize="14"/>
                                <TextBlock Text="Apply all recommended tweaks" Foreground="#9FB3D9" FontSize="11" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="QaGamingMode" Style="{StaticResource ActionCard}">
                            <StackPanel>
                                <TextBlock Text="🎮  GAMING MODE" FontWeight="Bold" FontSize="14"/>
                                <TextBlock Text="Boost FPS &amp; reduce input lag" Foreground="#9FB3D9" FontSize="11" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="QaCleanJunk" Style="{StaticResource ActionCard}">
                            <StackPanel>
                                <TextBlock Text="🗑️  CLEAN JUNK" FontWeight="Bold" FontSize="14"/>
                                <TextBlock Text="Remove temp &amp; cache files" Foreground="#9FB3D9" FontSize="11" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="QaFreeRam" Style="{StaticResource ActionCard}">
                            <StackPanel>
                                <TextBlock Text="🧠  FREE UP RAM" FontWeight="Bold" FontSize="14"/>
                                <TextBlock Text="Trim memory used by running apps" Foreground="#9FB3D9" FontSize="11" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="QaRestore" Style="{StaticResource ActionCard}">
                            <StackPanel>
                                <TextBlock Text="↺  RESTORE" FontWeight="Bold" FontSize="14"/>
                                <TextBlock Text="Undo changes" Foreground="#9FB3D9" FontSize="11" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Border Background="#0E1730" CornerRadius="10" Padding="14" Margin="0,10,0,0">
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnMusic" Content="🔊 Music" Width="110" Height="34" Background="#2A2438" Foreground="White" BorderThickness="0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Grid>
                </ScrollViewer>

                <!-- TWEAKS VIEW -->
                <ScrollViewer x:Name="TweaksView" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                <Grid Margin="30" MaxWidth="640" HorizontalAlignment="Center">
                    <StackPanel>
                        <TextBlock x:Name="TweaksTitleText" Text="OPTIMIZATION" Foreground="#9A8CB0" FontSize="20" FontWeight="Bold" Margin="0,0,0,4"/>
                        <TextBlock x:Name="TweaksDescText" Text="All available tweaks, grouped by category." Foreground="#7FA0D9" FontSize="12" Margin="0,0,0,18" TextWrapping="Wrap"/>
                        <CheckBox x:Name="ChkSelectAll" Content="Select All" FontWeight="Bold" Foreground="#7FB2FF" Margin="4,0,4,10"/>
                        <StackPanel x:Name="ChecklistPanel">
                            <CheckBox x:Name="ChkRestore" Content="Create system restore point (recommended first)"/>
                            <CheckBox x:Name="ChkPower" Content="Power plan -&gt; Ultimate/High Performance"/>
                            <CheckBox x:Name="ChkGraphics" Content="Graphics: HAGS, Game Mode, disable Game Bar/DVR, MMCSS boost"/>
                            <CheckBox x:Name="ChkInput" Content="Input: kill mouse accel, max keyboard rate, USB power-saving off"/>
                            <CheckBox x:Name="ChkNetwork" Content="Network: disable Nagle, remove QoS bandwidth reservation"/>
                            <CheckBox x:Name="ChkVisual" Content="Visual effects -&gt; Best Performance"/>
                            <CheckBox x:Name="ChkBackground" Content="Trim background UWP apps + telemetry/indexing services"/>
                            <CheckBox x:Name="ChkCpu" Content="CPU scheduling tuned for foreground/game responsiveness"/>
                            <CheckBox x:Name="ChkCleanup" Content="Clear temp/prefetch junk"/>
                            <CheckBox x:Name="ChkChrome" Content="Chrome: enable Memory Saver, cap disk cache, disable background mode"/>
                            <CheckBox x:Name="ChkNetPower" Content="Disable power-saving on network adapters"/>
                            <CheckBox x:Name="ChkDisk" Content="TRIM/optimize all fixed drives"/>
                            <CheckBox x:Name="ChkDns" Content="Switch to fast DNS (Cloudflare 1.1.1.1)"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,20,0,0">
                            <Button x:Name="BtnOptimize" Style="{StaticResource PrimaryButton}" Content="OPTIMIZE" Width="150" Height="42" Margin="0,0,10,0"/>
                            <Button x:Name="BtnRestore" Content="Open System Restore" Width="180" Height="42" Background="#2A2A3D" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>
                </ScrollViewer>

                <!-- STARTUP APPS MANAGER VIEW -->
                <ScrollViewer x:Name="StartupView" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                <Grid Margin="30" MaxWidth="720" HorizontalAlignment="Center">
                    <StackPanel>
                        <TextBlock Text="STARTUP APPS" Foreground="#9A8CB0" FontSize="20" FontWeight="Bold" Margin="0,0,0,4"/>
                        <TextBlock Text="Toggle off anything you don't need launching with Windows. Nothing is deleted - disabled entries can be re-enabled anytime." Foreground="#7FA0D9" FontSize="12" Margin="0,0,0,18" TextWrapping="Wrap"/>
                        <Button x:Name="BtnRefreshStartup" Content="Refresh List" Width="140" Height="34" Background="#2A2A3D" Foreground="White" BorderThickness="0" HorizontalAlignment="Left" Margin="0,0,0,14"/>
                        <StackPanel x:Name="StartupListPanel"/>
                    </StackPanel>
                </Grid>
                </ScrollViewer>
            </Grid>
        </Grid>

        <!-- SCANLINE SWEEP OVERLAY (purely visual, click-through) -->
        <Rectangle Grid.Row="0" Grid.RowSpan="2" Height="3" VerticalAlignment="Top" IsHitTestVisible="False" Opacity="0.5">
            <Rectangle.Fill>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                    <GradientStop Color="#0000FFFF" Offset="0"/>
                    <GradientStop Color="#803E9CFF" Offset="0.5"/>
                    <GradientStop Color="#0000FFFF" Offset="1"/>
                </LinearGradientBrush>
            </Rectangle.Fill>
            <Rectangle.RenderTransform>
                <TranslateTransform x:Name="ScanlineY" Y="0"/>
            </Rectangle.RenderTransform>
        </Rectangle>
    </Grid>
</Window>
"@

# =====================================================================
#  SPLASH WINDOW XAML (shown while tweaks apply)
# =====================================================================
[xml]$splashXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optimizing..." Height="360" Width="520"
        WindowStartupLocation="CenterScreen"
        Background="#0A0A14" WindowStyle="None" Topmost="True"
        ResizeMode="NoResize" AllowsTransparency="False">
    <Border BorderBrush="#5A3AA8" BorderThickness="2">
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="120"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Image x:Name="SplashLogo" Grid.Row="0" Stretch="Uniform" HorizontalAlignment="Center"/>
            <TextBlock x:Name="SplashStatus" Grid.Row="1" Text="Starting..." Foreground="#7FB2FF"
                       FontFamily="Consolas" FontSize="13" HorizontalAlignment="Center" Margin="0,12,0,8"/>
            <TextBox x:Name="SplashLog" Grid.Row="2" Background="#12121E" Foreground="#B9C6E6"
                     BorderThickness="0" FontFamily="Consolas" FontSize="11" IsReadOnly="True"
                     TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
        </Grid>
    </Border>
</Window>
"@

# =====================================================================
#  FULLSCREEN LOADING SCREEN XAML (starfield + logo + status)
# =====================================================================
[xml]$loadingXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Vexy" WindowState="Maximized" WindowStyle="None"
        Background="#05050B" Topmost="True" ShowInTaskbar="False">
    <Grid>
        <Canvas x:Name="StarCanvas"/>
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
            <Image x:Name="LoadLogo" Width="420" Stretch="Uniform" HorizontalAlignment="Center"/>
            <TextBlock x:Name="LoadStatus" Text="Preparing environment"
                       Foreground="#D4D4D4" FontFamily="Segoe UI Light" FontSize="16"
                       HorizontalAlignment="Center" Margin="0,26,0,0"/>
            <TextBlock Text="vexy optimizer" Foreground="#6E6E6E" FontFamily="Segoe UI"
                       FontSize="12" HorizontalAlignment="Center" Margin="0,60,0,0"/>
        </StackPanel>
    </Grid>
</Window>
"@

# =====================================================================
#  KEY ACTIVATION SCREEN XAML (shown before the loading screen if needed)
# =====================================================================
[xml]$keyXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Vexy - Activation" WindowState="Maximized" WindowStyle="None"
        Background="#05050B" Topmost="True" ShowInTaskbar="False">
    <Grid>
        <Canvas x:Name="KeyStarCanvas"/>
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center" Width="420">
            <Image x:Name="KeyLogoImg" Height="90" Stretch="Uniform" HorizontalAlignment="Center" Margin="0,0,0,30"/>
            <TextBlock Text="ENTER ACTIVATION KEY" Foreground="#D4D4D4" FontFamily="Segoe UI" FontSize="14"
                       FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,16"/>
            <Border Background="#1A1A1A" BorderBrush="#6E6E6E" BorderThickness="1.5" CornerRadius="8">
                <TextBox x:Name="KeyInputBox" Background="Transparent" Foreground="White" BorderThickness="0"
                         FontFamily="Consolas" FontSize="16" Padding="14,12" HorizontalContentAlignment="Center"
                         CharacterCasing="Upper"/>
            </Border>
            <Button x:Name="KeyActivateBtn" Content="ACTIVATE" Width="200" Height="42" Margin="0,18,0,0"
                    Background="#4A4A4A" Foreground="White" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
            <TextBlock x:Name="KeyErrorText" Text="" Foreground="#FF6B6B" FontSize="12"
                       HorizontalAlignment="Center" Margin="0,16,0,0" TextWrapping="Wrap" TextAlignment="Center"/>
        </StackPanel>
    </Grid>
</Window>
"@

# ---------- Load windows ----------
$reader = New-Object System.Xml.XmlNodeReader $mainXaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$reader2 = New-Object System.Xml.XmlNodeReader $splashXaml
$splash = [Windows.Markup.XamlReader]::Load($reader2)

$reader3 = New-Object System.Xml.XmlNodeReader $loadingXaml
$loading = [Windows.Markup.XamlReader]::Load($reader3)

$reader4 = New-Object System.Xml.XmlNodeReader $keyXaml
$keyWindow = [Windows.Markup.XamlReader]::Load($reader4)

# ---------- Wire up controls ----------
$topLogoImg   = $window.FindName("TopLogoImg")
$licenseStatusText = $window.FindName("LicenseStatusText")
$heroLogoImg  = $window.FindName("HeroLogoImg")
$btnMinimize  = $window.FindName("BtnMinimize")
$btnClose     = $window.FindName("BtnClose")
$btnMusic     = $window.FindName("BtnMusic")

$navDashboard = $window.FindName("NavDashboard")
$navTweaks    = $window.FindName("NavTweaks")
$navGaming    = $window.FindName("NavGaming")
$navNetwork   = $window.FindName("NavNetwork")
$navWindows   = $window.FindName("NavWindows")
$navServices  = $window.FindName("NavServices")
$navCleanup   = $window.FindName("NavCleanup")
$navPowerPlan = $window.FindName("NavPowerPlan")
$navRestore   = $window.FindName("NavRestore")
$navBrowser   = $window.FindName("NavBrowser")
$navStartup   = $window.FindName("NavStartup")
$startupView  = $window.FindName("StartupView")
$startupListPanel = $window.FindName("StartupListPanel")
$btnRefreshStartup = $window.FindName("BtnRefreshStartup")
$qaFreeRam    = $window.FindName("QaFreeRam")

$dashboardView = $window.FindName("DashboardView")
$tweaksView    = $window.FindName("TweaksView")
$tweaksTitleText = $window.FindName("TweaksTitleText")
$tweaksDescText  = $window.FindName("TweaksDescText")

$ringPath        = $window.FindName("RingPath")
$ringPercentText = $window.FindName("RingPercentText")
$statusListPanel = $window.FindName("StatusListPanel")

$cpuValueText = $window.FindName("CpuValueText")
$gpuValueText = $window.FindName("GpuValueText")
$ramValueText = $window.FindName("RamValueText")
$pingValueText= $window.FindName("PingValueText")
$cpuSpark = $window.FindName("CpuSpark")
$gpuSpark = $window.FindName("GpuSpark")
$pingSpark= $window.FindName("PingSpark")
$ramBar   = $window.FindName("RamBar")

$activityPanel  = $window.FindName("ActivityPanel")
$memGraphCanvas = $window.FindName("MemGraphCanvas")
$memUsageText   = $window.FindName("MemUsageText")
$tempInfoText   = $window.FindName("TempInfoText")
$heroStarCanvas = $window.FindName("HeroStarCanvas")

$qaOptimizeNow = $window.FindName("QaOptimizeNow")
$qaGamingMode  = $window.FindName("QaGamingMode")
$qaCleanJunk   = $window.FindName("QaCleanJunk")
$qaRestore     = $window.FindName("QaRestore")

$globalParticleCanvas = $window.FindName("GlobalParticleCanvas")
$titleText   = $window.FindName("TitleText")
$titleGlow   = $window.FindName("TitleGlow")
$titleSkew   = $window.FindName("TitleSkew")
$titleShift  = $window.FindName("TitleShift")
$topBarGlow  = $window.FindName("TopBarGlow")
$topBarBorder= $window.FindName("TopBarBorder")
$heroGlow    = $window.FindName("HeroGlow")
$heroBorder  = $window.FindName("HeroBorder")
$ringGlow    = $window.FindName("RingGlow")
$qaGlow      = $window.FindName("QaGlow")
$scanlineY   = $window.FindName("ScanlineY")

$chkAll     = $window.FindName("ChkSelectAll")
$btnOpt     = $window.FindName("BtnOptimize")
$btnRestore = $window.FindName("BtnRestore")

$splashLogo   = $splash.FindName("SplashLogo")
$splashStatus = $splash.FindName("SplashStatus")
$splashLog    = $splash.FindName("SplashLog")

$loadLogo   = $loading.FindName("LoadLogo")
$loadStatus = $loading.FindName("LoadStatus")
$starCanvas = $loading.FindName("StarCanvas")

$keyStarCanvas  = $keyWindow.FindName("KeyStarCanvas")
$keyLogoImg     = $keyWindow.FindName("KeyLogoImg")
$keyInputBox    = $keyWindow.FindName("KeyInputBox")
$keyActivateBtn = $keyWindow.FindName("KeyActivateBtn")
$keyErrorText   = $keyWindow.FindName("KeyErrorText")

if ($logoPath -and (Test-Path $logoPath)) {
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.UriSource = New-Object System.Uri($logoPath, [System.UriKind]::Absolute)
    $bmp.EndInit()
    $topLogoImg.Source = $bmp
    $heroLogoImg.Source = $bmp
    $splashLogo.Source = $bmp
    $loadLogo.Source = $bmp
    $keyLogoImg.Source = $bmp
}

# ---------- Window controls ----------
$script:vexyExiting = $false
$btnClose.Add_Click({
    $script:vexyExiting = $true
    $window.Topmost = $false
    $window.Close()
})

# ---------- Keep focus: snap back if the user tries to switch away, unless exiting via the X button ----------
$window.Add_Deactivated({
    if (-not $script:vexyExiting) {
        $window.Dispatcher.BeginInvoke([action]{
            if (-not $script:vexyExiting -and $window.IsVisible) {
                $window.Topmost = $true
                $window.Activate()
            }
        }) | Out-Null
    }
})
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

# ---------- View switching (sidebar nav) ----------
$allNavButtons = @($navDashboard, $navTweaks, $navGaming, $navNetwork, $navWindows, $navServices, $navPowerPlan, $navBrowser, $navStartup)

function Set-ActiveNav {
    param($ActiveButton)
    foreach ($b in $allNavButtons) {
        if ($b) {
            $b.Background = [System.Windows.Media.Brushes]::Transparent
            $b.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#9FB3D9")
            $b.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        }
    }
    if ($ActiveButton) {
        $ActiveButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2A2438")
        $ActiveButton.Foreground = [System.Windows.Media.Brushes]::White
        $ActiveButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#9A5CFF")
    }
}

function Show-Dashboard {
    $dashboardView.Visibility = [System.Windows.Visibility]::Visible
    $tweaksView.Visibility = [System.Windows.Visibility]::Collapsed
    $startupView.Visibility = [System.Windows.Visibility]::Collapsed
    Set-ActiveNav -ActiveButton $navDashboard
}

function Show-Tweaks {
    param($OnlyKeys = $null, $Title = "OPTIMIZATION", $Desc = "All available tweaks, grouped by category.")
    $dashboardView.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksView.Visibility = [System.Windows.Visibility]::Visible
    $startupView.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksTitleText.Text = $Title
    $tweaksDescText.Text = $Desc

    foreach ($key in $tweakMap.Keys) {
        $cb = $window.FindName($key)
        if (-not $cb) { continue }
        if ($OnlyKeys) {
            $isRelevant = $OnlyKeys -contains $key
            $cb.Visibility = if ($isRelevant) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
            $cb.IsChecked = $isRelevant
        } else {
            $cb.Visibility = [System.Windows.Visibility]::Visible
        }
    }
    $chkAll.Visibility = if ($OnlyKeys) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
}

function Show-Startup {
    $dashboardView.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksView.Visibility = [System.Windows.Visibility]::Collapsed
    $startupView.Visibility = [System.Windows.Visibility]::Visible
    Set-ActiveNav -ActiveButton $navStartup
    Refresh-StartupList
}

$navDashboard.Add_Click({ Show-Dashboard })
$navTweaks.Add_Click({
    Show-Tweaks -Title "OPTIMIZATION" -Desc "All available tweaks, grouped by category. Tick what you want and hit Optimize."
    Set-ActiveNav -ActiveButton $navTweaks
})
$navGaming.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkGraphics","ChkInput") -Title "GAMING" -Desc "GPU scheduling, Game Mode, Game Bar/DVR, mouse & keyboard latency tweaks."
    Set-ActiveNav -ActiveButton $navGaming
})
$navNetwork.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkNetwork","ChkNetPower","ChkDns") -Title "NETWORK" -Desc "Nagle's algorithm, QoS bandwidth cap, adapter power-saving, and fast DNS."
    Set-ActiveNav -ActiveButton $navNetwork
})
$navBrowser.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkChrome") -Title "BROWSER" -Desc "Limit Chrome's RAM usage via its own official Memory Saver and cache policies."
    Set-ActiveNav -ActiveButton $navBrowser
})
$navWindows.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkVisual","ChkBackground") -Title "WINDOWS" -Desc "Trim visual effects and background UWP apps for a leaner desktop."
    Set-ActiveNav -ActiveButton $navWindows
})
$navServices.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkBackground","ChkCpu") -Title "SERVICES" -Desc "Set non-critical background services to Manual and tune CPU scheduling."
    Set-ActiveNav -ActiveButton $navServices
})
$navPowerPlan.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkPower") -Title "POWER PLAN" -Desc "Switch to Ultimate/High Performance and disable USB selective suspend."
    Set-ActiveNav -ActiveButton $navPowerPlan
})
$navCleanup.Add_Click({
    Add-ActivityLine -Text (Invoke-Cleanup)
    Add-ActivityLine -Text (Optimize-Disks)
})
$navRestore.Add_Click({ Start-Process "rstrui.exe" })
$navStartup.Add_Click({ Show-Startup })

$btnRestore.Add_Click({ Start-Process "rstrui.exe" })
$qaRestore.Add_Click({ Start-Process "rstrui.exe" })
$qaCleanJunk.Add_Click({ Add-ActivityLine -Text (Invoke-Cleanup) })
$qaFreeRam.Add_Click({ Add-ActivityLine -Text (Invoke-FreeRam) })
$btnRefreshStartup.Add_Click({ Refresh-StartupList })
$qaGamingMode.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkGraphics","ChkInput") -Title "GAMING" -Desc "GPU scheduling, Game Mode, Game Bar/DVR, mouse & keyboard latency tweaks."
    Set-ActiveNav -ActiveButton $navGaming
    Run-SelectedTweaks
})
$qaOptimizeNow.Add_Click({
    Show-Tweaks -Title "OPTIMIZATION" -Desc "All available tweaks, grouped by category. Tick what you want and hit Optimize."
    foreach ($key in $tweakMap.Keys) { $cb = $window.FindName($key); if ($cb) { $cb.IsChecked = $true } }
    Set-ActiveNav -ActiveButton $navTweaks
    Run-SelectedTweaks
})

$chkAll.Add_Click({
    foreach ($key in $tweakMap.Keys) {
        $cb = $window.FindName($key)
        if ($cb) { $cb.IsChecked = $chkAll.IsChecked }
    }
})

# ---------- Background music: loop + mute toggle ----------
$mediaPlayer = New-Object System.Windows.Media.MediaPlayer
$script:musicMuted = $false
$script:musicAvailable = $false

if ($musicPath -and (Test-Path $musicPath)) {
    try {
        $mediaPlayer.Open((New-Object System.Uri($musicPath, [System.UriKind]::Absolute)))
        $mediaPlayer.Volume = 0.4
        $script:musicAvailable = $true
        $mediaPlayer.Add_MediaEnded({
            $mediaPlayer.Position = [TimeSpan]::Zero
            $mediaPlayer.Play()
        })
    } catch { $script:musicAvailable = $false }
} else {
    $btnMusic.IsEnabled = $false
    $btnMusic.Content = "No Music"
}

$btnMusic.Add_Click({
    if (-not $script:musicAvailable) { return }
    if ($script:musicMuted) {
        $mediaPlayer.Volume = 0.4
        $btnMusic.Content = "🔊 Music"
        $script:musicMuted = $false
    } else {
        $mediaPlayer.Volume = 0
        $btnMusic.Content = "🔇 Muted"
        $script:musicMuted = $true
    }
})

# ---------- Twinkling starfield in the hero banner ----------
function Add-Starfield {
    param($Canvas, $Count, $AreaW, $AreaH)
    $rand = New-Object System.Random
    for ($i = 0; $i -lt $Count; $i++) {
        $size = $rand.Next(1, 3) + ($rand.NextDouble())
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size
        $dot.Height = $size
        $dot.Fill = [System.Windows.Media.Brushes]::White
        $baseOpacity = 0.15 + ($rand.NextDouble() * 0.5)
        $dot.Opacity = $baseOpacity
        [System.Windows.Controls.Canvas]::SetLeft($dot, $rand.NextDouble() * $AreaW)
        [System.Windows.Controls.Canvas]::SetTop($dot, $rand.NextDouble() * $AreaH)
        $Canvas.Children.Add($dot) | Out-Null

        $twinkle = New-Object System.Windows.Media.Animation.DoubleAnimation
        $twinkle.From = [Math]::Max(0.05, $baseOpacity - 0.25)
        $twinkle.To = [Math]::Min(1.0, $baseOpacity + 0.35)
        $twinkle.Duration = [TimeSpan]::FromSeconds(2 + $rand.NextDouble() * 3)
        $twinkle.AutoReverse = $true
        $twinkle.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $twinkle.BeginTime = [TimeSpan]::FromMilliseconds($rand.Next(0, 3000))
        $dot.BeginAnimation([System.Windows.Shapes.Ellipse]::OpacityProperty, $twinkle)
    }
}
if ($heroStarCanvas) { Add-Starfield -Canvas $heroStarCanvas -Count 60 -AreaW 1400 -AreaH 220 }

# ---------- Ring progress (System Status) ----------
function Set-RingPercent {
    param($Percent)
    $Percent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $ringPercentText.Text = "$([Math]::Round($Percent))%"
    $cx = 55; $cy = 55; $r = 49
    if ($Percent -le 0.5) {
        $ringPath.Data = $null
        return
    }
    if ($Percent -ge 99.5) {
        # Full circle can't be a single arc; draw two half-arcs
        $data = "M $cx,$($cy - $r) A $r,$r 0 1 1 $($cx - 0.01),$($cy - $r) Z"
        $ringPath.Data = [System.Windows.Media.Geometry]::Parse($data)
        return
    }
    $startAngle = -90
    $endAngle = $startAngle + (360 * ($Percent / 100))
    $startRad = $startAngle * [Math]::PI / 180
    $endRad = $endAngle * [Math]::PI / 180
    $sx = $cx + $r * [Math]::Cos($startRad)
    $sy = $cy + $r * [Math]::Sin($startRad)
    $ex = $cx + $r * [Math]::Cos($endRad)
    $ey = $cy + $r * [Math]::Sin($endRad)
    $largeArc = if ($Percent -gt 50) { 1 } else { 0 }
    $data = "M $sx,$sy A $r,$r 0 $largeArc 1 $ex,$ey"
    $ringPath.Data = [System.Windows.Media.Geometry]::Parse($data)
}
Set-RingPercent -Percent 0

# ---------- Status list (mirrors tweak categories, updates as they're applied) ----------
$script:statusRows = @{}
function Build-StatusList {
    $statusListPanel.Children.Clear()
    $script:statusRows.Clear()
    $displayNames = [ordered]@{
        "ChkRestore"    = "System Tweaks"
        "ChkPower"      = "Power Plan"
        "ChkGraphics"   = "Graphics"
        "ChkInput"      = "Input"
        "ChkNetwork"    = "Network Tweaks"
        "ChkVisual"     = "Visual Effects"
        "ChkBackground" = "Background Apps"
        "ChkCpu"        = "CPU Scheduling"
        "ChkCleanup"    = "Cleanup"
        "ChkChrome"     = "Chrome Memory"
        "ChkNetPower"   = "Adapter Power"
        "ChkDisk"       = "Disk Optimize"
        "ChkDns"        = "Fast DNS"
    }
    foreach ($key in $displayNames.Keys) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = "0,4"
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = "*"
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = "Auto"
        $row.ColumnDefinitions.Add($col1)
        $row.ColumnDefinitions.Add($col2)

        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = $displayNames[$key]
        $label.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#B9C6E6")
        $label.FontSize = 12
        [System.Windows.Controls.Grid]::SetColumn($label, 0)
        $row.Children.Add($label) | Out-Null

        $status = New-Object System.Windows.Controls.TextBlock
        $status.Text = "Not applied"
        $status.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#5C6A8A")
        $status.FontSize = 11
        $status.HorizontalAlignment = "Right"
        [System.Windows.Controls.Grid]::SetColumn($status, 1)
        $row.Children.Add($status) | Out-Null

        $statusListPanel.Children.Add($row) | Out-Null
        $script:statusRows[$key] = $status
    }
}
Build-StatusList

function Update-RingFromApplied {
    $appliedCount = ($script:statusRows.Values | Where-Object { $_.Text -eq "Applied" }).Count
    $total = $script:statusRows.Count
    $pct = if ($total -gt 0) { ($appliedCount / $total) * 100 } else { 0 }
    Set-RingPercent -Percent $pct
}

# ---------- Recent activity feed ----------
function Add-ActivityLine {
    param($Text)
    $line = New-Object System.Windows.Controls.TextBlock
    $line.Text = "$(Get-Date -Format 'HH:mm')   $Text"
    $line.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#B9C6E6")
    $line.FontSize = 11
    $line.Margin = "0,0,0,8"
    $line.TextWrapping = "Wrap"
    $activityPanel.Children.Insert(0, $line)
    while ($activityPanel.Children.Count -gt 6) {
        $activityPanel.Children.RemoveAt($activityPanel.Children.Count - 1)
    }
}

# =====================================================================
#  STARTUP APPS MANAGER -- enumerate Run-key entries, toggle on/off
#  Disabling moves the value to a backup key (never deletes), so it's
#  always fully reversible.
# =====================================================================
$script:startupBackupPath = "HKCU:\Software\VexyOptimizer\DisabledStartup"

function Get-StartupEntries {
    $entries = New-Object System.Collections.Generic.List[object]
    $locations = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($path in $locations) {
        if (Test-Path $path) {
            $item = Get-Item $path -ErrorAction SilentlyContinue
            foreach ($name in $item.Property) {
                try {
                    $cmd = (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name
                    $entries.Add([PSCustomObject]@{ Name = $name; Command = $cmd; RegPath = $path; Enabled = $true })
                } catch {}
            }
        }
    }
    if (Test-Path $script:startupBackupPath) {
        $item = Get-Item $script:startupBackupPath -ErrorAction SilentlyContinue
        foreach ($name in $item.Property) {
            try {
                $cmd = (Get-ItemProperty -Path $script:startupBackupPath -Name $name -ErrorAction Stop).$name
                $entries.Add([PSCustomObject]@{ Name = $name; Command = $cmd; RegPath = $script:startupBackupPath; Enabled = $false })
            } catch {}
        }
    }
    return $entries
}

function Disable-StartupEntry {
    param($Name, $SourcePath)
    try {
        $val = (Get-ItemProperty -Path $SourcePath -Name $Name -ErrorAction Stop).$Name
        if (-not (Test-Path $script:startupBackupPath)) { New-Item -Path $script:startupBackupPath -Force | Out-Null }
        Set-ItemProperty -Path $script:startupBackupPath -Name $Name -Value $val -Force
        Remove-ItemProperty -Path $SourcePath -Name $Name -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Enable-StartupEntry {
    param($Name)
    try {
        $val = (Get-ItemProperty -Path $script:startupBackupPath -Name $Name -ErrorAction Stop).$Name
        $targetPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (-not (Test-Path $targetPath)) { New-Item -Path $targetPath -Force | Out-Null }
        Set-ItemProperty -Path $targetPath -Name $Name -Value $val -Force
        Remove-ItemProperty -Path $script:startupBackupPath -Name $Name -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

function Refresh-StartupList {
    $startupListPanel.Children.Clear()
    $entries = Get-StartupEntries
    if ($entries.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = "No startup entries found."
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#7FA0D9")
        $startupListPanel.Children.Add($empty) | Out-Null
        return
    }
    foreach ($entry in $entries) {
        $row = New-Object System.Windows.Controls.Border
        $row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#080C18")
        $row.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#2A2438")
        $row.BorderThickness = "1"
        $row.CornerRadius = "8"
        $row.Padding = "14,10"
        $row.Margin = "0,0,0,8"

        $grid = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = "*"
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = "Auto"
        $grid.ColumnDefinitions.Add($col1)
        $grid.ColumnDefinitions.Add($col2)

        $textPanel = New-Object System.Windows.Controls.StackPanel
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $entry.Name
        $nameText.Foreground = [System.Windows.Media.Brushes]::White
        $nameText.FontSize = 13
        $nameText.FontWeight = "Bold"
        $cmdText = New-Object System.Windows.Controls.TextBlock
        $cmdShort = $entry.Command
        if ($cmdShort.Length -gt 80) { $cmdShort = $cmdShort.Substring(0, 80) + "..." }
        $cmdText.Text = $cmdShort
        $cmdText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#7FA0D9")
        $cmdText.FontSize = 10
        $cmdText.FontFamily = "Consolas"
        $cmdText.Margin = "0,3,0,0"
        $cmdText.TextWrapping = "Wrap"
        $textPanel.Children.Add($nameText) | Out-Null
        $textPanel.Children.Add($cmdText) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($textPanel, 0)
        $grid.Children.Add($textPanel) | Out-Null

        $toggle = New-Object System.Windows.Controls.CheckBox
        $toggle.IsChecked = $entry.Enabled
        $toggle.Content = "Enabled"
        $toggle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#9FB3D9")
        $toggle.VerticalAlignment = "Center"
        $toggle.Tag = $entry
        $toggle.Add_Click({
            param($s, $e)
            $tagEntry = $s.Tag
            if ($s.IsChecked -eq $true) {
                Enable-StartupEntry -Name $tagEntry.Name | Out-Null
                Add-ActivityLine -Text "Enabled startup item: $($tagEntry.Name)"
            } else {
                Disable-StartupEntry -Name $tagEntry.Name -SourcePath $tagEntry.RegPath | Out-Null
                Add-ActivityLine -Text "Disabled startup item: $($tagEntry.Name)"
            }
            Refresh-StartupList
        })
        [System.Windows.Controls.Grid]::SetColumn($toggle, 1)
        $grid.Children.Add($toggle) | Out-Null

        $row.Child = $grid
        $startupListPanel.Children.Add($row) | Out-Null
    }
}

# ---------- Run selected tweaks (shared by Optimize button + Quick Actions) ----------
function Run-SelectedTweaks {
    $selected = @()
    foreach ($key in $tweakMap.Keys) {
        $cb = $window.FindName($key)
        if ($cb -and $cb.IsChecked -eq $true) { $selected += $key }
    }
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Select at least one option first.", "Vexy Optimizer") | Out-Null
        return
    }

    $splashLog.Text = ""
    $splash.Owner = $window
    $splash.Show()
    Pump-UI

    $done = 0
    $impactMinTotal = 0
    $impactMaxTotal = 0
    foreach ($key in $selected) {
        $entry = $tweakMap[$key]
        $splashStatus.Text = "Applying: $($entry.Label)..."
        Pump-UI
        $result = & $entry.Fn
        $done++
        $impactMinTotal += $entry.ImpactMin
        $impactMaxTotal += $entry.ImpactMax
        $splashLog.Text += "[$done/$($selected.Count)] $($entry.Label): $result`r`n"
        $splashLog.ScrollToEnd()
        if ($script:statusRows.ContainsKey($key)) {
            $script:statusRows[$key].Text = "Applied"
            $script:statusRows[$key].Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#33D17A")
        }
        Add-ActivityLine -Text $entry.Label
        Update-RingFromApplied
        Pump-UI
        Start-Sleep -Milliseconds 200
    }
    $splashStatus.Text = "Done. You may need to reboot for all changes to apply."
    $splashLog.Text += "`r`n--------------------------------------------------`r`n"
    $splashLog.Text += "Estimated potential FPS/responsiveness uplift: ~$impactMinTotal-$impactMaxTotal%`r`n"
    $splashLog.Text += "(Indicative only, based on typical community-reported ranges for these`r`n tweaks - not measured on your specific hardware/games.)`r`n"
    $splashLog.ScrollToEnd()
    Pump-UI
    Start-Sleep -Seconds 3
    $splash.Close()

    [System.Windows.MessageBox]::Show("Optimization complete ($done applied).`n`nEstimated potential uplift: ~$impactMinTotal-$impactMaxTotal% (indicative only, actual results vary by hardware and game).`n`nReboot recommended for GPU scheduling changes to take effect.", "Vexy Optimizer") | Out-Null
}

$btnOpt.Add_Click({ Run-SelectedTweaks })

function Pump-UI {
    $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}

# ---------- Live HUD stats: CPU / GPU / RAM / PING + memory graph + temps ----------
$script:cpuCounter = $null
try {
    $script:cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
    $script:cpuCounter.NextValue() | Out-Null
} catch { $script:cpuCounter = $null }

$script:gpuCounters = $null
try {
    $script:gpuCounters = (Get-Counter -ListSet "GPU Engine" -ErrorAction Stop).PathsWithInstances | Where-Object { $_ -match "engtype_3D" }
} catch { $script:gpuCounters = $null }

$script:memHistory = New-Object System.Collections.Generic.List[double]
$script:cpuHistory = New-Object System.Collections.Generic.List[double]
$script:gpuHistory = New-Object System.Collections.Generic.List[double]
$script:pingHistory = New-Object System.Collections.Generic.List[double]
$script:pingCounter = 0
$script:pingInFlight = $false
$script:gpuTickCounter = 0
$script:gpuInFlight = $false
$script:tempsChecked = $false

function Update-Sparkline {
    param($Polyline, $History, $Width, $Height, $MaxVal)
    if ($History.Count -lt 2) { return }
    $pts = New-Object System.Windows.Media.PointCollection
    $n = $History.Count
    for ($i = 0; $i -lt $n; $i++) {
        $x = ($i / [Math]::Max(1, $n - 1)) * $Width
        $v = [Math]::Min($MaxVal, $History[$i])
        $y = $Height - (($v / $MaxVal) * $Height)
        $pts.Add((New-Object System.Windows.Point($x, $y)))
    }
    $Polyline.Points = $pts
}

$script:memGraphPoly = $null
function Update-MemGraph {
    if ($script:memHistory.Count -lt 2) { return }
    if (-not $script:memGraphPoly) {
        $script:memGraphPoly = New-Object System.Windows.Shapes.Polyline
        $script:memGraphPoly.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#9A5CFF")
        $script:memGraphPoly.StrokeThickness = 2
        $memGraphCanvas.Children.Add($script:memGraphPoly) | Out-Null
    }
    $w = $memGraphCanvas.ActualWidth; if ($w -le 0) { $w = 400 }
    $h = $memGraphCanvas.ActualHeight; if ($h -le 0) { $h = 130 }
    $n = $script:memHistory.Count
    $maxV = 100
    $pts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $n; $i++) {
        $x = ($i / [Math]::Max(1, $n - 1)) * $w
        $y = $h - (($script:memHistory[$i] / $maxV) * $h)
        $pts.Add((New-Object System.Windows.Point($x, $y)))
    }
    $script:memGraphPoly.Points = $pts
}

function Check-Temps {
    try {
        $zones = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        if ($zones) {
            $lines = @()
            $i = 1
            foreach ($z in $zones) {
                $celsius = [Math]::Round(($z.CurrentTemperature / 10) - 273.15, 1)
                $lines += "Zone $i`: $celsius`°C"
                $i++
            }
            $tempInfoText.Text = ($lines -join "`n") + "`n`n(ACPI thermal zones - not guaranteed to map to specific components)"
        } else {
            $tempInfoText.Text = "No temperature sensors exposed by this system's ACPI tables."
        }
    } catch {
        $tempInfoText.Text = "Temp sensors unavailable via Windows APIs on this system (would need a hardware monitor driver like LibreHardwareMonitor for per-component CPU/GPU readings)."
    }
}

$script:hudTick = 0
$hudTimer = New-Object System.Windows.Threading.DispatcherTimer
$hudTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
$hudTimer.Add_Tick({
    $script:hudTick++
    try {
        if ($script:cpuCounter) {
            $cpuVal = [Math]::Round($script:cpuCounter.NextValue())
            $cpuValueText.Text = "$cpuVal%"
            $script:cpuHistory.Add($cpuVal)
            if ($script:cpuHistory.Count -gt 20) { $script:cpuHistory.RemoveAt(0) }
            Update-Sparkline -Polyline $cpuSpark -History $script:cpuHistory -Width 90 -Height 24 -MaxVal 100
        }
    } catch {}

    try {
        $script:gpuTickCounter++
        if ($script:gpuCounters -and $script:gpuCounters.Count -gt 0 -and ($script:gpuTickCounter % 3 -eq 0) -and -not $script:gpuInFlight) {
            $script:gpuInFlight = $true
            $ps = [PowerShell]::Create()
            $ps.AddScript({
                param($counters)
                try {
                    $vals = (Get-Counter -Counter $counters -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                    [Math]::Round(($vals | Measure-Object -Sum).Sum)
                } catch { -1 }
            }).AddArgument($script:gpuCounters) | Out-Null
            $asyncRes = $ps.BeginInvoke()
            $gpuCheckTimer = New-Object System.Windows.Threading.DispatcherTimer
            $gpuCheckTimer.Interval = [TimeSpan]::FromMilliseconds(200)
            $gpuCheckTimer.Add_Tick({
                if ($asyncRes.IsCompleted) {
                    $gpuCheckTimer.Stop()
                    try {
                        $result = $ps.EndInvoke($asyncRes)
                        $ps.Dispose()
                        $script:gpuInFlight = $false
                        if ($result -ge 0) {
                            $gpuValueText.Text = "$result%"
                            $script:gpuHistory.Add($result)
                            if ($script:gpuHistory.Count -gt 20) { $script:gpuHistory.RemoveAt(0) }
                            Update-Sparkline -Polyline $gpuSpark -History $script:gpuHistory -Width 90 -Height 24 -MaxVal 100
                        } else {
                            $gpuValueText.Text = "N/A"
                        }
                    } catch { $script:gpuInFlight = $false; $gpuValueText.Text = "N/A" }
                }
            })
            $gpuCheckTimer.Start()
        } elseif (-not $script:gpuCounters -or $script:gpuCounters.Count -eq 0) {
            $gpuValueText.Text = "N/A"
        }
    } catch { $gpuValueText.Text = "N/A" }

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $totalGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $usedGB = [Math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
            $pct = [Math]::Round(($usedGB / $totalGB) * 100)
            $ramValueText.Text = "$usedGB GB"
            $ramBar.Value = $pct
            $memUsageText.Text = "$usedGB / $totalGB GB"
            $script:memHistory.Add($pct)
            if ($script:memHistory.Count -gt 30) { $script:memHistory.RemoveAt(0) }
            Update-MemGraph
        }
    } catch {}

    $script:pingCounter++
    if ($script:pingCounter % 3 -eq 0 -and -not $script:pingInFlight) {
        $script:pingInFlight = $true
        try {
            $pinger = New-Object System.Net.NetworkInformation.Ping
            $asyncResult = $pinger.SendPingAsync("1.1.1.1", 1000)
            $asyncResult.ContinueWith({
                param($task)
                $script:pingInFlight = $false
                try {
                    if ($task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and $task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                        $ms = [int]$task.Result.RoundtripTime
                        $window.Dispatcher.BeginInvoke([action]{
                            $pingValueText.Text = "$ms ms"
                            $script:pingHistory.Add($ms)
                            if ($script:pingHistory.Count -gt 20) { $script:pingHistory.RemoveAt(0) }
                            Update-Sparkline -Polyline $pingSpark -History $script:pingHistory -Width 90 -Height 24 -MaxVal 150
                        }) | Out-Null
                    } else {
                        $window.Dispatcher.BeginInvoke([action]{ $pingValueText.Text = "N/A" }) | Out-Null
                    }
                } catch {}
            }) | Out-Null
        } catch { $script:pingInFlight = $false; $pingValueText.Text = "N/A" }
    }

    if (-not $script:tempsChecked) {
        $script:tempsChecked = $true
        Check-Temps
    }
})

# ---------- Global drifting particle field (moving background, whole window) ----------
$script:particleData = New-Object System.Collections.Generic.List[object]
function Add-DriftingParticles {
    param($Canvas, $Count, $AreaW, $AreaH)
    $rand = New-Object System.Random
    $neonColors = @("#9A5CFF", "#B266FF", "#C9C9C9", "#8C8C8C", "#9A8CB0")
    for ($i = 0; $i -lt $Count; $i++) {
        $size = $rand.Next(2, 5)
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size
        $dot.Height = $size
        $colorHex = $neonColors[$rand.Next(0, $neonColors.Count)]
        $dot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($colorHex)
        $dot.Opacity = 0.15 + ($rand.NextDouble() * 0.35)
        $x = $rand.NextDouble() * $AreaW
        $y = $rand.NextDouble() * $AreaH
        [System.Windows.Controls.Canvas]::SetLeft($dot, $x)
        [System.Windows.Controls.Canvas]::SetTop($dot, $y)
        $Canvas.Children.Add($dot) | Out-Null
        $script:particleData.Add(@{
            Dot = $dot
            X = $x; Y = $y
            VX = (($rand.NextDouble() - 0.5) * 0.6)
            VY = (($rand.NextDouble() - 0.5) * 0.6) - 0.15
        })
    }
}

$particleTimer = New-Object System.Windows.Threading.DispatcherTimer
$particleTimer.Interval = [TimeSpan]::FromMilliseconds(60)
$particleTimer.Add_Tick({
    $w = $window.ActualWidth; if ($w -le 0) { $w = 1600 }
    $h = $window.ActualHeight; if ($h -le 0) { $h = 900 }
    foreach ($p in $script:particleData) {
        $p.X += $p.VX
        $p.Y += $p.VY
        if ($p.X -lt -10) { $p.X = $w + 10 }
        if ($p.X -gt $w + 10) { $p.X = -10 }
        if ($p.Y -lt -10) { $p.Y = $h + 10 }
        if ($p.Y -gt $h + 10) { $p.Y = -10 }
        [System.Windows.Controls.Canvas]::SetLeft($p.Dot, $p.X)
        [System.Windows.Controls.Canvas]::SetTop($p.Dot, $p.Y)
    }
})

# ---------- RGB glow color-cycling on key HUD elements ----------
$script:neonPalette = @(
    [System.Windows.Media.Color]::FromRgb(0x9A,0x5C,0xFF),
    [System.Windows.Media.Color]::FromRgb(0xB2,0x66,0xFF),
    [System.Windows.Media.Color]::FromRgb(0xC9,0xC9,0xC9),
    [System.Windows.Media.Color]::FromRgb(0x8C,0x8C,0x8C),
    [System.Windows.Media.Color]::FromRgb(0x9A,0x5C,0xFF)
)
$script:glowTick2 = 0
function Get-CycledColor {
    param($TickOffset)
    $cycleLen = 240
    $pos = (($script:glowTick2 + $TickOffset) % $cycleLen) / $cycleLen
    $segCount = $script:neonPalette.Count - 1
    $segPos = $pos * $segCount
    $segIdx = [Math]::Min([int][Math]::Floor($segPos), $segCount - 1)
    $localT = $segPos - $segIdx
    $c1 = $script:neonPalette[$segIdx]
    $c2 = $script:neonPalette[$segIdx + 1]
    $r = [byte]($c1.R + ($c2.R - $c1.R) * $localT)
    $g = [byte]($c1.G + ($c2.G - $c1.G) * $localT)
    $b = [byte]($c1.B + ($c2.B - $c1.B) * $localT)
    return [System.Windows.Media.Color]::FromRgb($r, $g, $b)
}

$glowTimer = New-Object System.Windows.Threading.DispatcherTimer
$glowTimer.Interval = [TimeSpan]::FromMilliseconds(80)
$glowTimer.Add_Tick({
    $script:glowTick2++
    $c1 = Get-CycledColor -TickOffset 0
    $c2 = Get-CycledColor -TickOffset 60
    $c3 = Get-CycledColor -TickOffset 120
    $c4 = Get-CycledColor -TickOffset 180
    if ($topBarGlow) { $topBarGlow.Color = $c1; $topBarBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush($c1) }
    if ($heroGlow)   { $heroGlow.Color = $c2; $heroBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush($c2) }
    if ($ringGlow)   { $ringGlow.Color = $c3 }
    if ($qaGlow)     { $qaGlow.Color = $c4; $qaOptimizeNow.BorderBrush = New-Object System.Windows.Media.SolidColorBrush($c4) }
    if ($titleGlow)  { $titleGlow.Color = $c1 }
})

# ---------- Scanline sweep (pure XAML storyboard, GPU composited) ----------
function Start-ScanlineSweep {
    $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
    $anim.From = -10
    $anim.To = $screenH + 10
    $anim.Duration = [TimeSpan]::FromSeconds(6)
    $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $scanlineY.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
}

# ---------- Random glitch jitter on the VEXY title ----------
$glitchTimer = New-Object System.Windows.Threading.DispatcherTimer
$glitchTimer.Interval = [TimeSpan]::FromMilliseconds(3500)
$script:glitchRand = New-Object System.Random
$glitchTimer.Add_Tick({
    if ($script:glitchRand.NextDouble() -gt 0.55) { return }
    $skewAnim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $skewAnim.Duration = [TimeSpan]::FromMilliseconds(180)
    $k1 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(12, [TimeSpan]::FromMilliseconds(30))
    $k2 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(-8, [TimeSpan]::FromMilliseconds(70))
    $k3 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(0, [TimeSpan]::FromMilliseconds(180))
    $skewAnim.KeyFrames.Add($k1) | Out-Null
    $skewAnim.KeyFrames.Add($k2) | Out-Null
    $skewAnim.KeyFrames.Add($k3) | Out-Null
    $titleSkew.BeginAnimation([System.Windows.Media.SkewTransform]::AngleXProperty, $skewAnim)

    $shiftAnim = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $shiftAnim.Duration = [TimeSpan]::FromMilliseconds(180)
    $s1 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(3, [TimeSpan]::FromMilliseconds(40))
    $s2 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(-3, [TimeSpan]::FromMilliseconds(90))
    $s3 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame(0, [TimeSpan]::FromMilliseconds(180))
    $shiftAnim.KeyFrames.Add($s1) | Out-Null
    $shiftAnim.KeyFrames.Add($s2) | Out-Null
    $shiftAnim.KeyFrames.Add($s3) | Out-Null
    $titleShift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $shiftAnim)
})

$window.Add_Loaded({
    $hudTimer.Start()
    if ($globalParticleCanvas) {
        $ww = $window.ActualWidth; if ($ww -le 0) { $ww = [System.Windows.SystemParameters]::PrimaryScreenWidth }
        $hh = $window.ActualHeight; if ($hh -le 0) { $hh = [System.Windows.SystemParameters]::PrimaryScreenHeight }
        Add-DriftingParticles -Canvas $globalParticleCanvas -Count 55 -AreaW $ww -AreaH $hh
        $particleTimer.Start()
    }
    $glowTimer.Start()
    Start-ScanlineSweep
    $glitchTimer.Start()
    if ($licenseStatusText -and $script:activeLicenseKey) {
        $licenseStatusText.Text = "Key: $($script:activeLicenseKey)  |  $($script:activationDaysUsed)/$($script:activationDaysAllowed) days"
    }
    if ($script:musicAvailable -and -not $script:musicMuted) { $mediaPlayer.Play() }
})
$window.Add_Closed({
    $hudTimer.Stop(); $particleTimer.Stop(); $glowTimer.Stop(); $glitchTimer.Stop()
    if ($script:musicAvailable) { $mediaPlayer.Stop() }
})

# ---------- Loading screen: starfield + animated status, then hand off to dashboard ----------
function Show-LoadingScreen {
    $screenW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight

    # Twinkling starfield (color + fade in/out on random cycles)
    Add-Starfield -Canvas $starCanvas -Count 160 -AreaW $screenW -AreaH $screenH

    # Extra drifting silver/gray particles layered on top, for obvious real motion
    $script:loadParticleData = New-Object System.Collections.Generic.List[object]
    $rand2 = New-Object System.Random
    $grayColors = @("#FFFFFF", "#D8D8D8", "#B0B0B0", "#B266FF", "#9A5CFF")
    for ($i = 0; $i -lt 110; $i++) {
        $size = $rand2.Next(3, 8)
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size
        $dot.Height = $size
        $dot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($grayColors[$rand2.Next(0, $grayColors.Count)])
        $dot.Opacity = 0.35 + ($rand2.NextDouble() * 0.45)
        $x = $rand2.NextDouble() * $screenW
        $y = $rand2.NextDouble() * $screenH
        [System.Windows.Controls.Canvas]::SetLeft($dot, $x)
        [System.Windows.Controls.Canvas]::SetTop($dot, $y)
        $starCanvas.Children.Add($dot) | Out-Null
        $script:loadParticleData.Add(@{
            Dot = $dot; X = $x; Y = $y
            VX = (($rand2.NextDouble() - 0.5) * 3.2)
            VY = (($rand2.NextDouble() - 0.5) * 3.2) - 0.5
        })
    }
    $loadParticleTimer = New-Object System.Windows.Threading.DispatcherTimer
    $loadParticleTimer.Interval = [TimeSpan]::FromMilliseconds(30)
    $loadParticleTimer.Add_Tick({
        foreach ($p in $script:loadParticleData) {
            $p.X += $p.VX; $p.Y += $p.VY
            if ($p.X -lt -10) { $p.X = $screenW + 10 }
            if ($p.X -gt $screenW + 10) { $p.X = -10 }
            if ($p.Y -lt -10) { $p.Y = $screenH + 10 }
            if ($p.Y -gt $screenH + 10) { $p.Y = -10 }
            [System.Windows.Controls.Canvas]::SetLeft($p.Dot, $p.X)
            [System.Windows.Controls.Canvas]::SetTop($p.Dot, $p.Y)
        }
    })

    $messages = @("Checking system", "Loading modules", "Preparing environment")
    $script:loadTick = 0

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(450)
    $timer.Add_Tick({
        $script:loadTick++
        $msgIndex = [Math]::Min([Math]::Floor($script:loadTick / 2.5), $messages.Count - 1)
        $dots = "." * (($script:loadTick % 4))
        $loadStatus.Text = "$($messages[$msgIndex])$dots"

        if ($script:loadTick -ge 12) {
            $timer.Stop()
            $loadParticleTimer.Stop()
            $fadeOut = New-Object System.Windows.Media.Animation.DoubleAnimation(1, 0, [TimeSpan]::FromMilliseconds(450))
            $fadeOut.Add_Completed({
                $loading.Close()
                $window.ShowDialog() | Out-Null
            })
            $loading.BeginAnimation([System.Windows.Window]::OpacityProperty, $fadeOut)
        }
    })

    $loading.Add_Loaded({
        $timer.Start()
        $loadParticleTimer.Start()
        if ($script:musicAvailable -and -not $script:musicMuted) { $mediaPlayer.Play() }
    })
    $loading.ShowDialog() | Out-Null
}

# ---------- Key activation screen: shown only if no valid stored activation exists ----------
function Show-KeyEntryScreen {
    $screenW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight
    Add-Starfield -Canvas $keyStarCanvas -Count 140 -AreaW $screenW -AreaH $screenH

    # Drifting gray particles for obvious motion (same treatment as the loading screen)
    $script:keyParticleData = New-Object System.Collections.Generic.List[object]
    $randKey = New-Object System.Random
    $grayColorsKey = @("#FFFFFF", "#D8D8D8", "#B0B0B0", "#B266FF", "#9A5CFF")
    for ($i = 0; $i -lt 110; $i++) {
        $size = $randKey.Next(3, 8)
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size
        $dot.Height = $size
        $dot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($grayColorsKey[$randKey.Next(0, $grayColorsKey.Count)])
        $dot.Opacity = 0.35 + ($randKey.NextDouble() * 0.45)
        $x = $randKey.NextDouble() * $screenW
        $y = $randKey.NextDouble() * $screenH
        [System.Windows.Controls.Canvas]::SetLeft($dot, $x)
        [System.Windows.Controls.Canvas]::SetTop($dot, $y)
        $keyStarCanvas.Children.Add($dot) | Out-Null
        $script:keyParticleData.Add(@{
            Dot = $dot; X = $x; Y = $y
            VX = (($randKey.NextDouble() - 0.5) * 3.2)
            VY = (($randKey.NextDouble() - 0.5) * 3.2) - 0.5
        })
    }
    $keyParticleTimer = New-Object System.Windows.Threading.DispatcherTimer
    $keyParticleTimer.Interval = [TimeSpan]::FromMilliseconds(30)
    $keyParticleTimer.Add_Tick({
        foreach ($p in $script:keyParticleData) {
            $p.X += $p.VX; $p.Y += $p.VY
            if ($p.X -lt -10) { $p.X = $screenW + 10 }
            if ($p.X -gt $screenW + 10) { $p.X = -10 }
            if ($p.Y -lt -10) { $p.Y = $screenH + 10 }
            if ($p.Y -gt $screenH + 10) { $p.Y = -10 }
            [System.Windows.Controls.Canvas]::SetLeft($p.Dot, $p.X)
            [System.Windows.Controls.Canvas]::SetTop($p.Dot, $p.Y)
        }
    })

    $keyActivateBtn.Add_Click({
        $entered = $keyInputBox.Text.Trim().ToUpper()
        if (-not $entered) {
            $keyErrorText.Text = "Enter a key first."
            return
        }
        $status = Test-KeyStatus -Key $entered -License $script:license
        if ($status.Valid) {
            $script:license.LastKey = $entered
            Save-License -License $script:license
            $script:activeLicenseKey = $entered
            $script:activationDaysUsed = $status.DaysUsed
            $script:activationDaysAllowed = $status.DaysAllowed
            $keyParticleTimer.Stop()
            $keyWindow.Close()
            Show-LoadingScreen
        } else {
            $keyErrorText.Text = $status.Reason
        }
    })
    $keyInputBox.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) { $keyActivateBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    })

    $keyWindow.Add_Loaded({
        $keyInputBox.Focus() | Out-Null
        $keyParticleTimer.Start()
        if ($script:musicAvailable -and -not $script:musicMuted) { $mediaPlayer.Play() }
    })
    $keyWindow.Add_Closed({ $keyParticleTimer.Stop() })
    $keyWindow.ShowDialog() | Out-Null
}

# ---------- Entry point: check for a valid stored activation, otherwise require a key ----------
$storedKey = $script:license.LastKey
if ($storedKey) {
    $status = Test-KeyStatus -Key $storedKey -License $script:license
    if ($status.Valid) {
        $script:activeLicenseKey = $storedKey
        $script:activationDaysUsed = $status.DaysUsed
        $script:activationDaysAllowed = $status.DaysAllowed
        Save-License -License $script:license
        Show-LoadingScreen
    } else {
        Show-KeyEntryScreen
    }
} else {
    Show-KeyEntryScreen
}
