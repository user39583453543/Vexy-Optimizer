<#
VEXY BLACKSITE V5
PowerShell backend + Microsoft Edge app-mode frontend.

Launch target:
irm "https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/refs/heads/main/Vexy-Optimizer.ps1" | iex

Design:
- cinematic moving-star boot screen
- activation terminal
- gray / black 3D interface
- GitHub-hosted VEXY graphics
- GitHub-hosted VEXY music
- local-only authenticated API
- backup-first optimization profiles
- controlled shutdown sequence

Safety interlocks:
VEXY V5 intentionally does NOT disable Windows security, write firmware/BIOS,
alter voltages/clocks, destroy partitions, delete Windows components, or block
Windows recovery controls.
#>

# VEXY requires Windows PowerShell 5.1+.
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw 'VEXY requires Windows PowerShell 5.1 or newer.'
}

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'

# ----------------------------------------------------------------------
# SELF ELEVATION
# ----------------------------------------------------------------------
$script:SelfUrl = 'https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/refs/heads/main/Vexy-Optimizer.ps1'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$script:IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $script:IsAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy','Bypass',
            '-STA',
            '-File',"`"$PSCommandPath`""
        )
        exit
    }

    # Supports the GitHub: irm "..." | iex launch method.
    $elevatedCommand = "irm '$script:SelfUrl' | iex"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy','Bypass',
        '-STA',
        '-Command',$elevatedCommand
    )
    exit
}

# ----------------------------------------------------------------------
# APP DIRECTORIES
# ----------------------------------------------------------------------
$script:AppRoot = Join-Path $env:APPDATA 'VexyOptimizer'
$script:BackupRoot = Join-Path $script:AppRoot 'Backups'
$script:RuntimeRoot = Join-Path $env:TEMP 'VexyBlacksiteV5'
$script:EdgeProfile = Join-Path $script:RuntimeRoot 'EdgeProfile'
$script:LicenseFile = Join-Path $script:AppRoot 'last_license.json'

foreach ($dir in @($script:AppRoot,$script:BackupRoot,$script:RuntimeRoot,$script:EdgeProfile)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ----------------------------------------------------------------------
# UI + EXTERNAL GRAPHICS
# ----------------------------------------------------------------------
# The visual frontend below is the exact same VEXY V5 menu, stored as readable
# HTML instead of Base64. PNG/audio assets live beside this script in GitHub.
# This keeps irm | iex fast, readable, and much easier to debug.

$script:Html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VEXY // BLACKSITE</title>
<style>
:root{
  --black:#020304; --black2:#05070a; --graphite:#0a0d11; --graphite2:#10141a;
  --steel:#1a2027; --steel2:#2b333c; --silver:#8f9aa5; --silver2:#c8d0d7;
  --white:#f4f6f8; --green:#5ee3a0; --amber:#ffc05a; --red:#ff4b5d;
  --edge:#3d4650; --edge2:#59636d; --shadow:rgba(0,0,0,.72);
}
*{box-sizing:border-box}
html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000;color:var(--white);font-family:Inter,"Segoe UI",Arial,sans-serif}
button,input{font:inherit}
body{user-select:none}
#stars{position:fixed;inset:0;width:100%;height:100%;background:#000;z-index:0}
.film{position:fixed;inset:0;z-index:200;pointer-events:none;opacity:.35;background:repeating-linear-gradient(0deg,rgba(255,255,255,.018) 0 1px,transparent 1px 4px)}
.vignette{position:fixed;inset:0;z-index:190;pointer-events:none;box-shadow:inset 0 0 180px #000,inset 0 0 60px #000}

.screen{position:fixed;inset:0;display:none;z-index:10}
.screen.show{display:block}
.fade-in{animation:fadeIn .7s ease both}
.fade-out{animation:fadeOut .65s ease both}
@keyframes fadeIn{from{opacity:0}to{opacity:1}}
@keyframes fadeOut{from{opacity:1}to{opacity:0}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes spinReverse{to{transform:rotate(-360deg)}}
@keyframes pulse{0%,100%{opacity:.45}50%{opacity:1}}
@keyframes shimmer{0%{transform:translateX(-150%) skewX(-24deg)}100%{transform:translateX(330%) skewX(-24deg)}}
@keyframes breathe{0%,100%{filter:drop-shadow(0 0 5px rgba(255,255,255,.08));transform:translateZ(0) scale(.985)}50%{filter:drop-shadow(0 0 24px rgba(255,255,255,.22));transform:translateZ(40px) scale(1.015)}}
@keyframes scanline{from{transform:translateY(-100vh)}to{transform:translateY(100vh)}}
@keyframes panelIn{from{opacity:0;transform:translateY(14px) scale(.985)}to{opacity:1;transform:none}}
@keyframes unlockLeft{to{transform:translateX(-105%)}}
@keyframes unlockRight{to{transform:translateX(105%)}}

/* BOOT */
#boot{display:block;background:radial-gradient(circle at 50% 50%,rgba(70,78,88,.10),transparent 30%)}
.boot-shell{height:100%;display:grid;place-items:center;position:relative;perspective:1100px}
.boot-emblem-wrap{width:min(48vw,620px);position:relative;transform-style:preserve-3d;animation:breathe 4s ease-in-out infinite}
.boot-emblem{width:100%;display:block;filter:contrast(1.1) brightness(.88)}
.orbit{position:absolute;left:50%;top:50%;border:1px solid rgba(190,200,210,.16);border-radius:50%;transform:translate(-50%,-50%);pointer-events:none}
.o1{width:88%;aspect-ratio:1;animation:spin 18s linear infinite;border-style:dashed}
.o2{width:104%;aspect-ratio:1;animation:spinReverse 26s linear infinite;border-color:rgba(255,255,255,.08)}
.o3{width:120%;aspect-ratio:1;animation:spin 38s linear infinite;border-style:dotted}
.boot-copy{position:absolute;bottom:9vh;left:50%;transform:translateX(-50%);width:min(820px,82vw);text-align:center}
.boot-title{font-size:13px;letter-spacing:.5em;font-weight:900;color:#d6dbe0}
.boot-status{margin-top:12px;font:10px/1.8 Consolas,monospace;color:#77818b;height:18px}
.progress-track{height:3px;margin:16px auto 0;width:min(650px,72vw);background:#12161b;position:relative;overflow:hidden;border-left:1px solid #818990;border-right:1px solid #818990}
.progress-fill{position:absolute;left:0;top:0;bottom:0;width:0;background:linear-gradient(90deg,#4a5159,#f0f2f4,#656d76);box-shadow:0 0 12px rgba(255,255,255,.25)}
.boot-percent{margin-top:8px;font:10px Consolas,monospace;color:#b0b7be}
.boot-corners span{position:absolute;width:90px;height:90px;border-color:#4a535c;opacity:.35}
.boot-corners .tl{left:30px;top:30px;border-left:1px solid;border-top:1px solid}.boot-corners .tr{right:30px;top:30px;border-right:1px solid;border-top:1px solid}.boot-corners .bl{left:30px;bottom:30px;border-left:1px solid;border-bottom:1px solid}.boot-corners .br{right:30px;bottom:30px;border-right:1px solid;border-bottom:1px solid}

/* ACTIVATION */
#activation{background:rgba(0,0,0,.14);perspective:1200px}
.activation-shell{height:100%;display:grid;place-items:center;padding:24px;position:relative}
.activation-stage{width:min(1080px,92vw);height:min(650px,82vh);position:relative;transform-style:preserve-3d}
.metal-frame{
  position:absolute;inset:0;background:
  linear-gradient(145deg,#303840 0%,#0d1115 13%,#1c2228 18%,#080b0e 43%,#171c21 72%,#06080b 100%);
  clip-path:polygon(0 45px,45px 0,31% 0,33% 14px,67% 14px,69% 0,calc(100% - 45px) 0,100% 45px,100% calc(100% - 45px),calc(100% - 45px) 100%,69% 100%,67% calc(100% - 14px),33% calc(100% - 14px),31% 100%,45px 100%,0 calc(100% - 45px));
  box-shadow:0 50px 120px #000,0 0 45px rgba(160,170,180,.10)
}
.metal-frame:before{content:"";position:absolute;inset:7px;clip-path:inherit;background:linear-gradient(145deg,#0b0f13,#020304 55%,#10151a);border:1px solid #4a535d}
.metal-frame:after{content:"";position:absolute;inset:13px;clip-path:inherit;border:1px solid rgba(255,255,255,.055);box-shadow:inset 0 0 60px #000}
.activation-inner{position:absolute;inset:42px 54px;display:grid;grid-template-columns:44% 56%;z-index:2}
.activation-art{position:relative;display:grid;place-items:center;overflow:hidden}
.activation-art:after{content:"";position:absolute;inset:10%;border-radius:50%;background:radial-gradient(circle,rgba(170,180,190,.06),transparent 60%)}
.activation-emblem{width:88%;max-height:82%;object-fit:contain;filter:brightness(.80) contrast(1.16);animation:breathe 5s ease-in-out infinite;z-index:2}
.activation-console{padding:40px 46px 32px;display:flex;flex-direction:column;justify-content:center;position:relative}
.activation-console:before{content:"";position:absolute;left:0;top:14%;bottom:14%;width:1px;background:linear-gradient(transparent,#717b85 20%,#252b32 50%,#717b85 80%,transparent)}
.console-kicker{font-size:9px;letter-spacing:.34em;color:#6f7881;font-weight:900}
.console-title{font-size:34px;font-weight:1000;letter-spacing:.14em;margin-top:7px;color:#f0f2f4;text-shadow:0 0 22px rgba(255,255,255,.08)}
.console-sub{font-size:9px;color:#69737d;letter-spacing:.10em;margin:6px 0 28px}
.license-label{font-size:8px;color:#858e97;letter-spacing:.14em;font-weight:900;margin-bottom:8px}
.key-wrap{position:relative;height:58px;background:#050709;border:1px solid #3f474f;clip-path:polygon(0 9px,9px 0,calc(100% - 16px) 0,100% 16px,100% 100%,0 100%);box-shadow:inset 0 0 25px #000}
.key-wrap:before{content:"";position:absolute;left:0;top:0;width:75px;height:1px;background:#ccd1d5}
.key-input{width:100%;height:100%;background:transparent;border:0;outline:0;color:#eef1f3;padding:0 18px;font:16px Consolas,monospace;letter-spacing:.08em;text-transform:uppercase}
.auth-btn{height:54px;margin-top:12px;border:1px solid #5b646d;background:linear-gradient(180deg,#2b3239,#11161b 60%,#090c0f);color:#eef1f3;font-size:10px;font-weight:1000;letter-spacing:.16em;cursor:pointer;position:relative;overflow:hidden;clip-path:polygon(0 9px,9px 0,calc(100% - 16px) 0,100% 16px,100% calc(100% - 9px),calc(100% - 9px) 100%,0 100%)}
.auth-btn:before{content:"";position:absolute;top:0;bottom:0;width:32%;left:-40%;background:linear-gradient(90deg,transparent,rgba(255,255,255,.18),transparent);transform:skewX(-24deg)}
.auth-btn:hover:before{animation:shimmer .75s ease}.auth-btn:hover{border-color:#aeb6bd;background:linear-gradient(180deg,#374049,#14191e)}
.auth-state{height:26px;margin-top:13px;font:9px Consolas,monospace;color:#737d87}
.auth-grid{margin-top:18px;display:grid;grid-template-columns:1fr 1fr;gap:7px 18px}
.auth-row{display:flex;justify-content:space-between;border-bottom:1px solid #1b2025;padding:6px 0;font-size:8px;color:#66717b}.auth-row b{font-size:7px;color:#aab1b7}
.access-granted{color:var(--green)!important;text-shadow:0 0 9px rgba(94,227,160,.25)}
.access-denied{color:var(--red)!important}
.door{position:absolute;top:0;bottom:0;width:50%;z-index:20;background:linear-gradient(120deg,#090c0f,#1d2329 35%,#06080a 72%);display:none}
.door.left{left:0;border-right:1px solid #626a72}.door.right{right:0;border-left:1px solid #626a72}.door.open.left{display:block;animation:unlockLeft .85s cubic-bezier(.65,.05,.36,1) forwards}.door.open.right{display:block;animation:unlockRight .85s cubic-bezier(.65,.05,.36,1) forwards}

/* APP */
#dashboard{background:radial-gradient(circle at 52% 48%,rgba(130,140,150,.055),transparent 38%),linear-gradient(#040608,#020304)}
.app-shell{height:100%;display:grid;grid-template-rows:78px 1fr 36px}
.topbar{display:grid;grid-template-columns:330px 1fr 430px;align-items:center;padding:0 18px;background:linear-gradient(180deg,#11161b,#070a0d);border-bottom:1px solid #303840;box-shadow:0 12px 40px #000;clip-path:polygon(0 0,100% 0,100% 100%,77% 100%,76% 89%,24% 89%,23% 100%,0 100%)}
.brand{display:flex;align-items:center;gap:12px}.wordmark{height:48px;max-width:230px;object-fit:contain;object-position:left center;filter:brightness(.84) contrast(1.1)}
.brand-copy{font-size:7px;color:#636d76;font-weight:900;letter-spacing:.16em;border-left:1px solid #3d454e;padding-left:11px}
.top-center{text-align:center}.top-kicker{font-size:7px;color:#65707a;letter-spacing:.16em;font-weight:900}.top-title{font-size:19px;font-weight:1000;letter-spacing:.09em;margin:3px 0}.top-title span{color:#b8c0c7}.top-proto{font-size:7px;color:#8c959d;letter-spacing:.15em}
.top-right{display:flex;justify-content:flex-end;align-items:center;gap:14px}.top-stat .k{font-size:7px;color:#59636d;font-weight:900}.top-stat .v{font-size:9px;color:#d7dce0;margin-top:3px;font-weight:800}
.top-btn{width:39px;height:39px;border:1px solid #3b434c;background:#0a0e12;color:#aeb6bd;display:grid;place-items:center;cursor:pointer;clip-path:polygon(0 8px,8px 0,100% 0,100% calc(100% - 8px),calc(100% - 8px) 100%,0 100%)}
.top-btn:hover{border-color:#b5bdc4;color:#fff;background:#161c21}.top-btn.exit{color:#c38b91}
.work{display:grid;grid-template-columns:236px 1fr;min-height:0}
.rail{background:linear-gradient(180deg,#0b0f13,#050709);border-right:1px solid #283039;padding:16px 11px;display:flex;flex-direction:column;min-height:0;position:relative}
.rail:after{content:"";position:absolute;right:-1px;top:90px;bottom:90px;width:1px;background:linear-gradient(transparent,#8b949d 30%,#353c43 50%,#8b949d 70%,transparent);opacity:.25}
.rail-label{font-size:7px;color:#707a83;font-weight:900;letter-spacing:.16em;margin:0 11px 9px}
.nav{display:flex;flex-direction:column;gap:5px}
.nav button{height:57px;border:1px solid transparent;background:transparent;color:#8a949e;cursor:pointer;text-align:left;padding:0 12px;display:grid;grid-template-columns:40px 1fr;align-items:center;clip-path:polygon(0 8px,8px 0,calc(100% - 13px) 0,100% 13px,100% calc(100% - 8px),calc(100% - 8px) 100%,0 100%);transition:.18s}
.nav button:hover{background:#11161b;border-color:#323a42;color:#e9ecef}.nav button.active{background:linear-gradient(90deg,#242b31,#0c1014 78%);border-color:#5d6670;color:#fff;box-shadow:inset 0 0 18px rgba(255,255,255,.025)}
.nav-icon{width:30px;height:30px;display:grid;place-items:center;border:1px solid #394149;transform:rotate(45deg);background:#090c0f}.nav-icon i{font-style:normal;transform:rotate(-45deg);font-size:12px}.nav button.active .nav-icon{border-color:#a9b1b8;color:#e9ecef;box-shadow:0 0 12px rgba(255,255,255,.05)}
.nav-name{font-size:9px;font-weight:1000;letter-spacing:.05em}.nav-sub{font-size:6px;color:#5e6872;margin-top:3px;letter-spacing:.09em}
.rail-bottom{margin-top:auto}.rail-card{margin:8px 4px;padding:12px;background:#090d11;border:1px solid #293139;clip-path:polygon(0 9px,9px 0,calc(100% - 12px) 0,100% 12px,100% 100%,0 100%)}
.rail-card h4{font-size:7px;letter-spacing:.12em;color:#636d76;margin:0 0 8px}.rrow{display:flex;justify-content:space-between;font-size:7px;color:#68727c;margin:6px 0}.rrow b{font-size:6px;color:#b6bdc3}.good{color:var(--green)!important}.caution{color:var(--amber)!important}.danger{color:var(--red)!important}
.content{padding:14px 15px 10px;min-width:0;min-height:0;position:relative;perspective:1400px}
.page{display:none;height:100%;min-height:0}.page.active{display:block;animation:panelIn .28s ease both}
.page-head{height:45px;display:flex;justify-content:space-between;align-items:flex-start}.page-title{font-size:18px;font-weight:1000;letter-spacing:.08em}.page-sub{font-size:7px;color:#626d77;font-weight:900;letter-spacing:.11em;margin-top:4px}.badges{display:flex;gap:7px}.badge{padding:5px 8px;border:1px solid #353d45;background:#0a0e12;font-size:6px;font-weight:1000;letter-spacing:.12em;color:#aeb6bd}.badge.safe{color:var(--green);border-color:#24513d}.badge.adv{color:var(--amber);border-color:#59431d}.badge.red{color:var(--red);border-color:#67252d}
.frame{position:relative;background:linear-gradient(145deg,rgba(16,21,26,.98),rgba(4,6,8,.99) 65%);border:1px solid #303841;clip-path:polygon(0 14px,14px 0,calc(100% - 22px) 0,100% 22px,100% calc(100% - 14px),calc(100% - 14px) 100%,18px 100%,0 calc(100% - 18px));box-shadow:0 24px 70px #000}
.frame:before{content:"";position:absolute;inset:5px;pointer-events:none;clip-path:inherit;border:1px solid rgba(255,255,255,.025)}
.frame:after{content:"";position:absolute;left:18px;top:0;width:72px;height:1px;background:linear-gradient(90deg,#c4cbd1,transparent);opacity:.42}
.frame-title{font-size:8px;font-weight:1000;letter-spacing:.10em;color:#d9dee2}.frame-kicker{font-size:6px;color:#68727c;letter-spacing:.09em;font-weight:900;margin-top:3px}
.dash-grid{height:calc(100% - 45px);display:grid;grid-template-columns:minmax(580px,1fr) 350px;gap:11px;min-height:0}.dash-left{display:grid;grid-template-rows:minmax(0,1fr) 140px;gap:10px;min-height:0}.reactor{overflow:hidden;position:relative}
.reactor-bg{position:absolute;inset:0;background:radial-gradient(circle at 50% 48%,rgba(210,218,225,.065),transparent 25%),repeating-radial-gradient(circle at 50% 48%,transparent 0 39px,rgba(255,255,255,.016) 40px 41px)}
.reactor-lines{position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.018) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.014) 1px,transparent 1px);background-size:42px 42px;mask-image:radial-gradient(circle,#000 0 55%,transparent 76%)}
.core-assembly{position:absolute;left:50%;top:50%;width:min(76%,650px);aspect-ratio:1;transform:translate(-50%,-50%);display:grid;place-items:center;transform-style:preserve-3d}
.core-ring{position:absolute;border-radius:50%;border:1px solid #48515a}.cr1{inset:2%;border-style:dashed;animation:spin 22s linear infinite}.cr2{inset:8%;border:5px double #333b43;animation:spinReverse 15s linear infinite}.cr3{inset:15%;border:2px dashed #626b73;animation:spin 10s linear infinite}.cr4{inset:23%;border:7px double #20272d;animation:spinReverse 17s linear infinite}
.core-ring:before{content:"";position:absolute;inset:-5px;border-radius:50%;border:1px dotted rgba(255,255,255,.16)}
.core-emblem{width:54%;max-height:54%;object-fit:contain;z-index:5;filter:brightness(.8) contrast(1.17) drop-shadow(0 18px 35px #000);animation:breathe 4.5s ease-in-out infinite}
.core-score{position:absolute;z-index:6;bottom:18%;text-align:center}.core-score b{font-size:27px;font-weight:300}.core-score span{display:block;font-size:6px;color:#7c858d;letter-spacing:.14em;margin-top:3px;font-weight:900}
.hud-chip{position:absolute;width:120px;padding:10px 11px;background:linear-gradient(145deg,#151a1f,#070a0d);border:1px solid #3c454e;clip-path:polygon(0 8px,8px 0,calc(100% - 12px) 0,100% 12px,100% 100%,0 100%);z-index:8}.hud-chip.cpu{left:22px;top:22px}.hud-chip.ram{right:22px;top:22px}.hud-chip .k{font-size:6px;color:#68727c;font-weight:900}.hud-chip .v{font-size:17px;font-weight:1000;margin-top:3px}
.core-caption{position:absolute;bottom:14px;left:50%;transform:translateX(-50%);font-size:6px;color:#616b74;letter-spacing:.12em;font-weight:900}.core-caption b{color:#c1c7cc}
.metric-strip{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}.metric{padding:11px 12px;overflow:hidden}.metric-top{display:flex;justify-content:space-between}.metric .k{font-size:6px;color:#6a747e;font-weight:1000;letter-spacing:.1em}.metric .v{font-size:15px;font-weight:1000}.spark{width:100%;height:58px;margin-top:8px}.spark polyline{fill:none;stroke:#b6bec5;stroke-width:1.5;filter:drop-shadow(0 0 4px rgba(255,255,255,.08))}
.dash-right{display:grid;grid-template-rows:205px minmax(0,1fr) 160px;gap:10px;min-height:0}.quick,.ident,.events{padding:14px}.quick-grid{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-top:10px}
.action{height:56px;border:1px solid #424b54;background:linear-gradient(180deg,#1b2127,#0a0d10);color:#e5e9ec;font-size:8px;font-weight:1000;letter-spacing:.06em;cursor:pointer;clip-path:polygon(0 9px,9px 0,calc(100% - 13px) 0,100% 13px,100% calc(100% - 8px),calc(100% - 8px) 100%,0 100%);transition:.16s}.action:hover{border-color:#aab2b9;background:linear-gradient(180deg,#2a3239,#0e1216);transform:translateY(-1px);box-shadow:0 0 20px rgba(255,255,255,.05)}.action.primary{background:linear-gradient(180deg,#3a4249,#171c21);border-color:#89929b}
.ident-row{display:grid;grid-template-columns:65px 1fr;padding:8px 0;border-bottom:1px solid #1d2329;font-size:7px}.ident-row .k{color:#65707a;font-weight:1000}.ident-row .v{color:#c8ced3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.event-list{margin-top:8px;font:7px/1.7 Consolas,monospace;color:#7d8790}.event-list div{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.two-col{height:calc(100% - 45px);display:grid;grid-template-columns:minmax(0,1fr) 365px;gap:11px;min-height:0}.main-panel,.side-panel{padding:18px;overflow:auto}.hero{display:grid;grid-template-columns:320px 1fr;gap:18px;min-height:260px}.radar-wrap{display:grid;place-items:center}.radar{width:275px;aspect-ratio:1;border-radius:50%;border:1px solid #4c555e;position:relative;background:radial-gradient(circle,rgba(210,220,230,.04),transparent 62%)}.radar:before,.radar:after{content:"";position:absolute;border-radius:50%;border:1px solid rgba(255,255,255,.10);inset:18%}.radar:after{inset:36%}.radar-grid{position:absolute;inset:0;border-radius:50%;background:repeating-conic-gradient(from 0deg,rgba(255,255,255,.12) 0 1deg,transparent 1deg 30deg);mask-image:radial-gradient(circle,transparent 0 2px,#000 3px)}.radar-sweep{position:absolute;inset:5%;border-radius:50%;background:conic-gradient(transparent 0 320deg,rgba(210,220,230,.22) 345deg,transparent 360deg);animation:spin 4s linear infinite}.radar-core{position:absolute;inset:0;display:grid;place-items:center;text-align:center}.radar-core b{font-size:14px}.radar-core span{font-size:6px;color:#737d86;letter-spacing:.1em}.blip{position:absolute;width:4px;height:4px;border-radius:50%;background:#cdd3d8;box-shadow:0 0 10px #fff;animation:pulse 1.4s infinite}.b1{left:27%;top:35%}.b2{left:62%;top:26%;animation-delay:.4s}.b3{left:69%;top:62%;animation-delay:.8s}.b4{left:36%;top:70%;animation-delay:1.1s}
.eyebrow{font-size:7px;color:#9ca5ad;font-weight:1000;letter-spacing:.14em}.hero-copy h2{font-size:27px;margin:5px 0;font-weight:1000;letter-spacing:.05em}.hero-copy p,.side-panel p{font-size:8px;color:#7a848d;line-height:1.62}.stat-lines{border-top:1px solid #242b32;margin-top:14px;padding-top:7px}.stat-line{display:flex;justify-content:space-between;padding:6px 0;font-size:7px;color:#7b858e}.stat-line b{color:#d5dade}
.section-title{font-size:7px;font-weight:1000;letter-spacing:.12em;color:#929ba3;margin:15px 0 9px}.control-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.control{padding:12px;min-height:68px;background:#090d11;border:1px solid #303840;cursor:pointer;clip-path:polygon(0 9px,9px 0,calc(100% - 12px) 0,100% 12px,100% 100%,0 100%);transition:.16s}.control:hover{border-color:#a4adb5;background:#12171c;transform:translateY(-1px)}.control .risk{font-size:6px;font-weight:1000}.control .name{font-size:9px;font-weight:1000;margin-top:4px}.control .desc{font-size:7px;color:#68727c;margin-top:4px;line-height:1.45}.risk.safe{color:var(--green)}.risk.adv{color:var(--amber)}.risk.red{color:var(--red)}
.profile-row{display:grid;grid-template-columns:repeat(3,1fr);gap:9px;margin:15px 0}.profile{padding:14px;min-height:145px;background:#090d11;border:1px solid #343c44;clip-path:polygon(0 11px,11px 0,calc(100% - 16px) 0,100% 16px,100% calc(100% - 9px),calc(100% - 9px) 100%,0 100%)}.profile.safe{border-color:#2b5b47}.profile.comp{border-color:#635028}.profile.black{border-color:#685b61;background:linear-gradient(145deg,#16191d,#080a0d)}.profile .tier{font-size:6px;font-weight:1000}.profile .name{font-size:16px;font-weight:1000;margin:4px 0}.profile .desc{font-size:7px;color:#737d86;line-height:1.45;min-height:38px}
.side-section{margin-bottom:15px}.side-section h3{font-size:8px;margin:0 0 6px;color:#e1e5e8}.side-section p{margin:0}.rule{height:1px;background:#222930;margin:14px 0}
.net-map{height:275px;margin-top:12px;border:1px solid #2d353d;position:relative;overflow:hidden;background:radial-gradient(circle at 50% 50%,rgba(255,255,255,.03),transparent 55%)}.net-map:before{content:"";position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.025) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.025) 1px,transparent 1px);background-size:34px 34px}.node{position:absolute;padding:8px 10px;background:#090c10;border:1px solid #46505a;font-size:7px;font-weight:1000}.n1{left:6%;top:45%}.n2{left:31%;top:45%}.n3{left:57%;top:45%}.n4{left:81%;top:45%}.link{position:absolute;top:50%;height:1px;background:linear-gradient(90deg,#303840,#d2d7db,#303840)}.l1{left:15%;width:17%}.l2{left:40%;width:18%}.l3{left:66%;width:16%}
.storage{width:240px;aspect-ratio:1;border-radius:50%;border:1px solid #434c55;position:relative;background:radial-gradient(circle,#151a1f,#040608 65%);box-shadow:inset 0 0 60px #000}.storage:before,.storage:after{content:"";position:absolute;border-radius:50%;inset:12%;border:2px dashed #4b545d;animation:spin 13s linear infinite}.storage:after{inset:26%;border-style:solid;border-width:1px;animation:spinReverse 8s linear infinite}.storage-core{position:absolute;inset:0;display:grid;place-items:center;text-align:center}.storage-core b{font-size:25px}.storage-core span{display:block;font-size:6px;color:#707a83;margin-top:4px;letter-spacing:.1em}
.energy{display:grid;grid-template-columns:1fr 90px 1fr;gap:12px;align-items:center;margin:22px 0}.energy-card{padding:15px;border:1px solid #394149;background:#090d11}.energy-card b{font-size:14px}.energy-card small{display:block;font-size:6px;color:#6c7680;margin-top:5px}.energy-mid{text-align:center;font-size:22px;color:#b8c0c7;animation:pulse 1.4s infinite}
.timeline{padding-left:24px;position:relative;margin-top:16px}.timeline:before{content:"";position:absolute;left:7px;top:0;bottom:0;width:1px;background:#424b54}.snap{position:relative;padding:10px;background:#090d11;border:1px solid #2e363e;margin-bottom:10px}.snap:before{content:"";position:absolute;left:-21px;top:14px;width:8px;height:8px;border-radius:50%;background:#c7cdd2;box-shadow:0 0 10px rgba(255,255,255,.2)}.snap b{font-size:7px}.snap span{display:block;font-size:6px;color:#6b757e;margin-top:3px}
.lab-banner{padding:14px;background:linear-gradient(90deg,#171b20,#090c0f);border:1px solid #555e67;display:flex;justify-content:space-between;align-items:center}.lab-banner h2{font-size:25px;margin:0}.lab-banner p{font-size:7px;color:#727c85;margin:4px 0 0}.warn-list{margin-top:12px}.warn-item{display:grid;grid-template-columns:27px 1fr;gap:8px;padding:10px;border-bottom:1px solid #232a31}.warn-item .ico{font-size:16px;color:#c9b58d}.warn-item b{font-size:7px}.warn-item p{font-size:7px;margin:3px 0 0;color:#756f69}
.footer{display:grid;grid-template-columns:260px 1fr 420px;align-items:center;padding:0 15px;background:#050709;border-top:1px solid #20272e;font-size:6px;color:#59636d;clip-path:polygon(0 0,24% 0,25% 8px,75% 8px,76% 0,100% 0,100% 100%,0 100%)}.footer b{color:#c5cbd0}.footer-center{text-align:center}.footer-right{text-align:right}
.audio-panel{position:fixed;right:18px;bottom:50px;z-index:150;width:260px;padding:12px;background:#080b0f;border:1px solid #343d45;clip-path:polygon(0 9px,9px 0,100% 0,100% calc(100% - 9px),calc(100% - 9px) 100%,0 100%);display:none}.audio-panel.show{display:block}.audio-title{font-size:7px;font-weight:1000;letter-spacing:.1em}.audio-row{display:grid;grid-template-columns:32px 1fr 34px;align-items:center;gap:7px;margin-top:8px}.audio-row button{height:28px;background:#11161b;border:1px solid #3b444d;color:#d9dee2;cursor:pointer}.audio-row input{width:100%}
.toast{position:fixed;right:18px;bottom:48px;z-index:500;width:340px;padding:13px;background:#080b0f;border:1px solid #46505a;transform:translateX(120%);transition:.3s;clip-path:polygon(0 9px,9px 0,100% 0,100% calc(100% - 9px),calc(100% - 9px) 100%,0 100%)}.toast.show{transform:none}.toast b{font-size:8px}.toast p{font-size:7px;color:#707a83;margin:4px 0 0}
.modal-wrap{position:fixed;inset:0;z-index:600;background:rgba(0,0,0,.78);backdrop-filter:blur(7px);display:none;place-items:center}.modal-wrap.show{display:grid}.modal{width:min(560px,92vw);padding:17px;background:#090d11;border:1px solid #626b74;clip-path:polygon(0 13px,13px 0,calc(100% - 18px) 0,100% 18px,100% calc(100% - 13px),calc(100% - 13px) 100%,0 100%);box-shadow:0 35px 110px #000}.modal h2{font-size:16px;margin:0}.modal .tier{font-size:6px;color:var(--amber);font-weight:1000;letter-spacing:.12em;margin-top:4px}.modal p{font-size:8px;color:#7c868f;line-height:1.6}.exact{padding:9px;background:#040608;border:1px solid #293139;font:7px/1.5 Consolas,monospace;color:#cbd1d6;white-space:pre-wrap}.modal-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:12px}
.shutdown{position:fixed;inset:0;z-index:900;background:#000;display:none;place-items:center;text-align:center}.shutdown.show{display:grid}.shutdown img{width:min(320px,50vw);filter:brightness(.65)}.shutdown h2{font-size:12px;letter-spacing:.35em;margin-top:20px}.shutdown p{font:8px Consolas,monospace;color:#68727c}

@media(max-width:1320px){.work{grid-template-columns:210px 1fr}.rail{padding-left:7px;padding-right:7px}.dash-grid{grid-template-columns:minmax(520px,1fr) 310px}.topbar{grid-template-columns:280px 1fr 370px}.wordmark{max-width:190px}.hero{grid-template-columns:280px 1fr}.radar{width:240px}}
</style>
</head>
<body>
<canvas id="stars"></canvas>
<div class="film"></div><div class="vignette"></div>

<section id="boot" class="screen show">
  <div class="boot-shell">
    <div class="boot-corners"><span class="tl"></span><span class="tr"></span><span class="bl"></span><span class="br"></span></div>
    <div class="boot-emblem-wrap">
      <div class="orbit o1"></div><div class="orbit o2"></div><div class="orbit o3"></div>
      <img class="boot-emblem" src="/asset/emblem.png">
    </div>
    <div class="boot-copy">
      <div class="boot-title">VEXY BLACKSITE SYSTEM ENVIRONMENT</div>
      <div id="bootStatus" class="boot-status">AWAITING INITIALIZATION...</div>
      <div class="progress-track"><div id="progressFill" class="progress-fill"></div></div>
      <div id="bootPercent" class="boot-percent">0%</div>
    </div>
  </div>
</section>

<section id="activation" class="screen">
  <div class="activation-shell">
    <div class="activation-stage">
      <div class="metal-frame"></div>
      <div class="activation-inner">
        <div class="activation-art"><img class="activation-emblem" src="/asset/emblem.png"></div>
        <div class="activation-console">
          <div class="console-kicker">SECURE LICENSE TERMINAL // PRIME-01</div>
          <div class="console-title">VEXY ACCESS</div>
          <div class="console-sub">BLACKSITE PERFORMANCE CONTROL ENVIRONMENT</div>
          <div class="license-label">ACTIVATION KEY</div>
          <div class="key-wrap"><input id="licenseKey" class="key-input" maxlength="64" autocomplete="off" spellcheck="false" placeholder="VEXY-XXXX-XXXX"></div>
          <button id="activateBtn" class="auth-btn">AUTHENTICATE SESSION</button>
          <div id="authState" class="auth-state">LICENSE SERVER // STANDBY</div>
          <div class="auth-grid">
            <div class="auth-row"><span>ADMIN TOKEN</span><b>VERIFIED</b></div>
            <div class="auth-row"><span>RENDER ENGINE</span><b>ONLINE</b></div>
            <div class="auth-row"><span>HARDWARE BUS</span><b id="authHw">LINKED</b></div>
            <div class="auth-row"><span>BACKUP VAULT</span><b>ARMED</b></div>
          </div>
        </div>
      </div>
      <div class="door left"></div><div class="door right"></div>
    </div>
  </div>
</section>

<section id="dashboard" class="screen">
 <div class="app-shell">
  <header class="topbar">
    <div class="brand"><img class="wordmark" src="/asset/logo.png"><div class="brand-copy">BLACKSITE<br>PERFORMANCE CONTROL<br>V5 // CHROMIUM ENGINE</div></div>
    <div class="top-center"><div class="top-kicker">CONTROL NODE // PRIME-01</div><div class="top-title">SYSTEM <span>OPTIMAL</span></div><div class="top-proto">GRAYBOX PROTOCOL // SESSION VERIFIED</div></div>
    <div class="top-right"><div class="top-stat"><div class="k">TIME</div><div id="clock" class="v">00:00:00</div></div><div class="top-stat"><div class="k">UPTIME</div><div id="topUptime" class="v">--</div></div><div class="top-stat"><div class="k">LICENSE</div><div id="licenseState" class="v">ACTIVE</div></div><button id="audioBtn" class="top-btn">♫</button><button id="exitBtn" class="top-btn exit">✕</button></div>
  </header>
  <div class="work">
   <aside class="rail">
    <div class="rail-label">/// SYSTEM MODULES</div>
    <nav class="nav">
      <button class="active" data-page="core"><span class="nav-icon"><i>◈</i></span><span><div class="nav-name">CORE OVERVIEW</div><div class="nav-sub">TELEMETRY MATRIX</div></span></button>
      <button data-page="optimize"><span class="nav-icon"><i>ϟ</i></span><span><div class="nav-name">OPTIMIZATION</div><div class="nav-sub">PROFILES & TWEAKS</div></span></button>
      <button data-page="gaming"><span class="nav-icon"><i>⌁</i></span><span><div class="nav-name">GAMING ENGINE</div><div class="nav-sub">FRAME COMMAND</div></span></button>
      <button data-page="network"><span class="nav-icon"><i>⌘</i></span><span><div class="nav-name">NETWORK GRID</div><div class="nav-sub">TRAFFIC & DNS</div></span></button>
      <button data-page="cleanup"><span class="nav-icon"><i>◇</i></span><span><div class="nav-name">CLEANUP ARRAY</div><div class="nav-sub">STORAGE SWEEP</div></span></button>
      <button data-page="power"><span class="nav-icon"><i>⚡</i></span><span><div class="nav-name">POWER MATRIX</div><div class="nav-sub">POWER POLICY</div></span></button>
      <button data-page="restore"><span class="nav-icon"><i>↶</i></span><span><div class="nav-name">RESTORE VAULT</div><div class="nav-sub">RECOVERY CONTROL</div></span></button>
      <button data-page="lab"><span class="nav-icon"><i>⚠</i></span><span><div class="nav-name">BLACKSITE LAB</div><div class="nav-sub">ADVANCED ZONE</div></span></button>
    </nav>
    <div class="rail-bottom">
      <div class="rail-card"><h4>/// SECURITY INTERLOCK</h4><div class="rrow"><span>ADMIN</span><b class="good">LINKED</b></div><div class="rrow"><span>LOCAL API</span><b class="good">LOOPBACK</b></div><div class="rrow"><span>BACKUP</span><b class="good">ARMED</b></div><div class="rrow"><span>DESTRUCTIVE OPS</span><b class="danger">BLOCKED</b></div></div>
      <div class="rail-card"><h4>/// LICENSE</h4><div class="rrow"><span>STATE</span><b class="good">ACTIVATED</b></div><div class="rrow"><span>SESSION</span><b id="railLicense">VERIFIED</b></div></div>
    </div>
   </aside>
   <main class="content">
    <section id="page-core" class="page active">
      <div class="page-head"><div><div class="page-title">CORE OVERVIEW</div><div class="page-sub">REAL-TIME TELEMETRY // BLACKSITE CONTROL MATRIX</div></div><div class="badges"><span class="badge safe">RISK // SAFE</span><span class="badge">NODE // PRIME</span></div></div>
      <div class="dash-grid">
       <div class="dash-left">
        <div class="frame reactor">
          <div class="reactor-bg"></div><div class="reactor-lines"></div>
          <div class="hud-chip cpu"><div class="k">CPU SIGNAL</div><div id="cpuChip" class="v">--%</div></div>
          <div class="hud-chip ram"><div class="k">MEMORY</div><div id="ramChip" class="v">--%</div></div>
          <div class="core-assembly">
            <div class="core-ring cr1"></div><div class="core-ring cr2"></div><div class="core-ring cr3"></div><div class="core-ring cr4"></div>
            <img class="core-emblem" src="/asset/emblem.png">
            <div class="core-score"><b id="coreScore">92%</b><span id="coreState">SYSTEM NOMINAL</span></div>
          </div>
          <div class="core-caption">MECHANICAL CORE // <b id="arrayState">STABLE</b> // REF 0xV5A9</div>
        </div>
        <div class="metric-strip">
          <div class="frame metric"><div class="metric-top"><span class="k">CPU FRAME</span><span id="cpuMetric" class="v">--%</span></div><svg class="spark" viewBox="0 0 240 60"><polyline id="cpuSpark" points="0,38 20,36 40,42 60,25 80,37 100,30 120,42 140,24 160,34 180,28 200,38 220,32 240,35"/></svg></div>
          <div class="frame metric"><div class="metric-top"><span class="k">RAM LOAD</span><span id="ramMetric" class="v">--%</span></div><svg class="spark" viewBox="0 0 240 60"><polyline id="ramSpark" points="0,36 20,37 40,35 60,34 80,36 100,32 120,33 140,31 160,33 180,30 200,31 220,31 240,32"/></svg></div>
          <div class="frame metric"><div class="metric-top"><span class="k">NETWORK ↓</span><span id="netMetric" class="v">--</span></div><svg class="spark" viewBox="0 0 240 60"><polyline id="netSpark" points="0,45 20,43 40,45 60,39 80,42 100,25 120,44 140,20 160,41 180,30 200,39 220,31 240,35"/></svg></div>
          <div class="frame metric"><div class="metric-top"><span class="k">SESSION UPTIME</span><span id="uptimeMetric" class="v">--</span></div><svg class="spark" viewBox="0 0 240 60"><polyline points="0,44 35,44 42,38 54,44 105,44 114,35 125,44 176,44 187,31 200,44 240,44"/></svg></div>
        </div>
       </div>
       <div class="dash-right">
        <div class="frame quick"><div class="frame-title">QUICK COMMANDS</div><div class="frame-kicker">EXECUTION ARRAY // 04</div><div class="quick-grid"><button class="action primary" data-action="scan">DEEP SCAN</button><button class="action" data-profile="safe">SAFE PROFILE</button><button class="action" data-profile="competitive">COMPETITIVE</button><button class="action" data-action="backup">BACKUP NOW</button></div></div>
        <div class="frame ident"><div class="frame-title">SYSTEM IDENTIFICATION</div><div class="ident-row"><div class="k">OS</div><div id="osText" class="v">DETECTING...</div></div><div class="ident-row"><div class="k">CPU</div><div id="cpuText" class="v">DETECTING...</div></div><div class="ident-row"><div class="k">GPU</div><div id="gpuText" class="v">DETECTING...</div></div><div class="ident-row"><div class="k">RAM</div><div id="ramText" class="v">DETECTING...</div></div><div class="ident-row"><div class="k">BOARD</div><div id="boardText" class="v">DETECTING...</div></div></div>
        <div class="frame events"><div class="frame-title">EVENT STREAM</div><div id="eventList" class="event-list"></div></div>
       </div>
      </div>
    </section>

    <section id="page-optimize" class="page">
      <div class="page-head"><div><div class="page-title">OPTIMIZATION MATRIX</div><div class="page-sub">PROFILE EXECUTION // EXACT CHANGE PREVIEW // BACKUP-FIRST</div></div><div class="badges"><span class="badge adv">RISK // ADVANCED</span><span class="badge">REBOOT // POSSIBLE</span></div></div>
      <div class="two-col"><div class="frame main-panel">
        <div class="hero-copy"><div class="eyebrow">PERFORMANCE CONTROL</div><h2>OPERATING PROFILES</h2><p>Choose a controlled Windows-side profile. VEXY does not promise fixed FPS gains; results depend on hardware, drivers, games, thermals and the actual bottleneck.</p></div>
        <div class="profile-row"><div class="profile safe"><div class="tier risk safe">SAFE</div><div class="name">BASELINE</div><div class="desc">Game Mode, pointer acceleration, Game DVR.</div><button class="action" data-profile="safe">EXECUTE SAFE</button></div><div class="profile comp"><div class="tier risk adv">ADVANCED</div><div class="name">COMPETITIVE</div><div class="desc">Adds HAGS, performance power plan and reduced Windows effects.</div><button class="action" data-profile="competitive">EXECUTE COMP</button></div><div class="profile black"><div class="tier risk red">BLACKSITE</div><div class="name">MAXIMUM</div><div class="desc">Adds USB and NIC power changes. Backup and warning required.</div><button class="action primary" data-profile="blacksite">ARM BLACKSITE</button></div></div>
        <div class="section-title">INDIVIDUAL CONTROL CELLS</div>
        <div class="control-grid"><div class="control" data-action="gameMode"><div class="risk safe">SAFE</div><div class="name">WINDOWS GAME MODE</div><div class="desc">Enable Windows Game Mode.</div></div><div class="control" data-action="mouseAccel"><div class="risk safe">SAFE</div><div class="name">POINTER ACCELERATION</div><div class="desc">Disable Windows pointer acceleration.</div></div><div class="control" data-action="gameDvr"><div class="risk safe">SAFE</div><div class="name">GAME DVR CAPTURE</div><div class="desc">Disable Windows background game recording.</div></div><div class="control" data-action="visuals"><div class="risk safe">SAFE</div><div class="name">VISUAL PERFORMANCE</div><div class="desc">Reduce selected Windows animations/effects.</div></div><div class="control" data-action="hags"><div class="risk adv">ADVANCED</div><div class="name">HARDWARE GPU SCHEDULING</div><div class="desc">Request HAGS; reboot required and results vary.</div></div><div class="control" data-action="ultimatePower"><div class="risk adv">ADVANCED</div><div class="name">ULTIMATE PERFORMANCE</div><div class="desc">Performance power policy; can increase heat/power use.</div></div></div>
      </div><aside class="frame side-panel"><div class="radar-wrap"><div class="radar"><div class="radar-grid"></div><div class="radar-sweep"></div><i class="blip b1"></i><i class="blip b2"></i><i class="blip b3"></i><i class="blip b4"></i><div class="radar-core"><div><b>OPTIMIZE</b><br><span>CONTROL ARRAY</span></div></div></div></div><div class="rule"></div><div class="side-section"><h3>BACKUP FIRST</h3><p>Advanced profiles create a VEXY snapshot and request a Windows restore point when available.</p></div><div class="side-section"><h3>NO MAGIC NUMBERS</h3><p>Use actual frametime/FPS testing to judge whether a change helped your PC.</p></div><button class="action" data-action="openBackups">OPEN BACKUP VAULT</button></aside></div>
    </section>

    <section id="page-gaming" class="page">
      <div class="page-head"><div><div class="page-title">GAMING ENGINE</div><div class="page-sub">FRAME COMMAND // INPUT // WINDOWS-SIDE GAMING CONTROLS</div></div><div class="badges"><span class="badge adv">RISK // ADVANCED</span><span class="badge">FRAME PATH // ACTIVE</span></div></div>
      <div class="two-col"><div class="frame main-panel"><div class="hero"><div class="radar-wrap"><div class="radar"><div class="radar-grid"></div><div class="radar-sweep"></div><i class="blip b1"></i><i class="blip b3"></i><div class="radar-core"><div><b>GAMING</b><br><span>FRAME COMMAND</span></div></div></div></div><div class="hero-copy"><div class="eyebrow">FRAME COMMAND</div><h2>GAMING ENGINE</h2><p>Windows-side controls around capture, scheduling, pointer behavior and power policy. In-game settings, cooling, drivers and stable frametimes remain more important.</p><div class="stat-lines"><div class="stat-line"><span>CPU</span><b id="gameCpu">--</b></div><div class="stat-line"><span>GPU</span><b id="gameGpu">--</b></div><div class="stat-line"><span>DISPLAY PATH</span><b>GAME / DRIVER DEPENDENT</b></div></div></div></div><div class="section-title">FRAME CONTROL CELLS</div><div class="control-grid"><div class="control" data-action="gameMode"><div class="risk safe">SAFE</div><div class="name">GAME MODE</div><div class="desc">Enable Windows Game Mode.</div></div><div class="control" data-action="mouseAccel"><div class="risk safe">SAFE</div><div class="name">POINTER ACCEL OFF</div><div class="desc">Disable Windows mouse acceleration.</div></div><div class="control" data-action="gameDvr"><div class="risk safe">SAFE</div><div class="name">GAME DVR OFF</div><div class="desc">Disable background game capture.</div></div><div class="control" data-action="hags"><div class="risk adv">ADVANCED</div><div class="name">HAGS</div><div class="desc">Hardware GPU Scheduling; reboot required.</div></div><div class="control" data-action="ultimatePower"><div class="risk adv">ADVANCED</div><div class="name">POWER PROFILE</div><div class="desc">Activate performance-oriented power plan.</div></div><div class="control" data-action="visuals"><div class="risk safe">SAFE</div><div class="name">WINDOWS FX</div><div class="desc">Reduce selected desktop effects.</div></div></div></div><aside class="frame side-panel"><div class="side-section"><h3>FRAME TIMES &gt; SCORE</h3><p>Stable frametime delivery matters more than a cosmetic optimizer score.</p></div><div class="rule"></div><div class="side-section"><h3>INPUT</h3><p>Raw input, refresh rate, stable FPS, sensible frame caps and game low-latency options usually matter most.</p></div><div class="rule"></div><div class="side-section"><h3>THERMALS</h3><p>VEXY does not overclock, undervolt or modify firmware.</p></div></aside></div>
    </section>

    <section id="page-network" class="page">
      <div class="page-head"><div><div class="page-title">NETWORK GRID</div><div class="page-sub">ADAPTER TOPOLOGY // LIVE TRAFFIC // DNS CONTROL</div></div><div class="badges"><span class="badge adv">RISK // ADVANCED</span><span class="badge safe">LINK // ONLINE</span></div></div>
      <div class="two-col"><div class="frame main-panel"><div class="hero-copy"><div class="eyebrow">CONNECTION MATRIX</div><h2>NETWORK GRID</h2><p>Live adapter throughput plus transparent maintenance and power controls. DNS affects name resolution; it does not directly change the route to a game server.</p></div><div class="net-map"><div class="link l1"></div><div class="link l2"></div><div class="link l3"></div><div class="node n1">VEXY NODE</div><div class="node n2">ADAPTER</div><div class="node n3">INTERNET</div><div class="node n4">GAME SERVER</div></div><div class="section-title">NETWORK CELLS</div><div class="control-grid"><div class="control" data-action="cloudflareDns"><div class="risk adv">ADVANCED</div><div class="name">CLOUDFLARE DNS</div><div class="desc">Set active IPv4 DNS to 1.1.1.1 / 1.0.0.1.</div></div><div class="control" data-action="nicPower"><div class="risk adv">ADVANCED</div><div class="name">NIC POWER SAVE OFF</div><div class="desc">Request supported adapters stay awake.</div></div><div class="control" data-action="flushDns"><div class="risk safe">SAFE</div><div class="name">FLUSH DNS</div><div class="desc">Clear Windows DNS resolver cache.</div></div><div class="control" data-action="openAdapters"><div class="risk safe">SAFE</div><div class="name">ADAPTER STATUS</div><div class="desc">Open Windows Network Connections.</div></div></div></div><aside class="frame side-panel"><div class="frame-title">LIVE CONNECTION</div><div class="stat-lines"><div class="stat-line"><span>ADAPTER</span><b id="netAdapter">--</b></div><div class="stat-line"><span>DOWNLINK</span><b id="netDown">--</b></div><div class="stat-line"><span>UPLINK</span><b id="netUp">--</b></div></div><div class="rule"></div><div class="side-section"><h3>NO TCP FOLKLORE</h3><p>VEXY avoids blanket Nagle/QoS/BCD recipes copied without good evidence.</p></div></aside></div>
    </section>

    <section id="page-cleanup" class="page">
      <div class="page-head"><div><div class="page-title">CLEANUP ARRAY</div><div class="page-sub">TEMP STORAGE // SAFE CLEANUP // SSD RETRIM</div></div><div class="badges"><span class="badge safe">RISK // SAFE</span><span class="badge">SYSTEM FILES // BLOCKED</span></div></div>
      <div class="two-col"><div class="frame main-panel"><div class="hero"><div class="radar-wrap"><div class="storage"><div class="storage-core"><div><b id="tempCount">--</b><span>TEMP FILES</span></div></div></div></div><div class="hero-copy"><div class="eyebrow">STORAGE SWEEP</div><h2>CLEANUP ARRAY</h2><p>Targets user temporary data only. VEXY does not delete Prefetch, WinSxS, drivers, restore points, browser profiles or Windows components.</p><div class="stat-lines"><div class="stat-line"><span>ANALYSIS</span><b id="tempSize">NOT SCANNED</b></div><div class="stat-line"><span>LOCKED FILE POLICY</span><b>SKIP</b></div></div></div></div><div class="section-title">STORAGE CELLS</div><div class="control-grid"><div class="control" data-action="analyzeTemp"><div class="risk safe">SAFE</div><div class="name">ANALYZE TEMP ARRAY</div><div class="desc">Count temporary files and size.</div></div><div class="control" data-action="cleanTemp"><div class="risk safe">SAFE</div><div class="name">CLEAN TEMP ARRAY</div><div class="desc">Remove deletable temp items; skip locked files.</div></div><div class="control" data-action="retrim"><div class="risk adv">ADVANCED</div><div class="name">SSD RETRIM</div><div class="desc">Request ReTrim on supported fixed volumes.</div></div><div class="control" data-action="openTemp"><div class="risk safe">SAFE</div><div class="name">OPEN TEMP FOLDER</div><div class="desc">Inspect the directory manually.</div></div></div></div><aside class="frame side-panel"><div class="side-section"><h3>PREFETCH</h3><p>VEXY does not routinely wipe Prefetch because deleting it is not a reliable FPS optimization.</p></div><div class="rule"></div><div class="side-section"><h3>SSD TRIM</h3><p>Windows already handles routine optimization. ReTrim simply requests the supported operation.</p></div></aside></div>
    </section>

    <section id="page-power" class="page">
      <div class="page-head"><div><div class="page-title">POWER MATRIX</div><div class="page-sub">POWER POLICY // THERMAL AWARENESS // USB BEHAVIOR</div></div><div class="badges"><span class="badge adv">RISK // ADVANCED</span><span class="badge">THERMALS // WATCH</span></div></div>
      <div class="two-col"><div class="frame main-panel"><div class="hero-copy"><div class="eyebrow">POWER DELIVERY</div><h2>POWER MATRIX</h2><p>Performance-oriented Windows power policies may reduce power-saving behavior. They cannot manufacture extra hardware capability and may increase heat, fan noise or battery drain.</p></div><div class="energy"><div class="energy-card"><b>WINDOWS PLAN</b><small id="powerScheme">DETECTING...</small></div><div class="energy-mid">⇄</div><div class="energy-card"><b>CPU / GPU</b><small>BOOST BEHAVIOR IS HARDWARE DEPENDENT</small></div></div><div class="section-title">POWER CELLS</div><div class="control-grid"><div class="control" data-action="ultimatePower"><div class="risk adv">ADVANCED</div><div class="name">ULTIMATE / HIGH PERFORMANCE</div><div class="desc">Activate a performance-oriented Windows power scheme.</div></div><div class="control" data-action="usbSuspend"><div class="risk adv">ADVANCED</div><div class="name">USB SELECTIVE SUSPEND OFF</div><div class="desc">Disable selective suspend while on AC power.</div></div></div></div><aside class="frame side-panel"><div class="side-section"><h3 class="danger">THERMAL WARNING</h3><p>More aggressive power policies can raise energy use and temperatures. VEXY does not change voltages, clocks, fan curves, BIOS or firmware.</p></div></aside></div>
    </section>

    <section id="page-restore" class="page">
      <div class="page-head"><div><div class="page-title">RESTORE VAULT</div><div class="page-sub">BACKUP SNAPSHOTS // CONFIGURATION RECOVERY // SYSTEM RESTORE</div></div><div class="badges"><span class="badge safe">RISK // SAFE</span><span class="badge">VAULT // ARMED</span></div></div>
      <div class="two-col"><div class="frame main-panel"><div class="hero-copy"><div class="eyebrow">RECOVERY CONTROL</div><h2>RESTORE VAULT</h2><p>VEXY snapshots the settings it knows how to change. Windows System Restore remains the broader operating-system recovery path when available.</p></div><div id="timeline" class="timeline"><div class="snap"><b>VAULT INITIALIZED</b><span>Waiting for backup snapshots...</span></div></div><div class="section-title">RECOVERY CELLS</div><div class="control-grid"><div class="control" data-action="backup"><div class="risk safe">SAFE</div><div class="name">CREATE VEXY BACKUP</div><div class="desc">Snapshot supported settings.</div></div><div class="control" data-action="restorePoint"><div class="risk safe">SAFE</div><div class="name">WINDOWS RESTORE POINT</div><div class="desc">Request a Windows restore checkpoint.</div></div><div class="control" data-action="restoreLatest"><div class="risk adv">ADVANCED</div><div class="name">RESTORE LATEST</div><div class="desc">Restore the newest VEXY snapshot.</div></div><div class="control" data-action="openSystemRestore"><div class="risk safe">SAFE</div><div class="name">OPEN SYSTEM RESTORE</div><div class="desc">Launch Windows recovery UI.</div></div></div></div><aside class="frame side-panel"><div class="frame-title">VAULT STATUS</div><div class="stat-lines"><div class="stat-line"><span>BACKUPS</span><b id="backupCount">0</b></div><div class="stat-line"><span>LATEST</span><b id="latestBackup">NONE</b></div></div><div class="rule"></div><div class="side-section"><h3>ROLLBACK LIMITS</h3><p>VEXY restores values it captured; unrelated driver, firmware, Windows Update or third-party changes are outside this vault.</p></div></aside></div>
    </section>

    <section id="page-lab" class="page">
      <div class="page-head"><div><div class="page-title">BLACKSITE LAB</div><div class="page-sub">BACKUP-GATED ADVANCED CONTROL ZONE</div></div><div class="badges"><span class="badge red">WARNING // ADVANCED</span><span class="badge">INTERLOCK // ARMED</span></div></div>
      <div class="two-col"><div class="frame main-panel"><div class="lab-banner"><div><h2>BLACKSITE PROTOCOL</h2><p>AGGRESSIVE BUT REVERSIBLE WINDOWS-SIDE CONTROL CELLS</p></div><span class="badge red">⚠ CAUTION</span></div><div class="warn-list"><div class="warn-item"><div class="ico">⚠</div><div><b>POWER / THERMALS</b><p>Performance plans and disabled power saving may increase heat, fan noise and energy use.</p></div></div><div class="warn-item"><div class="ico">⚠</div><div><b>DRIVER DEPENDENCE</b><p>HAGS and adapter power options may help, hurt or do nothing depending on hardware/drivers.</p></div></div><div class="warn-item"><div class="ico">⛔</div><div><b>DESTRUCTIVE OPERATIONS BLOCKED</b><p>No security disabling, firmware writes, voltage changes, boot hacks or Windows component deletion.</p></div></div></div><div class="section-title">BLACKSITE CELLS</div><div class="control-grid"><div class="control" data-action="hags"><div class="risk adv">ADVANCED</div><div class="name">HAGS // REBOOT</div><div class="desc">Hardware GPU Scheduling request.</div></div><div class="control" data-action="ultimatePower"><div class="risk adv">ADVANCED</div><div class="name">ULTIMATE POWER</div><div class="desc">Performance-oriented power policy.</div></div><div class="control" data-action="usbSuspend"><div class="risk adv">ADVANCED</div><div class="name">USB SUSPEND OFF</div><div class="desc">Disable USB selective suspend on AC.</div></div><div class="control" data-action="nicPower"><div class="risk adv">ADVANCED</div><div class="name">NIC POWER SAVE OFF</div><div class="desc">Request supported adapters remain awake.</div></div></div><button class="action primary" style="width:100%;margin-top:11px" data-profile="blacksite">⚠ ARM FULL BLACKSITE PROFILE</button></div><aside class="frame side-panel"><div class="radar-wrap"><div class="radar"><div class="radar-grid"></div><div class="radar-sweep"></div><i class="blip b1"></i><i class="blip b2"></i><i class="blip b3"></i><i class="blip b4"></i><div class="radar-core"><div><b>BLACKSITE</b><br><span>RESTRICTED ARRAY</span></div></div></div></div><div class="rule"></div><div class="side-section"><h3>INTERLOCK PROTOCOL</h3><p>Backup → restore point when available → confirmation → execute → reboot if flagged → test the real game.</p></div></aside></div>
    </section>
   </main>
  </div>
  <footer class="footer"><div>/// VEXY <b>BLACKSITE V5</b></div><div class="footer-center">RENDER: CHROMIUM // API: LOOPBACK // SESSION: VERIFIED</div><div class="footer-right">ADVANCED SETTINGS CAN AFFECT POWER / HEAT / COMPATIBILITY</div></footer>
 </div>
</section>

<div id="audioPanel" class="audio-panel"><div class="audio-title">♫ VEXY AUDIO ENGINE</div><div class="audio-row"><button id="playPause">❚❚</button><input id="volume" type="range" min="0" max="100" value="24"><span id="volLabel">24%</span></div></div>
<audio id="music" loop preload="auto" src="https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/main/vexy_music%20(2).mp3"></audio>
<div id="toast" class="toast"><b id="toastTitle">VEXY</b><p id="toastBody"></p></div>
<div id="modal" class="modal-wrap"><div class="modal"><h2 id="modalTitle">CONFIRM ACTION</h2><div id="modalTier" class="tier">ADVANCED</div><p id="modalBody"></p><div id="modalExact" class="exact"></div><div class="modal-actions"><button id="modalCancel" class="action">CANCEL</button><button id="modalConfirm" class="action primary">CONFIRM</button></div></div></div>
<div id="shutdown" class="shutdown"><div><img src="/asset/logo.png"><h2>TERMINATING VEXY SESSION</h2><p id="shutdownState">SAVING SESSION...</p></div></div>

<script>
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const token=new URLSearchParams(location.search).get('token')||'';
const S={events:[],spark:{cpu:[],ram:[],net:[]},pending:null,licensed:false,audioStarted:false};

function screen(id){$$('.screen').forEach(x=>x.classList.remove('show'));$('#'+id).classList.add('show')}
function log(msg){const t=new Date().toLocaleTimeString('en-GB');S.events.unshift(`[${t}] ${msg}`);S.events=S.events.slice(0,8);if($('#eventList'))$('#eventList').innerHTML=S.events.map(x=>`<div>${x}</div>`).join('')}
function toast(title,body){$('#toastTitle').textContent=title;$('#toastBody').textContent=body;$('#toast').classList.add('show');setTimeout(()=>$('#toast').classList.remove('show'),3000)}
async function api(path,method='GET',body=null){const opt={method,headers:{'X-Vexy-Token':token}};if(body){opt.headers['Content-Type']='application/json';opt.body=JSON.stringify(body)}const r=await fetch(path,opt);const txt=await r.text();let d;try{d=JSON.parse(txt)}catch{throw new Error(txt||`HTTP ${r.status}`)}if(!r.ok||d.ok===false)throw new Error(d.message||`HTTP ${r.status}`);return d}

function startStars(){
 const c=$('#stars'),ctx=c.getContext('2d');let stars=[];
 function resize(){c.width=innerWidth*devicePixelRatio;c.height=innerHeight*devicePixelRatio;ctx.setTransform(devicePixelRatio,0,0,devicePixelRatio,0,0)}
 function reset(s,far=false){s.x=(Math.random()-.5)*innerWidth*1.8;s.y=(Math.random()-.5)*innerHeight*1.8;s.z=far?Math.random()*innerWidth:innerWidth;s.pz=s.z;s.b=.2+Math.random()*.8}
 function init(){stars=Array.from({length:320},()=>{const s={};reset(s,true);return s})}
 function frame(){ctx.fillStyle='rgba(0,0,0,.36)';ctx.fillRect(0,0,innerWidth,innerHeight);const cx=innerWidth/2,cy=innerHeight/2;for(const s of stars){s.pz=s.z;s.z-=3.0;if(s.z<1)reset(s);const x=cx+s.x/s.z*innerWidth,y=cy+s.y/s.z*innerWidth,px=cx+s.x/s.pz*innerWidth,py=cy+s.y/s.pz*innerWidth;if(x<0||x>innerWidth||y<0||y>innerHeight){reset(s);continue}const a=(1-s.z/innerWidth)*s.b;ctx.strokeStyle=`rgba(210,218,225,${Math.max(.04,a)})`;ctx.lineWidth=Math.max(.3,(1-s.z/innerWidth)*1.6);ctx.beginPath();ctx.moveTo(px,py);ctx.lineTo(x,y);ctx.stroke()}requestAnimationFrame(frame)}
 addEventListener('resize',()=>{resize();init()});resize();init();frame()
}
startStars();

const bootSteps=['INITIALIZING CHROMIUM RENDER ENGINE','VERIFYING ADMIN TOKEN','ENUMERATING HARDWARE BUS','CONNECTING TELEMETRY CHANNEL','ARMING BACKUP VAULT','LOADING OPTIMIZATION MODULES','ESTABLISHING BLACKSITE SESSION','SYSTEM READY'];
async function runBoot(){let p=0,i=0;const timer=setInterval(()=>{p+=1+Math.random()*2.8;if(p>100)p=100;$('#progressFill').style.width=p+'%';$('#bootPercent').textContent=Math.floor(p)+'%';const ni=Math.min(bootSteps.length-1,Math.floor(p/(100/bootSteps.length)));if(ni!==i||p<4){i=ni;$('#bootStatus').textContent=bootSteps[i]+' ........ '+(p>96?'OK':'IN PROGRESS')}if(p>=100){clearInterval(timer);$('#bootStatus').textContent='SYSTEM ENVIRONMENT INITIALIZED ........ OK';setTimeout(()=>{screen('activation');$('#activation').classList.add('fade-in');$('#licenseKey').focus()},700)}},55)}
setTimeout(runBoot,500);

const music=$('#music');music.volume=.24;
async function primeMusic(){if(S.audioStarted)return;try{music.volume=0;await music.play();S.audioStarted=true}catch{}}
function fadeMusic(target=.24){let v=music.volume;const t=setInterval(()=>{v+=.018;if(v>=target){v=target;clearInterval(t)}music.volume=v},65)}

$('#activateBtn').addEventListener('click',async()=>{
 await primeMusic();
 const key=$('#licenseKey').value.trim().toUpperCase();if(!key){$('#authState').textContent='ACTIVATION KEY REQUIRED';$('#authState').className='auth-state access-denied';return}
 $('#authState').textContent='VERIFYING LICENSE SIGNATURE...';$('#authState').className='auth-state';
 try{
  const d=await api('/api/activate','POST',{key});
  S.licensed=true;$('#authState').textContent=`ACCESS GRANTED // ${d.label}`;$('#authState').className='auth-state access-granted';
  $('#licenseState').textContent=d.label;$('#railLicense').textContent=d.label;fadeMusic(.24);
  setTimeout(()=>{$$('.door').forEach(x=>x.classList.add('open'));setTimeout(()=>{screen('dashboard');$('#dashboard').classList.add('fade-in');log('License signature accepted');log('VEXY BLACKSITE environment online');poll()},780)},500)
 }catch(e){music.pause();music.currentTime=0;S.audioStarted=false;$('#authState').textContent='ACCESS DENIED // '+e.message.toUpperCase();$('#authState').className='auth-state access-denied';toast('ACCESS DENIED',e.message)}
});
$('#licenseKey').addEventListener('keydown',e=>{if(e.key==='Enter')$('#activateBtn').click()});

