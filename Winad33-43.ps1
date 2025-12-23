<#
.SYNOPSIS
    對應 VMware Lab 教材 p.34-42
    設定 DNS 反向對應區域，並為 Lab 環境建立所需的 A 紀錄與 PTR 紀錄。

.DESCRIPTION
    1. 建立 IPv4 反向對應區域 (192.168.216.x)。
    2. 確保 ad2016 的 PTR 紀錄存在。
    3. 為 esxi01, esxi02, vc 建立 A 紀錄與關聯的 PTR 紀錄。
#>

# --- 變數設定 ---
$reverseZoneNetworkID = "192.168.217.0/24"
$reverseZoneName = "217.168.192.in-addr.arpa"
$forwardZoneName = "vmcj10217.local"

# 定義要建立的 DNS 紀錄
$dnsRecords = @(
    @{ Name = "esxiv701"; IP = "192.168.217.101" },
    @{ Name = "esxiv702"; IP = "192.168.217.102" },
    @{ Name = "vcsav7";     IP = "192.168.217.250" }
)

# --- 腳本執行 ---

# 檢查是否以系統管理員身分執行
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "此腳本需要系統管理員權限！請以系統管理員身分重新執行。"
    Exit
}

Write-Host "步驟 1/2: 正在建立 DNS 反向對應區域... (對應 p.34-37)" -ForegroundColor Green

# 檢查區域是否已存在，若否，則建立
if (-not (Get-DnsServerZone -Name $reverseZoneName -ErrorAction SilentlyContinue)) {
    Add-DnsServerPrimaryZone -NetworkID $reverseZoneNetworkID -ReplicationScope Domain -DynamicUpdate None
    Write-Host "DNS 反向對應區域 '$reverseZoneName' 已建立。" -ForegroundColor Green
} else {
    Write-Host "DNS 反向對應區域 '$reverseZoneName' 已存在，跳過建立步驟。" -ForegroundColor Yellow
}

# 根據教材，AD安裝時應已自動建立ad2016的PTR紀錄，此處確保其存在 (對應 p.38-40)
$dcIP = "192.168.217.100"
$dcName = "2016ad"
$dcFqdn = "$dcName.$forwardZoneName"
$ptrName = $dcIP.Split('.')[-1]

if (-not (Get-DnsServerResourceRecord -ZoneName $reverseZoneName -Name $ptrName -RRType Ptr -ErrorAction SilentlyContinue)) {
    Add-DnsServerResourceRecord -Ptr -Name $ptrName -ZoneName $reverseZoneName -PtrDomainName $dcFqdn
    Write-Host "已為 $dcFqdn 建立 PTR 紀錄。" -ForegroundColor Green
}

Write-Host "步驟 2/2: 正在為 esxi01, esxi02, vc 建立 DNS 紀錄... (對應 p.41-42)" -ForegroundColor Green
foreach ($record in $dnsRecords) {
    Write-Host " - 正在為 $($record.Name) 建立 A 與 PTR 紀錄 (IP: $($record.IP))"
    Add-DnsServerResourceRecord -A -Name $record.Name -ZoneName $forwardZoneName -IPv4Address $record.IP -CreatePtr -TimeToLive (New-TimeSpan -Hours 1)
}

Write-Host "DNS 設定完成！" -ForegroundColor Cyan
Write-Host "您可以使用 'Resolve-DnsName <hostname>' 或 'nslookup' 來驗證設定。 (對應 p.43)"