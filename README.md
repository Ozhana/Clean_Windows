cat << 'EOF' > README.md
# Windows 11 Armor V25 – Enterprise-Grade System Hardening & Telemetry Control

| **ENGLISH** | **TÜRKÇE** |
|-------------|------------|
| **Introduction** | **Giriş** |
| This project provides a **zero-assumption, deterministic PowerShell script** that systematically eliminates Microsoft telemetry, removes bloatware, disables resource-wasting services, and gives you **full control** over Windows Update and the Microsoft Store – all while preserving system stability and enabling **one-click rollback** of every change. | Bu proje, **sıfır varsayım, deterministik bir PowerShell betiği** sunar; Microsoft telemetrisini sistematik olarak ortadan kaldırır, bloatware'leri kaldırır, kaynak israf eden servisleri devre dışı bırakır ve Windows Update ile Microsoft Store üzerinde **tam kontrol** sağlar – tüm bunları sistem kararlılığını koruyarak ve her değişikliğin **tek tıkla geri alınmasına** imkan tanıyarak yapar. |
| | |
| **What it solves** | **Ne Çözer** |
| Windows 11 is notorious for excessive telemetry, pre-installed bloatware, and forced updates that can interrupt workflows. This script tackles the **root causes** without breaking core functionality. It blocks telemetry at multiple layers (hosts, firewall, DNS, services, scheduled tasks, WER, Edge, Office, Wi‑Fi Sense), removes OneDrive and dozens of bundled apps, and lets you toggle Windows Update on/off as needed – including a **security‑update‑check mode** that temporarily enables updates, installs critical patches, and disables them again. | Windows 11, aşırı telemetri, önceden yüklenmiş bloatware ve iş akışını kesintiye uğratan zorunlu güncellemeler ile ünlüdür. Bu betik, **temel nedenleri** çekirdek işlevselliği bozmadan ele alır. Telemetriyi çoklu katmanlarda (hosts, güvenlik duvarı, DNS, servisler, zamanlanmış görevler, WER, Edge, Office, Wi‑Fi Sense) bloklar, OneDrive ve düzinelerce paketi kaldırır ve Windows Update'i ihtiyaç halinde açıp kapatmanıza izin verir – hatta **güvenlik güncellemesi kontrol modu** ile güncellemeleri geçici olarak etkinleştirir, kritik yamaları yükler ve tekrar kapatır. |
| | |
| **Workspace Requirements** | **Çalışma Alanı Gereksinimleri** |
| - Windows 11 (22H2 / 23H2 / 24H2)<br>- Administrator privileges<br>- PowerShell 5.1 or later<br>- Internet connection (only for downloading the script) | - Windows 11 (22H2 / 23H2 / 24H2)<br>- Yönetici yetkileri<br>- PowerShell 5.1 veya sonrası<br>- İnternet bağlantısı (sadece betiği indirmek için) |
| | |
| **Fetch the Script** | **Betiği İndirme** |
| Open PowerShell **as Administrator** and run: | **Yönetici olarak** PowerShell'i açın ve şunu çalıştırın: |
| <code>Invoke-WebRequest -Uri "https://raw.githubusercontent.com/your-repo/Win11_Armor/main/Win11_Armor_V25.ps1" -OutFile "$env:USERPROFILE\Desktop\Win11_Armor_V25.ps1"</code> | <code>Invoke-WebRequest -Uri "https://raw.githubusercontent.com/your-repo/Win11_Armor/main/Win11_Armor_V25.ps1" -OutFile "$env:USERPROFILE\Desktop\Win11_Armor_V25.ps1"</code> |
| *Replace the URL with your actual repository link.* | *URL'yi kendi depo bağlantınızla değiştirin.* |
| | |
| **Set Permissions** | **Yetkilendirme** |
| Since the script modifies system settings, you must run it with elevated rights. Also, ensure PowerShell's execution policy allows scripts: | Betik sistem ayarlarını değiştirdiği için yükseltilmiş haklarla çalıştırılmalıdır. Ayrıca PowerShell yürütme politikasının betiklere izin verdiğinden emin olun: |
| <code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass</code> | <code>Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass</code> |
| (This sets it only for the current session – safe.) | (Bu sadece mevcut oturum için geçerlidir – güvenlidir.) |
| | |
| **Execute** | **Çalıştırma** |
| Navigate to your Desktop and run: | Masaüstüne gidin ve şunu çalıştırın: |
| <code>cd $env:USERPROFILE\Desktop</code> | <code>cd $env:USERPROFILE\Desktop</code> |
| <code>.\Win11_Armor_V25.ps1</code> | <code>.\Win11_Armor_V25.ps1</code> |
| | |
| A menu‑driven interface will appear. Choose from: | Menü tabanlı bir arayüz açılacaktır. Seçenekler: |
| <code>[1] Apply Full Armor & Debloat</code> – applies all hardening measures.<br><code>[2] UNLOCK Store</code><br><code>[3] LOCK Store</code><br><code>[4] Observatory</code> – 5‑min background performance report.<br><code>[5] ROLLBACK</code> – revert all changes (including power plan).<br><code>[6] Windows Update Control</code> – enable/disable/temporary.<br><code>[7] Security Update Check</code> – auto‑open WU, check, and close.<br><code>[8] Update Telemetry Lists</code> – manually edit the block list. | <code>[1] Full Armor ve Debloat'ı Uygula</code> – tüm sıkılaştırma önlemlerini uygular.<br><code>[2] Store'u AÇ</code><br><code>[3] Store'u KAPAT</code><br><code>[4] Gözlemevi</code> – 5 dakikalık arka plan performans raporu.<br><code>[5] GERİ AL</code> – tüm değişiklikleri (güç planı dahil) geri alır.<br><code>[6] Windows Update Kontrolü</code> – etkinleştir/devre dışı bırak/geçici.<br><code>[7] Güvenlik Güncelleme Kontrolü</code> – WU'yu otomatik aç, kontrol et ve kapat.<br><code>[8] Telemetri Listelerini Güncelle</code> – engelleme listesini manuel düzenle. |
| | |
| **What to Expect – Verification** | **Ne Beklemeli – Doğrulama** |
| After applying the armor, you can verify key changes with these commands: | Zırhı uyguladıktan sonra, önemli değişiklikleri aşağıdaki komutlarla doğrulayabilirsiniz: |
| <code>Get-Service wuauserv, UsoSvc, WaaSMedicSvc, BITS, DoSvc \| ft Name, Status, StartType</code> – should show <code>Disabled</code> or <code>Manual</code> depending on your choice. | <code>Get-Service wuauserv, UsoSvc, WaaSMedicSvc, BITS, DoSvc \| ft Name, Status, StartType</code> – seçiminize göre <code>Disabled</code> veya <code>Manual</code> göstermelidir. |
| <code>Get-AppxPackage \| Where-Object { $_.Name -match "BingNews\|XboxApp\|MicrosoftTeams" }</code> – should return nothing (if those were removed). | <code>Get-AppxPackage \| Where-Object { $_.Name -match "BingNews\|XboxApp\|MicrosoftTeams" }</code> – hiçbir şey döndürmemelidir (eğer kaldırıldılarsa). |
| <code>Get-NetFirewallRule -DisplayName "Block Telemetry*" \| ft DisplayName, Action</code> – lists all telemetry block rules. | <code>Get-NetFirewallRule -DisplayName "Block Telemetry*" \| ft DisplayName, Action</code> – tüm telemetri engelleme kurallarını listeler. |
| <code>powercfg -getactivescheme</code> – shows the active power plan; after rollback it should revert to your original. | <code>powercfg -getactivescheme</code> – aktif güç planını gösterir; geri alma sonrası orijinaline dönmelidir. |
| | |
| **Recovery & Rollback** | **Kurtarma ve Geri Alma** |
| The script creates a backup directory under <code>%ProgramData%\Win11ArmorBackup</code>. To revert **all** changes: | Betik, <code>%ProgramData%\Win11ArmorBackup</code> altında bir yedekleme dizini oluşturur. **Tüm** değişiklikleri geri almak için: |
| 1. Run the script again and select menu option <code>[5] ROLLBACK</code> – this will restore registry, hosts file, firewall rules, and power plan. | 1. Betiği tekrar çalıştırın ve menü seçeneği <code>[5] GERİ AL</code>'ı seçin – bu, kayıt defteri, hosts dosyası, güvenlik duvarı kuralları ve güç planını geri yükleyecektir. |
| 2. If the script is unavailable, manually restore from the backup folder: | 2. Betik mevcut değilse, yedek klasörden manuel olarak geri yükleyin: |
| <code>reg import "%ProgramData%\Win11ArmorBackup\*.reg"</code> | <code>reg import "%ProgramData%\Win11ArmorBackup\*.reg"</code> |
| <code>copy "%ProgramData%\Win11ArmorBackup\hosts.backup" "%windir%\System32\drivers\etc\hosts"</code> | <code>copy "%ProgramData%\Win11ArmorBackup\hosts.backup" "%windir%\System32\drivers\etc\hosts"</code> |
| <code>powercfg -restoredefaultschemes</code> (restores default power plans) | <code>powercfg -restoredefaultschemes</code> (varsayılan güç planlarını geri yükler) |
| | |
| **Note:** OneDrive removal is not automatically reverted; you can reinstall it from the Store if needed. | **Not:** OneDrive kaldırma işlemi otomatik olarak geri alınmaz; gerekirse Store'dan yeniden yükleyebilirsiniz. |
| | |
| **Author** | **Yazar** |
| **Dr. Ozhan Akdag & Senior Cyber Security Agent (Collaborative design)** | **Dr. Özhan Akdağ & Kıdemli Siber Güvenlik Ajanı (İşbirlikçi tasarım)** |

