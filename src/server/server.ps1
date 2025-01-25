# Server Module
# Provides HTTP server functionality for the package management GUI
# Handles API endpoints for both Winget and Chocolatey operations

#Requires -Version 5.0
#Requires -RunAsAdministrator

# Import required service modules
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Split-Path -Parent (Split-Path -Parent $scriptPath)
. "$rootPath\src\services\logService.ps1"          # Logging functionality
. "$rootPath\src\services\wingetService.ps1"       # Winget operations
. "$rootPath\src\services\chocoService.ps1"        # Chocolatey operations
. "$rootPath\src\services\winget_package_status_Service.ps1"  # Package status management
. "$rootPath\src\services\choco_package_status_Service.ps1"   # Chocolatey package status management

Write-TerminalLog "Starting server initialization..." "INFO"

<#
.SYNOPSIS
    Finds an available port for the server
.DESCRIPTION
    Scans ports in the range 9000-9010 to find an unused port
    for the HTTP server to listen on
.RETURNS
    Selected port number or exits if no ports are available
#>
function Get-AvailablePort {
    Write-TerminalLog "Scanning ports 9000-9010 for availability..." "DEBUG"
    $ports = 9000..9010
    
    foreach ($port in $ports) {
        $portInUse = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if (-not $portInUse) {
            Write-TerminalLog "Found available port: $port" "SUCCESS"
            return $port
        }
        Write-TerminalLog "Port $port is in use" "DEBUG"
    }
    
    Write-TerminalLog "No available ports found in range 9000-9010" "ERROR"
    exit
}

# Initialize server configuration
$script:port = Get-AvailablePort
$script:url = "http://localhost:$port/"
$script:listener = $null

# CORS Configuration
$corsHeaders = @{
    'Access-Control-Allow-Origin' = '*'
    'Access-Control-Allow-Methods' = 'GET, POST, OPTIONS'
    'Access-Control-Allow-Headers' = 'Content-Type'
    'Access-Control-Max-Age' = '86400'  # Cache preflight for 24 hours
}

function Add-CorsHeaders {
    param($response)
    foreach ($header in $corsHeaders.GetEnumerator()) {
        $response.Headers.Add($header.Key, $header.Value)
    }
}

<#
.SYNOPSIS
    Initializes and starts the HTTP server for handling GUI requests
.DESCRIPTION
    Creates an HTTP listener on the available port and handles incoming requests
    for package management operations. Supports both Winget and Chocolatey
    operations through a RESTful API interface.
