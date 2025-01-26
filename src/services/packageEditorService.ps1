# Package Editor Service
# Provides functionality for managing package lists for both Winget and Chocolatey

<#
.SYNOPSIS
    Gets the package list for the specified package type
.DESCRIPTION
    Reads and returns the package list from the appropriate JSON file
.PARAMETER PackageType
    The type of packages to get (winget or choco)
#>
function Get-PackageList {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('winget', 'choco')]
        [string]$PackageType
    )

    try {
        $fileName = if ($PackageType -eq 'winget') { 'winget_packages_list.json' } else { 'choco_packages_list.json' }
        $filePath = Join-Path $rootPath $fileName

        if (-not (Test-Path $filePath)) {
            Write-TerminalLog "Creating new package list file: $fileName" "INFO"
            @{ packages = @() } | ConvertTo-Json | Set-Content $filePath
        }

        $content = Get-Content $filePath -Raw
        $data = $content | ConvertFrom-Json

        @{
            success = $true
            packages = $data.packages
        }
    }
    catch {
        Write-TerminalLog "Error reading package list: $($_.Exception.Message)" "ERROR"
        @{
            success = $false
            error = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Saves the package list for the specified package type
.DESCRIPTION
    Saves the provided package list to the appropriate JSON file
.PARAMETER PackageType
    The type of packages to save (winget or choco)
.PARAMETER Packages
    The array of packages to save
#>
function Save-PackageList {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('winget', 'choco')]
        [string]$PackageType,

        [Parameter(Mandatory=$true)]
        [array]$Packages
    )

    try {
        $fileName = if ($PackageType -eq 'winget') { 'winget_packages_list.json' } else { 'choco_packages_list.json' }
        $filePath = Join-Path $rootPath $fileName

        # Create backup
        $backupPath = "$filePath.bak"
        if (Test-Path $filePath) {
            Copy-Item -Path $filePath -Destination $backupPath -Force
            Write-TerminalLog "Created backup of $fileName" "DEBUG"
        }

        # Save new data
        @{ packages = $Packages } | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath
        Write-TerminalLog "Successfully saved package list to $fileName" "SUCCESS"

        @{
            success = $true
            message = "Package list saved successfully"
        }
    }
    catch {
        Write-TerminalLog "Error saving package list: $($_.Exception.Message)" "ERROR"
        @{
            success = $false
            error = $_.Exception.Message
        }
    }
} 