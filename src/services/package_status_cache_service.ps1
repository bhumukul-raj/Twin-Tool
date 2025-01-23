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
    
    if ($script:PackageStatusCache.ContainsKey($AppId)) {
        return $script:PackageStatusCache[$AppId]
    }
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
    $script:PackageStatusCache.Clear()
} 