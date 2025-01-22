#Requires -Version 5.0

# Create logs directory if it doesn't exist
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootPath = Split-Path -Parent (Split-Path -Parent $scriptPath)
$logsPath = Join-Path $rootPath "logs"
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath | Out-Null
}

# Initialize log files for current session
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$terminalLogFile = Join-Path $logsPath "terminal_$timestamp.log"
$guiLogFile = Join-Path $logsPath "gui_$timestamp.log"

# Create log files
New-Item -ItemType File -Path $terminalLogFile | Out-Null
New-Item -ItemType File -Path $guiLogFile | Out-Null

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
    
    # Always write to console
    Write-Host $logMessage
    
    # Write to appropriate log file
    if ($Source -eq "GUI") {
        Add-Content -Path $guiLogFile -Value $logMessage
    } else {
        Add-Content -Path $terminalLogFile -Value $logMessage
    }
}

function Write-TerminalLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Type = "INFO"
    )
    
    Write-Log -Message $Message -Type $Type -Source "TERMINAL"
}

function Write-GuiLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$Type = "INFO"
    )
    
    Write-Log -Message $Message -Type $Type -Source "GUI"
}

function Get-CurrentLogFiles {
    return @{
        TerminalLog = $terminalLogFile
        GuiLog = $guiLogFile
    }
}

# Export functions
Export-ModuleMember -Function Write-TerminalLog, Write-GuiLog, Get-CurrentLogFiles 