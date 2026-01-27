<#
.SYNOPSIS
    Deploys ImDisk files to the network share for server installation.

.DESCRIPTION
    This script copies the required ImDisk files from a local installation
    to the network share for silent deployment on servers.

.PARAMETER TargetPath
    Network path where ImDisk files should be deployed.
    Default: \\t-no1fkxtst-app\FkCommon\Software\WindowsApps\imRamdisk

.PARAMETER SourcePath
    Path to local ImDisk installation. If not specified, uses the standard
    installation path or downloads fresh.

.EXAMPLE
    .\Deploy-ImDiskToShare.ps1
    Deploys ImDisk files to the default network share.

.NOTES
    Author: Geir Helge Starholm
    Requires: ImDisk installed locally or internet access to download
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetPath = "\\t-no1fkxtst-app\FkCommon\Software\WindowsApps\imRamdisk",

    [Parameter(Mandatory = $false)]
    [string]$SourcePath
)

$ErrorActionPreference = 'Stop'

# Import logging if available
try {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
    $useLogging = $true
}
catch {
    $useLogging = $false
}

function Write-Status {
    param([string]$Message, [string]$Level = "INFO")
    if ($useLogging) {
        Write-LogMessage $Message -Level $Level
    }
    else {
        $colors = @{ INFO = "Cyan"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }
        Write-Host "[$Level] $Message" -ForegroundColor $colors[$Level]
    }
}

try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ImDisk Network Share Deployment" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Verify target path is accessible
    $targetParent = Split-Path $TargetPath -Parent
    if (-not (Test-Path $targetParent)) {
        throw "Cannot access network path: $targetParent"
    }

    # Create target directory structure
    Write-Status "Creating directory structure at: $TargetPath"
    
    $directories = @(
        $TargetPath,
        (Join-Path $TargetPath "drivers"),
        (Join-Path $TargetPath "bin"),
        (Join-Path $TargetPath "lib")
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Status "Created: $dir"
        }
    }

    # Find source files
    $localImDiskPath = if ($SourcePath -and (Test-Path $SourcePath)) {
        $SourcePath
    }
    elseif (Test-Path "$env:ProgramFiles\ImDisk") {
        "$env:ProgramFiles\ImDisk"
    }
    elseif (Test-Path "${env:ProgramFiles(x86)}\ImDisk") {
        "${env:ProgramFiles(x86)}\ImDisk"
    }
    else {
        $null
    }

    # System files to copy
    $systemFiles = @{
        "$env:windir\System32\imdisk.exe" = "bin\imdisk.exe"
        "$env:windir\System32\imdisk.cpl" = "bin\imdisk.cpl"
        "$env:windir\System32\drivers\imdisk.sys" = "drivers\imdisk.sys"
        "$env:windir\System32\drivers\awealloc.sys" = "drivers\awealloc.sys"
    }

    # Check if we have the required system files
    $hasSystemFiles = $true
    foreach ($file in $systemFiles.Keys) {
        if (-not (Test-Path $file)) {
            Write-Status "Missing system file: $file" -Level WARN
            $hasSystemFiles = $false
        }
    }

    if (-not $hasSystemFiles) {
        Write-Status "ImDisk is not installed locally. Please install ImDisk first." -Level ERROR
        Write-Status "Download from: https://sourceforge.net/projects/imdisk-toolkit/" -Level INFO
        throw "ImDisk system files not found"
    }

    # Copy system files
    Write-Status "Copying system files..."
    foreach ($source in $systemFiles.Keys) {
        $dest = Join-Path $TargetPath $systemFiles[$source]
        Copy-Item -Path $source -Destination $dest -Force
        Write-Status "  Copied: $($systemFiles[$source])"
    }

    # Copy INF files if available
    $infFiles = @(
        "$env:windir\System32\imdisk.inf",
        "$env:windir\inf\imdisk.inf"
    )
    
    foreach ($inf in $infFiles) {
        if (Test-Path $inf) {
            Copy-Item -Path $inf -Destination (Join-Path $TargetPath "drivers\imdisk.inf") -Force
            Write-Status "  Copied: imdisk.inf"
            break
        }
    }

    # Copy ImDisk Toolkit files if available
    if ($localImDiskPath) {
        Write-Status "Copying ImDisk Toolkit files from: $localImDiskPath"
        
        $toolkitFiles = @(
            "config.exe",
            "RamDiskUI.exe",
            "RamDyn.exe",
            "MountImg.exe",
            "ImDisk-Dlg.exe",
            "ImDiskTk-svc.exe",
            "lang.txt"
        )
        
        foreach ($file in $toolkitFiles) {
            $sourcePath = Join-Path $localImDiskPath $file
            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination (Join-Path $TargetPath "bin\$file") -Force
                Write-Status "  Copied: $file"
            }
        }

        # Copy DiscUtils folder
        $discUtilsPath = Join-Path $localImDiskPath "DiscUtils"
        if (Test-Path $discUtilsPath) {
            Write-Status "Copying DiscUtils libraries..."
            Get-ChildItem -Path $discUtilsPath -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination (Join-Path $TargetPath "lib\$($_.Name)") -Force
                Write-Status "  Copied: $($_.Name)"
            }
        }
    }

    # Create installation script
    Write-Status "Creating installation script..."
    
    $installScript = @'