$$('.nav button').forEach(b=>b.onclick=()=>{$$('.nav button').forEach(x=>x.classList.toggle('active',x===b));$$('.page').forEach(x=>x.classList.toggle('active',x.id==='page-'+b.dataset.page))});

const meta={
gameMode:['WINDOWS GAME MODE','SAFE','Enable Windows Game Mode.','HKCU\\\\Software\\\\Microsoft\\\\GameBar\\\\AutoGameModeEnabled = 1'],
mouseAccel:['POINTER ACCELERATION','SAFE','Disable the Windows pointer acceleration curve.','MouseSpeed / MouseThreshold1 / MouseThreshold2 = 0'],
gameDvr:['GAME DVR CAPTURE','SAFE','Disable Windows background game recording.','GameDVR_Enabled = 0; AllowGameDVR = 0'],
visuals:['VISUAL PERFORMANCE','SAFE','Reduce selected Windows animations and effects.','VisualFXSetting = 2; TaskbarAnimations = 0; MinAnimate = 0'],
hags:['HARDWARE GPU SCHEDULING','ADVANCED','Request HAGS. Results vary by GPU/driver/game and a reboot is required.','HKLM\\\\...\\\\GraphicsDrivers\\\\HwSchMode = 2'],
ultimatePower:['ULTIMATE PERFORMANCE','ADVANCED','Activate Ultimate/High Performance. This can increase idle power use, heat or fan activity.','powercfg -> Ultimate Performance / High Performance'],
usbSuspend:['USB SELECTIVE SUSPEND','ADVANCED','Disable USB selective suspend on AC power.','Current AC plan: USB selective suspend = Disabled'],
nicPower:['NIC POWER SAVING','ADVANCED','Request supported network adapters stay awake. Driver support varies.','AllowComputerToTurnOffDevice = Disabled'],
cloudflareDns:['CLOUDFLARE DNS','ADVANCED','Set active IPv4 DNS to Cloudflare. This changes name resolution, not direct game-server routing.','DNS = 1.1.1.1 / 1.0.0.1'],
retrim:['SSD RETRIM','ADVANCED','Request ReTrim on supported fixed volumes. Windows already performs routine optimization.','Optimize-Volume -ReTrim'],
cleanTemp:['CLEAN TEMP ARRAY','SAFE','Remove deletable user temporary items. Locked files are skipped.','Delete deletable items under %TEMP% only'],
restoreLatest:['RESTORE LATEST BACKUP','ADVANCED','Restore supported VEXY settings from the newest snapshot.','Restore captured registry, DNS and power-plan values']
};
function confirmBox(title,tier,body,exact,fn){$('#modalTitle').textContent=title;$('#modalTier').textContent=tier;$('#modalBody').textContent=body;$('#modalExact').textContent=exact||'';S.pending=fn;$('#modal').classList.add('show')}
$('#modalCancel').onclick=()=>{$('#modal').classList.remove('show');S.pending=null};$('#modalConfirm').onclick=()=>{$('#modal').classList.remove('show');const f=S.pending;S.pending=null;if(f)f()};

