# Winget Package Status Service Module
# Provides functionality for managing package installation status through winget

#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import required services
. "$PSScriptRoot\package_status_cache_service.ps1"
. "$PSScriptRoot\logService.ps1"

# Cache configuration
$script:WingetStatusCache = @{}
$script:LastBulkCheck = $null
$script:BulkCheckInterval = 900 # 15 minutes
$script:SingleCheckInterval = 600 # 10 minutes
$script:CacheTimestamps = @{}

<#
.SYNOPSIS
    Gets the list of managed Winget packages from JSON configuration
.DESCRIPTION
    Reads and parses the winget_packages_list.json file containing
    package definitions and metadata
.RETURNS
    Hashtable containing success status and packages array
#>
function Get-WingetPackagesList {
    Write-TerminalLog "Reading winget packages list from JSON..." "DEBUG"
    
    try {
        $jsonPath = Join-Path $PSScriptRoot "..\..\winget_packages_list.json"
        $jsonContent = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        
        Write-TerminalLog "Successfully loaded winget packages list" "SUCCESS"
        return @{
            success = $true
            packages = $jsonContent.packages
        }
    }
    catch {
        Write-TerminalLog "Failed to read winget packages list: $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to read packages list: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Gets installation status for a Winget package in bulk check mode
.DESCRIPTION
    Checks if a package is installed using winget list command
    Uses and updates the package status cache
.PARAMETER AppIds
    The unique identifiers of the packages to check
.PARAMETER ForceRefresh
    If true, bypasses cache and performs fresh check
.RETURNS
    Hashtable containing installation status and version
#>
function Get-WingetBulkPackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$AppIds,
        [switch]$ForceRefresh
    )
    
    Write-TerminalLog "Starting bulk status check for ${AppIds.Count} Winget packages" "DEBUG"
    
    # Check if we need to refresh any packages
    $needsRefresh = $ForceRefresh
    if (-not $needsRefresh) {
        $currentTime = Get-Date
        foreach ($appId in $AppIds) {
            if (-not $script:CacheTimestamps[$appId] -or 
                ($currentTime - $script:CacheTimestamps[$appId]).TotalSeconds -gt $script:BulkCheckInterval) {
                $needsRefresh = $true
                break
            }
        }
    }
    
    # Return cached results if no refresh needed
    if (-not $needsRefresh) {
        Write-TerminalLog "Using cached bulk status results" "DEBUG"
        return $AppIds | ForEach-Object {
            @{
                appId = $_
                status = $script:WingetStatusCache[$_]
            }
        }
    }

    try {
        # Get all installed packages in one call
        Write-TerminalLog "Fetching all installed packages..." "DEBUG"
        $installedPackages = winget list --accept-source-agreements | Out-String
        $currentTime = Get-Date
        
        # Parse the output once
        $packageLines = $installedPackages -split "`n" | 
                       Where-Object { $_ -match '\S' } | 
                       Select-Object -Skip 2  # Skip header lines
        
        # Process packages in parallel
        $maxParallelJobs = 4  # Adjust based on system capabilities
        $jobs = @()
        $results = @{}
        
        # Create job scriptblock
        $jobScript = {
            param($appId, $packageLines)
            
            $status = @{
                installed = $false
                version = $null
            }
            
            # Look for package in parsed output
            foreach ($line in $packageLines) {
                if ($line -match [regex]::Escape($appId)) {
                    $parts = $line -split '\s+' | Where-Object { $_ }
                    $status.installed = $true
                    $status.version = $parts[1]
                    break
                }
            }
            
            return @{
                appId = $appId
                status = $status
            }
        }
        
        # Process packages in batches
        for ($i = 0; $i -lt $AppIds.Count; $i += $maxParallelJobs) {
            $batch = $AppIds | Select-Object -Skip $i -First $maxParallelJobs
            
            # Start jobs for current batch
            foreach ($appId in $batch) {
                $jobs += Start-Job -ScriptBlock $jobScript -ArgumentList $appId, $packageLines
            }
            
            # Wait for current batch to complete
            $jobs | Wait-Job | Receive-Job | ForEach-Object {
                $results[$_.appId] = $_
                
                # Update cache
                $script:WingetStatusCache[$_.appId] = $_.status
                $script:CacheTimestamps[$_.appId] = $currentTime
            }
            
            # Clean up jobs
            $jobs | Remove-Job
            $jobs = @()
        }
        
        # Return results in original order
        $finalResults = $AppIds | ForEach-Object { $results[$_] }
        
        Write-TerminalLog "Bulk status check completed successfully" "SUCCESS"
        return $finalResults
    }
    catch {
        Write-TerminalLog "Error during bulk status check: $($_.Exception.Message)" "ERROR"
        throw
    }
}

