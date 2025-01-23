# Winget Package Status Service Module
# Provides functionality for managing package installation status through winget

#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import required services
. "$PSScriptRoot\package_status_cache_service.ps1"
. "$PSScriptRoot\logService.ps1"

<#
.SYNOPSIS
    Gets the list of managed packages from JSON configuration
.DESCRIPTION
    Reads and parses the winget_packages_list.json file containing
    package definitions and metadata
.RETURNS
    Hashtable containing success status and packages array
#>
function Get-PackagesList {
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
    Gets installation status for a package in bulk check mode
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
function Get-BulkPackageInstallationStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId,
        [switch]$ForceRefresh
    )
    
    Write-TerminalLog "Checking installation status for package: $AppId" "DEBUG"
    
    if (-not $ForceRefresh) {
        $cachedStatus = Get-CachedPackageStatus -AppId $AppId
        if ($cachedStatus) {
            Write-TerminalLog "Returning cached status for package: $AppId" "DEBUG"
            return $cachedStatus
        }
    }
    
    try {
        Write-TerminalLog "Querying winget for package: $AppId" "DEBUG"
        $result = winget list --id $AppId --accept-source-agreements | Out-String
        
        # Parse the output
        $installed = $false
        $version = $null
        
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        foreach ($line in $lines) {
            if ($line -match $AppId) {
                $installed = $true
                if ($line -match '^[^\s]+\s+([^\s]+)') {
                    $version = $matches[1]
                }
                break
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        
        Write-TerminalLog "Package $AppId status: $(if($installed){'Installed'}else{'Not Installed'})$(if($version){" v$version"})" "INFO"
        return $status
    }
    catch {
        Write-TerminalLog "Failed to get package status: $($_.Exception.Message)" "ERROR"
        
        $status = @{
            installed = $false
            version = $null
        }
        Set-CachedPackageStatus -AppId $AppId -Status $status
        return $status
    }
}

<#
.SYNOPSIS
    Gets installation status for a single package
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
function Get-SinglePackageInstallStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId,
        [switch]$ForceRefresh
    )
    
    Write-TerminalLog "Checking single package status: $AppId" "DEBUG"
    
    if (-not $ForceRefresh) {
        $cachedStatus = Get-CachedPackageStatus -AppId $AppId
        if ($cachedStatus) {
            Write-TerminalLog "Returning cached status for package: $AppId" "DEBUG"
            return $cachedStatus
        }
    }
    
    try {
        Write-TerminalLog "Querying winget for single package: $AppId" "DEBUG"
        $result = winget list --id $AppId --accept-source-agreements | Out-String
        
        # Parse the output
        $installed = $false
        $version = $null
        
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        foreach ($line in $lines) {
            if ($line -match $AppId) {
                $installed = $true
                if ($line -match '^[^\s]+\s+([^\s]+)') {
                    $version = $matches[1]
                }
                break
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        
        Write-TerminalLog "Package $AppId status: $(if($installed){'Installed'}else{'Not Installed'})$(if($version){" v$version"})" "INFO"
        return $status
    }
    catch {
        Write-TerminalLog "Failed to get package status: $($_.Exception.Message)" "ERROR"
        
        $status = @{
            installed = $false
            version = $null
        }
        Set-CachedPackageStatus -AppId $AppId -Status $status
        return $status
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
    
    Write-TerminalLog "Starting installation of package: $AppId" "INFO"
    
    try {
        $result = winget install --exact --id $AppId --accept-source-agreements --accept-package-agreements
        Clear-PackageStatusCache
        
        Write-TerminalLog "Successfully initiated installation of package: $AppId" "SUCCESS"
        return @{
            success = $true
            message = "Package installation initiated"
        }
    }
    catch {
        Write-TerminalLog "Failed to install package $AppId : $($_.Exception.Message)" "ERROR"
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
    
    Write-TerminalLog "Starting uninstallation of package: $AppId" "INFO"
    
    try {
        $result = winget uninstall --exact --id $AppId
        Clear-PackageStatusCache
        
        Write-TerminalLog "Successfully initiated uninstallation of package: $AppId" "SUCCESS"
        return @{
            success = $true
            message = "Package uninstallation initiated"
        }
    }
    catch {
        Write-TerminalLog "Failed to uninstall package $AppId : $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to uninstall package: $($_.Exception.Message)"
        }
    }
} 