async function runAction(id){try{if(id==='scan')playScan();log('Command requested // '+id);const d=await api('/api/action','POST',{action:id});log(d.message||'Command complete');toast('VEXY COMMAND',d.message||'Completed');if(d.temp){$('#tempCount').textContent=d.temp.count;$('#tempSize').textContent=d.temp.display}if(d.backups)updateVault(d.backups)}catch(e){log('ERROR // '+e.message);toast('VEXY ERROR',e.message)}}
function triggerAction(id){const m=meta[id];if(m)confirmBox(m[0],m[1],m[2],m[3],()=>runAction(id));else runAction(id)}
$$('[data-action]').forEach(x=>x.addEventListener('click',()=>triggerAction(x.dataset.action)));
$$('[data-profile]').forEach(x=>x.addEventListener('click',()=>{const p=x.dataset.profile;const adv=p!=='safe';const body=p==='blacksite'?'Applies safe gaming changes plus HAGS, performance power policy, visual changes, USB selective suspend and NIC power behavior. It may increase heat/power use or be neutral/worse on some hardware.':'Creates a VEXY backup first. Advanced profiles also request a Windows restore point when available.';confirmBox((p==='blacksite'?'BLACKSITE':p.toUpperCase())+' PROFILE',adv?'ADVANCED':'SAFE',body,'Profile: '+p.toUpperCase(),()=>runAction('profile:'+p))}));