---

## Technical Hardening Matrix / Teknik Sıkılaştırma Matrisi

| **Component / Bileşen** | **Action / Eylem** | **Method / Yöntem** | **Verification / Doğrulama** |
|--------------------------|---------------------|----------------------|------------------------------|
| Windows Update (WU) | Toggle on/off + dependent services & tasks | `Toggle-WindowsUpdate` (service control, scheduled tasks, registry `NoAutoUpdate`, `AUOptions`) | `Get-Service wuauserv`, `Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator"` |
| Microsoft Store | Enable/Disable (background updates) | Registry `RemoveWindowsStore`, `AutoDownload`; `wsreset.exe` | `Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"` |
| Telemetry Domains | Blocked at hosts file (0.0.0.0) | `Add-TelemetryBlock` | `Select-String -Path "$env:windir\System32\drivers\etc\hosts" -Pattern "vortex.data.microsoft.com"` |
| Telemetry IPs | Blocked via Windows Firewall | `Add-FirewallTelemetryBlock` (outbound rules) | `Get-NetFirewallRule -DisplayName "Block Telemetry IP*"` |
| DNS over HTTPS (DoH) | Disabled to prevent hosts bypass | Registry `EnableAutoDoh=0` | `Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"` |
| Windows Defender Telemetry | Disabled | Registry `DisableCoreServiceTelemetry=1` + `Set-MpPreference` | `Get-MpPreference \| Select DisableCoreServiceTelemetry` |
| Edge Telemetry | Policies set to 0 | Registry `MetricsReportingEnabled`, `SendSiteInfoToImproveServices`, `DiagnosticData` | `Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge"` |
| Office Telemetry | Disabled for 2013/2016/365 | Registry keys `DisableTelemetry`, `TelemetryEnabled` | `Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Telemetry"` |
| Wi‑Fi Sense & Hotspot | Disabled | Registry `AllowWiFiHotSpotReporting`, `AllowAutoConnectToWiFiSenseHotspots`, `Hotspot\Enabled` | `Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi"` |
| Windows Error Reporting (WER) | Fully disabled (service + registry) | `WerSvc` disabled, `Disabled=1`, `LoggingDisabled=1` | `Get-Service WerSvc`, `Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"` |
| OneDrive | Removed (AppX + provisioned + registry) | `Remove-AppxPackage`, `Remove-AppxProvisionedPackage`, registry deletion | `Get-AppxPackage -Name "*OneDrive*"` (should be empty) |
| Bloatware Apps | Removed via AppX (list of ~30 packages) | `Remove-AppxPackage -AllUsers`, `Remove-AppxProvisionedPackage` | `Get-AppxPackage -Name "*BingNews*"` (should be empty) |
| Power Plan (CPU Boost, Modern Standby) | Disabled CPU boost and Modern Standby | `powercfg` commands; backup/restore via registry | `powercfg -getactivescheme`, `powercfg -attributes SUB_PROCESSOR PERFBOOSTMODE` |
| Scheduled Telemetry Tasks | Disabled | `Disable-ScheduledTask` for Compatibility Appraiser, CEIP, Siuf, QueueReporting | `Get-ScheduledTask -TaskPath "\Microsoft\Windows\Application Experience"` |
| Suspect Vendor Services | Disabled (ASUS, Armoury, DTS, Intel Telemetry) | `Stop-Service`, `Set-Service -StartupType Disabled` | `Get-Service -DisplayName "*ASUS*"` |

---

**Disclaimer:** This script is provided as-is. Always test in a non‑production environment first. The authors assume no liability for any system instability or data loss.

**Sorumluluk Reddi:** Bu betik “olduğu gibi” sunulmaktadır. Önce üretim dışı bir ortamda test edin. Yazarlar, sistem kararsızlığı veya veri kaybından sorumlu değildir.

EOF
