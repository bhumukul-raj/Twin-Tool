#Requires -Version 5.0
#Requires -RunAsAdministrator

function Write-DebugLog {
    param($Message, $Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] CHOCO $Type : $Message"
}

function Get-ChocoVersion {
    Write-DebugLog "Checking Chocolatey version..." "DEBUG"
    try {
        $version = choco --version
        Write-DebugLog "Chocolatey version found: $version" "SUCCESS"
        return @{
            installed = $true
            version = $version
        }
    }
    catch {
        Write-DebugLog "Chocolatey not found on system" "DEBUG"
        return @{
            installed = $false
            version = "Not Installed"
        }
    }
}

function Install-Chocolatey {
    Write-DebugLog "Starting Chocolatey installation..." "DEBUG"
    try {
        # Try winget first
        Write-DebugLog "Attempting installation via winget..." "DEBUG"
        winget install chocolatey
        Start-Sleep -Seconds 2
        
        # Verify installation
        Write-DebugLog "Verifying installation..." "DEBUG"
        $status = Get-ChocoVersion
        if ($status.installed) {
            Write-DebugLog "Chocolatey installed successfully via winget" "SUCCESS"
            return "Success"
        }

        # If winget fails, try web installer
        Write-DebugLog "Winget installation failed, trying web installer..." "DEBUG"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        $status = Get-ChocoVersion
        if ($status.installed) {
            Write-DebugLog "Chocolatey installed successfully via web installer" "SUCCESS"
            return "Success"
        }
        
        Write-DebugLog "Installation failed" "ERROR"
        return "Failed"
    }
    catch {
        Write-DebugLog "Installation error: $_" "ERROR"
        return "Failed"
    }
}

function Uninstall-Chocolatey {
    Write-DebugLog "Starting Chocolatey uninstallation..." "DEBUG"
    try {
        if (Test-Path "$env:ChocolateyInstall") {
            Write-DebugLog "Found Chocolatey installation at: $env:ChocolateyInstall" "DEBUG"
            Remove-Item -Path "$env:ChocolateyInstall" -Recurse -Force
            [System.Environment]::SetEnvironmentVariable('ChocolateyInstall', $null, 'Machine')
            Write-DebugLog "Chocolatey uninstalled successfully" "SUCCESS"
            return "Success"
        }
        Write-DebugLog "Chocolatey installation not found" "DEBUG"
        return "Not installed"
    }
    catch {
        Write-DebugLog "Uninstallation error: $_" "ERROR"
        return "Failed"
    }
} 