function playScan(){const score=$('#coreScore'),state=$('#coreState'),arr=$('#arrayState');state.textContent='DEEP ANALYSIS';arr.textContent='SCANNING';let n=0;const t=setInterval(()=>{n+=2+Math.floor(Math.random()*5);if(n>100)n=100;score.textContent=n+'%';if(n>=100){clearInterval(t);setTimeout(()=>{score.textContent='92%';state.textContent='SYSTEM NOMINAL';arr.textContent='STABLE'},500)}},38)}
function updateSpark(id,a,v){a.push(Number(v)||0);if(a.length>22)a.shift();const w=240,h=60;$(id).setAttribute('points',a.map((x,i)=>`${i*w/Math.max(1,a.length-1)},${h-7-Math.min(100,x)/100*(h-18)}`).join(' '))}
function fmtUp(s){s=Math.max(0,+s||0);const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return d?`${d}d ${h}h`:`${h}h ${m}m`}
function updateVault(v){if(!v)return;$('#backupCount').textContent=v.count??0;$('#latestBackup').textContent=v.latest||'NONE';if(v.items)$('#timeline').innerHTML=v.items.length?v.items.slice(0,7).map(x=>`<div class="snap"><b>${x.name}</b><span>${x.time}</span></div>`).join(''):'<div class="snap"><b>VAULT EMPTY</b><span>No snapshots found.</span></div>'}
async function poll(){if(!S.licensed)return;try{const d=await api('/api/status');const cpu=Math.round(d.cpu||0),ram=Math.round(d.ram||0);$('#cpuChip').textContent=cpu+'%';$('#ramChip').textContent=ram+'%';$('#cpuMetric').textContent=cpu+'%';$('#ramMetric').textContent=ram+'%';$('#netMetric').textContent=(d.netDown||0).toFixed(1);const up=fmtUp(d.uptimeSeconds);$('#uptimeMetric').textContent=up;$('#topUptime').textContent=up;$('#osText').textContent=d.hardware?.os||'Windows';$('#cpuText').textContent=d.hardware?.cpu||'--';$('#gpuText').textContent=d.hardware?.gpu||'--';$('#ramText').textContent=d.hardware?.ram||'--';$('#boardText').textContent=d.hardware?.board||'--';$('#gameCpu').textContent=d.hardware?.cpu||'--';$('#gameGpu').textContent=d.hardware?.gpu||'--';$('#netAdapter').textContent=d.adapter||'--';$('#netDown').textContent=(d.netDown||0).toFixed(2)+' Mbps';$('#netUp').textContent=(d.netUp||0).toFixed(2)+' Mbps';$('#powerScheme').textContent=d.powerScheme||'--';updateSpark('#cpuSpark',S.spark.cpu,cpu);updateSpark('#ramSpark',S.spark.ram,ram);updateSpark('#netSpark',S.spark.net,Math.min(100,d.netDown||0));updateVault(d.backups)}catch(e){}}
setInterval(poll,1000);setInterval(()=>$('#clock').textContent=new Date().toLocaleTimeString('en-GB'),1000);

