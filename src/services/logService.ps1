# Log Service Module
# Provides centralized logging functionality with colored output and file logging

# Define log colors for different message types
$LogColors = @{
    'INFO'     = 'White'
    'DEBUG'    = 'Cyan'
    'SUCCESS'  = 'Green'
    'WARNING'  = 'Yellow'
    'ERROR'    = 'Red'
    'REQUEST'  = 'Magenta'
    'RESPONSE' = 'Blue'
}

# Create logs directory if it doesn't exist
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Split-Path -Parent (Split-Path -Parent $scriptPath)
$logsPath = Join-Path $rootPath "logs"
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath | Out-Null
}

# Initialize log files for current session with timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$terminalLogFile = Join-Path $logsPath "terminal_$timestamp.log"
$guiLogFile = Join-Path $logsPath "gui_$timestamp.log"

# Create log files if they don't exist
if (-not (Test-Path $terminalLogFile)) {
    New-Item -ItemType File -Path $terminalLogFile | Out-Null
}
if (-not (Test-Path $guiLogFile)) {
    New-Item -ItemType File -Path $guiLogFile | Out-Null
}

<#
.SYNOPSIS
    Writes a log message to both console and file with color coding
.DESCRIPTION
    Central logging function that handles both console output with colors
    and file logging with timestamps
.PARAMETER Message
    The message to log
.PARAMETER Type
    The type of message (INFO, DEBUG, SUCCESS, WARNING, ERROR, REQUEST, RESPONSE)
.PARAMETER Source
    The source of the log (TERMINAL or GUI)
#>
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Type = "INFO",
        
        [Parameter(Mandatory=$false)]
        [string]$Source = "TERMINAL"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Type : $Message"
    
    # Write to console with color
    $color = $LogColors[$Type]
    Write-Host $logMessage -ForegroundColor $color
    
    # Write to appropriate log file
    if ($Source -eq "GUI") {
        Add-Content -Path $guiLogFile -Value $logMessage
    } else {
        Add-Content -Path $terminalLogFile -Value $logMessage
    }
}

<#
.SYNOPSIS
    Writes a terminal-specific log message
.DESCRIPTION
    Wrapper function for Write-Log that defaults to TERMINAL source
#>
function Write-TerminalLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Type = "INFO"
    )
    
    Write-Log -Message $Message -Type $Type -Source "TERMINAL"
}

<#
.SYNOPSIS
    Writes a GUI-specific log message
.DESCRIPTION
    Wrapper function for Write-Log that defaults to GUI source
#>
function Write-GuiLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Type = "INFO"
    )
    
    Write-Log -Message $Message -Type $Type -Source "GUI"
}

<#
.SYNOPSIS
    Gets the current log file paths
.DESCRIPTION
    Returns a hashtable containing the paths to current terminal and GUI log files
#>
function Get-CurrentLogFiles {
    return @{
        TerminalLog = $terminalLogFile
        GuiLog = $guiLogFile
    }
} 