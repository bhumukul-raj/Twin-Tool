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

# Add configuration for retry limits
$script:MaxInstallCheckRetries = 10  # Maximum number of retries for checking installation status
$script:RetryDelaySeconds = 5      # Delay between retries

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
    
    Write-TerminalLog "Starting bulk status check for $($AppIds.Count) packages" "DEBUG"
    
    try {
        $results = @()
        $batchSize = 3  # Process in small batches to avoid overwhelming the system
        
        for ($i = 0; $i -lt $AppIds.Count; $i += $batchSize) {
            $batch = $AppIds[$i..([Math]::Min($i + $batchSize - 1, $AppIds.Count - 1))]
            
            foreach ($appId in $batch) {
                try {
                    $status = Get-WingetSinglePackageStatus -AppId $appId -ForceRefresh:$ForceRefresh
                    if ($status) {
                        $results += @{
                            appId = $appId
                            status = $status
                        }
                    } else {
                        Write-TerminalLog "No status returned for $appId" "WARNING"
                        $results += @{
                            appId = $appId
                            status = @{
                                installed = $false
                                version = $null
                                error = "Failed to get status"
                            }
                        }
                    }
                } catch {
                    Write-TerminalLog "Error checking status for $appId : $($_.Exception.Message)" "ERROR"
                    $results += @{
                        appId = $appId
                        status = @{
                            installed = $false
                            version = $null
                            error = $_.Exception.Message
                        }
                    }
                }
            }
            
            # Small delay between batches
            if ($i + $batchSize -lt $AppIds.Count) {
                Start-Sleep -Milliseconds 100
            }
        }
        
        if ($results.Count -eq 0) {
            throw "No results returned from bulk status check"
        }
        
        Write-TerminalLog "Bulk status check completed successfully" "SUCCESS"
        return @{
            success = $true
            results = $results
        }
    } catch {
        Write-TerminalLog "Error during bulk status check: $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = $_.Exception.Message
            results = @()  # Return empty array instead of null
        }
    }
}

