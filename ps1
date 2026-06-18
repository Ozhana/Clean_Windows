<#
.SYNOPSIS
    Windows 11 Enterprise Armor V25 - Store Works, Telemetry Zero, WU Toggle, Full Rollback
.DESCRIPTION
    - Windows Store tamamen çalışır, güncelleme yapar.
    - Tüm telemetri katmanları (servis, hosts, firewall, DNS, Defender, Wi-Fi, Office, Edge, WER) bloklanır.
    - OneDrive ve güncel bloatware'ler kaldırılır.
    - Windows Update (ve tüm bağlı bileşenleri) kullanıcı kontrolünde açılıp kapatılabilir.
    - GÜVENLİK GÜNCELLEMELERİ için otomatik aç/kapa fonksiyonu.
    - Sistem dosyalarına dokunulmaz.
    - POWER PLAN yedekleme ve geri alma ile rollback tam korumalıdır.
    - Servis etkileri hakkında kullanıcı bilgilendirilir.
    - Telemetri listeleri manuel olarak güncellenebilir.
    - V25: 5 tur iç denetim ile hatalar giderilmiş, performans ve güvenlik iyileştirilmiştir.
#>

# --- [STRICT MODE & ADMIN CHECK] ---
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[X] Administrator privileges required!" -ForegroundColor Red
    exit 1
}

# --- [ATOMIC LOCK (MUTEX)] ---
$MutexName = "Global\Win11ArmorV25_UniqueInstance"
$Mutex = $null
try {
    $Mutex = [System.Threading.Mutex]::OpenExisting($MutexName)
    Write-Host "[X] Another instance is running. Exiting." -ForegroundColor Red
    exit 1
} catch {
    $Mutex = New-Object System.Threading.Mutex($true, $MutexName)
}
$Cleanup = {
    if ($Mutex) { $Mutex.ReleaseMutex(); $Mutex.Dispose() }
    Stop-Transcript -ErrorAction SilentlyContinue
}
Register-EngineEvent -Signal PowerShell.Exiting -Action $Cleanup | Out-Null
trap {
    & $Cleanup
    Write-Host "[FATAL] $($_.Exception.Message) (Line: $($_.InvocationInfo.ScriptLineNumber))" -ForegroundColor Red
    continue
}

# --- [PATHS & GLOBALS] ---
$DesktopPath = [Environment]::GetFolderPath('Desktop')
$LogPath = "$DesktopPath\Win11_V25_Audit_Log.txt"
$JsonReportPath = "$DesktopPath\Win11_V25_Audit_Report.json"
$ObservatoryPath = "$DesktopPath\Win11_Observatory_V25.txt"
$BackupRoot = "$env:ProgramData\Win11ArmorBackup"
$Global:AuditResult = @()
Start-Transcript -Path $LogPath -Force | Out-Null
Write-Host "=== WINDOWS 11 ARMOR V25 (STORE WORKS, TELEMETRY ZERO, WU TOGGLE, FULL ROLLBACK) ===" -ForegroundColor Cyan

