#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import cache service
. "$PSScriptRoot\package_status_cache_service.ps1"

function Get-PackagesList {
    try {
        $jsonPath = Join-Path $PSScriptRoot "..\..\winget_packages_list.json"
        $jsonContent = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
        @{
            success = $true
            packages = $jsonContent.packages
        }
    }
    catch {
        @{
            success = $false
            error = "Failed to read packages list: $($_.Exception.Message)"
        }
    }
}

function Get-PackageInstallStatus {
    param (
        [string]$AppId,
        [switch]$ForceRefresh
    )
    
    if (-not $ForceRefresh) {
        $cachedStatus = Get-CachedPackageStatus -AppId $AppId
        if ($cachedStatus) {
            return $cachedStatus
        }
    }
    
    try {
        $result = winget list --exact --id $AppId | Out-String
        $installed = $result -match $AppId
        $version = if ($installed) {
            if ($result -match "$AppId\s+(\S+)") {
                $matches[1]
            }
        }
        
        $status = @{
            installed = $installed
            version = $version
        }
        
        Set-CachedPackageStatus -AppId $AppId -Status $status
        return $status
    }
    catch {
        $status = @{
            installed = $false
            version = $null
        }
        Set-CachedPackageStatus -AppId $AppId -Status $status
        return $status
    }
} 