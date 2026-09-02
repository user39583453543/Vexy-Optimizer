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

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# ---------- Asset locations: prefer local files next to the script, fall back to download ----------
$logoUrl  = "https://i.imgur.com/SwOrIYU.png"
$musicUrl = "https://tmpfiles.org/dl/wNwxhmofQw34/vexy_music1.mp3"

$assetDir = Join-Path $env:TEMP "VexyOptimizerAssets"
if (-not (Test-Path $assetDir)) { New-Item -Path $assetDir -ItemType Directory -Force | Out-Null }

function Resolve-Asset {
    param($LocalName, $Url, $CachedName)
    $localCandidate = Join-Path $scriptDir $LocalName
    if (Test-Path $localCandidate) { return $localCandidate }

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
$musicPath = Resolve-Asset -LocalName "vexy_music.mp3" -Url $musicUrl -CachedName "vexy_music.mp3"
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

        <!-- TOP BAR -->
        <Border Grid.Row="0" Background="#080C18" BorderBrush="#12203D" BorderThickness="0,0,0,1">
            <Grid Margin="20,0">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image x:Name="TopLogoImg" Height="30" Margin="0,0,10,0"/>
                    <TextBlock Text="VEXY" Foreground="White" FontWeight="Bold" FontSize="20" VerticalAlignment="Center" FontFamily="Segoe UI"/>
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
                        <Border Background="#080C18" BorderBrush="#12203D" BorderThickness="1" CornerRadius="12" Height="220" Margin="0,0,0,16">
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
                                <ColumnDefinition Width="16"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <Border Grid.Column="0" Background="#080C18" BorderBrush="#12203D" BorderThickness="1" CornerRadius="12" Padding="18">
                                <StackPanel>
                                    <TextBlock Text="SYSTEM STATUS" Foreground="#5C8AD9" FontSize="12" FontWeight="Bold" Margin="0,0,0,14"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="120"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Grid Width="110" Height="110" HorizontalAlignment="Left">
                                            <Ellipse Width="110" Height="110" Stroke="#1A2C4E" StrokeThickness="12"/>
                                            <Path x:Name="RingPath" Stroke="#3E9CFF" StrokeThickness="12" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
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

                            <Border Grid.Column="2" Background="#080C18" BorderBrush="#12203D" BorderThickness="1" CornerRadius="12" Padding="18">
                                <StackPanel>
                                    <TextBlock Text="PERFORMANCE" Foreground="#5C8AD9" FontSize="12" FontWeight="Bold" Margin="0,0,0,14"/>
                                    <UniformGrid Columns="2" Rows="2">
                                        <Border Background="#0E1730" CornerRadius="8" Margin="0,0,8,8" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="CPU" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="CpuValueText" Text="--%" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <Polyline x:Name="CpuSpark" Stroke="#3E9CFF" StrokeThickness="1.5" Height="24"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#0E1730" CornerRadius="8" Margin="0,0,0,8" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="GPU" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="GpuValueText" Text="--%" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <Polyline x:Name="GpuSpark" Stroke="#3E9CFF" StrokeThickness="1.5" Height="24"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#0E1730" CornerRadius="8" Margin="0,0,8,0" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="RAM" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="RamValueText" Text="-- GB" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <ProgressBar x:Name="RamBar" Height="6" Minimum="0" Maximum="100" Value="0" Foreground="#3E9CFF" Background="#1A2C4E" BorderThickness="0" Margin="0,4,0,0"/>
                                            </StackPanel>
                                        </Border>
                                        <Border Background="#0E1730" CornerRadius="8" Padding="10">
                                            <StackPanel>
                                                <TextBlock Text="PING" Foreground="#7FA0D9" FontSize="11"/>
                                                <TextBlock x:Name="PingValueText" Text="-- ms" Foreground="White" FontSize="18" FontWeight="Bold"/>
                                                <Polyline x:Name="PingSpark" Stroke="#3E9CFF" StrokeThickness="1.5" Height="24"/>
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

                            <Border Grid.Column="0" Background="#080C18" BorderBrush="#12203D" BorderThickness="1" CornerRadius="12" Padding="16" MinHeight="200">
                                <StackPanel>
                                    <TextBlock Text="RECENT ACTIVITY" Foreground="#5C8AD9" FontSize="12" FontWeight="Bold" Margin="0,0,0,10"/>
                                    <StackPanel x:Name="ActivityPanel"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="2" Background="#080C18" BorderBrush="#12203D" BorderThickness="1" CornerRadius="12" Padding="16" MinHeight="200">
                                <StackPanel>
                                    <Grid>
                                        <TextBlock Text="MEMORY USAGE" Foreground="#5C8AD9" FontSize="12" FontWeight="Bold" HorizontalAlignment="Left"/>
                                        <TextBlock x:Name="MemUsageText" Text="-- / -- GB" Foreground="#9FB3D9" FontSize="11" HorizontalAlignment="Right"/>
                                    </Grid>
                                    <Canvas x:Name="MemGraphCanvas" Height="130" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="4" Background="#080C18" BorderBrush="#12203D" BorderThickness="1" CornerRadius="12" Padding="16" MinHeight="200">
                                <StackPanel>
                                    <TextBlock Text="TEMPERATURES" Foreground="#5C8AD9" FontSize="12" FontWeight="Bold" Margin="0,0,0,10"/>
                                    <TextBlock x:Name="TempInfoText" Text="Checking sensors..." Foreground="#7FA0D9" FontSize="12" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                    </StackPanel>

                    <!-- QUICK ACTIONS -->
                    <StackPanel Grid.Column="1">
                        <TextBlock Text="QUICK ACTIONS" Foreground="#5C8AD9" FontSize="12" FontWeight="Bold" Margin="4,0,0,10"/>
                        <Button x:Name="QaOptimizeNow" Style="{StaticResource ActionCard}">
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
                        <Button x:Name="QaRestore" Style="{StaticResource ActionCard}">
                            <StackPanel>
                                <TextBlock Text="↺  RESTORE" FontWeight="Bold" FontSize="14"/>
                                <TextBlock Text="Undo changes" Foreground="#9FB3D9" FontSize="11" Margin="0,3,0,0"/>
                            </StackPanel>
                        </Button>
                        <Border Background="#0E1730" CornerRadius="10" Padding="14" Margin="0,10,0,0">
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnMusic" Content="🔊 Music" Width="110" Height="34" Background="#12203D" Foreground="White" BorderThickness="0"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Grid>
                </ScrollViewer>

                <!-- TWEAKS VIEW -->
                <ScrollViewer x:Name="TweaksView" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                <Grid Margin="30" MaxWidth="640" HorizontalAlignment="Center">
                    <StackPanel>
                        <TextBlock Text="OPTIMIZATION" Foreground="#5C8AD9" FontSize="14" FontWeight="Bold" Margin="0,0,0,16"/>
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
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,20,0,0">
                            <Button x:Name="BtnOptimize" Style="{StaticResource PrimaryButton}" Content="OPTIMIZE" Width="150" Height="42" Margin="0,0,10,0"/>
                            <Button x:Name="BtnRestore" Content="Open System Restore" Width="180" Height="42" Background="#2A2A3D" Foreground="White" BorderThickness="0"/>
                        </StackPanel>
                    </StackPanel>
                </Grid>
                </ScrollViewer>
            </Grid>
        </Grid>
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
    <Border BorderBrush="#1657D6" BorderThickness="2">
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
                       Foreground="#CFE0FF" FontFamily="Segoe UI Light" FontSize="16"
                       HorizontalAlignment="Center" Margin="0,26,0,0"/>
            <TextBlock Text="vexy optimizer" Foreground="#3E5C9E" FontFamily="Segoe UI"
                       FontSize="12" HorizontalAlignment="Center" Margin="0,60,0,0"/>
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

# ---------- Wire up controls ----------
$topLogoImg   = $window.FindName("TopLogoImg")
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

$dashboardView = $window.FindName("DashboardView")
$tweaksView    = $window.FindName("TweaksView")

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

$chkAll     = $window.FindName("ChkSelectAll")
$btnOpt     = $window.FindName("BtnOptimize")
$btnRestore = $window.FindName("BtnRestore")

$splashLogo   = $splash.FindName("SplashLogo")
$splashStatus = $splash.FindName("SplashStatus")
$splashLog    = $splash.FindName("SplashLog")

$loadLogo   = $loading.FindName("LoadLogo")
$loadStatus = $loading.FindName("LoadStatus")
$starCanvas = $loading.FindName("StarCanvas")

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
}

