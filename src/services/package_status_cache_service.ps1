# Cache to store package status
$script:PackageStatusCache = @{}

function Get-CachedPackageStatus {
    param (
        [string]$AppId
    )
    
    if ($script:PackageStatusCache.ContainsKey($AppId)) {
        return $script:PackageStatusCache[$AppId]
    }
    return $null
}

function Set-CachedPackageStatus {
    param (
        [string]$AppId,
        [hashtable]$Status
    )
    
    $script:PackageStatusCache[$AppId] = $Status
}

function Clear-PackageStatusCache {
    $script:PackageStatusCache.Clear()
} 