# vCenter Datacenter and ESXi Host Management Script
# Lab Manual p.95-99

$vCenterServer = "vcsav7.vmcj10217.local"  # vCenter Server address
$datacenterName = "dc"  # Datacenter name to create
$esxiHostsToAdd = @(
    @{
        Name     = "esxiv701.vmcj10217.local"
        User     = "root"
        Password = "P@ssw0rd2016ad02"
    },
    @{
        Name     = "esxiv702.vmcj10217.local"
        User     = "root"
        Password = "P@ssw0rd2016ad02"
    }
)

# Start Script Execution
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  vCenter Datacenter & Host Management" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Set PowerCLI configuration (fast and silent)
    Write-Host "Step 1: Configure PowerCLI..." -NoNewline
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds 300 -Confirm:$false -Scope Session -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    
    # Connect to vCenter Server
    Write-Host "Step 2: Connect to vCenter Server: $vCenterServer..." -NoNewline
    Connect-VIServer -Server $vCenterServer -Force -ErrorAction Stop | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    Write-Host ""

    # Create datacenter if it doesn't exist
    Write-Host "Step 3: Check datacenter '$datacenterName'..." -NoNewline
    $datacenter = Get-Datacenter -Name $datacenterName -ErrorAction SilentlyContinue
    
    if (-not $datacenter) {
        $datacenter = New-Datacenter -Name $datacenterName -Location (Get-Folder -NoRecursion)
        Write-Host " [Created]" -ForegroundColor Green
    } else {
        Write-Host " [Already exists]" -ForegroundColor Yellow
    }
    Write-Host ""

    # Add ESXi hosts to the datacenter
    Write-Host "Step 4: Add ESXi hosts to datacenter" -ForegroundColor Yellow
    $hostCount = 0
    foreach ($hostInfo in $esxiHostsToAdd) {
        Write-Host "  - Check host: $($hostInfo.Name)..." -NoNewline
        
        # Check if host already exists in vCenter
        $existingHost = Get-VMHost -Name $hostInfo.Name -ErrorAction SilentlyContinue
        
        if (-not $existingHost) {
            try {
                # Add host to datacenter
                Add-VMHost -Name $hostInfo.Name -Location $datacenter -User $hostInfo.User -Password $hostInfo.Password -Force -RunAsync | Out-Null
                Write-Host " [Added]" -ForegroundColor Green
                $hostCount++
            }
            catch {
                Write-Host " [Failed]" -ForegroundColor Red
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host " [Already exists]" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    if ($hostCount -gt 0) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  $hostCount host(s) added successfully!" -ForegroundColor Green
        Write-Host "  Monitor progress in vSphere Client" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
    } else {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  All hosts already configured!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
    }
}
catch {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  Error" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    # Disconnect from vCenter
    if ($global:DefaultVIServers.Count -gt 0) {
        Write-Host ""
        Write-Host "Disconnecting from vCenter..." -NoNewline
        Disconnect-VIServer -Confirm:$false
        Write-Host " [OK]" -ForegroundColor Green
    }
}