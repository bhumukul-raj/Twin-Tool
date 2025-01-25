# Package Status Cache Service Module
# Provides in-memory caching functionality for package installation status

# Initialize global cache hashtable
$script:PackageStatusCache = @{}

<#
.SYNOPSIS
    Retrieves cached package status for a given application ID
.DESCRIPTION
    Checks if package status exists in cache and returns it if found
.PARAMETER AppId
    The unique identifier of the package to look up
.RETURNS
    Hashtable containing package status if found, null otherwise
#>
function Get-CachedPackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId
    )
    
    Write-TerminalLog "Checking cache for package: $AppId" "DEBUG"
    if ($script:PackageStatusCache.ContainsKey($AppId)) {
        $status = $script:PackageStatusCache[$AppId]
        Write-TerminalLog "Found cached status for $AppId : $($status | ConvertTo-Json)" "DEBUG"
        return $status
    }
    Write-TerminalLog "No cached status found for $AppId" "DEBUG"
    return $null
}

<#
.SYNOPSIS
    Stores package status in the cache
.DESCRIPTION
    Updates or adds new package status information to the cache
.PARAMETER AppId
    The unique identifier of the package
.PARAMETER Status
    Hashtable containing package status information (installed, version)
#>
function Set-CachedPackageStatus {
    param (
        [Parameter(Mandatory=$true)]
        [string]$AppId,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Status
    )
    
    Write-TerminalLog "Caching status for package $AppId : $($Status | ConvertTo-Json)" "DEBUG"
    $script:PackageStatusCache[$AppId] = $Status
}

<#
.SYNOPSIS
    Clears all cached package status information
.DESCRIPTION
    Removes all entries from the package status cache.
    Should be called after package installations/uninstallations
    to ensure cache consistency.
#>
function Clear-PackageStatusCache {
    Write-TerminalLog "Clearing package status cache" "DEBUG"
    $script:PackageStatusCache.Clear()
} 