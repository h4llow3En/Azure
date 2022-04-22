<#
.SYNOPSIS
    Moves a selected VM and its disks to a target availability zone
.DESCRIPTION
    Moves a selected VM and its disks to a target availability zone
.PARAMETER LogPath
    Logpath output for all operations
.PARAMETER LogRollover
    Number of days before logfiles are rolled over. Default is 5
.PARAMETER subscriptionId
    Sets the Subscription ID for the operation
.PARAMETER ResourceGroup
    Sets the Resource Group Name for the operations
.PARAMETER Location
    Sets the Azure Location
.PARAMETER Zone
    Sets the desired Availability Zone
.PARAMETER OSType
    Specifies either Windows or Linux OS type. Defaults to Windows
.PARAMETER CleanupSnapshots
    Cleans up Snapshots after migration (deletes!)
.PARAMETER CleanupSourceDisks
    Cleans up source disks after migration (deletes!)

.EXAMPLE
  .\ChangeVMAz.ps1 -subscriptionId "89745-888-9978" -ResourceGroup "RG-AE-TEST" -vmName "MyVM" -Location "australiaeast" -Zone 1 -CleanupSnapshots -CleanupSourceDisks 
  Moves the desired VM to AZ1 and cleans up snapshots and source disks. Outputs to C:\Logs\ZoneMigrate_VMName.log
#>

#region Params
# ============================================================================
# Parameters
# ============================================================================
Param(
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\ZoneMigrate_$vmName.log", 

    [Parameter(Mandatory = $false)]
    [int]$LogRollover = 5, # number of days before logfile rollover occurs

    [Parameter(Mandatory = $True)]
    [string]$SubscriptionId = "", # subscription ID

    [Parameter(Mandatory = $True)]
    [string]$ResourceGroup = "", # Resource Group Name

    [Parameter(Mandatory = $True)]
    [string]$vmName = "", # VM Name

    [Parameter(Mandatory = $True)]
    [string]$Location = "", # Azure Location

    [Parameter(Mandatory = $True)]
    [ValidateSet("1","2","3")]
    [string]$Zone = "", # Target Zone

    [Parameter(Mandatory = $False)]
    [ValidateSet("Windows","Linux")]
    [String]$OSType = "Windows", #Windows or Linux

    [Parameter(Mandatory = $false)]
    [switch]$CleanupSnapshots, # Cleanup Snapshots

    [Parameter(Mandatory = $false)]
    [switch]$CleanupSourceDisks # Cleanup Source Disks

)
#endregion

#region Functions
# ============================================================================
# Functions
# ============================================================================
function Write-Log {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("LogContent")]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [Alias('LogPath')]
        [string]$Path = $LogPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $false)]
        [switch]$NoClobber
    )

    Begin {
        # Set VerbosePreference to Continue so that verbose messages are displayed.
        $VerbosePreference = 'Continue'
    }
    Process {
        
        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -AND $NoClobber) {
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name."
            Return
        }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path.
        elseif (!(Test-Path $Path)) {
            Write-Verbose "Creating $Path."
            $NewLogFile = New-Item $Path -Force -ItemType File
        }

        else {
            # Nothing to see here yet.
        }

        # Format Date for our Log File
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Write message to error, warning, or verbose pipeline and specify $LevelText
        switch ($Level) {
            'Error' {
                Write-Error $Message
                $LevelText = 'ERROR:'
            }
            'Warn' {
                Write-Warning $Message
                $LevelText = 'WARNING:'
            }
            'Info' {
                Write-Verbose $Message
                $LevelText = 'INFO:'
            }
        }
        
        # Write log entry to $Path
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append
    }
    End {
    }
}

function Start-Stopwatch {
    Write-Log -Message "Starting Timer" -Level Info
    $Global:StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
}

function Stop-Stopwatch {
    Write-Log -Message "Stopping Timer" -Level Info
    $StopWatch.Stop()
    if ($StopWatch.Elapsed.TotalSeconds -le 1) {
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.TotalMilliseconds) ms to complete." -Level Info
    }
    else {
        Write-Log -Message "Script processing took $($StopWatch.Elapsed.TotalSeconds) seconds to complete." -Level Info
    }
}

function RollOverlog {
    $LogFile = $LogPath
    $LogOld = Test-Path $LogFile -OlderThan (Get-Date).AddDays(-$LogRollover)
    $RolloverDate = (Get-Date -Format "dd-MM-yyyy")
    if ($LogOld) {
        Write-Log -Message "$LogFile is older than $LogRollover days, rolling over" -Level Info
        $NewName = [io.path]::GetFileNameWithoutExtension($LogFile)
        $NewName = $NewName + "_$RolloverDate.log"
        Rename-Item -Path $LogFile -NewName $NewName
        Write-Log -Message "Old logfile name is now $NewName" -Level Info
    }    
}