$('#audioBtn').onclick=()=>$('#audioPanel').classList.toggle('show');
$('#volume').oninput=e=>{music.volume=e.target.value/100;$('#volLabel').textContent=e.target.value+'%'};
$('#playPause').onclick=async()=>{if(music.paused){try{await music.play();$('#playPause').textContent='❚❚'}catch{}}else{music.pause();$('#playPause').textContent='▶'}};

async function shutdown(){if($('#shutdown').classList.contains('show'))return;$('#shutdown').classList.add('show');const s=$('#shutdownState');const steps=['SAVING SESSION...','CLOSING TELEMETRY BUS...','SECURING BACKUP VAULT...','STOPPING AUDIO ENGINE...','SESSION TERMINATED'];let i=0;const iv=setInterval(()=>{s.textContent=steps[Math.min(++i,steps.length-1)];if(i>=steps.length-1){clearInterval(iv);music.pause();setTimeout(async()=>{try{await api('/api/exit','POST',{})}catch{};window.close()},550)}},420)}
$('#exitBtn').onclick=()=>confirmBox('TERMINATE VEXY SESSION','SAFE','Close the VEXY environment using the controlled shutdown sequence.','Telemetry → backup vault → audio → local API',shutdown);
window.addEventListener('beforeunload',e=>{if(S.licensed){e.preventDefault();e.returnValue=''}});

