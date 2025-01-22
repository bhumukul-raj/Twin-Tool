#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import services
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Split-Path -Parent (Split-Path -Parent $scriptPath)
. "$rootPath\src\services\wingetService.ps1"
. "$rootPath\src\services\chocoService.ps1"
. "$rootPath\src\services\logService.ps1"
. "$rootPath\src\services\winget_package_status_Service.ps1"

Write-TerminalLog "Starting server initialization..."

# Find available port
$ports = 9000..9010
$selectedPort = $null

Write-TerminalLog "Scanning ports 9000-9010 for availability..."
foreach ($port in $ports) {
    $portInUse = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if (-not $portInUse) {
        $selectedPort = $port
        Write-TerminalLog "Found available port: $selectedPort"
        break
    }
    else {
        Write-TerminalLog "Port $port is in use" "DEBUG"
    }
}

if (-not $selectedPort) {
    Write-TerminalLog "No available ports found in range 9000-9010" "ERROR"
    exit
}

# Create and start listener
Write-TerminalLog "Creating HTTP listener on port $selectedPort..."
$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add("http://localhost:$selectedPort/")

try {
    $Listener.Start()
    Write-TerminalLog "Server started successfully on http://localhost:$selectedPort/" "SUCCESS"

    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response
        
        Write-TerminalLog "Received $($Request.HttpMethod) request: $($Request.Url.LocalPath)" "REQUEST"
        
        # CORS headers
        $Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $Response.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS")
        $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        
        if ($Request.HttpMethod -eq "OPTIONS") {
            $Response.StatusCode = 200
            $Response.Close()
            Write-TerminalLog "Handled OPTIONS request" "DEBUG"
            continue
        }

        # Handle endpoints
        $ResponseData = switch ($Request.Url.LocalPath) {
            "/api/winget-version" { 
                Write-TerminalLog "Checking Winget version..." "DEBUG"
                $version = Get-WingetVersion
                Write-TerminalLog "Winget version result: $version" "DEBUG"
                @{ version = $version }
            }
            "/api/choco-version" { 
                Write-TerminalLog "Checking Chocolatey version..." "DEBUG"
                $version = Get-ChocoVersion
                Write-TerminalLog "Chocolatey version result: $($version | ConvertTo-Json)" "DEBUG"
                @{ version = $version }
            }
            "/api/choco-install" { 
                Write-TerminalLog "Installing Chocolatey..." "DEBUG"
                $result = Install-Chocolatey
                Write-TerminalLog "Chocolatey installation result: $result" "DEBUG"
                @{ message = $result }
            }
            "/api/choco-uninstall" { 
                Write-TerminalLog "Uninstalling Chocolatey..." "DEBUG"
                $result = Uninstall-Chocolatey
                Write-TerminalLog "Chocolatey uninstallation result: $result" "DEBUG"
                @{ message = $result }
            }
            "/api/log" {
                if ($Request.HttpMethod -eq "POST") {
                    $reader = New-Object System.IO.StreamReader($Request.InputStream)
                    $body = $reader.ReadToEnd()
                    $logData = $body | ConvertFrom-Json
                    
                    Write-GuiLog -Message $logData.message -Type $logData.type
                    @{ status = "logged" }
                }
                else {
                    $Response.StatusCode = 405
                    @{ error = "Method not allowed" }
                }
            }
            "/api/packages-list" {
                Write-TerminalLog "Fetching packages list..." "DEBUG"
                $result = Get-PackagesList
                Write-TerminalLog "Packages list fetched" "DEBUG"
                $result
            }
            "/api/package-status" {
                if ($Request.HttpMethod -eq "POST") {
                    $reader = New-Object System.IO.StreamReader($Request.InputStream)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    Write-TerminalLog "Checking status for package: $($body.appId)" "DEBUG"
                    $status = Get-PackageInstallStatus -AppId $body.appId -ForceRefresh:$body.refresh
                    Write-TerminalLog "Package status retrieved" "DEBUG"
                    $status
                }
                else {
                    $Response.StatusCode = 405
                    @{ error = "Method not allowed" }
                }
            }
            "/api/package-install" {
                if ($Request.HttpMethod -eq "POST") {
                    $reader = New-Object System.IO.StreamReader($Request.InputStream)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    Write-TerminalLog "Installing package: $($body.appId)" "DEBUG"
                    $result = winget install --exact --id $body.appId --accept-source-agreements --accept-package-agreements
                    @{ success = $true }
                }
                else {
                    $Response.StatusCode = 405
                    @{ error = "Method not allowed" }
                }
            }
            "/api/package-uninstall" {
                if ($Request.HttpMethod -eq "POST") {
                    $reader = New-Object System.IO.StreamReader($Request.InputStream)
                    $body = $reader.ReadToEnd() | ConvertFrom-Json
                    Write-TerminalLog "Uninstalling package: $($body.appId)" "DEBUG"
                    $result = winget uninstall --exact --id $body.appId
                    @{ success = $true }
                }
                else {
                    $Response.StatusCode = 405
                    @{ error = "Method not allowed" }
                }
            }
            default { 
                Write-TerminalLog "Invalid endpoint requested: $($Request.Url.LocalPath)" "WARNING"
                $Response.StatusCode = 404
                @{ error = "Endpoint not found" }
            }
        }

        # Send response
        $JsonResponse = $ResponseData | ConvertTo-Json
        $Buffer = [System.Text.Encoding]::UTF8.GetBytes($JsonResponse)
        $Response.ContentLength64 = $Buffer.Length
        $Response.ContentType = "application/json"
        $Response.OutputStream.Write($Buffer, 0, $Buffer.Length)
        $Response.Close()
        
        Write-TerminalLog "Response sent: $JsonResponse" "RESPONSE"
    }
}
catch {
    Write-TerminalLog "Server error: $_" "ERROR"
    Write-Error "Server error: $_"
}
finally {
    if ($Listener.IsListening) {
        Write-TerminalLog "Shutting down server..." "INFO"
        $Listener.Stop()
        $Listener.Close()
        Write-TerminalLog "Server shutdown complete" "INFO"
    }
} 