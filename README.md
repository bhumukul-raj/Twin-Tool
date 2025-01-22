# Twin Tool - Package Manager Interface

A PowerShell-based tool for managing Windows package managers (Winget and Chocolatey) with a web interface and comprehensive logging.

## Project Structure

```
twin-tool/
├── src/
│   ├── client/
│   │   └── public/
│   │       └── index.html         # Web interface
│   ├── server/
│   │   └── server.ps1            # HTTP server implementation
│   └── services/
│       ├── wingetService.ps1     # Winget operations
│       ├── chocoService.ps1      # Chocolatey operations
│       └── logService.ps1        # Logging system
├── logs/                         # Log files directory
│   ├── terminal_*.log           # Server-side logs
│   └── gui_*.log               # Client-side logs
└── start.bat                    # Startup script
```

## Features

### 1. Package Manager Operations
- **Winget Integration**
  - Version checking
  - Installation status verification
  - Error handling and reporting

- **Chocolatey Integration**
  - Version checking
  - Installation/Uninstallation
  - Multiple installation methods (winget/web installer)
  - Status monitoring

### 2. Server Features
- Dynamic port selection (9000-9010)
- CORS support
- RESTful API endpoints
- Error handling
- Request/Response logging

### 3. Logging System
- **Dual Logging System**
  - Terminal logs for server operations
  - GUI logs for user interactions
  - Timestamp-based log files
  - Session-specific logging

- **Log Types**
  - INFO: General information
  - DEBUG: Detailed process information
  - SUCCESS: Successful operations
  - WARNING: Non-critical issues
  - ERROR: Critical issues
  - REQUEST: Incoming requests
  - RESPONSE: Outgoing responses

### 4. Web Interface
- Clean, modern design
- Real-time status updates
- Toggle switch for Chocolatey installation
- Error handling and user feedback
- Responsive layout

## API Endpoints

1. `/api/winget-version`
   - Method: GET
   - Returns: Winget version information

2. `/api/choco-version`
   - Method: GET
   - Returns: Chocolatey installation status and version

3. `/api/choco-install`
   - Method: GET
   - Action: Installs Chocolatey
   - Returns: Installation status

4. `/api/choco-uninstall`
   - Method: GET
   - Action: Uninstalls Chocolatey
   - Returns: Uninstallation status

5. `/api/log`
   - Method: POST
   - Purpose: GUI event logging
   - Body: `{ message, type, source }`

## Getting Started

1. **Prerequisites**
   - Windows 10/11
   - PowerShell 5.0 or higher
   - Administrator privileges

2. **Installation**
   - Clone or download the repository
   - No additional installation required

3. **Running the Application**
   ```batch
   start.bat
   ```
   This will:
   - Start the server with admin privileges
   - Open the web interface
   - Initialize logging system

## Technical Details

### Server Implementation
- Uses `System.Net.HttpListener`
- Automatic port selection
- JSON response format
- Comprehensive error handling

### Logging Implementation
- File-based logging system
- Separate GUI and terminal logs
- Automatic log file creation
- Structured log format

### Security Features
- Admin privilege requirement
- CORS protection
- Error message sanitization
- Safe process handling

## Error Handling

1. **Server-side**
   - Port conflict resolution
   - Process execution monitoring
   - Exception logging
   - Client communication errors

2. **Client-side**
   - Connection error handling
   - Operation status feedback
   - Visual error indicators
   - User-friendly messages

## Development Notes

- **Modular Design**: Separate services for different functionalities
- **Clean Code**: Well-documented and structured codebase
- **Error Handling**: Comprehensive error management
- **Logging**: Detailed logging for debugging and monitoring
- **User Interface**: Intuitive and responsive design

## Future Enhancements

1. Additional package manager support
2. Enhanced error reporting
3. Configuration file support
4. Log rotation and management
5. Advanced installation options
6. Package search functionality 