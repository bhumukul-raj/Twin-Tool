#Requires -Version 5.0
#Requires -RunAsAdministrator

function Write-DebugLog {
    param($Message, $Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] WINGET $Type : $Message"
}

function Test-WingetInstalled {
    Write-DebugLog "Checking if Winget is installed..." "DEBUG"
    try {
        $null = Get-Command winget -ErrorAction Stop
        Write-DebugLog "Winget found on system" "SUCCESS"
        return $true
    }
    catch {
        Write-DebugLog "Winget not found on system" "WARNING"
        return $false
    }
}

function Get-WingetVersion {
    Write-DebugLog "Getting Winget version..." "DEBUG"
    try {
        if (-not (Test-WingetInstalled)) {
            Write-DebugLog "Winget is not installed" "ERROR"
            return "Error: Winget is not installed"
        }

        Write-DebugLog "Executing winget --version..." "DEBUG"
        $process = Start-Process -FilePath "winget" -ArgumentList "--version" -Wait -NoNewWindow -RedirectStandardOutput "$env:TEMP\winget_version.txt" -PassThru
        
        if ($process.ExitCode -eq 0) {
            $version = Get-Content "$env:TEMP\winget_version.txt"
            Remove-Item "$env:TEMP\winget_version.txt" -Force
            $version = $version.Trim()
            Write-DebugLog "Winget version: $version" "SUCCESS"
            return $version
        } else {
            Write-DebugLog "Winget command failed with exit code: $($process.ExitCode)" "ERROR"
            return "Error: Winget command failed"
        }
    }
    catch {
        Write-DebugLog "Error getting Winget version: $_" "ERROR"
        return "Error: Unable to get winget version - $($_.Exception.Message)"
    }
} 