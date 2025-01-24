# Twin Tool - Package Manager Interface

A comprehensive PowerShell-based tool for managing Windows package managers (Winget and Chocolatey) with a web interface, WebSocket integration, and advanced logging capabilities.

## Project Structure

```
twin-tool/
├── src/
│   ├── client/
│   │   └── public/
│   │       └── index.html         # Web interface with WebSocket support
│   ├── server/
│   │   └── server.ps1            # HTTP server & WebSocket implementation
│   └── services/
│       ├── wingetService.ps1             # Winget core operations
│       ├── chocoService.ps1              # Chocolatey core operations
│       ├── winget_package_status_Service.ps1    # Winget package status management
│       ├── choco_package_status_Service.ps1     # Chocolatey package status management
│       ├── package_status_cache_service.ps1     # Package status caching
│       └── logService.ps1                # Centralized logging system
├── logs/                         # Log files directory
│   ├── terminal_*.log           # Server-side logs
│   └── gui_*.log               # Client-side logs
├── winget_packages_list.json    # Winget package definitions
├── choco_packages_list.json     # Chocolatey package definitions
└── start.bat                    # Startup script
```

## Features

### 1. Package Manager Operations
- **Winget Integration**
  - Version checking and status monitoring
  - Package installation/uninstallation
  - Bulk status checking
  - Real-time status updates
  - Package operation queue management

- **Chocolatey Integration**
  - Installation/Uninstallation of Chocolatey itself
  - Package management with version control
  - Status monitoring and caching
  - Bulk operations support
  - Operation queue management

### 2. Server Features
- **HTTP Server**
  - Dynamic port selection (9000-9010)
  - CORS support
  - RESTful API endpoints
  - Comprehensive error handling
  - Request/Response logging

- **WebSocket Server**
  - Real-time terminal output streaming
  - Automatic reconnection handling
  - Connection status monitoring
  - Event-based communication

### 3. Advanced Logging System
- **Multi-Channel Logging**
  - Terminal logs (server operations)
  - GUI logs (user interactions)
  - WebSocket communication logs
  - Operation queue logs

- **Log Categories**
  - INFO: General information
  - DEBUG: Detailed debugging data
  - SUCCESS: Successful operations
  - WARNING: Non-critical issues
  - ERROR: Critical issues
  - REQUEST: API requests
  - RESPONSE: Server responses

### 4. Web Interface
- **Modern UI Components**
  - Tab-based navigation
  - Package status cards
  - Real-time status indicators
  - Operation controls
  - Terminal output viewer

- **Features**
  - Real-time WebSocket updates
  - Package operation queue
  - Bulk refresh capabilities
  - Status caching
  - Error handling with visual feedback

## API Endpoints

### Winget Endpoints
1. `/api/winget-version`
   - Method: GET
   - Returns: Current Winget version

2. `/api/winget/packages-list`
   - Method: GET
   - Returns: List of managed Winget packages

3. `/api/winget/bulk-package-status`
   - Method: POST
   - Body: `{ appId, refresh }`
   - Returns: Package installation status

4. `/api/winget/single-package-status`
   - Method: POST
   - Body: `{ appId, refresh }`
   - Returns: Single package status

5. `/api/winget/install-package`
   - Method: POST
   - Body: `{ appId }`
   - Action: Initiates package installation

6. `/api/winget/uninstall-package`
   - Method: POST
   - Body: `{ appId }`
   - Action: Initiates package uninstallation

### Chocolatey Endpoints
1. `/api/choco-version`
   - Method: GET
   - Returns: Chocolatey status and version

2. `/api/choco/packages-list`
   - Method: GET
   - Returns: List of managed Chocolatey packages

3. `/api/choco/bulk-package-status`
   - Method: POST
   - Body: `{ appId, refresh }`
   - Returns: Package installation status

4. `/api/choco/single-package-status`
   - Method: POST
   - Body: `{ appId, refresh }`
   - Returns: Single package status

5. `/api/choco/install-package`
   - Method: POST
   - Body: `{ appId }`
   - Action: Initiates package installation

6. `/api/choco/uninstall-package`
   - Method: POST
   - Body: `{ appId }`
   - Action: Initiates package uninstallation

7. `/api/choco-install`
   - Method: GET
   - Action: Installs Chocolatey

8. `/api/choco-uninstall`
   - Method: GET
   - Action: Uninstalls Chocolatey

### Logging Endpoint
1. `/api/log`
   - Method: POST
   - Body: `{ message, type, source }`
   - Purpose: Client-side log submission

## WebSocket Integration

- **Connection**: `ws://localhost:9001`
- **Message Types**:
  - system: System messages
  - stdout: Standard output
  - stderr: Standard error
  - command: Command execution
  - output: General output

## Getting Started

1. **System Requirements**
   - Windows 10/11
   - PowerShell 5.0+
   - Administrator privileges
   - .NET Framework 4.5+

2. **Installation**
   ```batch
   git clone https://github.com/yourusername/twin-tool.git
   cd twin-tool
   ```

3. **Running the Application**
   ```batch
   start.bat
   ```
   This will:
   - Launch server with admin privileges
   - Initialize WebSocket server
   - Open web interface
   - Start logging system

## Configuration Files

### winget_packages_list.json
```json
{
    "packages": [
        {
            "app_id": "Package.ID",
            "app_name": "Display Name",
            "app_desc": "Description"
        }
    ]
}
```

### choco_packages_list.json
```json
{
    "packages": [
        {
            "app_id": "package-id",
            "app_name": "Display Name",
            "app_desc": "Description"
        }
    ]
}
```

## Core Functions

### Package Management
- `Get-WingetPackagesList()`: Retrieves Winget packages
- `Get-ChocoPackagesList()`: Retrieves Chocolatey packages
- `Install-WingetPackage()`: Installs Winget package
- `Install-ChocoPackage()`: Installs Chocolatey package
- `Get-WingetVersion()`: Gets Winget version
- `Get-ChocoVersion()`: Gets Chocolatey version

### Status Management
- `Get-WingetBulkPackageStatus()`: Bulk status check
- `Get-ChocoBulkPackageStatus()`: Bulk status check
- `Get-CachedPackageStatus()`: Retrieves cached status
- `Set-CachedPackageStatus()`: Updates status cache

### Logging
- `Write-TerminalLog()`: Server-side logging
- `Write-GuiLog()`: Client-side logging
- `Write-Log()`: General logging function

## Error Handling

1. **Server-side**
   - Port conflict resolution
   - Process execution monitoring
   - WebSocket connection management
   - Package operation queuing

2. **Client-side**
   - Connection error recovery
   - Operation status tracking
   - Visual error indicators
   - Queue management

## Development Notes

- **Architecture**: Modular design with separate services
- **Communication**: Dual HTTP/WebSocket approach
- **State Management**: Cache-based status tracking
- **Error Handling**: Comprehensive error management
- **Logging**: Multi-channel logging system

## Future Enhancements

1. Package dependency management
2. Scheduled operations
3. Package update notifications
4. Custom package repository support
5. Advanced filtering and search
6. Backup and restore functionality

## Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details. 