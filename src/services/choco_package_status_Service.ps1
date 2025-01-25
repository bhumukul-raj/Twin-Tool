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
            return @{
                status = $cachedStatus
            }
        }
    }
    
    try {
        Write-TerminalLog "Querying Chocolatey for package: $AppId" "DEBUG"
        # Get all installed packages in one call
        $result = choco list | Out-String
        
        # Parse the output
        $installed = $false
        $version = $null
        
        # Split into lines and remove empty lines
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        
        # Process each line
        Write-TerminalLog "Raw choco list output:`n$result" "DEBUG"
        
        foreach ($line in $lines) {
            # Skip the first line (Chocolatey version) and last line (summary)
            if ($line -match "^Chocolatey\s+v" -or $line -match "^\d+\s+packages installed\.$") {
                Write-TerminalLog "Skipping line: $line" "DEBUG"
                continue
            }
            
            # Split line into package name and version
            $parts = $line -split '\s+'
            Write-TerminalLog "Line parts: $($parts -join ' | ')" "DEBUG"
            
            if ($parts.Count -ge 2) {
                $packageName = $parts[0]
                $packageVersion = $parts[1]
                
                Write-TerminalLog "Comparing package: '$packageName' (version: $packageVersion) with target: '$AppId'" "DEBUG"
                
                # Check if this is our target package (case-insensitive)
                if ($packageName -ieq $AppId) {
                    Write-TerminalLog "Found matching package: $packageName v$packageVersion" "SUCCESS"
                    $installed = $true
                    $version = $packageVersion
                    break
                }
            } else {
                Write-TerminalLog "Invalid line format: $line" "WARNING"
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Write-TerminalLog "Final status for $AppId : $($status | ConvertTo-Json)" "DEBUG"
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        
        Write-TerminalLog "Chocolatey package $AppId status: $(if($installed){'Installed v' + $version}else{'Not Installed'})" "INFO"
        
        return $status
    }
    catch {
        Write-TerminalLog "Failed to get Chocolatey package status: $($_.Exception.Message)" "ERROR"
        
        $status = @{
            installed = $false
            version = $null
        }
        Set-CachedPackageStatus -AppId $AppId -Status $status
        return @{
            status = $status
        }
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
        $result = choco info $AppId --local-only | Out-String
        
        # Parse the output
        $installed = $false
        $version = $null
        
        $lines = $result -split "`n" | Where-Object { $_ -match '\S' }
        
        foreach ($line in $lines) {
            # Look for the "Installed:" line
            if ($line -match '^\s*Installed:\s*(.+)$') {
                $installedInfo = $matches[1].Trim()
                Write-TerminalLog "Found installation info: '$installedInfo'" "DEBUG"
                if ($installedInfo -ne '(not installed)') {
                    $installed = $true
                    $version = $installedInfo
                }
                break
            }
            # Also check for package name line to verify case-insensitive match
            if ($line -match '^\s*Title:\s*(.+)$') {
                $packageName = $matches[1].Trim()
                Write-TerminalLog "Found package title: '$packageName'" "DEBUG"
                if (-not ($packageName -ieq $AppId)) {
                    Write-TerminalLog "Package name mismatch: Expected '$AppId', found '$packageName'" "WARNING"
                }
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        
        if ($installed) {
            Write-TerminalLog "Chocolatey package $AppId status: Installed v$version" "INFO"
        } else {
            Write-TerminalLog "Chocolatey package $AppId status: Not Installed" "INFO"
        }
        
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
        # Run the installation command
        Write-TerminalLog "Running choco install command for $AppId" "DEBUG"
        $installResult = choco install $AppId -y | Out-String
        Write-TerminalLog "Chocolatey install output: $installResult" "DEBUG"

        # Check for common error patterns in the output
        if ($installResult -match "ERROR: (.+)") {
            $errorMessage = $matches[1]
            Write-TerminalLog "Installation error detected: $errorMessage" "ERROR"
            
            # Create a status object with the error
            $errorStatus = @{
                installed = $false
                version = $null
                error = $errorMessage
                shouldStopChecking = $true  # Flag to stop status checking
            }
            
            # Cache the error status
            Set-CachedPackageStatus -AppId $AppId -Status $errorStatus
            
            return @{
                success = $false
                message = "Installation failed"
                error = $errorMessage
                status = $errorStatus
            }
        }

        # Verify installation using single package status check
        Write-TerminalLog "Verifying installation status for $AppId" "DEBUG"
        $verificationStatus = Get-ChocoSinglePackageStatus -AppId $AppId -ForceRefresh
        
        if ($verificationStatus.installed) {
            Write-TerminalLog "Successfully installed Chocolatey package $AppId v$($verificationStatus.version)" "SUCCESS"
            return @{
                success = $true
                message = "Package installed successfully"
                version = $verificationStatus.version
                status = $verificationStatus
            }
        } else {
            $errorMsg = "Package installation verification failed"
            Write-TerminalLog "$errorMsg for $AppId" "ERROR"
            
            # Create a status object with the error
            $errorStatus = @{
                installed = $false
                version = $null
                error = $errorMsg
                shouldStopChecking = $true  # Flag to stop status checking
            }
            
            # Cache the error status
            Set-CachedPackageStatus -AppId $AppId -Status $errorStatus
            
            return @{
                success = $false
                message = $errorMsg
                status = $errorStatus
            }
        }
    }
    catch {
        $errorMsg = "Installation failed: $($_.Exception.Message)"
        Write-TerminalLog "Failed to install Chocolatey package: $($_.Exception.Message)" "ERROR"
        
        # Create a status object with the error
        $errorStatus = @{
            installed = $false
            version = $null
            error = $errorMsg
            shouldStopChecking = $true  # Flag to stop status checking
        }
        
        # Cache the error status
        Set-CachedPackageStatus -AppId $AppId -Status $errorStatus
        
        return @{
            success = $false
            message = $errorMsg
            status = $errorStatus
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