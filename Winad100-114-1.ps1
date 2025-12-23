# ESXi vSwitch and Network Configuration Script
# Lab Manual p.100-114

# === CONFIG ===
$vCenterServer = "vcsav7.vmcj10217.local"

$hostsConfig = @(
  @{
    HostName = "esxiv701.vmcj10217.local"
    vSwitches = @(
      @{
        Name = "vSwitch1"; Purpose = "vMotion"; Nics = @("vmnic1")
        VMKernel = @{ PortGroupName = "for vMotion"; IP = "192.168.217.61"; SubnetMask = "255.255.255.0"; EnablevMotion = $true; EnableiSCSI = $false }
      },
      @{
        Name = "vSwitch2"; Purpose = "Production/Test"; Nics = @("vmnic2","vmnic3","vmnic4")
        PortGroups = @(
          @{ Name = "production"; TeamingPolicy = @{ Active=@("vmnic2","vmnic3"); Standby=@("vmnic4"); Unused=@() } },
          @{ Name = "test";       TeamingPolicy = @{ Active=@("vmnic2");         Standby=@("vmnic3"); Unused=@("vmnic4") } }
        )
      },
      @{
        Name = "vSwitch3"; Purpose = "iSCSI"; Nics = @("vmnic5")
        VMKernel = @{ PortGroupName = "for iSCSI"; IP = "192.168.217.51"; SubnetMask = "255.255.255.0"; EnablevMotion = $false; EnableiSCSI = $true }
      }
    )
  },
  @{
    HostName = "esxiv702.vmcj10217.local"
    vSwitches = @(
      @{
        Name = "vSwitch1"; Purpose = "vMotion"; Nics = @("vmnic1")
        VMKernel = @{ PortGroupName = "for vMotion"; IP = "192.168.217.62"; SubnetMask = "255.255.255.0"; EnablevMotion = $true; EnableiSCSI = $false }
      },
      @{
        Name = "vSwitch2"; Purpose = "Production/Test"; Nics = @("vmnic2","vmnic3","vmnic4")
        PortGroups = @(
          @{ Name = "production"; TeamingPolicy = @{ Active=@("vmnic2","vmnic3"); Standby=@("vmnic4"); Unused=@() } },
          @{ Name = "test";       TeamingPolicy = @{ Active=@("vmnic2");         Standby=@("vmnic3"); Unused=@("vmnic4") } }
        )
      },
      @{
        Name = "vSwitch3"; Purpose = "iSCSI"; Nics = @("vmnic5")
        VMKernel = @{ PortGroupName = "for iSCSI"; IP = "192.168.217.52"; SubnetMask = "255.255.255.0"; EnablevMotion = $false; EnableiSCSI = $true }
      }
    )
  }
)


# Start Script Execution
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ESXi vSwitch Configuration Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

