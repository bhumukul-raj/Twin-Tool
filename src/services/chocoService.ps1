# Chocolatey Service Module
# Provides core functionality for interacting with Chocolatey Package Manager

#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import required services
. "$PSScriptRoot\logService.ps1"

<#
.SYNOPSIS
    Checks if Chocolatey is installed on the system using multiple detection methods
.DESCRIPTION
    Attempts to find choco command using various methods:
    1. Direct command check
    2. Path existence check
    3. Registry check
    4. Environment variable check
.RETURNS
    Boolean indicating whether Chocolatey is installed
#>
function Test-ChocoInstalled {
    Write-TerminalLog "Checking if Chocolatey is installed (using multiple methods)..." "DEBUG"
    
    try {
        # Method 1: Try direct command check
        Write-TerminalLog "Method 1: Checking choco command..." "DEBUG"
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-TerminalLog "Chocolatey found via command check" "SUCCESS"
            return $true
        }
        
        # Method 2: Check common installation paths
        Write-TerminalLog "Method 2: Checking installation paths..." "DEBUG"
        $commonPaths = @(
            "$env:ChocolateyInstall\bin\choco.exe",
            "C:\ProgramData\chocolatey\bin\choco.exe",
            "${env:SystemDrive}\ProgramData\chocolatey\bin\choco.exe"
        )
        
        foreach ($path in $commonPaths) {
            if (Test-Path $path) {
                Write-TerminalLog "Chocolatey found at path: $path" "SUCCESS"
                return $true
            }
        }
        
        # Method 3: Check registry
        Write-TerminalLog "Method 3: Checking registry..." "DEBUG"
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Chocolatey'
        if (Test-Path $regPath) {
            Write-TerminalLog "Chocolatey found in registry" "SUCCESS"
            return $true
        }
        
        # Method 4: Check ChocolateyInstall environment variable
        Write-TerminalLog "Method 4: Checking environment variables..." "DEBUG"
        if ($env:ChocolateyInstall -and (Test-Path $env:ChocolateyInstall)) {
            Write-TerminalLog "Chocolatey found via environment variable" "SUCCESS"
            return $true
        }
        
        Write-TerminalLog "Chocolatey not found using any detection method" "WARNING"
        return $false
    }
    catch {
        Write-TerminalLog "Error checking Chocolatey installation: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the installed version of Chocolatey
.DESCRIPTION
    Executes choco --version using the found Chocolatey installation
    Handles various edge cases and provides detailed logging
.RETURNS
    Hashtable containing installation status and version
#>
function Get-ChocoVersion {
    Write-TerminalLog "Getting Chocolatey version..." "DEBUG"
    
    try {
        if (-not (Test-ChocoInstalled)) {
            Write-TerminalLog "Chocolatey is not installed" "INFO"
            return @{
                installed = $false
                version = $null
            }
        }

        Write-TerminalLog "Executing choco --version..." "DEBUG"
        
        # Try different methods to get version
        $version = $null
        
        # Method 1: Direct command
        try {
            $version = (choco --version) | Out-String
        }
        catch {
            Write-TerminalLog "Direct command failed, trying alternative methods" "DEBUG"
        }
        
        # Method 2: Full path if direct command failed
        if (-not $version) {
            $chocoPath = if ($env:ChocolateyInstall) {
                Join-Path $env:ChocolateyInstall "bin\choco.exe"
            } else {
                "C:\ProgramData\chocolatey\bin\choco.exe"
            }
            
            if (Test-Path $chocoPath) {
                $version = (& $chocoPath --version) | Out-String
            }
        }
        
        if ($version) {
            $version = $version.Trim()
            Write-TerminalLog "Chocolatey version: $version" "SUCCESS"
            return @{
                installed = $true
                version = $version
            }
        }
        
        Write-TerminalLog "Failed to get Chocolatey version" "ERROR"
        return @{
            installed = $true  # We know it's installed but couldn't get version
            version = "Unknown"
        }
    }
    catch {
        Write-TerminalLog "Error getting Chocolatey version: $($_.Exception.Message)" "ERROR"
        return @{
            installed = $false
            version = $null
        }
    }
}

<#
.SYNOPSIS
    Installs Chocolatey on the system
.DESCRIPTION
    Downloads and executes the Chocolatey installation script
    Includes additional verification steps and environment setup
.RETURNS
    Hashtable containing success status and message
#>
function Install-Chocolatey {
    Write-TerminalLog "Starting Chocolatey installation..." "INFO"
    
    try {
        if (Test-ChocoInstalled) {
            Write-TerminalLog "Chocolatey is already installed" "WARNING"
            return @{
                success = $true
                message = "Chocolatey is already installed"
            }
        }

        Write-TerminalLog "Setting up installation environment..." "DEBUG"
        
        # Ensure TLS 1.2
        [System.Net.ServicePointManager]::SecurityProtocol = 
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        
        # Set execution policy for this process
        Set-ExecutionPolicy Bypass -Scope Process -Force
        
        Write-TerminalLog "Downloading Chocolatey installation script..." "DEBUG"
        $installScript = (New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')
        
        Write-TerminalLog "Executing Chocolatey installation script..." "DEBUG"
        Invoke-Expression $installScript
        
        # Wait for installation to complete
        Start-Sleep -Seconds 2
        
        # Verify installation
        Write-TerminalLog "Verifying installation..." "DEBUG"
        if (Test-ChocoInstalled) {
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            Write-TerminalLog "Chocolatey installation completed successfully" "SUCCESS"
            return @{
                success = $true
                message = "Chocolatey installed successfully"
            }
        }
        
        throw "Installation verification failed"
    }
    catch {
        Write-TerminalLog "Failed to install Chocolatey: $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to install Chocolatey: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Uninstalls Chocolatey from the system
.DESCRIPTION
    Removes Chocolatey and its files from the system
    Includes cleanup of registry and environment variables
.RETURNS
    Hashtable containing success status and message
#>
function Uninstall-Chocolatey {
    Write-TerminalLog "Starting Chocolatey uninstallation..." "INFO"
    
    try {
        if (-not (Test-ChocoInstalled)) {
            Write-TerminalLog "Chocolatey is not installed" "WARNING"
            return @{
                success = $true
                message = "Chocolatey is not installed"
            }
        }

        Write-TerminalLog "Removing Chocolatey..." "DEBUG"
        
        # Get Chocolatey directory
        $chocoDir = if ($env:ChocolateyInstall) {
            $env:ChocolateyInstall
        } else {
            "C:\ProgramData\chocolatey"
        }
        
        # Stop any running Chocolatey processes
        Write-TerminalLog "Stopping Chocolatey processes..." "DEBUG"
        Get-Process -Name "choco*" -ErrorAction SilentlyContinue | Stop-Process -Force
        
        # Remove Chocolatey directory
        if (Test-Path $chocoDir) {
            Write-TerminalLog "Removing Chocolatey directory: $chocoDir" "DEBUG"
            Remove-Item -Path $chocoDir -Recurse -Force
        }
        
        # Remove environment variables
        Write-TerminalLog "Removing environment variables..." "DEBUG"
        $envTarget = [System.EnvironmentVariableTarget]::Machine
        [System.Environment]::SetEnvironmentVariable('ChocolateyInstall', $null, $envTarget)
        [System.Environment]::SetEnvironmentVariable('ChocolateyLastPathUpdate', $null, $envTarget)
        
        # Remove from PATH
        Write-TerminalLog "Updating PATH environment variable..." "DEBUG"
        $path = [System.Environment]::GetEnvironmentVariable('Path', $envTarget)
        $path = ($path.Split(';') | Where-Object { $_ -notlike "*chocolatey*" }) -join ';'
        [System.Environment]::SetEnvironmentVariable('Path', $path, $envTarget)
        
        # Remove registry entries
        Write-TerminalLog "Cleaning registry entries..." "DEBUG"
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Chocolatey'
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force
        }
        
        # Verify uninstallation
        Write-TerminalLog "Verifying uninstallation..." "DEBUG"
        if (-not (Test-ChocoInstalled)) {
            Write-TerminalLog "Chocolatey uninstallation completed successfully" "SUCCESS"
            return @{
                success = $true
                message = "Chocolatey uninstalled successfully"
            }
        }
        
        throw "Uninstallation verification failed"
    }
    catch {
        Write-TerminalLog "Failed to uninstall Chocolatey: $($_.Exception.Message)" "ERROR"
        return @{
            success = $false
            error = "Failed to uninstall Chocolatey: $($_.Exception.Message)"
        }
    }
} 