<#
.SYNOPSIS
    Gets installation status for a single Winget package
.DESCRIPTION
    Checks if a package is installed using winget list command
    Uses and updates the package status cache
.PARAMETER AppId
    The unique identifier of the package to check
.PARAMETER ForceRefresh
    If true, bypasses cache and performs fresh check
.RETURNS
    Hashtable containing installation status and version
#>
function Get-WingetSinglePackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId,
        [switch]$ForceRefresh
    )
    
    $currentTime = Get-Date
    
    # Check cache first with timestamp validation
    if (-not $ForceRefresh -and 
        $script:WingetStatusCache.ContainsKey($AppId) -and 
        $script:CacheTimestamps[$AppId] -and
        ($currentTime - $script:CacheTimestamps[$AppId]).TotalSeconds -lt $script:SingleCheckInterval) {
        Write-TerminalLog "Returning cached status for $AppId" "DEBUG"
        return $script:WingetStatusCache[$AppId]
    }
    
    try {
        Write-TerminalLog "Checking status for package: $AppId" "DEBUG"
        $result = winget list --id $AppId --accept-source-agreements | Out-String
        
        $status = @{
            installed = $false
            version = $null
        }
        
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        foreach ($line in $lines) {
            if ($line -match $AppId) {
                $status.installed = $true
                if ($line -match '^[^\s]+\s+([^\s]+)') {
                    $status.version = $matches[1]
                }
                break
            }
        }
        
        # Update cache with timestamp
        $script:WingetStatusCache[$AppId] = $status
        $script:CacheTimestamps[$AppId] = $currentTime
        
        Write-TerminalLog "Status check completed for $AppId" "SUCCESS"
        return $status
    }
    catch {
        Write-TerminalLog "Error checking package status: $($_.Exception.Message)" "ERROR"
        throw
    }
}

<#
.SYNOPSIS
    Installs a package using winget
.DESCRIPTION
    Initiates package installation and clears status cache
.PARAMETER AppId
    The unique identifier of the package to install
.RETURNS
    Hashtable containing success status and message
#>
function Install-WingetPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId
    )
    
    Write-TerminalLog "Starting installation of Winget package: $AppId" "INFO"
    
    try {
        $result = winget install --exact --id $AppId --accept-source-agreements --accept-package-agreements
        Clear-PackageStatusCache
        
        Write-TerminalLog "Successfully initiated installation of Winget package: $AppId" "SUCCESS"
        return @{
            success = $true
            message = "Package installation initiated"
        }
    }
    catch {
        Write-TerminalLog "Failed to install Winget package $AppId : $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to install package: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Uninstalls a package using winget
.DESCRIPTION
    Initiates package uninstallation and clears status cache
.PARAMETER AppId
    The unique identifier of the package to uninstall
.RETURNS
    Hashtable containing success status and message
#>
function Uninstall-WingetPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId
    )
    
    Write-TerminalLog "Starting uninstallation of Winget package: $AppId" "INFO"
    
    try {
        $result = winget uninstall --exact --id $AppId
        Clear-PackageStatusCache
        
        Write-TerminalLog "Successfully initiated uninstallation of Winget package: $AppId" "SUCCESS"
        return @{
            success = $true
            message = "Package uninstallation initiated"
        }
    }
    catch {
        Write-TerminalLog "Failed to uninstall Winget package $AppId : $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to uninstall package: $($_.Exception.Message)"
        }
    }
}

# Clear cache when installing/uninstalling
function Clear-WingetStatusCache {
    param (
        [string]$AppId
    )
    
    if ($AppId) {
        # Clear cache for specific package
        $script:WingetStatusCache.Remove($AppId)
        $script:CacheTimestamps.Remove($AppId)
        Write-TerminalLog "Cleared Winget status cache for $AppId" "DEBUG"
    } else {
        # Clear entire cache
        $script:WingetStatusCache.Clear()
        $script:CacheTimestamps.Clear()
        Write-TerminalLog "Cleared all Winget status cache" "DEBUG"
    }
} 