log('VEXY V5 frontend initialized');
</script>
</body>
</html>
'@

$script:AssetBaseUrl = 'https://raw.githubusercontent.com/user39583453543/Vexy-Optimizer/refs/heads/main'
$script:LogoUrl = "$($script:AssetBaseUrl)/vexy_logo_gray.png"
$script:EmblemUrl = "$($script:AssetBaseUrl)/vexy_emblem.png"

$script:LogoCache = Join-Path $script:RuntimeRoot 'vexy_logo_gray.png'
$script:EmblemCache = Join-Path $script:RuntimeRoot 'vexy_emblem.png'

function Get-VexyRemoteAsset {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name
    )

    $needsDownload = $true

    if (Test-Path -LiteralPath $Path) {
        try {
            $existing = [IO.File]::ReadAllBytes($Path)
            if (
                $existing.Length -gt 8 -and
                $existing[0] -eq 0x89 -and
                $existing[1] -eq 0x50 -and
                $existing[2] -eq 0x4E -and
                $existing[3] -eq 0x47
            ) {
                $needsDownload = $false
            }
        }
        catch {
            $needsDownload = $true
        }
    }

    if ($needsDownload) {
        try {
            Invoke-WebRequest `
                -UseBasicParsing `
                -Uri $Url `
                -OutFile $Path `
                -TimeoutSec 30 `
                -ErrorAction Stop
        }
        catch {
            throw "VEXY could not download $Name from GitHub. Make sure '$Name' exists in the repo root. $($_.Exception.Message)"
        }
    }

    try {
        $bytes = [IO.File]::ReadAllBytes($Path)

        if (
            $bytes.Length -lt 8 -or
            $bytes[0] -ne 0x89 -or
            $bytes[1] -ne 0x50 -or
            $bytes[2] -ne 0x4E -or
            $bytes[3] -ne 0x47
        ) {
            throw 'downloaded file is not a PNG'
        }

        return $bytes
    }
    catch {
        throw "VEXY asset validation failed for $Name. $($_.Exception.Message)"
    }
}

$script:LogoBytes = Get-VexyRemoteAsset `
    -Url $script:LogoUrl `
    -Path $script:LogoCache `
    -Name 'vexy_logo_gray.png'

$script:EmblemBytes = Get-VexyRemoteAsset `
    -Url $script:EmblemUrl `
    -Path $script:EmblemCache `
    -Name 'vexy_emblem.png'

# ----------------------------------------------------------------------
# ACTIVATION
# ----------------------------------------------------------------------
$script:ValidLicenseHashes = @{
    'BF4C904D77DF675DF481BBBC72C48090E3774BE4DA256BD9BFA79217BD5405F9' = @{ Days = 7; Label = 'TRIAL // 7D' }
    'A6152580B752C30020FDAD7D11A6A30FA54D79EE336A1F6D89BB9F03CBB0F46B' = @{ Days = 30; Label = 'PRIME // 30D' }
    'CBE620C8D6BB8541CE64A263D555B327F13285B8B133AAB8881D03E552774719' = @{ Days = 3650; Label = 'BLACKSITE // LIFE' }
}

$script:Activated = $false
$script:LicenseLabel = 'INACTIVE'
$script:LicenseExpires = $null

function Get-VexySha256 {
    param([string]$Text)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-','').ToUpperInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-VexyLicense {
    param([string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw 'Activation key required.'
    }

    $normalized = $Key.Trim().ToUpperInvariant()
    $hash = Get-VexySha256 $normalized

    if (-not $script:ValidLicenseHashes.ContainsKey($hash)) {
        throw 'Invalid activation key.'
    }

    $record = $script:ValidLicenseHashes[$hash]
    $script:Activated = $true
    $script:LicenseLabel = [string]$record.Label
    $script:LicenseExpires = (Get-Date).AddDays([int]$record.Days)

    $saved = [ordered]@{
        label = $script:LicenseLabel
        activatedAt = (Get-Date).ToString('o')
        expiresAt = $script:LicenseExpires.ToString('o')
        keyHash = $hash
    }

    try {
        $saved | ConvertTo-Json | Set-Content -Path $script:LicenseFile -Encoding UTF8 -Force
    }
    catch {}

    return [ordered]@{
        ok = $true
        label = $script:LicenseLabel
        expiresAt = $script:LicenseExpires.ToString('o')
    }
}

# ----------------------------------------------------------------------
# FAST MEMORY API
# ----------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'VexyNative.MemoryApi').Type) {
    Add-Type -Namespace VexyNative -Name MemoryApi -Language CSharp -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public class MEMORYSTATUSEX
{
    public uint dwLength = (uint)System.Runtime.InteropServices.Marshal.SizeOf(typeof(MEMORYSTATUSEX));
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}

[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
public static extern bool GlobalMemoryStatusEx(
    [System.Runtime.InteropServices.In, System.Runtime.InteropServices.Out] MEMORYSTATUSEX buffer
);
'@
}

# ----------------------------------------------------------------------
# HTTP HELPERS
# ----------------------------------------------------------------------
function Send-VexyBytes {
    param(
        [System.Net.HttpListenerContext]$Context,
        [byte[]]$Bytes,
        [string]$ContentType = 'application/octet-stream',
        [int]$StatusCode = 200
    )

    try {
        $Context.Response.StatusCode = $StatusCode
        $Context.Response.ContentType = $ContentType
        $Context.Response.ContentLength64 = $Bytes.Length
        $Context.Response.Headers['Cache-Control'] = 'no-store'
        $Context.Response.OutputStream.Write($Bytes,0,$Bytes.Length)
        $Context.Response.OutputStream.Close()
    }
    catch {}
}

function Send-VexyText {
    param(
        [System.Net.HttpListenerContext]$Context,
        [string]$Text,
        [string]$ContentType = 'text/plain; charset=utf-8',
        [int]$StatusCode = 200
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    Send-VexyBytes -Context $Context -Bytes $bytes -ContentType $ContentType -StatusCode $StatusCode
}

function Send-VexyJson {
    param(
        [System.Net.HttpListenerContext]$Context,
        $Object,
        [int]$StatusCode = 200
    )

    $text = $Object | ConvertTo-Json -Depth 12 -Compress
    Send-VexyText -Context $Context -Text $text -ContentType 'application/json; charset=utf-8' -StatusCode $StatusCode
}

# ----------------------------------------------------------------------
# BACKUP ENGINE
# ----------------------------------------------------------------------
function Get-RegValueState {
    param([string]$Path,[string]$Name)

    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [ordered]@{
            exists = $true
            value = $item.$Name
        }
    }
    catch {
        return [ordered]@{
            exists = $false
            value = $null
        }
    }
}

function Restore-RegValueState {
    param(
        [string]$Path,
        [string]$Name,
        $State,
        [string]$Type = 'DWord'
    )

    try {
        if ($State.exists) {
            New-Item -Path $Path -Force | Out-Null
            Set-ItemProperty -Path $Path -Name $Name -Value $State.value -Type $Type -Force
        }
        else {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Get-ActivePowerGuid {
    try {
        $raw = powercfg /getactivescheme 2>$null | Out-String
        $match = [regex]::Match($raw,'[0-9a-fA-F-]{36}')

        if ($match.Success) {
            return $match.Value
        }
    }
    catch {}

    return $null
}

function Get-ActiveDnsSnapshot {
    $rows = @()

    try {
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Up' } |
            ForEach-Object {
                $dns = Get-DnsClientServerAddress `
                    -InterfaceIndex $_.IfIndex `
                    -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue

                $rows += [pscustomobject]@{
                    interfaceIndex = $_.IfIndex
                    name = $_.Name
                    servers = @($dns.ServerAddresses)
                }
            }
    }
    catch {}

    return $rows
}

function Get-VexyBackups {
    $all = @(
        Get-ChildItem -Path $script:BackupRoot -Filter 'vexy_backup_*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    )

    $items = @(
        $all |
        Select-Object -First 8 |
        ForEach-Object {
            [ordered]@{
                name = $_.Name
                time = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            }
        }
    )

    return [ordered]@{
        count = $all.Count
        latest = if ($all.Count -gt 0) { $all[0].Name } else { $null }
        items = $items
    }
}

function New-VexyBackup {
    param([string]$Reason = 'Manual backup')

    $path = Join-Path $script:BackupRoot (
        'vexy_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json'
    )

    $snapshot = [ordered]@{
        version = 5
        created = (Get-Date).ToString('o')
        reason = $Reason
        computer = $env:COMPUTERNAME
        powerGuid = Get-ActivePowerGuid
        dns = @(Get-ActiveDnsSnapshot)

        registry = [ordered]@{
            hags = Get-RegValueState 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
            gameMode = Get-RegValueState 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
            gameDvr = Get-RegValueState 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
            gameDvrPolicy = Get-RegValueState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'

            mouseSpeed = Get-RegValueState 'HKCU:\Control Panel\Mouse' 'MouseSpeed'
            mouseT1 = Get-RegValueState 'HKCU:\Control Panel\Mouse' 'MouseThreshold1'
            mouseT2 = Get-RegValueState 'HKCU:\Control Panel\Mouse' 'MouseThreshold2'

            visualFx = Get-RegValueState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
            taskbarAnimations = Get-RegValueState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations'
            minAnimate = Get-RegValueState 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate'
        }
    }

    $snapshot |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $path -Encoding UTF8 -Force

    return "Backup created: $([IO.Path]::GetFileName($path))"
}

function Restore-LatestVexyBackup {
    $file = Get-ChildItem -Path $script:BackupRoot -Filter 'vexy_backup_*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $file) {
        return 'No VEXY backup found.'
    }

    try {
        $data = Get-Content $file.FullName -Raw | ConvertFrom-Json

        Restore-RegValueState 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $data.registry.hags
        Restore-RegValueState 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' $data.registry.gameMode
        Restore-RegValueState 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' $data.registry.gameDvr
        Restore-RegValueState 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' $data.registry.gameDvrPolicy

        Restore-RegValueState 'HKCU:\Control Panel\Mouse' 'MouseSpeed' $data.registry.mouseSpeed 'String'
        Restore-RegValueState 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' $data.registry.mouseT1 'String'
        Restore-RegValueState 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' $data.registry.mouseT2 'String'

        Restore-RegValueState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $data.registry.visualFx
        Restore-RegValueState 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' $data.registry.taskbarAnimations
        Restore-RegValueState 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' $data.registry.minAnimate 'String'

        if ($data.powerGuid) {
            powercfg /setactive $data.powerGuid 2>$null | Out-Null
        }

        foreach ($row in @($data.dns)) {
            try {
                if ($row.servers -and @($row.servers).Count -gt 0) {
                    Set-DnsClientServerAddress `
                        -InterfaceIndex ([int]$row.interfaceIndex) `
                        -ServerAddresses @($row.servers) `
                        -ErrorAction SilentlyContinue
                }
                else {
                    Set-DnsClientServerAddress `
                        -InterfaceIndex ([int]$row.interfaceIndex) `
                        -ResetServerAddresses `
                        -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }

        return "Restored: $($file.Name). Reboot/sign-out may be required."
    }
    catch {
        return "Restore failed: $($_.Exception.Message)"
    }
}

function New-VexyRestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue

        Checkpoint-Computer `
            -Description 'VEXY BLACKSITE V5 - Pre Optimization' `
            -RestorePointType MODIFY_SETTINGS `
            -ErrorAction Stop

        return 'Windows restore point created.'
    }
    catch {
        return "Restore point unavailable or rate-limited: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------
# OPTIMIZATION ACTIONS
# ----------------------------------------------------------------------
function Set-VexyGameMode {
    New-Item 'HKCU:\Software\Microsoft\GameBar' -Force | Out-Null

    Set-ItemProperty `
        'HKCU:\Software\Microsoft\GameBar' `
        -Name AutoGameModeEnabled `
        -Type DWord `
        -Value 1 `
        -Force

    return 'Windows Game Mode enabled.'
}

function Disable-VexyMouseAcceleration {
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseSpeed -Value '0' -Force
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold1 -Value '0' -Force
    Set-ItemProperty 'HKCU:\Control Panel\Mouse' -Name MouseThreshold2 -Value '0' -Force

    return 'Windows pointer acceleration disabled.'
}

function Disable-VexyGameDvr {
    New-Item 'HKCU:\System\GameConfigStore' -Force | Out-Null
    New-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Force | Out-Null

    Set-ItemProperty `
        'HKCU:\System\GameConfigStore' `
        -Name GameDVR_Enabled `
        -Type DWord `
        -Value 0 `
        -Force

    Set-ItemProperty `
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' `
        -Name AllowGameDVR `
        -Type DWord `
        -Value 0 `
        -Force

    return 'Game DVR background capture disabled.'
}

function Set-VexyVisualPerformance {
    New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Force | Out-Null
    New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Force | Out-Null
    New-Item 'HKCU:\Control Panel\Desktop\WindowMetrics' -Force | Out-Null

    Set-ItemProperty `
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' `
        -Name VisualFXSetting `
        -Type DWord `
        -Value 2 `
        -Force

    Set-ItemProperty `
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Name TaskbarAnimations `
        -Type DWord `
        -Value 0 `
        -Force

    Set-ItemProperty `
        'HKCU:\Control Panel\Desktop\WindowMetrics' `
        -Name MinAnimate `
        -Value '0' `
        -Force

    return 'Selected Windows visual effects reduced.'
}

function Set-VexyHags {
    New-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Force | Out-Null

    Set-ItemProperty `
        'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
        -Name HwSchMode `
        -Type DWord `
        -Value 2 `
        -Force

    return 'Hardware GPU Scheduling requested. Reboot required; results vary by GPU/driver/game.'
}

function Set-VexyUltimatePower {
    $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'

    if (-not (powercfg /list 2>$null | Select-String $ultimate)) {
        powercfg -duplicatescheme $ultimate 2>$null | Out-Null
    }

    powercfg /setactive $ultimate 2>$null | Out-Null

    if ($LASTEXITCODE -ne 0) {
        powercfg /setactive SCHEME_MIN 2>$null | Out-Null
    }

    $script:PowerCacheTime = [datetime]::MinValue

    return 'Ultimate/High Performance activated. Higher power use, heat or fan activity is possible.'
}

function Disable-VexyUsbSuspend {
    powercfg /setacvalueindex `
        SCHEME_CURRENT `
        2a737441-1930-4402-8d77-b2bebba308a3 `
        48e6b7a6-50f5-4782-a5d4-53bb8f07e226 `
        0 2>$null | Out-Null

    powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null

    return 'USB selective suspend disabled while on AC power.'
}

function Disable-VexyNicPower {
    $count = 0

    Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'Disabled' } |
        ForEach-Object {
            try {
                Set-NetAdapterPowerManagement `
                    -Name $_.Name `
                    -AllowComputerToTurnOffDevice Disabled `
                    -ErrorAction Stop

                $count++
            }
            catch {}
        }

    return "NIC power-saving change attempted on $count adapter(s). Driver support varies."
}