# ---------- Window controls ----------
$btnClose.Add_Click({ $window.Close() })
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

# ---------- View switching (sidebar nav) ----------
$allNavButtons = @($navDashboard, $navTweaks, $navGaming, $navNetwork, $navWindows, $navServices, $navPowerPlan)

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
        $ActiveButton.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#12203D")
        $ActiveButton.Foreground = [System.Windows.Media.Brushes]::White
        $ActiveButton.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3E8CFF")
    }
}

function Show-Dashboard {
    $dashboardView.Visibility = [System.Windows.Visibility]::Visible
    $tweaksView.Visibility = [System.Windows.Visibility]::Collapsed
    Set-ActiveNav -ActiveButton $navDashboard
}
function Show-Tweaks {
    param($OnlyKeys = $null)
    $dashboardView.Visibility = [System.Windows.Visibility]::Collapsed
    $tweaksView.Visibility = [System.Windows.Visibility]::Visible
    if ($OnlyKeys) {
        foreach ($key in $tweakMap.Keys) {
            $cb = $window.FindName($key)
            if ($cb) { $cb.IsChecked = ($OnlyKeys -contains $key) }
        }
    }
}

$navDashboard.Add_Click({ Show-Dashboard })
$navTweaks.Add_Click({ Show-Tweaks; Set-ActiveNav -ActiveButton $navTweaks })
$navGaming.Add_Click({ Show-Tweaks -OnlyKeys @("ChkGraphics","ChkInput"); Set-ActiveNav -ActiveButton $navGaming })
$navNetwork.Add_Click({ Show-Tweaks -OnlyKeys @("ChkNetwork"); Set-ActiveNav -ActiveButton $navNetwork })
$navWindows.Add_Click({ Show-Tweaks -OnlyKeys @("ChkVisual","ChkBackground"); Set-ActiveNav -ActiveButton $navWindows })
$navServices.Add_Click({ Show-Tweaks -OnlyKeys @("ChkBackground","ChkCpu"); Set-ActiveNav -ActiveButton $navServices })
$navPowerPlan.Add_Click({ Show-Tweaks -OnlyKeys @("ChkPower"); Set-ActiveNav -ActiveButton $navPowerPlan })
$navCleanup.Add_Click({ Add-ActivityLine -Text (Invoke-Cleanup) })
$navRestore.Add_Click({ Start-Process "rstrui.exe" })