function ImportModule {
    param (
        [Parameter(Mandatory = $True)]
        [String]$ModuleName
    )
    Write-Log -Message "Importing $ModuleName Module" -Level Info
    try {
        Import-Module -Name $ModuleName -Force -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to Import $ModuleName Module. Exiting" -Level Warn
        StopIteration
        Exit 1
    }
}

function StartIteration {
    Write-Log -Message "--------Starting Iteration--------" -Level Info
    RollOverlog
    Start-Stopwatch
}

function StopIteration {
    Stop-Stopwatch
    Write-Log -Message "--------Finished Iteration--------" -Level Info
}

#endregion

#region Variables
# ============================================================================
# Variables
# ============================================================================
# Set Variables

#endregion

#Region Execute
# ============================================================================
# Execute
# ============================================================================
StartIteration

Write-Log -Message "Setting Azure Subscription to: $($SubscriptionId)" -Level Info

try {
    Select-AzSubscription -Subscriptionid $SubscriptionId -ErrorAction Stop | Out-Null
}
catch {
    Write-Log -Message $_ -Level Warn
    break
}

# Get the VM and Disks
Write-Log -Message "Getting Virtual Machine Details for $($vmName)" -Level Info

try {
    $originalVM = Get-AzVM -ResourceGroupName $resourceGroup -Name $vmName -ErrorAction Stop
    Write-Log -Message "Retrieved Virtual Machine Details for $($vmName)" -Level Info
    Write-Log -Message "Getting OS Disk Details for $($vmName)" -Level Info
    $OriginalOSDisk = $originalVM.StorageProfile.OsDisk
    Write-Log -Message "Getting Data Disk Details for $($vmName)" -Level Info
    $OriginalDataDisks = $originalVM.StorageProfile.DataDisks
    Write-Log -Message "There are $($OriginalDataDisks.Count) data disks for $($vmName)" -Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
    break
}

# Stop the VM to take snapshot
try {
    Write-Log -Message "Stopping VM: $($vmName)" -Level Info
    Stop-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force -ErrorAction Stop | out-Null
    Write-Log -Message "Stopped VM: $($vmName)" -Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
    break
}

# Create a SnapShot of the OS disk and then, create an Azure Disk with Zone information
try {
    # Create the Snapshot
    Write-Log -Message "Creating OS Disk Snapshot for $($OriginalOSDisk.Name)" -Level Info
    $DiskDetailsOS = Get-AzDisk -ResourceGroupName $originalVM.ResourceGroupName -DiskName $OriginalOSDisk.Name -ErrorAction Stop
    $snapshotOSConfig = New-AzSnapshotConfig -SourceUri $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy -SkuName Standard_ZRS -ErrorAction Stop
    $OSSnapshot = New-AzSnapshot -Snapshot $snapshotOSConfig -SnapshotName ($originalVM.StorageProfile.OsDisk.Name + "-snapshot") -ResourceGroupName $resourceGroup -ErrorAction Stop
    Write-Log -Message "Created OS Disk Snapshot: $($OSSnapshot.Name)" -Level Info
    
    #Create the Disk
    Write-Log -Message "Creating OS Disk in zone: $($Zone)" -Level Info
    $diskConfig = New-AzDiskConfig -Location $OSSnapshot.Location -SourceResourceId $OSSnapshot.Id -CreateOption Copy -SkuName $DiskDetailsOS.Sku.Name -Zone $zone -ErrorAction Stop
    $OSdisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName ($originalVM.StorageProfile.OsDisk.Name + "_z_$Zone") -ErrorAction Stop
    Write-Log -Message "Created OS Disk $($OSDisk.Name) in zone: $($Zone)" -Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
    break
}

# Create a Snapshot from the Data Disks and the Azure Disks with Zone information
try {
    Write-Log -Message "Creating Data Disk Snapshots" -Level Info
    foreach ($disk in $originalVM.StorageProfile.DataDisks) {
        # Create the Snapshot
        Write-Log -Message "Getting Disk details for $($Disk.Name)" -Level Info
        $DiskDetails = Get-AzDisk -ResourceGroupName $originalVM.ResourceGroupName -DiskName $disk.Name -ErrorAction Stop

        Write-Log -Message "Creating snapshot for $($Disk.Name)" -Level Info
        $snapshotDataConfig = New-AzSnapshotConfig -SourceUri $disk.ManagedDisk.Id -Location $location -CreateOption copy -SkuName Standard_ZRS -ErrorAction Stop
        $DataSnapshot = New-AzSnapshot -Snapshot $snapshotDataConfig -SnapshotName ($disk.Name + '-snapshot') -ResourceGroupName $resourceGroup -ErrorAction Stop
        Write-Log -Message "Created Snapshot: $($DataSnapshot.Name)" -Level Info

        #Create the Disk
        Write-Log -Message "Creating Data Disk $($disk.Name + "_z_$Zone") in zone: $($Zone)" -Level Info
        $datadiskConfig = New-AzDiskConfig -Location $DataSnapshot.Location -SourceResourceId $DataSnapshot.Id -CreateOption Copy -SkuName $DiskDetails.Sku.Name -Zone $zone
        $datadisk = New-AzDisk -Disk $datadiskConfig -ResourceGroupName $resourceGroup -DiskName ($disk.Name + "_z_$Zone")
        Write-Log -Message "Created Data Disk: $($datadisk.Name) in zone: $($Zone)" -Level Info
    }
}
catch {
    Write-Log -Message $_ -Level Warn
    break
}