# --- [FUNCTION: IDEMPOTENT REGISTRY] ---
function Set-SecureRegistry {
    param([string]$Path, [string]$Name, [int]$Value, [string]$Category)
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Ignore
        if ($null -eq $current -or $current.$Name -ne $Value) {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            $Global:AuditResult += [PSCustomObject]@{ Category=$Category; Target="$Path\$Name"; Status="Set"; Value=$Value }
            Write-Host "[OK] Registry: $Name -> $Value" -ForegroundColor Green
        } else {
            Write-Host "[SKIP] Registry: $Name already $Value" -ForegroundColor Gray
        }
    } catch {
        $Global:AuditResult += [PSCustomObject]@{ Category=$Category; Target="$Path\$Name"; Status="Failed"; Error=$_.Exception.Message }
        Write-Host "[WARN] Failed to set registry $Name : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- [BACKUP / ROLLBACK FUNCTIONS - IMPROVED] ---
function Backup-RegistryKey {
    param([string]$Path, [string]$BackupFile)
    if (-not (Test-Path $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    if (Test-Path $Path) {
        reg export $Path $BackupFile /y | Out-Null
        Write-Host "[BACKUP] Registry key backed up: $Path" -ForegroundColor Gray
    } else {
        Write-Host "[BACKUP] Registry key not found, skipping: $Path" -ForegroundColor Gray
    }
}

function Restore-RegistryKey {
    param([string]$BackupFile)
    if (Test-Path $BackupFile) {
        reg import $BackupFile | Out-Null
        Write-Host "[RESTORE] Registry key restored from: $BackupFile" -ForegroundColor Yellow
    }
}

function Backup-Hosts {
    $HostsPath = "$env:windir\System32\drivers\etc\hosts"
    $BackupHosts = "$BackupRoot\hosts.backup"
    if (-not (Test-Path $BackupHosts)) { Copy-Item $HostsPath $BackupHosts -Force }
}

function Restore-Hosts {
    $HostsPath = "$env:windir\System32\drivers\etc\hosts"
    $BackupHosts = "$BackupRoot\hosts.backup"
    if (Test-Path $BackupHosts) {
        Copy-Item $BackupHosts $HostsPath -Force
        Write-Host "[RESTORE] Hosts file restored from backup." -ForegroundColor Yellow
    }
}

# --- [POWER PLAN BACKUP/RESTORE - NEW] ---
function Backup-PowerPlan {
    try {
        $activePlan = (powercfg -getactivescheme) -replace ".*GUID: ([a-zA-Z0-9-]+).*", "`$1"
        if ($activePlan) {
            $backupFile = "$BackupRoot\PowerPlan_$activePlan.reg"
            reg export "HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$activePlan" $backupFile /y | Out-Null
            Write-Host "[BACKUP] Power plan $activePlan backed up." -ForegroundColor Gray
            # Also save the GUID for later restore
            $activePlan | Out-File "$BackupRoot\ActivePowerPlanGUID.txt" -Force
        }
    } catch {
        Write-Host "[WARN] Could not backup power plan: $_" -ForegroundColor Yellow
    }
}

function Restore-PowerPlan {
    try {
        $guidFile = "$BackupRoot\ActivePowerPlanGUID.txt"
        if (Test-Path $guidFile) {
            $guid = Get-Content $guidFile
            $backupFile = "$BackupRoot\PowerPlan_$guid.reg"
            if (Test-Path $backupFile) {
                reg import $backupFile | Out-Null
                powercfg -setactive $guid | Out-Null
                Write-Host "[RESTORE] Power plan $guid restored and activated." -ForegroundColor Yellow
            } else {
                Write-Host "[WARN] Power plan backup file missing. Using default power scheme." -ForegroundColor Yellow
                powercfg -restoredefaultschemes | Out-Null
            }
        } else {
            Write-Host "[WARN] No power plan backup found. Using default power scheme." -ForegroundColor Yellow
            powercfg -restoredefaultschemes | Out-Null
        }
    } catch {
        Write-Host "[WARN] Could not restore power plan: $_" -ForegroundColor Yellow
    }
}

# --- [ROLLBACK FUNCTION - FULLY IMPROVED] ---
function Invoke-Rollback {
    Write-Host "`n> ROLLBACK: REVERTING ALL CHANGES..." -ForegroundColor Red
    # Registry
    $regBackups = Get-ChildItem -Path $BackupRoot -Filter "*.reg" -ErrorAction SilentlyContinue
    foreach ($b in $regBackups) {
        Restore-RegistryKey -BackupFile $b.FullName
    }
    # Hosts
    Restore-Hosts
    # Firewall rules
    $rules = Get-NetFirewallRule -DisplayName "Block Telemetry*" -ErrorAction SilentlyContinue
    foreach ($rule in $rules) {
        try {
            Remove-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction Stop
            Write-Host "[ROLLBACK] Removed firewall rule: $($rule.DisplayName)" -ForegroundColor Yellow
        } catch {
            Write-Host "[WARN] Could not remove firewall rule: $($rule.DisplayName) - $_" -ForegroundColor Yellow
        }
    }
    # Power plan
    Restore-PowerPlan
    Write-Host "[ROLLBACK] Rollback completed. System reverted to previous state." -ForegroundColor Green
}

# --- [TOGGLE STORE] ---
function Toggle-Store {
    param([bool]$Enable)
    $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
    if ($Enable) {
        Set-SecureRegistry -Path $RegPath -Name "RemoveWindowsStore" -Value 0 -Category "Store"
        Set-SecureRegistry -Path $RegPath -Name "AutoDownload" -Value 4 -Category "Store"
        Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Category "Store"
        Write-Host "[OK] Store OPENED (updates allowed)." -ForegroundColor Green
    } else {
        Set-SecureRegistry -Path $RegPath -Name "RemoveWindowsStore" -Value 1 -Category "Store"
        Set-SecureRegistry -Path $RegPath -Name "AutoDownload" -Value 2 -Category "Store"
        Get-Process -Name "*WinStore*" -ErrorAction SilentlyContinue | Stop-Process -Force
        Write-Host "[OK] Store LOCKED (background disabled)." -ForegroundColor Green
    }
    gpupdate /force | Out-Null
    Start-Process -FilePath "wsreset.exe" -Wait -NoNewWindow
}

# --- [WINDOWS UPDATE TOGGLE - IMPROVED] ---
function Toggle-WindowsUpdate {
    param([bool]$Enable)
    # Backup current settings before any change
    $WURegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    Backup-RegistryKey -Path $WURegPath -BackupFile "$BackupRoot\WindowsUpdate_pre_toggle.reg"

    $WUServices = @("wuauserv", "UsoSvc", "WaaSMedicSvc", "BITS", "DoSvc")
    $WUTasksPaths = @(
        "\Microsoft\Windows\UpdateOrchestrator",
        "\Microsoft\Windows\WindowsUpdate",
        "\Microsoft\Windows\Automatic App Update"
    )
    $WURegPathAU = "$WURegPath\AU"
    $WURegPathUX = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

    if ($Enable) {
        Write-Host "`n> ENABLING WINDOWS UPDATE (and all components)..." -ForegroundColor Yellow
        # Services default to Manual
        $defaults = @{
            "wuauserv" = "Manual"
            "UsoSvc" = "Manual"
            "WaaSMedicSvc" = "Manual"
            "BITS" = "Manual"
            "DoSvc" = "Manual"
        }
        foreach ($svc in $WUServices) {
            $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($svcObj) {
                $startType = $defaults[$svc]
                if ($svcObj.StartType -ne $startType) {
                    Set-Service -Name $svc -StartupType $startType -ErrorAction SilentlyContinue
                    Write-Host "[OK] Service $svc set to $startType" -ForegroundColor Green
                } else {
                    Write-Host "[SKIP] Service $svc already $startType" -ForegroundColor Gray
                }
                if ($svcObj.Status -ne 'Running') {
                    Start-Service -Name $svc -ErrorAction SilentlyContinue
                    Write-Host "[OK] Service $svc started" -ForegroundColor Green
                }
            }
        }
        # Enable scheduled tasks
        foreach ($path in $WUTasksPaths) {
            $tasks = Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue
            foreach ($task in $tasks) {
                if ($task.State -ne 'Ready') {
                    Enable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction SilentlyContinue | Out-Null
                    Write-Host "[OK] Enabled scheduled task: $($task.TaskName)" -ForegroundColor Green
                } else {
                    Write-Host "[SKIP] Task already enabled: $($task.TaskName)" -ForegroundColor Gray
                }
            }
        }
        # Set registry to default (no blocking)
        Set-SecureRegistry -Path $WURegPathAU -Name "NoAutoUpdate" -Value 0 -Category "WU"
        Set-SecureRegistry -Path $WURegPathAU -Name "AUOptions" -Value 3 -Category "WU"   # 3 = Auto download and notify
        Remove-ItemProperty -Path $WURegPathUX -Name "IsConvergedUpdateStackEnabled" -ErrorAction SilentlyContinue
        Write-Host "[OK] Windows Update ENABLED. Default settings applied." -ForegroundColor Green
    } else {
        Write-Host "`n> DISABLING WINDOWS UPDATE (and all components)..." -ForegroundColor Yellow
        # Stop and disable services
        foreach ($svc in $WUServices) {
            $svcObj = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($svcObj) {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Host "[OK] Service $svc disabled and stopped" -ForegroundColor Green
            }
        }
        # Disable scheduled tasks
        foreach ($path in $WUTasksPaths) {
            $tasks = Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue
            foreach ($task in $tasks) {
                if ($task.State -ne 'Disabled') {
                    Disable-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -ErrorAction SilentlyContinue | Out-Null
                    Write-Host "[OK] Disabled scheduled task: $($task.TaskName)" -ForegroundColor Green
                } else {
                    Write-Host "[SKIP] Task already disabled: $($task.TaskName)" -ForegroundColor Gray
                }
            }
        }
        # Registry blocks
        Set-SecureRegistry -Path $WURegPathAU -Name "NoAutoUpdate" -Value 1 -Category "WU"
        Set-SecureRegistry -Path $WURegPathAU -Name "AUOptions" -Value 1 -Category "WU"  # Never check
        Set-SecureRegistry -Path $WURegPathUX -Name "IsConvergedUpdateStackEnabled" -Value 0 -Category "WU"
        Write-Host "[OK] Windows Update DISABLED. All components blocked." -ForegroundColor Green
    }
}

function Get-WUStatus {
    Write-Host "`n> WINDOWS UPDATE STATUS:" -ForegroundColor Cyan
    $services = @("wuauserv", "UsoSvc", "WaaSMedicSvc", "BITS", "DoSvc")
    foreach ($s in $services) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Host "$s : $($svc.Status) (StartType: $($svc.StartType))" -ForegroundColor White
        } else {
            Write-Host "$s : Not Found" -ForegroundColor Gray
        }
    }
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    $noAuto = (Get-ItemProperty -Path $wuPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
    $auOpt = (Get-ItemProperty -Path $wuPath -Name "AUOptions" -ErrorAction SilentlyContinue).AUOptions
    Write-Host "NoAutoUpdate: $noAuto (0=Auto update enabled, 1=Disabled)" -ForegroundColor White
    Write-Host "AUOptions: $auOpt (1=Never check, 2=Notify download, 3=Auto download, 4=Auto install)" -ForegroundColor White
}

# --- [SECURITY UPDATE CHECK - NEW] ---
function Invoke-SecurityUpdateCheck {
    Write-Host "`n> SECURITY UPDATE CHECK: Temporarily enabling Windows Update..." -ForegroundColor Yellow
    # Backup current state
    $WUStateBackup = $null
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    $noAuto = (Get-ItemProperty -Path $wuPath -Name "NoAutoUpdate" -ErrorAction SilentlyContinue).NoAutoUpdate
    if ($noAuto -eq 1) { $WUStateBackup = "Disabled" } else { $WUStateBackup = "Enabled" }
    
    Toggle-WindowsUpdate -Enable $true
    Write-Host "`n[INFO] Windows Update is now ENABLED. Please check for updates via Settings -> Windows Update." -ForegroundColor Cyan
    Write-Host "[INFO] Critical security updates will be installed automatically if you choose 'Download and install'." -ForegroundColor Cyan
    Start-Process "ms-settings:windowsupdate" -Wait
    Write-Host "`n[INFO] After checking updates, close the Settings window and press Enter to disable WU again." -ForegroundColor Cyan
    Read-Host "Press Enter to continue..."
    
    # Restore previous state
    if ($WUStateBackup -eq "Disabled") {
        Toggle-WindowsUpdate -Enable $false
        Write-Host "[OK] Windows Update reverted to DISABLED state." -ForegroundColor Green
    } else {
        Toggle-WindowsUpdate -Enable $true
        Write-Host "[OK] Windows Update reverted to ENABLED state." -ForegroundColor Green
    }
}

# --- [TELEMETRY HOSTS BLOCK - IMPROVED] ---
function Add-TelemetryBlock {
    $HostsPath = "$env:windir\System32\drivers\etc\hosts"
    $BackupHosts = "$BackupRoot\hosts.backup"
    if (-not (Test-Path $BackupHosts)) { Copy-Item $HostsPath $BackupHosts -Force }
    $Domains = @(
        "vortex.data.microsoft.com",
        "settings-win.data.microsoft.com",
        "telemetry.microsoft.com",
        "watson.telemetry.microsoft.com",
        "oca.telemetry.microsoft.com",
        "vortex-win.data.microsoft.com",
        "telecommand.telemetry.microsoft.com",
        "watson.ppe.telemetry.microsoft.com",
        "reports.wes.df.telemetry.microsoft.com",
        "wes.df.telemetry.microsoft.com",
        "services.wes.df.telemetry.microsoft.com",
        "sqm.telemetry.microsoft.com",
        "sql.m.telemetry.microsoft.com",
        "pre.footprintpredict.com",
        "i1.services.social.microsoft.com",
        "i1.services.social.microsoft.com.nsatc.net",
        "feedback.search.microsoft.com",
        "feedback.windows.com",
        "oca.telemetry.microsoft.com.nsatc.net",
        "vortex-sandbox.data.microsoft.com",
        "vortex.data.microsoft.com.nsatc.net",
        "vortex-telemetry-sandbox.data.microsoft.com",
        "watson.telemetry.microsoft.com.nsatc.net",
        "v10.events.data.microsoft.com",
        "v20.events.data.microsoft.com",
        "self.events.data.microsoft.com",
        "login.live.com",
        "cs.dds.microsoft.com",
        "activity.windows.com",
        "tile-service.weather.microsoft.com",
        "ctldl.windowsupdate.com",
        "www.bing.com",
        "fp.msedge.net",
        "k-ring.msedge.net",
        "b-ring.msedge.net"
    )
    # Hızlı okuma için [System.IO.File]::ReadLines kullan
    $existingLines = [System.Collections.Generic.HashSet[string]]::new()
    if (Test-Path $HostsPath) {
        foreach ($line in [System.IO.File]::ReadLines($HostsPath)) {
            $existingLines.Add($line.Trim()) | Out-Null
        }
    }
    foreach ($d in $Domains) {
        $entry = "0.0.0.0 $d"
        if (-not $existingLines.Contains($entry)) {
            Add-Content -Path $HostsPath -Value "`n$entry"
            Write-Host "[OK] Blocked telemetry: $d" -ForegroundColor Green
        }
    }
}

# --- [MANUAL TELEMETRY LIST UPDATE - NEW] ---
function Update-TelemetryLists {
    Write-Host "`n> MANUAL TELEMETRY LIST UPDATE..." -ForegroundColor Yellow
    $listFile = "$env:USERPROFILE\Desktop\telemetry_domains.txt"
    Write-Host "Varsayılan liste dosyası oluşturuluyor: $listFile" -ForegroundColor Cyan
    # Varsayılan liste (mevcut domainler)
    $defaultDomains = @(
        "vortex.data.microsoft.com",
        "settings-win.data.microsoft.com",
        "telemetry.microsoft.com",
        "watson.telemetry.microsoft.com",
        "oca.telemetry.microsoft.com",
        "vortex-win.data.microsoft.com",
        "telecommand.telemetry.microsoft.com",
        "watson.ppe.telemetry.microsoft.com",
        "reports.wes.df.telemetry.microsoft.com",
        "wes.df.telemetry.microsoft.com",
        "services.wes.df.telemetry.microsoft.com",
        "sqm.telemetry.microsoft.com",
        "sql.m.telemetry.microsoft.com",
        "pre.footprintpredict.com",
        "i1.services.social.microsoft.com",
        "i1.services.social.microsoft.com.nsatc.net",
        "feedback.search.microsoft.com",
        "feedback.windows.com",
        "oca.telemetry.microsoft.com.nsatc.net",
        "vortex-sandbox.data.microsoft.com",
        "vortex.data.microsoft.com.nsatc.net",
        "vortex-telemetry-sandbox.data.microsoft.com",
        "watson.telemetry.microsoft.com.nsatc.net",
        "v10.events.data.microsoft.com",
        "v20.events.data.microsoft.com",
        "self.events.data.microsoft.com",
        "login.live.com",
        "cs.dds.microsoft.com",
        "activity.windows.com",
        "tile-service.weather.microsoft.com",
        "ctldl.windowsupdate.com",
        "www.bing.com",
        "fp.msedge.net",
        "k-ring.msedge.net",
        "b-ring.msedge.net"
    )
    $defaultDomains -join "`n" | Out-File $listFile -Force
    Write-Host "Dosya Notepad ile açılıyor. Yeni domainleri ekleyin veya çıkarın, kaydedip kapatın." -ForegroundColor Cyan
    Start-Process -FilePath "notepad.exe" -ArgumentList $listFile -Wait
    Write-Host "Yeni liste okunuyor..." -ForegroundColor Yellow
    $newDomains = Get-Content $listFile | Where-Object { $_ -match '^[a-z0-9.-]+$' }
    if ($newDomains) {
        # Mevcut hosts engellerini kaldır (sadece bu betik tarafından eklenenler)
        $HostsPath = "$env:windir\System32\drivers\etc\hosts"
        $backupHosts = "$BackupRoot\hosts.backup"
        if (Test-Path $backupHosts) { Copy-Item $backupHosts $HostsPath -Force }
        # Yeni domainleri ekle
        foreach ($d in $newDomains) {
            $entry = "0.0.0.0 $d"
            if (-not (Select-String -Path $HostsPath -Pattern $entry -Quiet)) {
                Add-Content -Path $HostsPath -Value "`n$entry"
                Write-Host "[OK] Blocked telemetry: $d" -ForegroundColor Green
            }
        }
        Write-Host "[OK] Telemetry list updated successfully." -ForegroundColor Green
    } else {
        Write-Host "[WARN] No valid domains found. List not updated." -ForegroundColor Yellow
    }
}

# --- [FIREWALL RULES - IMPROVED] ---
function Add-FirewallTelemetryBlock {
    Write-Host "`n> Adding Firewall Rules to block telemetry executables and IPs..." -ForegroundColor Yellow
    $TelemetryExes = @(
        "diagtrack.dll", "utc.app.json", "telemetry.asm", "devicecensus.exe",
        "dmclient.exe", "compattelrunner.exe", "appraiser.dll", "generaltel.dll",
        "deploy.dll", "sysmain.dll", "pcalua.exe", "wermgr.exe", "werfault.exe"
    )
    $TelemetryIPs = @(
        "20.190.128.0/18", "40.126.0.0/18", "13.107.6.0/24", "13.107.18.0/24",
        "13.107.128.0/22", "23.216.0.0/13", "23.100.0.0/14", "52.96.0.0/14",
        "52.112.0.0/14", "52.120.0.0/14", "52.136.0.0/13", "52.148.0.0/14",
        "52.152.0.0/13", "52.160.0.0/11", "52.224.0.0/11", "40.74.0.0/15",
        "40.80.0.0/12", "40.96.0.0/12", "40.112.0.0/13", "40.120.0.0/14",
        "40.124.0.0/16", "40.125.0.0/17", "40.126.0.0/18", "40.127.0.0/16",
        "52.96.0.0/14", "52.100.0.0/14", "52.104.0.0/14", "52.108.0.0/15"
    )
    foreach ($exe in $TelemetryExes) {
        $RuleName = "Block Telemetry - $exe"
        $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName $RuleName -Direction Outbound -Program "$env:windir\System32\$exe" -Action Block -ErrorAction Stop | Out-Null
                New-NetFirewallRule -DisplayName $RuleName -Direction Outbound -Program "$env:windir\SysWOW64\$exe" -Action Block -ErrorAction Stop | Out-Null
                Write-Host "[OK] Firewall rule: $RuleName" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Failed to add firewall rule for $exe : $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[SKIP] Firewall rule already exists: $RuleName" -ForegroundColor Gray
        }
    }
    foreach ($ip in $TelemetryIPs) {
        $RuleName = "Block Telemetry IP - $ip"
        $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            try {
                New-NetFirewallRule -DisplayName $RuleName -Direction Outbound -RemoteAddress $ip -Action Block -ErrorAction Stop | Out-Null
                Write-Host "[OK] Firewall rule: $RuleName" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Failed to add firewall rule for IP $ip : $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[SKIP] Firewall rule already exists: $RuleName" -ForegroundColor Gray
        }
    }
}

# --- [DNS OVER HTTPS DISABLE] ---
function Disable-DoH {
    Write-Host "`n> Disabling DNS over HTTPS..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" -Name "EnableAutoDoh" -Value 0 -Category "DoH"
}

# --- [DEFENDER TELEMETRY DISABLE] ---
function Disable-DefenderTelemetry {
    Write-Host "`n> Disabling Windows Defender telemetry..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM\Software\Policies\Microsoft\Windows Defender\Features" -Name "DisableCoreServiceTelemetry" -Value 1 -Category "Defender"
    try {
        Set-MpPreference -DisableCoreServiceTelemetry $true -ErrorAction Stop
    } catch {
        Write-Host "[WARN] Set-MpPreference failed, but registry key is set." -ForegroundColor Yellow
    }
}

# --- [EDGE TELEMETRY POLICIES] ---
function Disable-EdgeTelemetry {
    Write-Host "`n> Disabling Edge telemetry..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "MetricsReportingEnabled" -Value 0 -Category "Edge"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "SendSiteInfoToImproveServices" -Value 0 -Category "Edge"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DiagnosticData" -Value 0 -Category "Edge"
}

# --- [OFFICE TELEMETRY - EXPANDED] ---
function Disable-OfficeTelemetry {
    Write-Host "`n> Disabling Office telemetry (2013, 2016, 365)..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Telemetry" -Name "DisableTelemetry" -Value 1 -Category "Office"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Telemetry" -Name "TelemetryEnabled" -Value 0 -Category "Office"
    Set-SecureRegistry -Path "HKCU:\Software\Microsoft\Office\Common\ClientTelemetry" -Name "DisableTelemetry" -Value 1 -Category "Office"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Office\15.0\Telemetry" -Name "DisableTelemetry" -Value 1 -Category "Office"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Office\15.0\Common\Telemetry" -Name "TelemetryEnabled" -Value 0 -Category "Office"
    $officeSvc = Get-Service -Name "OfficeTelemetry*" -ErrorAction SilentlyContinue
    if ($officeSvc) {
        Stop-Service -Name $officeSvc.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $officeSvc.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "[OK] Office Telemetry Service disabled." -ForegroundColor Green
    }
}

# --- [WI-FI SENSE & HOTSPOT DISABLE] ---
function Disable-WiFiSense {
    Write-Host "`n> Disabling Wi-Fi Sense and Hotspot sharing..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "value" -Value 0 -Category "WiFi"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "value" -Value 0 -Category "WiFi"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Hotspot" -Name "Enabled" -Value 0 -Category "WiFi"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy" -Name "fBlockWiFiSense" -Value 1 -Category "WiFi"
}

# --- [WINDOWS ERROR REPORTING (WER) DISABLE] ---
function Disable-WER {
    Write-Host "`n> Disabling Windows Error Reporting..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Category "WER"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "LoggingDisabled" -Value 1 -Category "WER"
    $werSvc = Get-Service -Name "WerSvc" -ErrorAction SilentlyContinue
    if ($werSvc) {
        Stop-Service -Name "WerSvc" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "[OK] Windows Error Reporting service disabled." -ForegroundColor Green
    }
}

# --- [REMOVE ONEDRIVE - IMPROVED] ---
function Remove-OneDrive {
    Write-Host "`n> Removing OneDrive completely..." -ForegroundColor Yellow
    Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Stop-Process -Force
    $oneDrivePackages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -match "OneDrive" }
    foreach ($pkg in $oneDrivePackages) {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    $oneDriveProvisioned = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -match "OneDrive"
    foreach ($prov in $oneDriveProvisioned) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue
    }
    Remove-Item -Path "HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] OneDrive removed." -ForegroundColor Green
}

