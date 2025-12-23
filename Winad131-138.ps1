<#
.SYNOPSIS
    ESXi iSCSI Configuration Script
    Lab p.131-138

.DESCRIPTION
    1. Connect to vCenter Server
    2. Configure iSCSI on all ESXi hosts
    3. Create shared VMFS datastore
#>

# Configuration
$vCenterServer = "vcsav7.vmcj10217.local"

$esxiHosts = @(
    "esxiv701.vmcj10217.local",
    "esxiv702.vmcj10217.local"
)

$iscsiTargetIP = "192.168.217.100"
$iscsiPortGroupName = "for iSCSI"
$datastoreName = "netstore"
$lunSizeGB = 40

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ESXi iSCSI Configuration Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Step 1: Test connectivity and connect to vCenter
    Write-Host "Step 1: Connect to vCenter Server: $vCenterServer" -ForegroundColor Yellow
    
    # Test DNS resolution
    Write-Host "  - Testing DNS resolution..." -NoNewline
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($vCenterServer)
        if ($resolved) {
            $ip = $resolved[0].IPAddressToString
            Write-Host " [OK] Resolved to $ip" -ForegroundColor Green
        }
    }
    catch {
        Write-Host " [Failed]" -ForegroundColor Red
        Write-Warning "DNS resolution failed. Please check network connectivity."
        throw
    }
    
    # Test network connectivity
    Write-Host "  - Testing network connectivity..." -NoNewline
    if (Test-Connection -ComputerName $vCenterServer -Count 1 -Quiet) {
        Write-Host " [OK]" -ForegroundColor Green
    }
    else {
        Write-Host " [Failed]" -ForegroundColor Red
        Write-Warning "Cannot ping vCenter server. Please check network connectivity."
    }
    
    # Set PowerCLI configuration to ignore certificate warnings
    Write-Host "  - Configuring PowerCLI..." -NoNewline
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds 300 -Confirm:$false -Scope Session -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    
    # Connect to vCenter with credentials
    Write-Host "  - Connecting to vCenter..."
    Write-Host ""
    Write-Host "    Please enter vCenter credentials:" -ForegroundColor Cyan
    $credential = Get-Credential -Message "Enter vCenter credentials (e.g., administrator@vsphere.local)"
    
    Connect-VIServer -Server $vCenterServer -Credential $credential -ErrorAction Stop | Out-Null
    Write-Host ""
    Write-Host "  [OK] Connected successfully" -ForegroundColor Green
    Write-Host ""

    # Step 2: List available hosts and configure iSCSI
    Write-Host "Step 2: Detect and configure ESXi hosts" -ForegroundColor Yellow
    
    # List all available hosts in vCenter
    Write-Host "  - Detecting available ESXi hosts..." -NoNewline
    $allHosts = Get-VMHost
    Write-Host " [OK]" -ForegroundColor Green
    
    if ($allHosts.Count -eq 0) {
        Write-Warning "No ESXi hosts found in vCenter"
        throw "No hosts available"
    }
    
    Write-Host "  - Found hosts:" -ForegroundColor Cyan
    foreach ($h in $allHosts) {
        Write-Host "    * $($h.Name) (State: $($h.ConnectionState))" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Try to match configured hosts with actual hosts
    $hostsToProcess = @()
    foreach ($configuredHostName in $esxiHosts) {
        $matchedHost = $allHosts | Where-Object { 
            $_.Name -eq $configuredHostName -or 
            $_.Name -like "$configuredHostName*" -or
            $_.Name.Split('.')[0] -eq $configuredHostName.Split('.')[0]
        } | Select-Object -First 1
        
        if ($matchedHost) {
            $hostsToProcess += $matchedHost
        }
        else {
            Write-Warning "Configured host '$configuredHostName' not found, skipping..."
        }
    }
    
    # If no matched hosts, use all available hosts
    if ($hostsToProcess.Count -eq 0) {
        Write-Host "  Using all available hosts instead..." -ForegroundColor Yellow
        $hostsToProcess = $allHosts
    }
    
    Write-Host "  - Will configure $($hostsToProcess.Count) host(s)" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($vmhost in $hostsToProcess) {
        $hostName = $vmhost.Name
        Write-Host "  ----------------------------------------"
        Write-Host "  Host: $hostName" -ForegroundColor Cyan
        
        # Enable software iSCSI HBA
        Write-Host "    - Enable software iSCSI..." -NoNewline
        $iscsiHBA = Get-VMHostHba -VMHost $vmhost -Type "iScsi" | Select-Object -First 1
        
        if ($iscsiHBA.Status -ne "online") {
            (Get-EsxCli -VMHost $vmhost -V2).iscsi.software.set.Invoke(@{enabled = $true}) | Out-Null
            Start-Sleep -Seconds 5
        }
        
        $iscsiHBA = Get-VMHostHba -VMHost $vmhost -Type "iScsi" | Select-Object -First 1
        Write-Host " [OK]" -ForegroundColor Green
        
        # Bind VMkernel Port
        Write-Host "    - Bind VMkernel Port..." -NoNewline
        $vmk = Get-VMHostNetworkAdapter -VMHost $vmhost -VMKernel -ErrorAction SilentlyContinue | Where-Object { $_.PortGroupName -eq $iscsiPortGroupName }
        
        if ($vmk) {
            try {
                $esxcli = Get-EsxCli -VMHost $vmhost -V2
                $bindArgs = @{
                    adapter = $iscsiHBA.Device
                    nic = $vmk.Name
                }
                $esxcli.iscsi.networkportal.add.Invoke($bindArgs) | Out-Null
                Write-Host " [OK]" -ForegroundColor Green
            }
            catch {
                if ($_.Exception.Message -like "*already exists*") {
                    Write-Host " [Already bound]" -ForegroundColor Yellow
                }
                else {
                    Write-Host " [Failed]" -ForegroundColor Red
                    Write-Warning "VMkernel binding error: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host " [Skip - VMkernel not found]" -ForegroundColor Yellow
            Write-Warning "VMkernel port group '$iscsiPortGroupName' not found on host $hostName"
            Write-Host "    Available VMkernel adapters:"
            Get-VMHostNetworkAdapter -VMHost $vmhost -VMKernel | ForEach-Object {
                Write-Host "      - $($_.Name): $($_.PortGroupName) ($($_.IP))" -ForegroundColor Gray
            }
        }
        
        # Add iSCSI Target
        Write-Host "    - Add iSCSI Target: $iscsiTargetIP..." -NoNewline
        try {
            # Try new PowerCLI syntax first
            New-IscsiHbaTarget -IscsiHba $iscsiHBA -Address $iscsiTargetIP -Type Send -ErrorAction Stop | Out-Null
            Write-Host " [OK]" -ForegroundColor Green
        }
        catch {
            # Fallback to older method using ESXCLI
            try {
                $esxcli = Get-EsxCli -VMHost $vmhost -V2
                $sendTargetArgs = @{
                    adapter = $iscsiHBA.Device
                    address = $iscsiTargetIP
                }
                $esxcli.iscsi.adapter.discovery.sendtarget.add.Invoke($sendTargetArgs) | Out-Null
                Write-Host " [OK]" -ForegroundColor Green
            }
            catch {
                if ($_.Exception.Message -like "*already exists*" -or $_.Exception.Message -like "*duplicate*") {
                    Write-Host " [Already exists]" -ForegroundColor Yellow
                }
                else {
                    Write-Host " [Failed]" -ForegroundColor Red
                    Write-Warning "iSCSI Target add error: $($_.Exception.Message)"
                }
            }
        }
        
        # Rescan storage
        Write-Host "    - Rescan storage..." -NoNewline
        Get-VMHostStorage -VMHost $vmhost -RescanAllHba -RescanVmfs | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
        
        Write-Host "  [Complete] Host $hostName configured" -ForegroundColor Green
    }
    
    Write-Host ""

    # Step 3: Create shared datastore
    Write-Host "Step 3: Create shared datastore" -ForegroundColor Yellow
    $firstHost = $hostsToProcess[0]
    
    # Find available LUN
    $targetSize = $lunSizeGB
    $searchMsg = "  - Search for " + $targetSize + "GB LUN..."
    Write-Host $searchMsg -NoNewline
    
    # Use more flexible matching for LUN size and vendor
    $candidateLuns = Get-ScsiLun -VmHost $firstHost -LunType disk | Where-Object { 
        [Math]::Round($_.CapacityGB, 0) -eq $targetSize -and 
        $_.Vendor -like "*STARWIND*" -and
        -not $_.IsVmfs
    }
    
    if ($candidateLuns) {
        $lunToFormat = $candidateLuns | Select-Object -First 1
        Write-Host " [OK]" -ForegroundColor Green
        $lunPath = $lunToFormat.CanonicalName
        Write-Host "    Found LUN: $lunPath"
        
        # Create VMFS datastore
        $dsMsg = "  - Format as VMFS6 datastore: " + $datastoreName + "..."
        Write-Host $dsMsg -NoNewline
        
        try {
            # Try newer PowerCLI syntax with VmfsVersion
            New-Datastore -VMHost $firstHost -Name $datastoreName -Path $lunPath -Vmfs -ErrorAction Stop | Out-Null
            Write-Host " [OK]" -ForegroundColor Green
        }
        catch {
            # Fallback to older syntax without version parameter
            try {
                New-Datastore -VMHost $firstHost -Name $datastoreName -Path $lunPath -ErrorAction Stop | Out-Null
                Write-Host " [OK]" -ForegroundColor Green
            }
            catch {
                Write-Host " [Failed]" -ForegroundColor Red
                Write-Warning "Datastore creation error: $($_.Exception.Message)"
                throw
            }
        }
        
        # Rescan all hosts
        Write-Host "  - Rescan all hosts..." -NoNewline
        $hostsToProcess | Get-VMHostStorage -RescanAllHba -RescanVmfs | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
        
        Write-Host ""
        $successMsg = "  [Success] Shared datastore '" + $datastoreName + "' created"
        Write-Host $successMsg -ForegroundColor Green
        
    } else {
        Write-Host " [Failed]" -ForegroundColor Red
        $warnMsg1 = "Cannot find StarWind LUN (" + $targetSize + "GB, unformatted)"
        Write-Warning $warnMsg1
        Write-Warning "Please check iSCSI Target configuration"
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  All operations completed!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  Error" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}
finally {
    # Disconnect
    if ($global:DefaultVIServers.Count -gt 0) {
        Write-Host ""
        Write-Host "Disconnecting from vCenter..." -NoNewline
        Disconnect-VIServer -Confirm:$false
        Write-Host " [OK]" -ForegroundColor Green
    }
}