#>
function Start-PackageServer {
    Write-TerminalLog "Creating HTTP listener on port $port..." "DEBUG"
    
    try {
        # Initialize HTTP listener
        $script:listener = New-Object System.Net.HttpListener
        $script:listener.Prefixes.Add($url)
        
        # Start listening for requests
        $script:listener.Start()
        Write-TerminalLog "Server started successfully at $url" "SUCCESS"
        
        # Main request handling loop
        while ($script:listener.IsListening) {
            try {
                # Wait for and get request context
                $context = $script:listener.GetContext()
                $request = $context.Request
                $response = $context.Response
                
                # Add CORS headers to all responses
                Add-CorsHeaders $response
                
                # Handle preflight requests efficiently
                if ($request.HttpMethod -eq "OPTIONS") {
                    $response.StatusCode = 204
                    $response.Close()
                    continue
                }
                
                # Log incoming request details
                Write-TerminalLog "Received $($request.HttpMethod) request: $($request.RawUrl)" "REQUEST"
                
                # Handle request based on endpoint path
                $result = switch -Regex ($request.RawUrl) {
                    # Winget Version Endpoint
                    '/api/winget-version' {
                        Write-TerminalLog "Processing Winget version check request" "DEBUG"
                        @{
                            version = Get-WingetVersion
                        }
                    }
                    
                    # Winget Package List Endpoint
                    '/api/winget/packages-list' {
                        Write-TerminalLog "Processing packages list request" "DEBUG"
                        Get-WingetPackagesList
                    }
                    
                    # Winget Bulk Package Status Endpoint
                    '/api/winget/bulk-package-status' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing bulk package status request for: $($data.appId)" "DEBUG"
                            @{
                                status = Get-WingetBulkPackageStatus -AppId $data.appId -ForceRefresh:$data.refresh
                            }
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Winget Single Package Status Endpoint
                    '/api/winget/single-package-status' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing single package status request for: $($data.appId)" "DEBUG"
                            @{
                                status = Get-WingetSinglePackageStatus -AppId $data.appId -ForceRefresh:$data.refresh
                            }
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Winget Package Installation Endpoint
                    '/api/winget/install-package' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing package installation request for: $($data.appId)" "DEBUG"
                            Install-WingetPackage -AppId $data.appId
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Winget Package Uninstallation Endpoint
                    '/api/winget/uninstall-package' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing package uninstallation request for: $($data.appId)" "DEBUG"
                            Uninstall-WingetPackage -AppId $data.appId
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Winget Bulk Status Endpoint
                    '/api/winget/bulk-status' {
                        if ($request.HttpMethod -eq "POST") {
                            Write-TerminalLog "Processing Winget bulk status request" "DEBUG"
                            try {
                                # Read request body for specific appId
                                $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                                $data = $body | ConvertFrom-Json
                                
                                if ($data.appId) {
                                    # Single package request
                                    Write-TerminalLog "Checking status for package: $($data.appId)" "DEBUG"
                                    $result = Get-WingetBulkPackageStatus -AppIds @($data.appId) -ForceRefresh:$true
                                    
                                    if ($result.success) {
                                        @{
                                            success = $true
                                            results = $result.results
                                        }
                                    } else {
                                        $response.StatusCode = 500
                                        @{
                                            success = $false
                                            error = $result.error
                                        }
                                    }
                                } else {
                                    # Get packages list if no specific ID provided
                                    $packagesList = Get-WingetPackagesList
                                    if (-not $packagesList.success) {
                                        $response.StatusCode = 500
                                        @{
                                            success = $false
                                            error = "Failed to get packages list: $($packagesList.error)"
                                        }
                                    }
                                    
                                    $appIds = $packagesList.packages | ForEach-Object { $_.app_id }
                                    Write-TerminalLog "Checking status for $($appIds.Count) packages" "DEBUG"
                                    
                                    # Process all packages
                                    $result = Get-WingetBulkPackageStatus -AppIds $appIds -ForceRefresh:$true
                                    
                                    if ($result.success) {
                                        @{
                                            success = $true
                                            results = $result.results
                                        }
                                    } else {
                                        $response.StatusCode = 500
                                        @{
                                            success = $false
                                            error = $result.error
                                        }
                                    }
                                }
                            } catch {
                                Write-TerminalLog "Error during bulk status check: $($_.Exception.Message)" "ERROR"
                                $response.StatusCode = 500
                                @{
                                    success = $false
                                    error = $_.Exception.Message
                                }
                            }
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Operation Progress Endpoint
                    '/api/winget/operation-progress/{appId}' {
                        if ($request.HttpMethod -eq "GET") {
                            $response.Headers.Add("Content-Type", "text/event-stream")
                            $response.Headers.Add("Cache-Control", "no-cache")
                            $response.Headers.Add("Connection", "keep-alive")
                            
                            try {
                                $appId = $request.Url.Segments[-1]
                                $progressFile = Join-Path $env:TEMP "winget_progress_$appId.txt"
                                
                                while ($true) {
                                    if (Test-Path $progressFile) {
                                        $progress = Get-Content $progressFile | ConvertFrom-Json
                                        $data = @{
                                            progress = $progress.percentage
                                            status = $progress.status
                                        } | ConvertTo-Json
                                        
                                        $message = "data: $data`n`n"
                                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
                                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                                        $response.OutputStream.Flush()
                                        
                                        if ($progress.complete) {
                                            Remove-Item $progressFile
                                            break
                                        }
                                    }
                                    Start-Sleep -Milliseconds 100
                                }
                            } catch {
                                Write-TerminalLog "Error in progress stream: $($_.Exception.Message)" "ERROR"
                            }
                        }
                    }
                    
                    # Chocolatey Version Endpoint
                    '/api/choco-version' {
                        Write-TerminalLog "Processing Chocolatey version check request" "DEBUG"
                        @{
                            version = Get-ChocoVersion
                        }
                    }
                    
                    # Chocolatey Package List Endpoint
                    '/api/choco/packages-list' {
                        Write-TerminalLog "Processing Chocolatey packages list request" "DEBUG"
                        Get-ChocoPackagesList
                    }
                    
                    # Chocolatey Bulk Package Status Endpoint
                    '/api/choco/bulk-package-status' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing Chocolatey bulk package status request for: $($data.appId)" "DEBUG"
                            @{
                                status = Get-ChocoBulkPackageStatus -AppId $data.appId -ForceRefresh:$data.refresh
                            }
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Chocolatey Single Package Status Endpoint
                    '/api/choco/single-package-status' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing Chocolatey single package status request for: $($data.appId)" "DEBUG"
                            @{
                                status = Get-ChocoSinglePackageStatus -AppId $data.appId -ForceRefresh:$data.refresh
                            }
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Chocolatey Package Installation Endpoint
                    '/api/choco/install-package' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing Chocolatey package installation request for: $($data.appId)" "DEBUG"
                            Install-ChocoPackage -AppId $data.appId
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Chocolatey Package Uninstallation Endpoint
                    '/api/choco/uninstall-package' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-TerminalLog "Processing Chocolatey package uninstallation request for: $($data.appId)" "DEBUG"
                            Uninstall-ChocoPackage -AppId $data.appId
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Chocolatey Installation Endpoint
                    '/api/choco-install' {
                        Write-TerminalLog "Processing Chocolatey installation request" "DEBUG"
                        @{
                            result = Install-Chocolatey
                        }
                    }
                    
                    # Chocolatey Uninstallation Endpoint
                    '/api/choco-uninstall' {
                        Write-TerminalLog "Processing Chocolatey uninstallation request" "DEBUG"
                        @{
                            result = Uninstall-Chocolatey
                        }
                    }
                    
                    # Operation Progress Endpoint
                    '/api/choco/operation-progress/{appId}' {
                        if ($request.HttpMethod -eq "GET") {
                            $response.Headers.Add("Content-Type", "text/event-stream")
                            $response.Headers.Add("Cache-Control", "no-cache")
                            $response.Headers.Add("Connection", "keep-alive")
                            
                            try {
                                $appId = $request.Url.Segments[-1]
                                $progressFile = Join-Path $env:TEMP "choco_progress_$appId.txt"
                                
                                while ($true) {
                                    if (Test-Path $progressFile) {
                                        $progress = Get-Content $progressFile | ConvertFrom-Json
                                        $data = @{
                                            progress = $progress.percentage
                                            status = $progress.status
                                        } | ConvertTo-Json
                                        
                                        $message = "data: $data`n`n"
                                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
                                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                                        $response.OutputStream.Flush()
                                        
                                        if ($progress.complete) {
                                            Remove-Item $progressFile
                                            break
                                        }
                                    }
                                    Start-Sleep -Milliseconds 100
                                }
                            } catch {
                                Write-TerminalLog "Error in progress stream: $($_.Exception.Message)" "ERROR"
                            }
                        }
                    }
                    
                    # GUI Logging Endpoint
                    '/api/log' {
                        if ($request.HttpMethod -eq "POST") {
                            $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                            $data = $body | ConvertFrom-Json
                            Write-GuiLog -Message $data.message -Type $data.type
                            @{
                                success = $true
                            }
                        } else {
                            $response.StatusCode = 405
                            @{ error = "Method not allowed" }
                        }
                    }
                    
                    # Handle Unknown Endpoints
                    default {
                        Write-TerminalLog "Received request for unknown endpoint: $($request.RawUrl)" "WARNING"
                        $response.StatusCode = 404
                        @{
                            error = "Endpoint not found"
                        }
                    }
                }
                
                # Prepare and send response
                $jsonResponse = $result | ConvertTo-Json -Depth 10
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "application/json"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
                
                # Log response details
                Write-TerminalLog "Sent response: $($response.StatusCode)" "RESPONSE"
            }
            catch {
                # Handle request processing errors
                Write-TerminalLog "Error handling request: $($_.Exception.Message)" "ERROR"
                Write-TerminalLog "Stack trace: $($_.Exception.StackTrace)" "DEBUG"
                
                # Send error response
                $errorResponse = @{
                    error = $_.Exception.Message
                    stackTrace = $_.Exception.StackTrace
                } | ConvertTo-Json
                
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($errorResponse)
                $response.StatusCode = 500
                $response.ContentLength64 = $buffer.Length
                $response.ContentType = "application/json"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.Close()
            }
        }
    }
    catch {
        # Handle server startup/runtime errors
        Write-TerminalLog "Critical server error: $($_.Exception.Message)" "ERROR"
        Write-TerminalLog "Stack trace: $($_.Exception.StackTrace)" "DEBUG"
    }
    finally {
        # Ensure server is properly shut down
        if ($script:listener) {
            $script:listener.Stop()
            Write-TerminalLog "Server stopped" "INFO"
            Cleanup-LogService
        }
    }
}

<#
.SYNOPSIS
    Gracefully stops the HTTP server
.DESCRIPTION
    Stops the HTTP listener and performs cleanup operations
    to ensure proper server shutdown
#>
function Stop-PackageServer {
    Write-TerminalLog "Stopping package management server..." "INFO"
    try {
        if ($script:listener) {
            $script:listener.Stop()
            $script:listener.Close()
            Write-TerminalLog "Server stopped successfully" "SUCCESS"
            Cleanup-LogService
        }
    }
    catch {
        Write-TerminalLog "Error stopping server: $($_.Exception.Message)" "ERROR"
        Write-TerminalLog "Stack trace: $($_.Exception.StackTrace)" "DEBUG"
    }
}

# Start the server when this script is run
Start-PackageServer 