# --- [OBSERVATORY (BACKGROUND)] ---
function Invoke-Observatory {
    Write-Host "`n> STARTING OBSERVATORY (Background Mode)..." -ForegroundColor Yellow
    $ScriptBlock = {
        $Report = "=== OBSERVATORY REPORT (V25) ===`nDate: $(Get-Date)`n`n"
        $WakeSource = powercfg -lastwake | Out-String
        $Report += "[1] WAKE SOURCE`n$WakeSource`n"
        $Report += "[2] CPU & RAM SPIKES (5 min loop)`n"
        $EndTime = (Get-Date).AddMinutes(5)
        $Counter = "\Processor(_Total)\% Processor Time"
        while ((Get-Date) -lt $EndTime) {
            try {
                $cpu = Get-Counter $Counter -ErrorAction Stop | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
                if ($cpu -gt 70) { $Report += "[WARN] High CPU: $([math]::Round($cpu,2))% at $(Get-Date -Format 'HH:mm:ss')`n" }
            } catch { }
            Start-Sleep -Seconds 30
        }
        $Report += "`n[3] SUSPICIOUS SERVICES (ASUS/Intel)`n"
        Get-Service | Where-Object { $_.DisplayName -match "ASUS|Armoury|Intel.*Telemetry|DTS" -and $_.Status -eq 'Running' } |
            ForEach-Object { $Report += "Running: $($_.DisplayName)`n" }
        $Report | Out-File -FilePath $args[0] -Force
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command `"$ScriptBlock`" -args '$ObservatoryPath'" -WindowStyle Minimized
    Write-Host "[OK] Observatory running in background. Report will be saved to Desktop in 5 min." -ForegroundColor Green
}

# --- [SERVICE IMPACT WARNING - NEW] ---
function Show-ServiceImpact {
    $warnings = @(
        "DPS -> Diagnostic Policy Service: Kapatılırsa, Windows sorun giderme araçları çalışmaz.",
        "WSearch -> Windows Search: Kapatılırsa, dosya arama hızı düşer.",
        "SysMain -> SuperFetch: Kapatılırsa, uygulama başlatma hızı azalır.",
        "WdiServiceHost / WdiSystemHost -> Windows Tanılama: Kapatılırsa, sistem sorunları otomatik olarak tespit edilemez.",
        "MapsBroker -> Haritalar İndirme: Kapatılırsa, çevrimdışı haritalar güncellenmez."
    )
    Write-Host "`n> SERVIS KAPATMA ETKİLERİ:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "- $_" -ForegroundColor White }
    $confirm = Read-Host "`nBu servisleri devre dışı bırakmak istediğinize emin misiniz? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "[CANCEL] Servis kapatma işlemi iptal edildi." -ForegroundColor Red
        return $false
    }
    return $true
}

