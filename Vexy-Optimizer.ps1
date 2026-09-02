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

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { try { Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue } catch { $null } }
if (-not $scriptDir) { $scriptDir = "" }

# ---------- Asset locations: prefer local files next to the script, fall back to download ----------
$logoUrl  = "https://i.imgur.com/SwOrIYU.png"
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

$logoPath  = Resolve-Asset -LocalName "vexy_logo.png"  -Url $logoUrl  -CachedName "vexy_logo_v2.png"
$musicPath = Resolve-Asset -LocalName "vexy_music.mp3" -Url $musicUrl -CachedName "vexy_music_v2.mp3"
if (-not $logoPath)  { $logoPath  = "" }
if (-not $musicPath) { $musicPath = "" }

# =====================================================================
#  TWEAK FUNCTIONS  -- each returns a short result string for the log
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
        Background="#050810" ResizeMode="NoResize" Opacity="0" ShowInTaskbar="True">
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
                                <Setter TargetName="Bd" Property="Background" Value="#12203D"/>
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
            <Setter Property="BorderBrush" Value="#1F3E7A"/>
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
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#3E8CFF"/>
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
            <Setter Property="Background" Value="#1657D6"/>
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
        <Border x:Name="TopBarBorder" Grid.Row="0" Background="#080C18" BorderBrush="#3E8CFF" BorderThickness="0,0,0,2">
            <Border.Effect>
                <DropShadowEffect x:Name="TopBarGlow" Color="#3E8CFF" BlurRadius="16" ShadowDepth="2" Direction="270" Opacity="0.8"/>
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
                            <DropShadowEffect x:Name="TitleGlow" Color="#3E8CFF" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/>
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
            <Border Grid.Column="0" Background="#080C18" BorderBrush="#12203D" BorderThickness="0,0,1,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Margin="0,16,0,0">
                        <Button x:Name="NavDashboard" Style="{StaticResource NavButton}" Content="🏠  Dashboard" Background="#12203D" Foreground="White" BorderBrush="#3E8CFF"/>
                        <Button x:Name="NavTweaks" Style="{StaticResource NavButton}" Content="🚀  Optimization"/>
                        <Button x:Name="NavGaming" Style="{StaticResource NavButton}" Content="🎮  Gaming"/>
                        <Button x:Name="NavNetwork" Style="{StaticResource NavButton}" Content="🌐  Network"/>
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
                        <TextBlock Text="Built for Performance." Foreground="#4C5C7A" FontSize="10" Margin="16,2,0,0"/>
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
                        <Border x:Name="HeroBorder" Background="#080C18" BorderBrush="#3E8CFF" BorderThickness="1.5" CornerRadius="12" Height="220" Margin="0,0,0,16">
                            <Border.Effect>
                                <DropShadowEffect x:Name="HeroGlow" Color="#3E8CFF" BlurRadius="30" ShadowDepth="0" Opacity="0.65"/>
                            </Border.Effect>
                            <Grid>
                                <Canvas x:Name="HeroStarCanvas" ClipToBounds="True" IsHitTestVisible="False"/>
                                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                    <Image x:Name="HeroLogoImg" Height="120" Stretch="Uniform"/>
                                    <TextBlock Text="OPTIMIZE   •   TWEAK   •   DOMINATE" Foreground="#5C8AD9" FontSize="13"
                                               FontFamily="Consolas" HorizontalAlignment="Center" Margin="0,14,0,0"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- STATUS + PERFORMANCE ROW -->
                        <Grid Margin="0,0,0,16">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                