# Remove the original VM
try {
    Write-Log -Message "Removing original VM: $($originalVM.Name)" -Level Info
    Remove-AzVM -ResourceGroupName $resourceGroup -Name $vmName -Force -ErrorAction Stop | Out-Null
    Write-Log -Message "Removed original VM: $($originalVM.Name)" -Level Info
}
catch {
    Write-Log -Message $_ -Level Warn
    break
}

# Create the basic configuration for the replacement VM
try {
    Write-Log -Message "Building New VM config: $($originalVM.Name)" -Level Info
    $newVM = New-AzVMConfig -VMName $originalVM.Name -VMSize $originalVM.HardwareProfile.VmSize -Zone $zone -ErrorAction Stop

    # Add the pre-created OS disk 
    Write-Log -Message "Adding OS Disk $($OSdisk.Name) to VM config: $($originalVM.Name)" -Level Info
    if ($OSType -eq "Windows") {
        Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $OSdisk.Id -Name $OSdisk.Name -Windows -ErrorAction Stop | Out-Null
    }
    if ($OSType -eq "Linux") {
        Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $OSdisk.Id -Name $OSdisk.Name -Linux -ErrorAction Stop | Out-Null
    }
    
    if (($originalVM.StorageProfile.DataDisks).Count -ne 0) {
        # Add the pre-created data disks
        foreach ($disk in $originalVM.StorageProfile.DataDisks) { 
            Write-Log -Message "Adding Data Disk $($disk.Name + "_z_$Zone") to VM config: $($originalVM.Name)" -Level Info
            $datadiskdetails = Get-AzDisk -ResourceGroupName $resourceGroup -DiskName ($disk.Name + "_z_$Zone") -ErrorAction Stop
            Add-AzVMDataDisk -VM $newVM -Name $datadiskdetails.Name -ManagedDiskId $datadiskdetails.Id -Caching $disk.Caching -Lun $disk.Lun -DiskSizeInGB $disk.DiskSizeGB -CreateOption Attach -ErrorAction Stop | Out-Null
            Write-Log -Message "Added Data Disk $($disk.Name + "_z_$Zone") to VM config: $($originalVM.Name)" -Level Info
        }
    }

    # Add NIC(s) and keep the same NIC as primary
    Write-Log -Message "Adding NIC: $($originalVM.NetworkProfile.NetworkInterfaces.Id | split-Path -leaf) to VM config: $($originalVM.Name)" -Level Info
    try {
        foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {	
            if ($nic.Primary -eq "True") {
                Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id -Primary -ErrorAction Stop | Out-Null
            }
            else {
                Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id -ErrorAction Stop | Out-Null
            }
        }
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }

    # Recreate the VM
    Write-Log -Message "Building New VM: $($originalVM.Name) in zone $($Zone)" -Level Info
    New-AzVM -ResourceGroupName $resourceGroup -Location $originalVM.Location -VM $newVM -ErrorAction Stop | Out-Null
    Write-Log -Message "Created New VM: $($originalVM.Name) in zone $($Zone)" -Level Info

}
catch {
    Write-Log -Message $_ -Level Warn
}

#Cleanup Snapshots
if ($CleanupSnapshots.IsPresent) {
    Write-Log -Message "Removing Snapshot: $($originalVM.StorageProfile.OsDisk.Name + "-snapshot")" -Level Info

    try {
        Remove-AzSnapshot -ResourceGroupName $resourceGroup -SnapshotName ($originalVM.StorageProfile.OsDisk.Name + "-snapshot") -Force -ErrorAction Stop | Out-Null
        foreach ($disk in $originalVM.StorageProfile.DataDisks) {
            Write-Log -Message "Removing Snapshot: $($disk.Name + "-snapshot")" -Level Info
            Remove-AzSnapshot -ResourceGroupName $resourceGroup -SnapshotName ($disk.Name + "-snapshot") -Force -ErrorAction Stop | out-Null
        }    
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
}

#Cleanup Old Disks
if ($CleanupSourceDisks.IsPresent) {
    Write-Log -Message "Removing Original Disk: $($originalVM.StorageProfile.OsDisk.Name)" -Level Info
    try {
        Remove-AzDisk -ResourceGroupName $resourceGroup -DiskName ($originalVM.StorageProfile.OsDisk.Name) -Force -ErrorAction Stop | Out-Null

        foreach ($disk in $originalVM.StorageProfile.DataDisks) {
            Write-Log -Message "Removing Original Disk: $($disk.Name)" -Level Info
            Remove-AzDisk -ResourceGroupName $resourceGroup -DiskName $disk.Name -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-Log -Message $_ -Level Warn
    }
}

StopIteration
Exit 0
#endregion