function Set-VexyCloudflareDns {
    $count = 0

    Get-NetAdapter -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq 'Up' } |
        ForEach-Object {
            try {
                Set-DnsClientServerAddress `
                    -InterfaceIndex $_.IfIndex `
                    -ServerAddresses @('1.1.1.1','1.0.0.1') `
                    -ErrorAction Stop

                $count++
            }
            catch {}
        }

    return "Cloudflare DNS applied to $count active adapter(s). This changes name resolution, not direct game-server routing."
}

function Invoke-VexyReTrim {
    $completed = @()

    Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } |
        ForEach-Object {
            try {
                Optimize-Volume `
                    -DriveLetter $_.DriveLetter `
                    -ReTrim `
                    -ErrorAction Stop

                $completed += "$($_.DriveLetter):"
            }
            catch {}
        }

    if ($completed.Count -eq 0) {
        return 'No supported fixed volume reported a successful ReTrim.'
    }

    return "ReTrim requested on: $($completed -join ', ')"
}

function Get-VexyTempAnalysis {
    $count = 0
    $bytes = [int64]0

    try {
        Get-ChildItem `
            -LiteralPath $env:TEMP `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
            ForEach-Object {
                $count++
                $bytes += $_.Length
            }
    }
    catch {}

    return [ordered]@{
        count = $count
        bytes = $bytes
        display = "$count files // $([math]::Round($bytes / 1GB,2)) GB"
    }
}