try {
    # Step 1: Connect to vCenter Server
    Write-Host "Step 1: Connect to vCenter Server: $vCenterServer" -ForegroundColor Yellow
    
    # Set PowerCLI configuration (fast and silent)
    Write-Host "  - Configuring PowerCLI..." -NoNewline
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds 300 -Confirm:$false -Scope Session -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    
    # Connect to vCenter
    Write-Host "  - Connecting to vCenter..." -NoNewline
    Connect-VIServer -Server $vCenterServer -Force -ErrorAction Stop | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    Write-Host ""

    # Process each host configuration
    foreach ($config in $hostsConfig) {
        Write-Host "--------------------------------------------------" -ForegroundColor Cyan
        Write-Host "Configuring host: $($config.HostName)" -ForegroundColor Cyan
        
        try {
            $vmhost = Get-VMHost -Name $config.HostName -ErrorAction Stop
            
            # Remove default 'VM Network' port group
            Write-Host "Removing default 'VM Network' port group..." -ForegroundColor Yellow
            Get-VirtualPortGroup -VMHost $vmhost -Name "VM Network" -ErrorAction SilentlyContinue | Remove-VirtualPortGroup -Confirm:$false
            Write-Host "Default 'VM Network' port group removed." -ForegroundColor Green

            # Process each vSwitch configuration
            foreach ($vSwitchConfig in $config.vSwitches) {
                Write-Host "Creating $($vSwitchConfig.Name) ($($vSwitchConfig.Purpose))..." -ForegroundColor Yellow
                
                # Create the vSwitch
                $vSwitch = New-VirtualSwitch -VMHost $vmhost -Name $vSwitchConfig.Name -Nic $vSwitchConfig.Nics
                
                # Configure based on purpose
                if ($vSwitchConfig.VMKernel) {
                    # Create VMkernel adapter for iSCSI or vMotion
                    $vmkParams = @{
                        VMHost = $vmhost
                        VirtualSwitch = $vSwitch
                        PortGroup = $vSwitchConfig.VMKernel.PortGroupName
                        IP = $vSwitchConfig.VMKernel.IP
                        SubnetMask = $vSwitchConfig.VMKernel.SubnetMask
                    }
                    
                    if ($vSwitchConfig.VMKernel.EnablevMotion) {
                        $vmkParams.VMotionEnabled = $true
                    }
                    
                    New-VMHostNetworkAdapter @vmkParams
                    Write-Host "$($vSwitchConfig.Name) VMkernel adapter configured (IP: $($vSwitchConfig.VMKernel.IP))." -ForegroundColor Green
                }
                
                if ($vSwitchConfig.PortGroups) {
                    # Create port groups for VM traffic
                    foreach ($pgConfig in $vSwitchConfig.PortGroups) {
                        $portGroup = New-VirtualPortGroup -VirtualSwitch $vSwitch -Name $pgConfig.Name
                        
                        # Configure teaming policy based on detailed configuration
                        if ($pgConfig.TeamingPolicy -is [hashtable]) {
                            $teamingParams = @{}
                            
                            # Set active NICs
                            if ($pgConfig.TeamingPolicy.Active -and $pgConfig.TeamingPolicy.Active.Count -gt 0) {
                                $teamingParams.MakeNicActive = $pgConfig.TeamingPolicy.Active
                            }
                            
                            # Set standby NICs
                            if ($pgConfig.TeamingPolicy.Standby -and $pgConfig.TeamingPolicy.Standby.Count -gt 0) {
                                $teamingParams.MakeNicStandby = $pgConfig.TeamingPolicy.Standby
                            }
                            
                            # Set unused NICs
                            if ($pgConfig.TeamingPolicy.Unused -and $pgConfig.TeamingPolicy.Unused.Count -gt 0) {
                                $teamingParams.MakeNicUnused = $pgConfig.TeamingPolicy.Unused
                            }
                            
                            # Apply teaming policy if we have parameters
                            if ($teamingParams.Count -gt 0) {
                                Get-NicTeamingPolicy -VirtualPortGroup $portGroup | Set-NicTeamingPolicy @teamingParams
                                Write-Host "    - Teaming policy: Active=$($pgConfig.TeamingPolicy.Active -join ','), Standby=$($pgConfig.TeamingPolicy.Standby -join ','), Unused=$($pgConfig.TeamingPolicy.Unused -join ',')" -ForegroundColor Cyan
                            }
                        }
                        
                        Write-Host "Port group '$($pgConfig.Name)' created successfully." -ForegroundColor Green
                    }
                }
                
                Write-Host "$($vSwitchConfig.Name) ($($vSwitchConfig.Purpose)) configuration completed." -ForegroundColor Green
            }

            Write-Host "Host $($config.HostName) configuration completed successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to configure host $($config.HostName): $($_.Exception.Message)" -ForegroundColor Red
        }
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
}
finally {
    if ($global:DefaultVIServers.Count -gt 0) {
        Write-Host ""
        Write-Host "Disconnecting from vCenter..." -NoNewline
        Disconnect-VIServer -Confirm:$false
        Write-Host " [OK]" -ForegroundColor Green
    }
}