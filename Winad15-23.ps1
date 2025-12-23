<#
.SYNOPSIS
    自動化設定 Windows Server 2016，對應 VMware ESXi 6.7 Lab 教材 p.15-23 的操作，並新增關閉即時保護。

.DESCRIPTION
    此腳本會執行以下初始伺服器設定：
    - 關閉防火牆 (Private, Public)
    - 關閉 Windows Defender 即時保護
    - 設定時區為台北標準時間
    - 設定靜態 IP 位址
    - 更改電腦名稱為 'ad2016'
    - 設定 Administrator 帳戶密碼
    - 要求使用者登入時必須輸入密碼
    - 完成後自動重新啟動電腦

.NOTES
    注意: 必須以系統管理員身分執行此腳本。
#>

# --- 檢查是否以系統管理員身分執行 ---
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "此腳本需要系統管理員權限！請以系統管理員身分重新執行。"
    Exit
}

# --- 變數設定 (可依據您的環境修改) ---
$computerName = "2016ad"
$ipAddress = "192.168.11.100"
$subnetPrefix = 24 # 相當於子網路遮罩 255.255.255.0
$dnsServer = "192.168.11.100"
$timeZone = "Taipei Standard Time"
$adminPassword = "P@ssw0rd2016ad02" # 教材中設定的密碼
$interfaceAlias = "Ethernet0" # 網路卡名稱，請依據實際情況調整

# --- 腳本執行開始 ---
Write-Host "開始自動化伺服器初始設定..." -ForegroundColor Green

# 1. 關閉防火牆 (教材 p.16)
Write-Host "正在關閉私人和公用網路的 Windows 防火牆..."
Set-NetFirewallProfile -Profile Private, Public -Enabled False
Write-Host "防火牆已關閉。" -ForegroundColor Green

# 2. 關閉 Windows Defender 即時保護 (根據您的新要求新增)
Write-Host "正在關閉 Windows Defender 即時保護..."
try {
    Set-MpPreference -DisableRealtimeMonitoring $true
    Write-Host "即時保護已關閉。" -ForegroundColor Green
} catch {
    Write-Warning "關閉即時保護失敗。在某些伺服器版本或有其他防毒軟體時可能受影響。"
}

# 3. 設定時區 (教材 p.17)
Write-Host "正在設定時區為 '$timeZone'..."
Set-TimeZone -Id $timeZone
Write-Host "時區設定完成。" -ForegroundColor Green

# 4. 設定網路介面卡 (教材 p.17-18)
Write-Host "正在設定網路介面卡 '$interfaceAlias'..."
try {
    Get-NetAdapter -Name $interfaceAlias | ForEach-Object {
        # 移除舊的 IP 設定以避免衝突
        Remove-NetIPAddress -InterfaceAlias $_.Name -Confirm:$false -ErrorAction SilentlyContinue
        
        # 設定新的靜態 IP 位址
        New-NetIPAddress -InterfaceAlias $_.Name -IPAddress $ipAddress -PrefixLength $subnetPrefix
        
        # 設定 DNS 伺服器
        Set-DnsClientServerAddress -InterfaceAlias $_.Name -ServerAddresses $dnsServer
        
        # 停用 IPv6
        Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6
    }
    Write-Host "網路介面卡設定完成: IP=$ipAddress, DNS=$dnsServer, IPv6 已停用。" -ForegroundColor Green
} catch {
    Write-Error "網路設定失敗！請檢查網路介面卡名稱 ('$interfaceAlias') 是否正確。"
    Exit
}

# 5. 設定 Administrator 密碼 (教材 p.21)
Write-Host "正在設定 Administrator 帳戶的密碼..."
try {
    # 使用 net user 命令，這是在腳本中設定密碼的直接方法
    net user Administrator $adminPassword
    Write-Host "Administrator 密碼設定完成。" -ForegroundColor Green
} catch {
    Write-Error "設定 Administrator 密碼失敗！"
    Exit
}

# 6. 要求使用者登入時輸入密碼 (netplwiz 的腳本化操作) (教材 p.22-23)
Write-Host "正在設定為必須輸入使用者名稱和密碼才能登入..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value 0
Write-Host "登入設定完成。" -ForegroundColor Green

# 7. 更改電腦名稱 (教材 p.19)
# 這一步放在最後，因為它需要重新啟動
Write-Host "正在將電腦名稱更改為 '$computerName'..."
Rename-Computer -NewName $computerName -Force
Write-Host "電腦名稱已設定。變更將在重新啟動後生效。" -ForegroundColor Green


# --- 完成並準備重新啟動 ---
Write-Host "所有設定已完成。電腦將立即重新啟動以套用所有變更。" -ForegroundColor Yellow
Restart-Computer -Force