function Invoke-VexyTempCleanup {
    $deleted = 0
    $skipped = 0

    Get-ChildItem `
        -LiteralPath $env:TEMP `
        -Force `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-Item `
                    -LiteralPath $_.FullName `
                    -Force `
                    -Recurse `
                    -ErrorAction Stop

                $deleted++
            }
            catch {
                $skipped++
            }
        }

    return "Temporary cleanup complete: $deleted removed, $skipped locked/skipped."
}

function Invoke-VexyProfile {
    param(
        [ValidateSet('safe','competitive','blacksite')]
        [string]$Profile
    )

    $messages = @()
    $messages += New-VexyBackup -Reason "Profile: $Profile"

    if ($Profile -ne 'safe') {
        $messages += New-VexyRestorePoint
    }

    $messages += Set-VexyGameMode
    $messages += Disable-VexyMouseAcceleration
    $messages += Disable-VexyGameDvr

    if ($Profile -in @('competitive','blacksite')) {
        $messages += Set-VexyVisualPerformance
        $messages += Set-VexyHags
        $messages += Set-VexyUltimatePower
    }

    if ($Profile -eq 'blacksite') {
        $messages += Disable-VexyUsbSuspend
        $messages += Disable-VexyNicPower
    }

    return ($messages -join ' | ')
}

# ----------------------------------------------------------------------
# HARDWARE IDENTITY - READ ONCE
# ----------------------------------------------------------------------
$script:Hardware = [ordered]@{
    os = 'Windows'
    cpu = 'Unknown CPU'
    gpu = 'Unknown GPU'
    ram = '--'
    board = '--'
}

try {
    $script:Hardware.os = (
        Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    ).Caption
}
catch {}

try {
    $script:Hardware.cpu = (
        Get-CimInstance Win32_Processor -ErrorAction Stop |
        Select-Object -First 1
    ).Name.Trim()
}
catch {}

try {
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -notmatch 'Remote|Basic Display' } |
        Select-Object -First 1

    if ($gpu) {
        $script:Hardware.gpu = $gpu.Name.Trim()
    }
}
catch {}

try {
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $script:Hardware.ram = "$([math]::Round([double]$computer.TotalPhysicalMemory / 1GB,1)) GB"
}
catch {}

try {
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop |
        Select-Object -First 1

    $script:Hardware.board = (
        "$($board.Manufacturer) $($board.Product)"
    ).Trim()
}
catch {}

# ----------------------------------------------------------------------
# LIGHTWEIGHT TELEMETRY
# ----------------------------------------------------------------------
try {
    $script:CpuCounter = New-Object System.Diagnostics.PerformanceCounter(
        'Processor',
        '% Processor Time',
        '_Total'
    )

    [void]$script:CpuCounter.NextValue()
}
catch {
    $script:CpuCounter = $null
}

$script:NetInterface = $null
$script:LastRx = [int64]0
$script:LastTx = [int64]0
$script:LastNetTime = [datetime]::UtcNow

try {
    $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object {
            $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
            $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel
        }

    $script:NetInterface = $interfaces |
        Sort-Object Speed -Descending |
        Select-Object -First 1

    if ($script:NetInterface) {
        $stats = $script:NetInterface.GetIPv4Statistics()

        $script:LastRx = [int64]$stats.BytesReceived
        $script:LastTx = [int64]$stats.BytesSent
        $script:LastNetTime = [datetime]::UtcNow
    }
}
catch {}

$script:PowerCache = ''
$script:PowerCacheTime = [datetime]::MinValue

function Get-VexyPowerSchemeText {
    if (
        ((Get-Date) - $script:PowerCacheTime).TotalSeconds -lt 5 -and
        $script:PowerCache
    ) {
        return $script:PowerCache
    }

    try {
        $scheme = (
            powercfg /getactivescheme 2>$null |
            Out-String
        ) -replace '\s+',' '

        $script:PowerCache = $scheme.Trim()
        $script:PowerCacheTime = Get-Date
    }
    catch {}

    return $script:PowerCache
}

function Get-VexyStatus {
    $cpu = 0
    $ram = 0
    $down = 0.0
    $up = 0.0
    $adapter = '--'

    try {
        if ($script:CpuCounter) {
            $cpu = [math]::Max(
                0,
                [math]::Min(
                    100,
                    [math]::Round($script:CpuCounter.NextValue())
                )
            )
        }
    }
    catch {}

    try {
        $memory = New-Object 'VexyNative.MemoryApi+MEMORYSTATUSEX'

        if ([VexyNative.MemoryApi]::GlobalMemoryStatusEx($memory)) {
            $ram = [int]$memory.dwMemoryLoad
        }
    }
    catch {}

    try {
        if ($script:NetInterface) {
            $adapter = $script:NetInterface.Name
            $now = [datetime]::UtcNow
            $seconds = ($now - $script:LastNetTime).TotalSeconds

            if ($seconds -gt 0.15) {
                $stats = $script:NetInterface.GetIPv4Statistics()

                $rx = [int64]$stats.BytesReceived
                $tx = [int64]$stats.BytesSent

                $down = [math]::Max(
                    0,
                    (($rx - $script:LastRx) * 8 / 1000000) / $seconds
                )

                $up = [math]::Max(
                    0,
                    (($tx - $script:LastTx) * 8 / 1000000) / $seconds
                )

                $script:LastRx = $rx
                $script:LastTx = $tx
                $script:LastNetTime = $now
            }
        }
    }
    catch {}

    return [ordered]@{
        ok = $true
        cpu = $cpu
        ram = $ram
        uptimeSeconds = [math]::Floor([Environment]::TickCount64 / 1000)
        netDown = [math]::Round($down,3)
        netUp = [math]::Round($up,3)
        adapter = $adapter
        hardware = $script:Hardware
        powerScheme = Get-VexyPowerSchemeText
        backups = Get-VexyBackups
        license = [ordered]@{
            label = $script:LicenseLabel
            expiresAt = if ($script:LicenseExpires) {
                $script:LicenseExpires.ToString('o')
            }
            else {
                $null
            }
        }
    }
}

# ----------------------------------------------------------------------
# COMMAND ROUTER
# ----------------------------------------------------------------------
function Invoke-VexyAction {
    param([string]$Action)

    if (-not $script:Activated) {
        throw 'Activation required.'
    }

    $message = ''
    $temp = $null

    switch -Regex ($Action) {
        '^scan$' {
            $message = 'Deep system analysis sequence initiated.'
            break
        }

        '^backup$' {
            $message = New-VexyBackup
            break
        }

        '^restorePoint$' {
            $message = New-VexyRestorePoint
            break
        }

        '^restoreLatest$' {
            $message = Restore-LatestVexyBackup
            break
        }

        '^gameMode$' {
            $message = Set-VexyGameMode
            break
        }

        '^mouseAccel$' {
            $message = Disable-VexyMouseAcceleration
            break
        }

        '^gameDvr$' {
            $message = Disable-VexyGameDvr
            break
        }

        '^visuals$' {
            $message = Set-VexyVisualPerformance
            break
        }

        '^hags$' {
            $message = Set-VexyHags
            break
        }

        '^ultimatePower$' {
            $message = Set-VexyUltimatePower
            break
        }

        '^usbSuspend$' {
            $message = Disable-VexyUsbSuspend
            break
        }

        '^nicPower$' {
            $message = Disable-VexyNicPower
            break
        }

        '^cloudflareDns$' {
            $message = Set-VexyCloudflareDns
            break
        }

        '^retrim$' {
            $message = Invoke-VexyReTrim
            break
        }

        '^analyzeTemp$' {
            $temp = Get-VexyTempAnalysis
            $message = "Temp analysis complete: $($temp.display)"
            break
        }

        '^cleanTemp$' {
            $message = Invoke-VexyTempCleanup
            break
        }

        '^flushDns$' {
            ipconfig /flushdns | Out-Null
            $message = 'DNS resolver cache flushed.'
            break
        }

        '^openAdapters$' {
            Start-Process control.exe 'ncpa.cpl'
            $message = 'Windows Network Connections opened.'
            break
        }

        '^openBackups$' {
            Start-Process explorer.exe $script:BackupRoot
            $message = 'Backup vault opened.'
            break
        }

        '^openTemp$' {
            Start-Process explorer.exe $env:TEMP
            $message = 'Temporary folder opened.'
            break
        }

        '^openSystemRestore$' {
            Start-Process rstrui.exe
            $message = 'Windows System Restore opened.'
            break
        }

        '^profile:(safe|competitive|blacksite)$' {
            $message = Invoke-VexyProfile -Profile $Matches[1]
            break
        }

        default {
            throw "Unknown VEXY action: $Action"
        }
    }

    return [ordered]@{
        ok = $true
        message = $message
        temp = $temp
        backups = Get-VexyBackups
    }
}

# ----------------------------------------------------------------------
# LOOPBACK SESSION TOKEN
# ----------------------------------------------------------------------
$tokenBytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()

try {
    $rng.GetBytes($tokenBytes)
}
finally {
    $rng.Dispose()
}

$script:SessionToken = (
    [Convert]::ToBase64String($tokenBytes) -replace '[^A-Za-z0-9]',''
).Substring(0,32)

# Pick a free localhost port.
$tcp = [Net.Sockets.TcpListener]::new(
    [Net.IPAddress]::Loopback,
    0
)

$tcp.Start()
$port = ([Net.IPEndPoint]$tcp.LocalEndpoint).Port
$tcp.Stop()

$prefix = "http://127.0.0.1:$port/"

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
}
catch {
    Write-Host "VEXY could not start the local UI channel: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# ----------------------------------------------------------------------
# OPEN EDGE APP WINDOW
# ----------------------------------------------------------------------
$url = "${prefix}?token=$($script:SessionToken)"

$edgeCandidates = @()

if ($env:LOCALAPPDATA) {
    $edgeCandidates += Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe'
}

if ($env:ProgramFiles) {
    $edgeCandidates += Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'
}

if (${env:ProgramFiles(x86)}) {
    $edgeCandidates += Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
}

$edge = $edgeCandidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

try {
    if ($edge) {
        Start-Process `
            -FilePath $edge `
            -ArgumentList @(
                "--app=$url",
                '--start-maximized',
                '--no-first-run',
                '--disable-sync',
                "--user-data-dir=`"$script:EdgeProfile`""
            ) |
            Out-Null
    }
    else {
        Start-Process $url | Out-Null
    }
}
catch {
    Start-Process $url | Out-Null
}

# ----------------------------------------------------------------------
# SERVER LOOP
# ----------------------------------------------------------------------
$script:StopServer = $false

try {
    while (-not $script:StopServer) {
        $async = $listener.BeginGetContext($null,$null)

        while (-not $async.AsyncWaitHandle.WaitOne(250)) {
            if ($script:StopServer) {
                break
            }
        }

        if ($script:StopServer) {
            break
        }

        $context = $listener.EndGetContext($async)
        $path = $context.Request.Url.AbsolutePath
        $method = $context.Request.HttpMethod.ToUpperInvariant()

        # Frontend document.
        if ($path -eq '/' -and $method -eq 'GET') {
            Send-VexyText `
                -Context $context `
                -Text $script:Html `
                -ContentType 'text/html; charset=utf-8'

            continue
        }

        # Embedded images.
        if ($path -eq '/asset/logo.png' -and $method -eq 'GET') {
            Send-VexyBytes `
                -Context $context `
                -Bytes $script:LogoBytes `
                -ContentType 'image/png'

            continue
        }

        if ($path -eq '/asset/emblem.png' -and $method -eq 'GET') {
            Send-VexyBytes `
                -Context $context `
                -Bytes $script:EmblemBytes `
                -ContentType 'image/png'

            continue
        }

        # Protect all API requests with the random session token.
        $providedToken = $context.Request.Headers['X-Vexy-Token']

        if ($providedToken -ne $script:SessionToken) {
            Send-VexyJson `
                -Context $context `
                -StatusCode 403 `
                -Object @{
                    ok = $false
                    message = 'Invalid VEXY session token.'
                }

            continue
        }

        if ($path -eq '/api/activate' -and $method -eq 'POST') {
            try {
                $reader = New-Object IO.StreamReader(
                    $context.Request.InputStream,
                    $context.Request.ContentEncoding
                )

                $payload = $reader.ReadToEnd() | ConvertFrom-Json
                $reader.Close()

                $activation = Test-VexyLicense -Key ([string]$payload.key)

                Send-VexyJson `
                    -Context $context `
                    -Object $activation
            }
            catch {
                Send-VexyJson `
                    -Context $context `
                    -StatusCode 401 `
                    -Object @{
                        ok = $false
                        message = $_.Exception.Message
                    }
            }

            continue
        }

        if ($path -eq '/api/status' -and $method -eq 'GET') {
            if (-not $script:Activated) {
                Send-VexyJson `
                    -Context $context `
                    -StatusCode 401 `
                    -Object @{
                        ok = $false
                        message = 'Activation required.'
                    }

                continue
            }

            Send-VexyJson `
                -Context $context `
                -Object (Get-VexyStatus)

            continue
        }

        if ($path -eq '/api/action' -and $method -eq 'POST') {
            try {
                $reader = New-Object IO.StreamReader(
                    $context.Request.InputStream,
                    $context.Request.ContentEncoding
                )

                $payload = $reader.ReadToEnd() | ConvertFrom-Json
                $reader.Close()

                $result = Invoke-VexyAction -Action ([string]$payload.action)

                Send-VexyJson `
                    -Context $context `
                    -Object $result
            }
            catch {
                Send-VexyJson `
                    -Context $context `
                    -StatusCode 400 `
                    -Object @{
                        ok = $false
                        message = $_.Exception.Message
                    }
            }

            continue
        }

        if ($path -eq '/api/exit' -and $method -eq 'POST') {
            $script:StopServer = $true

            Send-VexyJson `
                -Context $context `
                -Object @{
                    ok = $true
                    message = 'VEXY session terminated.'
                }

            continue
        }

        Send-VexyJson `
            -Context $context `
            -StatusCode 404 `
            -Object @{
                ok = $false
                message = 'VEXY endpoint not found.'
            }
    }
}
finally {
    try {
        $listener.Stop()
        $listener.Close()
    }
    catch {}

    try {
        if ($script:CpuCounter) {
            $script:CpuCounter.Dispose()
        }
    }
    catch {}
}