$btnRestore.Add_Click({ Start-Process "rstrui.exe" })
$qaRestore.Add_Click({ Start-Process "rstrui.exe" })
$qaCleanJunk.Add_Click({ Add-ActivityLine -Text (Invoke-Cleanup) })
$qaGamingMode.Add_Click({
    Show-Tweaks -OnlyKeys @("ChkGraphics","ChkInput")
    Set-ActiveNav -ActiveButton $navGaming
    Run-SelectedTweaks
})
$qaOptimizeNow.Add_Click({
    Show-Tweaks
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

function Update-MemGraph {
    $memGraphCanvas.Children.Clear()
    if ($script:memHistory.Count -lt 2) { return }
    $w = $memGraphCanvas.ActualWidth; if ($w -le 0) { $w = 400 }
    $h = $memGraphCanvas.ActualHeight; if ($h -le 0) { $h = 130 }
    $n = $script:memHistory.Count
    $maxV = 100
    $poly = New-Object System.Windows.Shapes.Polyline
    $poly.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3E9CFF")
    $poly.StrokeThickness = 2
    $pts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $n; $i++) {
        $x = ($i / [Math]::Max(1, $n - 1)) * $w
        $y = $h - (($script:memHistory[$i] / $maxV) * $h)
        $pts.Add((New-Object System.Windows.Point($x, $y)))
    }
    $poly.Points = $pts
    $memGraphCanvas.Children.Add($poly) | Out-Null
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
        if ($script:gpuCounters -and $script:gpuCounters.Count -gt 0) {
            $vals = (Get-Counter -Counter $script:gpuCounters -ErrorAction SilentlyContinue).CounterSamples.CookedValue
            $gpuVal = [Math]::Round(($vals | Measure-Object -Sum).Sum)
            $gpuValueText.Text = "$gpuVal%"
            $script:gpuHistory.Add($gpuVal)
            if ($script:gpuHistory.Count -gt 20) { $script:gpuHistory.RemoveAt(0) }
            Update-Sparkline -Polyline $gpuSpark -History $script:gpuHistory -Width 90 -Height 24 -MaxVal 100
        } else {
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
    if ($script:pingCounter % 3 -eq 0) {
        try {
            $reply = Test-Connection -ComputerName "1.1.1.1" -Count 1 -ErrorAction Stop
            $ms = [Math]::Round(($reply | Select-Object -First 1).ResponseTime)
            $pingValueText.Text = "$ms ms"
            $script:pingHistory.Add($ms)
            if ($script:pingHistory.Count -gt 20) { $script:pingHistory.RemoveAt(0) }
            Update-Sparkline -Polyline $pingSpark -History $script:pingHistory -Width 90 -Height 24 -MaxVal 150
        } catch { $pingValueText.Text = "N/A" }
    }

    if (-not $script:tempsChecked) {
        $script:tempsChecked = $true
        Check-Temps
    }
})
$window.Add_Loaded({
    $hudTimer.Start()
    if ($script:musicAvailable -and -not $script:musicMuted) { $mediaPlayer.Play() }
})
$window.Add_Closed({ $hudTimer.Stop(); if ($script:musicAvailable) { $mediaPlayer.Stop() } })

# ---------- Loading screen: starfield + animated status, then hand off to dashboard ----------
function Show-LoadingScreen {
    $rand = New-Object System.Random
    $screenW = [System.Windows.SystemParameters]::PrimaryScreenWidth
    $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight

    for ($i = 0; $i -lt 180; $i++) {
        $size = $rand.Next(1, 3) + ($rand.NextDouble())
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $size
        $dot.Height = $size
        $dot.Fill = [System.Windows.Media.Brushes]::White
        $dot.Opacity = 0.15 + ($rand.NextDouble() * 0.65)
        [System.Windows.Controls.Canvas]::SetLeft($dot, $rand.NextDouble() * $screenW)
        [System.Windows.Controls.Canvas]::SetTop($dot, $rand.NextDouble() * $screenH)
        $starCanvas.Children.Add($dot) | Out-Null
    }

    $messages = @("Checking system", "Loading modules", "Preparing environment")
    $script:loadTick = 0

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(450)
    $timer.Add_Tick({
        $script:loadTick++
        $msgIndex = [Math]::Min([Math]::Floor($script:loadTick / 2.5), $messages.Count - 1)
        $dots = "." * (($script:loadTick % 4))
        $loadStatus.Text = "$($messages[$msgIndex])$dots"

        if ($script:loadTick -ge 8) {
            $timer.Stop()
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
        if ($script:musicAvailable -and -not $script:musicMuted) { $mediaPlayer.Play() }
    })
    $loading.ShowDialog() | Out-Null
}

Show-LoadingScreen
