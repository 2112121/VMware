<#
.SYNOPSIS
    對應 VMware Lab 教材 p.25-33
    安裝 Active Directory 網域服務並將伺服器升級為新的網域樹系中的第一個網域控制站。

.DESCRIPTION
    1. 安裝 AD DS 角色及相關管理工具。
    2. 建立一個新的 AD 樹系。
    3. 設定網域名稱、DSRM 密碼並安裝 DNS 服務。
    4. 執行完畢後會自動重新啟動。
#>

# --- 變數設定 ---
$domainName = "vmcj10217.local"
$netbiosName = "VMCJ10217"
$dsrmPassword = "P@ssw0rd2016ad02"

# --- 腳本執行 ---

# 檢查是否以系統管理員身分執行
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "此腳本需要系統管理員權限！請以系統管理員身分重新執行。"
    Exit
}

Write-Host "步驟 1/3: 正在安裝 Active Directory Domain Services 角色... (對應 p.25-28)" -ForegroundColor Green
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Write-Host "步驟 2/3: 正在準備將此伺服器升級為網域控制站... (對應 p.29-32)" -ForegroundColor Green

# 將密碼轉換為 PowerShell 所需的安全字串格式
$secureDSRMPassword = ConvertTo-SecureString -AsPlainText $dsrmPassword -Force

# 匯入 AD 部署模組
Import-Module ADDSDeployment

# 執行樹系安裝與伺服器升級
Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainName $domainName `
    -DomainNetbiosName $netbiosName `
    -ForestMode "WinThreshold" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true `
    -SafeModeAdministratorPassword $secureDSRMPassword

Write-Host "步驟 3/3: 升級命令已發送。伺服器即將自動重新啟動。" -ForegroundColor Yellow