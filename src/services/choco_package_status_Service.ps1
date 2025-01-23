# Chocolatey Package Status Service Module
# Provides functionality for managing package installation status through Chocolatey

#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import required services
. "$PSScriptRoot\package_status_cache_service.ps1"
. "$PSScriptRoot\logService.ps1"

<#
.SYNOPSIS
    Gets the list of managed Chocolatey packages from JSON configuration
.DESCRIPTION
    Reads and parses the choco_packages_list.json file containing
    package definitions and metadata
.RETURNS
    Hashtable containing success status and packages array
#>
function Get-ChocoPackagesList {
    Write-TerminalLog "Reading Chocolatey packages list from JSON..." "DEBUG"
    
    try {
        $jsonPath = Join-Path $PSScriptRoot "..\..\choco_packages_list.json"
        $jsonContent = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        
        Write-TerminalLog "Successfully loaded Chocolatey packages list" "SUCCESS"
        return @{
            success = $true
            packages = $jsonContent.packages
        }
    }
    catch {
        Write-TerminalLog "Failed to read Chocolatey packages list: $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to read packages list: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Gets installation status for a Chocolatey package in bulk check mode
.DESCRIPTION
    Checks if a package is installed using choco list command
    Uses and updates the package status cache
.PARAMETER AppId
    The unique identifier of the package to check
.PARAMETER ForceRefresh
    If true, bypasses cache and performs fresh check
.RETURNS
    Hashtable containing installation status and version
#>
function Get-ChocoBulkPackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId,
        [switch]$ForceRefresh
    )
    
    Write-TerminalLog "Checking installation status for Chocolatey package: $AppId" "DEBUG"
    
    if (-not $ForceRefresh) {
        $cachedStatus = Get-CachedPackageStatus -AppId $AppId
        if ($cachedStatus) {
            Write-TerminalLog "Returning cached status for Chocolatey package: $AppId" "DEBUG"
            return $cachedStatus
        }
    }
    
    try {
        Write-TerminalLog "Querying Chocolatey for package: $AppId" "DEBUG"
        $result = choco list --local-only --exact $AppId | Out-String
        
        # Parse the output
        $installed = $false
        $version = $null
        
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        foreach ($line in $lines) {
            if ($line -match "$AppId\s+([^\s]+)") {
                $installed = $true
                $version = $matches[1]
                break
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        
        Write-TerminalLog "Chocolatey package $AppId status: $(if($installed){'Installed'}else{'Not Installed'})$(if($version){" v$version"})" "INFO"
        return $status
    }
    catch {
        Write-TerminalLog "Failed to get Chocolatey package status: $($_.Exception.Message)" "ERROR"
        
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
    Gets installation status for a single Chocolatey package
.DESCRIPTION
    Checks if a package is installed using choco list command
    Uses and updates the package status cache
.PARAMETER AppId
    The unique identifier of the package to check
.PARAMETER ForceRefresh
    If true, bypasses cache and performs fresh check
.RETURNS
    Hashtable containing installation status and version
#>
function Get-ChocoSinglePackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId,
        [switch]$ForceRefresh
    )
    
    Write-TerminalLog "Checking single Chocolatey package status: $AppId" "DEBUG"
    
    if (-not $ForceRefresh) {
        $cachedStatus = Get-CachedPackageStatus -AppId $AppId
        if ($cachedStatus) {
            Write-TerminalLog "Returning cached status for Chocolatey package: $AppId" "DEBUG"
            return $cachedStatus
        }
    }
    
    try {
        Write-TerminalLog "Querying Chocolatey for single package: $AppId" "DEBUG"
        $result = choco list --local-only --exact $AppId | Out-String
        
        # Parse the output
        $installed = $false
        $version = $null
        
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        foreach ($line in $lines) {
            if ($line -match "$AppId\s+([^\s]+)") {
                $installed = $true
                $version = $matches[1]
                break
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        
        Write-TerminalLog "Chocolatey package $AppId status: $(if($installed){'Installed'}else{'Not Installed'})$(if($version){" v$version"})" "INFO"
        return $status
    }
    catch {
        Write-TerminalLog "Failed to get Chocolatey package status: $($_.Exception.Message)" "ERROR"
        
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
    Installs a package using Chocolatey
.DESCRIPTION
    Initiates package installation and clears status cache
.PARAMETER AppId
    The unique identifier of the package to install
.RETURNS
    Hashtable containing success status and message
#>
function Install-ChocoPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId
    )
    
    Write-TerminalLog "Starting installation of Chocolatey package: $AppId" "INFO"
    
    try {
        $result = choco install $AppId -y
        Clear-PackageStatusCache
        
        Write-TerminalLog "Successfully initiated installation of Chocolatey package: $AppId" "SUCCESS"
        return @{
            success = $true
            message = "Package installation initiated"
        }
    }
    catch {
        Write-TerminalLog "Failed to install Chocolatey package $AppId : $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to install package: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Uninstalls a package using Chocolatey
.DESCRIPTION
    Initiates package uninstallation and clears status cache
.PARAMETER AppId
    The unique identifier of the package to uninstall
.RETURNS
    Hashtable containing success status and message
#>
function Uninstall-ChocoPackage {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId
    )
    
    Write-TerminalLog "Starting uninstallation of Chocolatey package: $AppId" "INFO"
    
    try {
        $result = choco uninstall $AppId -y
        Clear-PackageStatusCache
        
        Write-TerminalLog "Successfully initiated uninstallation of Chocolatey package: $AppId" "SUCCESS"
        return @{
            success = $true
            message = "Package uninstallation initiated"
        }
    }
    catch {
        Write-TerminalLog "Failed to uninstall Chocolatey package $AppId : $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to uninstall package: $($_.Exception.Message)"
        }
    }
} 