function Get-WingetPackageStatusFromOutput {
    param (
        [string]$Output,
        [string]$AppId
    )
    
    $status = @{
        installed = $false
        version = $null
        name = $null
        source = $null
    }
    
    # Check if package is not installed
    if ($Output -match "No installed package found matching input criteria") {
        Write-TerminalLog "Package $AppId is not installed (no match found)" "DEBUG"
        return $status
    }
    
    # Parse the output lines
    $lines = $Output -split "`n" | Where-Object { $_ -match '\S' }
    Write-TerminalLog "Found $($lines.Count) non-empty lines in output" "DEBUG"
    
    Write-TerminalLog "Processing output lines for package data..." "DEBUG"
    # Find the line with actual package data (after headers)
    $packageLine = $lines | Where-Object { 
        $_ -notmatch "^(-+|Name|Windows|\s*$|\s*[\-\\|])" -and 
        $_ -match $AppId 
    } | Select-Object -First 1
    
    Write-TerminalLog "Package line found: $packageLine" "DEBUG"
    
    if ($packageLine) {
        Write-TerminalLog "Attempting to parse package line: '$packageLine'" "DEBUG"
        # Try different patterns based on output format
        if ($packageLine -match '^(.+?)\s+(\S+)\s+(\S+)\s*$') {
            # Format: Name Id Version
            $name = $matches[1].Trim()
            $id = $matches[2]
            $version = $matches[3]
            Write-TerminalLog "Matched 3-column format - Name: '$name', Id: '$id', Version: '$version'" "DEBUG"
            
            if ($id -eq $AppId) {
                Write-TerminalLog "Found exact ID match for $AppId" "DEBUG"
                return @{
                    installed = $true
                    version = $version
                    name = $name
                    source = "winget"  # Default source if not specified
                }
            }
        }
        elseif ($packageLine -match '^(.+?)\s+(\S+)\s+(\S+)\s+(\S+)\s*$') {
            # Format: Name Id Version Source
            $name = $matches[1].Trim()
            $id = $matches[2]
            $version = $matches[3]
            $source = $matches[4]
            Write-TerminalLog "Matched 4-column format - Name: '$name', Id: '$id', Version: '$version', Source: '$source'" "DEBUG"
            
            if ($id -eq $AppId) {
                Write-TerminalLog "Found exact ID match for $AppId" "DEBUG"
                return @{
                    installed = $true
                    version = $version
                    name = $name
                    source = $source
                }
            }
        }
    }
    
    return $status
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
        
        # Get package info using PowerShell object handling
        $output = winget list --accept-source-agreements --source winget --id $AppId | Out-String
        Write-TerminalLog "Raw output for $AppId : $output" "DEBUG"
        
        # Parse the output lines
        $lines = $output -split "`n" | Where-Object { $_ -match '\S' }
        Write-TerminalLog "Found $($lines.Count) non-empty lines in output" "DEBUG"
        
        $status = @{
            installed = $false
            version = $null
            name = $null
            source = $null
        }
        
        # Check if package is not installed
        if ($output -match "No installed package found matching input criteria") {
            Write-TerminalLog "Package $AppId is not installed (no match found)" "DEBUG"
        }
        else {
            Write-TerminalLog "Processing output lines for package data..." "DEBUG"
            # Find the line with actual package data (after headers)
            $packageLine = $lines | Where-Object { 
                $_ -notmatch "^(-+|Name|Windows|\s*$|\s*[\-\\|])" -and 
                $_ -match $AppId 
            } | Select-Object -First 1
            
            Write-TerminalLog "Package line found: $packageLine" "DEBUG"
            
            if ($packageLine) {
                Write-TerminalLog "Attempting to parse package line: '$packageLine'" "DEBUG"
                # Try different patterns based on output format
                if ($packageLine -match '^(.+?)\s+(\S+)\s+(\S+)\s*$') {
                    # Format: Name Id Version
                    $name = $matches[1].Trim()
                    $id = $matches[2]
                    $version = $matches[3]
                    Write-TerminalLog "Matched 3-column format - Name: '$name', Id: '$id', Version: '$version'" "DEBUG"
                    
                    if ($id -eq $AppId) {
                        Write-TerminalLog "Found exact ID match for $AppId" "DEBUG"
                        $status = @{
                            installed = $true
                            version = $version
                            name = $name
                            source = "winget"  # Default source if not specified
                        }
                    }
                }
                elseif ($packageLine -match '^(.+?)\s+(\S+)\s+(\S+)\s+(\S+)\s*$') {
                    # Format: Name Id Version Source
                    $name = $matches[1].Trim()
                    $id = $matches[2]
                    $version = $matches[3]
                    $source = $matches[4]
                    Write-TerminalLog "Matched 4-column format - Name: '$name', Id: '$id', Version: '$version', Source: '$source'" "DEBUG"
                    
                    if ($id -eq $AppId) {
                        Write-TerminalLog "Found exact ID match for $AppId" "DEBUG"
                        $status = @{
                            installed = $true
                            version = $version
                            name = $name
                            source = $source
                        }
                    }
                }
                else {
                    Write-TerminalLog "Failed to match package line format: '$packageLine'" "WARNING"
                }
            }
            else {
                Write-TerminalLog "No package line found matching $AppId" "DEBUG"
            }
        }
        
        Write-TerminalLog "Final status for $AppId - Installed: $($status.installed), Version: $($status.version), Name: $($status.name)" "DEBUG"
        
        # Update cache with timestamp
        $script:WingetStatusCache[$AppId] = $status
        $script:CacheTimestamps[$AppId] = $currentTime
        
        if ($status.installed) {
            Write-TerminalLog "Winget package $AppId status: Installed v$($status.version)" "INFO"
        } else {
            Write-TerminalLog "Winget package $AppId status: Not Installed" "INFO"
        }
        
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
        
        # Add retry logic with maximum attempts
        $retryCount = 0
        $installed = $false
        
        while (-not $installed -and $retryCount -lt $script:MaxInstallCheckRetries) {
            Start-Sleep -Seconds $script:RetryDelaySeconds
            $status = Get-WingetSinglePackageStatus -AppId $AppId -ForceRefresh
            
            if ($status.installed) {
                $installed = $true
                Write-TerminalLog "Successfully installed Winget package $AppId (version: $($status.version))" "SUCCESS"
            } else {
                $retryCount++
                Write-TerminalLog "Installation check attempt $retryCount of $script:MaxInstallCheckRetries for $AppId" "DEBUG"
            }
        }
        
        if (-not $installed) {
            Write-TerminalLog "Installation status check exceeded maximum retries for $AppId" "WARNING"
        }
        
        return @{
            success = $true
            message = "Package installation initiated"
            installed = $installed
            finalStatus = $status
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
        
        # Add retry logic with maximum attempts
        $retryCount = 0
        $uninstalled = $false
        
        while (-not $uninstalled -and $retryCount -lt $script:MaxInstallCheckRetries) {
            Start-Sleep -Seconds $script:RetryDelaySeconds
            $status = Get-WingetSinglePackageStatus -AppId $AppId -ForceRefresh
            
            if (-not $status.installed) {
                $uninstalled = $true
                Write-TerminalLog "Successfully uninstalled Winget package $AppId" "SUCCESS"
            } else {
                $retryCount++
                Write-TerminalLog "Uninstallation check attempt $retryCount of $script:MaxInstallCheckRetries for $AppId" "DEBUG"
            }
        }
        
        if (-not $uninstalled) {
            Write-TerminalLog "Uninstallation status check exceeded maximum retries for $AppId" "WARNING"
        }
        
        return @{
            success = $true
            message = "Package uninstallation initiated"
            uninstalled = $uninstalled
            finalStatus = $status
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