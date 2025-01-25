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
        # Get the correct path using $PSScriptRoot
        $scriptPath = $PSScriptRoot
        $rootPath = Split-Path -Parent (Split-Path -Parent $scriptPath)
        $jsonPath = Join-Path $rootPath "choco_packages_list.json"
        
        Write-TerminalLog "Attempting to read from path: $jsonPath" "DEBUG"
        
        if (-not (Test-Path $jsonPath)) {
            Write-TerminalLog "Chocolatey packages list not found at: $jsonPath" "ERROR"
            return @{
                success = $false
                error = "Packages list file not found"
            }
        }
        
        $jsonContent = Get-Content -Path $jsonPath -Raw -ErrorAction Stop
        $packages = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        
        Write-TerminalLog "Successfully loaded Chocolatey packages list" "SUCCESS"
        return @{
            success = $true
            packages = $packages.packages
        }
    }
    catch {
        $errorMsg = "Failed to read Chocolatey packages list: $($_.Exception.Message)"
        Write-TerminalLog $errorMsg "ERROR"
        return @{
            success = $false
            error = $errorMsg
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
    
    # Simply use the single package check since it works correctly
    return Get-ChocoSinglePackageStatus -AppId $AppId -ForceRefresh:$ForceRefresh
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
        $result = choco list $AppId | Out-String
        Write-TerminalLog "Raw choco list output:`n$result" "DEBUG"
        
        # If we see "0 packages installed", return not installed immediately
        if ($result -match "0 packages installed") {
            $status = @{
                installed = $false
                version = $null
            }
            Set-CachedPackageStatus -AppId $AppId -Status $status
            Write-TerminalLog "Chocolatey package $AppId status: Not Installed" "INFO"
            return $status
        }
        
        # Parse the output lines
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        
        # Look for a line that starts with our package name (case insensitive)
        $packageLine = $lines | Where-Object { $_ -match "^$AppId\s+\d" -or $_ -match "^$($AppId.ToUpper())\s+\d" }
        
        if ($packageLine) {
            $parts = $packageLine -split '\s+'
            $version = $parts[1]
            
            $status = @{
                installed = $true
                version = $version
            }
            
            Set-CachedPackageStatus -AppId $AppId -Status $status
            Write-TerminalLog "Chocolatey package $AppId status: Installed v$version" "INFO"
            return $status
        }
        
        # If we get here, package not found
        $status = @{
            installed = $false
            version = $null
        }
        Set-CachedPackageStatus -AppId $AppId -Status $status
        Write-TerminalLog "Chocolatey package $AppId status: Not Installed" "INFO"
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
        # Clear the cache before installation
        Clear-PackageStatusCache
        
        # Run the installation command
        Write-TerminalLog "Running choco install command for $AppId" "DEBUG"
        $installResult = choco install $AppId -y --ignore-checksums --no-progress | Out-String
        Write-TerminalLog "Chocolatey install output: $installResult" "DEBUG"

        # Check for various error patterns
        if ($installResult -match "ERROR: (.+)" -or 
            $installResult -match "The install of .+ was NOT successful." -or
            $installResult -match "Access to the path .+ is denied") {
            $errorMessage = if ($matches[1]) { $matches[1] } else { $installResult }
            Write-TerminalLog "Installation error detected: $errorMessage" "ERROR"
            
            return @{
                success = $false
                message = "Installation failed"
                error = $errorMessage
                status = @{
                    installed = $false
                    version = $null
                }
            }
        }

        # Wait a moment for installation to complete
        Start-Sleep -Seconds 2
        
        # Check installation status using Get-ChocoSinglePackageStatus
        Write-TerminalLog "Verifying installation status for $AppId" "DEBUG"
        $status = Get-ChocoSinglePackageStatus -AppId $AppId -ForceRefresh
        
        if ($status.installed) {
            Write-TerminalLog "Successfully installed Chocolatey package $AppId v$($status.version)" "SUCCESS"
            return @{
                success = $true
                message = "Package installed successfully"
                version = $status.version
                status = $status
            }
        } else {
            $errorMsg = "Package installation verification failed - package not found after install"
            Write-TerminalLog $errorMsg "ERROR"
            return @{
                success = $false
                message = $errorMsg
                status = $status
            }
        }
    }
    catch {
        $errorMsg = "Installation failed: $($_.Exception.Message)"
        Write-TerminalLog "Failed to install Chocolatey package: $($_.Exception.Message)" "ERROR"
        
        return @{
            success = $false
            message = $errorMsg
            status = @{
                installed = $false
                version = $null
            }
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
        # Run the uninstallation command
        Write-TerminalLog "Running choco uninstall command for $AppId" "DEBUG"
        $uninstallResult = choco uninstall $AppId -y | Out-String
        Write-TerminalLog "Chocolatey uninstall output: $uninstallResult" "DEBUG"

        # Verify uninstallation using single package status check
        Write-TerminalLog "Verifying uninstallation status for $AppId" "DEBUG"
        $verificationStatus = Get-ChocoSinglePackageStatus -AppId $AppId -ForceRefresh
        
        if (-not $verificationStatus.installed) {
            Write-TerminalLog "Successfully uninstalled Chocolatey package $AppId" "SUCCESS"
            return @{
                success = $true
                message = "Package uninstalled successfully"
            }
        } else {
            Write-TerminalLog "Package uninstallation verification failed for $AppId" "ERROR"
            return @{
                success = $false
                message = "Package uninstallation verification failed - package still appears to be installed"
            }
        }
    }
    catch {
        Write-TerminalLog "Failed to uninstall Chocolatey package: $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            message = "Uninstallation failed: $($_.Exception.Message)"
        }
    }
} 