<#
.SYNOPSIS
    Installs ImDisk from the network share.

.DESCRIPTION
    Copies ImDisk files to system directories and registers the drivers.
    Must be run as Administrator.

.EXAMPLE
    .\Install-ImDisk.ps1
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

$scriptDir = $PSScriptRoot

Write-Host "Installing ImDisk from network share..." -ForegroundColor Cyan

try {
    # Stop existing services
    Stop-Service -Name "ImDskSvc" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "ImDisk" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "AWEAlloc" -Force -ErrorAction SilentlyContinue

    # Copy drivers
    Write-Host "  Copying drivers..."
    Copy-Item -Path "$scriptDir\drivers\imdisk.sys" -Destination "$env:windir\System32\drivers\" -Force
    Copy-Item -Path "$scriptDir\drivers\awealloc.sys" -Destination "$env:windir\System32\drivers\" -Force

    # Copy CLI and CPL
    Write-Host "  Copying executables..."
    Copy-Item -Path "$scriptDir\bin\imdisk.exe" -Destination "$env:windir\System32\" -Force
    Copy-Item -Path "$scriptDir\bin\imdisk.cpl" -Destination "$env:windir\System32\" -Force

    # Copy INF if present
    if (Test-Path "$scriptDir\drivers\imdisk.inf") {
        Copy-Item -Path "$scriptDir\drivers\imdisk.inf" -Destination "$env:windir\System32\" -Force
    }

    # Register drivers using sc.exe
    Write-Host "  Registering ImDisk driver..."
    & sc.exe create ImDisk type= kernel start= demand binPath= "System32\drivers\imdisk.sys" DisplayName= "ImDisk Virtual Disk Driver" 2>$null
    & sc.exe description ImDisk "ImDisk Virtual Disk Driver - Creates virtual disk devices" 2>$null

    Write-Host "  Registering AWEAlloc driver..."
    & sc.exe create AWEAlloc type= kernel start= demand binPath= "System32\drivers\awealloc.sys" DisplayName= "AWE Allocation Driver" 2>$null
    & sc.exe description AWEAlloc "AWE Allocation Driver - Physical memory allocation for ImDisk" 2>$null

    # Start drivers
    Write-Host "  Starting drivers..."
    Start-Service -Name "ImDisk" -ErrorAction SilentlyContinue
    Start-Service -Name "AWEAlloc" -ErrorAction SilentlyContinue

    # Verify installation
    $imdiskExe = Get-Command imdisk -ErrorAction SilentlyContinue
    if ($imdiskExe) {
        Write-Host ""
        Write-Host "ImDisk installed successfully!" -ForegroundColor Green
        Write-Host "  Location: $($imdiskExe.Source)" -ForegroundColor Green
        
        # Quick test
        $version = & imdisk --version 2>&1 | Select-Object -First 1
        Write-Host "  Version: $version" -ForegroundColor Green
    }
    else {
        Write-Host "Installation completed but imdisk.exe not found in PATH" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
'@

    Set-Content -Path (Join-Path $TargetPath "Install-ImDisk.ps1") -Value $installScript -Encoding UTF8
    Write-Status "Created: Install-ImDisk.ps1"

    # Create uninstallation script
    $uninstallScript = @'
<#
.SYNOPSIS
    Uninstalls ImDisk from the system.

.DESCRIPTION
    Removes ImDisk drivers, services, and files.
    Must be run as Administrator.

.EXAMPLE
    .\Uninstall-ImDisk.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "This script must be run as Administrator"
}

Write-Host "Uninstalling ImDisk..." -ForegroundColor Cyan

try {
    # Remove any mounted ImDisk devices
    Write-Host "  Removing mounted devices..."
    $imdiskPath = Get-Command imdisk -ErrorAction SilentlyContinue
    if ($imdiskPath) {
        $devices = & imdisk -l 2>$null
        if ($devices) {
            # Force remove all devices
            & imdisk -l | ForEach-Object {
                if ($_ -match "Device\s+(\d+)") {
                    & imdisk -D -u $Matches[1] 2>$null
                }
            }
        }
    }

    # Stop and delete services
    Write-Host "  Stopping services..."
    Stop-Service -Name "ImDskSvc" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "ImDisk" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "AWEAlloc" -Force -ErrorAction SilentlyContinue

    Write-Host "  Removing services..."
    & sc.exe delete ImDskSvc 2>$null
    & sc.exe delete ImDisk 2>$null
    & sc.exe delete AWEAlloc 2>$null

    # Remove files
    Write-Host "  Removing files..."
    $filesToRemove = @(
        "$env:windir\System32\imdisk.exe",
        "$env:windir\System32\imdisk.cpl",
        "$env:windir\System32\imdisk.inf",
        "$env:windir\System32\drivers\imdisk.sys",
        "$env:windir\System32\drivers\awealloc.sys"
    )

    foreach ($file in $filesToRemove) {
        if (Test-Path $file) {
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
            Write-Host "    Removed: $file"
        }
    }

    # Remove Program Files folder
    $progFilesPath = "$env:ProgramFiles\ImDisk"
    if (Test-Path $progFilesPath) {
        Remove-Item -Path $progFilesPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    Removed: $progFilesPath"
    }

    Write-Host ""
    Write-Host "ImDisk uninstalled successfully!" -ForegroundColor Green
    Write-Host "A reboot may be required to complete removal." -ForegroundColor Yellow
}
catch {
    Write-Host "Uninstallation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
'@

    Set-Content -Path (Join-Path $TargetPath "Uninstall-ImDisk.ps1") -Value $uninstallScript -Encoding UTF8
    Write-Status "Created: Uninstall-ImDisk.ps1"

    # Create a README
    $readme = @"
# ImDisk Network Installation

This folder contains ImDisk Virtual Disk Driver for silent server deployment.

## Quick Install

Run as Administrator:
``````powershell
& "\\t-no1fkxtst-app\FkCommon\Software\WindowsApps\imRamdisk\Install-ImDisk.ps1"
``````

## Quick Uninstall

Run as Administrator:
``````powershell
& "\\t-no1fkxtst-app\FkCommon\Software\WindowsApps\imRamdisk\Uninstall-ImDisk.ps1"
``````

## Using with Handle-RamDisk Module

``````powershell
Import-Module Handle-RamDisk -Force
Handle-RamDisk -Action Install
Handle-RamDisk -Action Create -SizeGB 4 -DriveLetter V:
``````

## Directory Structure

- ``bin/`` - Executables (imdisk.exe, imdisk.cpl, toolkit apps)
- ``drivers/`` - Kernel drivers (imdisk.sys, awealloc.sys)
- ``lib/`` - .NET libraries (DiscUtils, etc.)

## Notes

- All RAM disks are created using AWEAlloc (locked physical memory)
- RAM disk data is NOT swapped to page file
- Requires Administrator privileges for installation
"@

    Set-Content -Path (Join-Path $TargetPath "README.md") -Value $readme -Encoding UTF8
    Write-Status "Created: README.md"

    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Deployment Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files deployed to: $TargetPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Directory contents:" -ForegroundColor White
    Get-ChildItem -Path $TargetPath -Recurse | ForEach-Object {
        $indent = "  " * ($_.FullName.Split('\').Count - $TargetPath.Split('\').Count)
        if ($_.PSIsContainer) {
            Write-Host "$indent$($_.Name)/" -ForegroundColor Yellow
        }
        else {
            Write-Host "$indent$($_.Name)" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "To install on a server, run:" -ForegroundColor Cyan
    Write-Host "  & `"$TargetPath\Install-ImDisk.ps1`"" -ForegroundColor White
}
catch {
    Write-Status "Deployment failed: $($_.Exception.Message)" -Level ERROR
    throw
}
