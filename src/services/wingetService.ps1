# Winget Service Module
# Provides core functionality for interacting with Windows Package Manager (winget)

#Requires -Version 5.0
#Requires -RunAsAdministrator

function Write-DebugLog {
    param($Message, $Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] WINGET $Type : $Message"
}

<#
.SYNOPSIS
    Checks if winget is installed on the system
.DESCRIPTION
    Attempts to find winget command and returns boolean indicating availability
.RETURNS
    Boolean indicating whether winget is installed
#>
function Test-WingetInstalled {
    Write-TerminalLog "Checking if Winget is installed..." "DEBUG"
    try {
        $null = Get-Command winget -ErrorAction Stop
        Write-TerminalLog "Winget found on system" "SUCCESS"
        return $true
    }
    catch {
        Write-TerminalLog "Winget not found on system" "WARNING"
        return $false
    }
}

<#
.SYNOPSIS
    Gets the installed version of winget
.DESCRIPTION
    Executes winget --version and parses the output
.RETURNS
    String containing version number or error message
#>
function Get-WingetVersion {
    Write-TerminalLog "Getting Winget version..." "DEBUG"
    try {
        if (-not (Test-WingetInstalled)) {
            Write-TerminalLog "Winget is not installed" "ERROR"
            return "Error: Winget is not installed"
        }

        Write-TerminalLog "Executing winget --version..." "DEBUG"
        $process = Start-Process -FilePath "winget" -ArgumentList "--version" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_version.txt" -PassThru
        
        if ($process.ExitCode -eq 0) {
            $version = Get-Content "$env:TEMP\winget_version.txt"
            Remove-Item "$env:TEMP\winget_version.txt" -Force
            $version = $version.Trim()
            Write-TerminalLog "Winget version: $version" "SUCCESS"
            return $version
        } else {
            Write-TerminalLog "Winget command failed with exit code: $($process.ExitCode)" "ERROR"
            return "Error: Winget command failed"
        }
    }
    catch {
        Write-TerminalLog "Error getting Winget version: $_" "ERROR"
        return "Error: Unable to get winget version - $($_.Exception.Message)"
    }
} 