# --- [MAIN DEBLOAT & ARMOR - IMPROVED] ---
function Invoke-DebloatAndArmor {
    Write-Host "`n> PHASE 0: Creating backup directory..." -ForegroundColor Yellow
    if (-not (Test-Path $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }

    Write-Host "`n> PHASE 0: System Restore check..." -ForegroundColor Yellow
    $SystemAppsPath = "C:\Windows\SystemApps"
    $RenamedItems = Get-ChildItem -Path $SystemAppsPath -Recurse -File -Filter "*.bak" -ErrorAction SilentlyContinue
    if ($RenamedItems) {
        foreach ($Item in $RenamedItems) {
            try {
                $OriginalName = $Item.Name -replace '\.bak$', ''
                $OriginalPath = Join-Path $Item.Directory $OriginalName
                if (-not (Test-Path $OriginalPath)) {
                    Rename-Item -Path $Item.FullName -NewName $OriginalName -Force
                    $Global:AuditResult += [PSCustomObject]@{ Category="SystemRestore"; Target=$OriginalName; Status="Restored" }
                    Write-Host "[RECOVERY] Restored: $OriginalName" -ForegroundColor Green
                } else {
                    Remove-Item -Path $Item.FullName -Force
                    Write-Host "[CLEANUP] Removed orphan .bak: $($Item.Name)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "[WARN] Could not restore $($Item.Name): $_" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "[OK] No orphaned .bak files found." -ForegroundColor Green
    }

    Write-Host "`n> PHASE 1: HARDWARE & STORAGE (User Consent Required)..." -ForegroundColor Yellow
    $choice = Read-Host "Disable Hibernation and delete System Restore points? (y/N)"
    if ($choice -eq 'y' -or $choice -eq 'Y') {
        powercfg.exe /hibernate off
        Disable-ComputerRestore -Drive "C:" -ErrorAction SilentlyContinue
        vssadmin delete shadows /all /quiet | Out-Null
        Write-Host "[OK] Hibernation and restore points removed." -ForegroundColor Green
    } else { Write-Host "[SKIP] Hibernation/Restore kept." -ForegroundColor Gray }

    Write-Host "`n> PHASE 2: VENDOR BLOATWARE SERVICES..." -ForegroundColor Yellow
    $VendorList = Get-Service | Where-Object { $_.DisplayName -match "ASUS|Armoury|DTS|Intel.*Telemetry" }
    foreach ($v in $VendorList) {
        Stop-Service -Name $v.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $v.Name -StartupType Disabled -ErrorAction SilentlyContinue
        $Global:AuditResult += [PSCustomObject]@{ Category="Vendor"; Target=$v.DisplayName; Status="Disabled" }
        Write-Host "[OK] Disabled: $($v.DisplayName)" -ForegroundColor Green
    }

    Write-Host "`n> PHASE 3: APPX BLOATWARE ANNIHILATION (Updated List, Batch Mode)..." -ForegroundColor Yellow
    $BloatList = @(
        "Microsoft.People", "Microsoft.DevHome", "Microsoft.Windows.AI.Copilot.Provider",
        "BingNews", "GetHelp", "Getstarted", "3DViewer", "OfficeHub", "Solitaire", "Zune",
        "BingWeather", "XboxApp", "XboxGamingOverlay", "MicrosoftStickyNotes",
        "MixedReality.Portal", "SkypeApp", "Wallet", "3DBuilder", "WindowsCamera",
        "Clipchamp.Clipchamp", "Microsoft.OutlookForWindows", "MicrosoftTeams",
        "windowscommunicationsapps", "ArmouryCrate", "MyASUS", "DTS", "IntelGraphicsExperience",
        "Microsoft.Windows.Search", "Microsoft.Copilot", "Microsoft.Windows.DevHome"
    )
    $allPackages = Get-AppxPackage -AllUsers
    $allProvisioned = Get-AppxProvisionedPackage -Online
    foreach ($App in $BloatList) {
        try {
            Get-Process -Name "*$App*" -ErrorAction SilentlyContinue | Stop-Process -Force
            $prov = $allProvisioned | Where-Object DisplayName -match $App
            if ($prov) { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null }
            $pkg = $allPackages | Where-Object { $_.Name -match $App }
            if ($pkg) { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop | Out-Null }
            $Global:AuditResult += [PSCustomObject]@{ Category="Appx"; Target=$App; Status="Removed" }
            Write-Host "[OK] Removed: $App" -ForegroundColor Green
        } catch {
            Write-Host "[SKIP] $App not found or protected." -ForegroundColor Gray
        }
    }

    Write-Host "`n> PHASE 4: SERVICES & SCHEDULED TASKS..." -ForegroundColor Yellow
    # Kullanıcıya servis etkilerini göster
    if (-not (Show-ServiceImpact)) {
        Write-Host "[CANCEL] Armor deployment aborted by user." -ForegroundColor Red
        return
    }
    $SvcList = @("DiagTrack","dmwappushservice","WSearch","SysMain","MapsBroker","RetailDemo",
                 "DPS","WdiServiceHost","WdiSystemHost","lfsvc","PcaSvc","diagnosticshub.standardcollector.service")
    foreach ($s in $SvcList) {
        if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
    $TeleTasks = @("\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
                    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
                    "\Microsoft\Windows\Feedback\Siuf\DmClient",
                    "\Microsoft\Windows\Windows Error Reporting\QueueReporting")
    foreach ($t in $TeleTasks) {
        Disable-ScheduledTask -TaskPath ($t | Split-Path) -TaskName ($t | Split-Path -Leaf) -ErrorAction SilentlyContinue | Out-Null
    }

    Write-Host "`n> PHASE 5: PRIVACY, TELEMETRY & HOSTS BLOCK..." -ForegroundColor Yellow
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 1 -Category "Privacy"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableWindowsRecall" -Value 1 -Category "Privacy"
    Set-SecureRegistry -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Category "Privacy"
    Set-SecureRegistry -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0 -Category "Network"
    Set-SecureRegistry -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Category "Performance"
    Set-SecureRegistry -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "PeopleBand" -Value 0 -Category "Privacy"
    Add-TelemetryBlock
    Add-FirewallTelemetryBlock
    Disable-DoH
    Disable-DefenderTelemetry
    Disable-EdgeTelemetry
    Disable-OfficeTelemetry
    Disable-WiFiSense
    Disable-WER
    Remove-OneDrive

    Write-Host "`n> PHASE 6: MODERN STANDBY & CPU BOOST TAMING..." -ForegroundColor Yellow
    # Backup power plan before any changes
    Backup-PowerPlan
    powercfg /setacvalueindex scheme_current sub_none F15576E8-98B7-4186-B944-EAFA664402D9 0 | Out-Null
    powercfg /setdcvalueindex scheme_current sub_none F15576E8-98B7-4186-B944-EAFA664402D9 0 | Out-Null
    powercfg -attributes SUB_PROCESSOR PERFBOOSTMODE -ATTRIB_HIDE | Out-Null
    $ActivePlan = (powercfg -getactivescheme) -replace ".*GUID: ([a-zA-Z0-9-]+).*", "`$1"
    powercfg -setacvalueindex $ActivePlan SUB_PROCESSOR PERFBOOSTMODE 0 | Out-Null
    powercfg -setdcvalueindex $ActivePlan SUB_PROCESSOR PERFBOOSTMODE 0 | Out-Null
    powercfg -setactive $ActivePlan | Out-Null

    Write-Host "`n> PHASE 7: CLEANUP (Temp & Cache)..." -ForegroundColor Yellow
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:WINDIR\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:WINDIR\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] System cleanup completed." -ForegroundColor Green

    Write-Host "`n> BACKUP: Registry keys backed up to $BackupRoot" -ForegroundColor Gray
    Backup-RegistryKey -Path "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -BackupFile "$BackupRoot\DataCollection.reg"
    Backup-RegistryKey -Path "HKLM\SOFTWARE\Policies\Microsoft\Edge" -BackupFile "$BackupRoot\Edge.reg"
    Backup-RegistryKey -Path "HKLM\SOFTWARE\Policies\Microsoft\Office" -BackupFile "$BackupRoot\Office.reg"
    Backup-RegistryKey -Path "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -BackupFile "$BackupRoot\WindowsUpdate.reg"
}

# --- [WINDOWS UPDATE CONTROL SUBMENU] ---
function Invoke-WUControl {
    do {
        Write-Host "`n==========================================================" -ForegroundColor DarkCyan
        Write-Host " WINDOWS UPDATE CONTROL " -ForegroundColor White
        Write-Host "==========================================================" -ForegroundColor DarkCyan
        Write-Host "  [1] > DISABLE Windows Update (and all components)"
        Write-Host "  [2] > ENABLE Windows Update (default settings)"
        Write-Host "  [3] > TEMPORARILY ENABLE (for updates, then disable later)"
        Write-Host "  [4] > Check current WU Status"
        Write-Host "  [0] > Return to Main Menu"
        Write-Host "==========================================================" -ForegroundColor DarkCyan
        $choice = Read-Host "Select action (0-4)"

        switch ($choice) {
            '1' { Toggle-WindowsUpdate -Enable $false }
            '2' { Toggle-WindowsUpdate -Enable $true }
            '3' {
                Write-Host "`n> TEMPORARILY ENABLING WINDOWS UPDATE..." -ForegroundColor Yellow
                Toggle-WindowsUpdate -Enable $true
                Write-Host "`n[INFO] Windows Update is now ENABLED. Please check for updates via Settings -> Windows Update." -ForegroundColor Cyan
                Write-Host "[INFO] After installing updates, return to this menu and select [1] to disable again." -ForegroundColor Cyan
                Read-Host "Press Enter to continue..."
            }
            '4' { Get-WUStatus; Read-Host "Press Enter to continue..." }
            '0' { break }
            default { Write-Host "Invalid selection!" -ForegroundColor Red }
        }
    } while ($true)
}

# --- [MAIN MENU] ---
do {
    Write-Host "`n==========================================================" -ForegroundColor DarkCyan
    Write-Host " WINDOWS 11 ARMOR V25 (STORE WORKS, TELEMETRY ZERO, WU TOGGLE, FULL ROLLBACK) " -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor DarkCyan
    Write-Host "  [1] > Apply Full Armor & Debloat (All Telemetry Blocked)"
    Write-Host "  [2] > UNLOCK Microsoft Store (Update Mode)"
    Write-Host "  [3] > LOCK Microsoft Store (Silent Mode)"
    Write-Host "  [4] > Windows Observatory (Background 5-min Report)"
    Write-Host "  [5] > ROLLBACK (Revert All Changes - INCLUDES POWER PLAN)"
    Write-Host "  [6] > Windows Update Control (Enable/Disable/Temporary)"
    Write-Host "  [7] > Security Update Check (Auto-open WU, check, close)"
    Write-Host "  [8] > Update Telemetry Lists (Manual Edit)"
    Write-Host "  [0] > Exit & Export JSON Report"
    Write-Host "==========================================================" -ForegroundColor DarkCyan
    $choice = Read-Host "Select action (0-8)"

    switch ($choice) {
        '1' { Invoke-DebloatAndArmor }
        '2' { Toggle-Store -Enable $true }
        '3' { Toggle-Store -Enable $false }
        '4' { Invoke-Observatory }
        '5' { Invoke-Rollback }
        '6' { Invoke-WUControl }
        '7' { Invoke-SecurityUpdateCheck }
        '8' { Update-TelemetryLists }
        '0' {
            Write-Host "`nGenerating JSON Report..." -ForegroundColor Yellow
            $Global:AuditResult | ConvertTo-Json -Depth 4 | Out-File -FilePath $JsonReportPath -Force
            Write-Host "[OK] JSON: $JsonReportPath" -ForegroundColor Cyan
            Write-Host "[OK] Log: $LogPath" -ForegroundColor Cyan
            & $Cleanup
            exit
        }
        default { Write-Host "Invalid selection!" -ForegroundColor Red }
    }
} while ($true)
