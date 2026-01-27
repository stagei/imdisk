<#
.SYNOPSIS
    Quick installer for ImDisk Virtual Disk Driver on Windows servers.

.DESCRIPTION
    Downloads and installs ImDisk silently, then optionally creates a RAM disk.
    Can be run on any Windows server without prerequisites.

.PARAMETER RamDiskSize
    Size of RAM disk to create after installation (e.g., "4G", "512M", "8G").
    If not specified, no RAM disk is created.

.PARAMETER RamDiskLetter
    Drive letter for the RAM disk (default: R)

.PARAMETER UseAWE
    Use AWEAlloc for locked physical memory (recommended for performance).
    Default: $true

.PARAMETER FileSystem
    File system to format the RAM disk with (NTFS, FAT32, exFAT).
    Default: NTFS

.PARAMETER DownloadOnly
    Only download the installer, don't install.

.PARAMETER Uninstall
    Uninstall ImDisk instead of installing.

.EXAMPLE
    .\Install-ImDisk.ps1
    Installs ImDisk without creating a RAM disk.

.EXAMPLE
    .\Install-ImDisk.ps1 -RamDiskSize 4G
    Installs ImDisk and creates a 4GB RAM disk on R:

.EXAMPLE
    .\Install-ImDisk.ps1 -RamDiskSize 8G -RamDiskLetter T -UseAWE
    Installs ImDisk and creates an 8GB locked RAM disk on T:

.NOTES
    Author: Auto-generated for ImDisk deployment
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RamDiskSize,

    [Parameter(Mandatory = $false)]
    [ValidatePattern("^[D-Z]$")]
    [string]$RamDiskLetter = "R",

    [Parameter(Mandatory = $false)]
    [switch]$UseAWE = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet("NTFS", "FAT32", "exFAT")]
    [string]$FileSystem = "NTFS",

    [Parameter(Mandatory = $false)]
    [switch]$DownloadOnly,

    [Parameter(Mandatory = $false)]
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

#region Configuration
$ImDiskVersion = "2.0.10"
$ImDiskUrl = "https://github.com/LTRData/ImDisk/releases/download/v$($ImDiskVersion)/imdisk_$($ImDiskVersion).zip"
$TempPath = Join-Path $env:TEMP "ImDisk_Install"
$ZipPath = Join-Path $TempPath "imdisk.zip"
$ExtractPath = Join-Path $TempPath "imdisk"
#endregion

#region Helper Functions
function Write-Status {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{ INFO = "Cyan"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
    Write-Host "[$Level] " -NoNewline -ForegroundColor $colors[$Level]
    Write-Host $Message
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ImDiskInstalled {
    $driverPath = "$env:SystemRoot\System32\drivers\imdisk.sys"
    $cliPath = "$env:SystemRoot\System32\imdisk.exe"
    return (Test-Path $driverPath) -and (Test-Path $cliPath)
}

function Get-ImDiskVersion {
    if (Test-ImDiskInstalled) {
        try {
            $output = & imdisk --version 2>&1
            if ($output -match "version\s+(\d+\.\d+\.\d+)") {
                return $Matches[1]
            }
        }
        catch { }
    }
    return $null
}
#endregion

#region Main Script
try {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ImDisk Virtual Disk Driver Installer" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check administrator
    if (-not (Test-Administrator)) {
        Write-Status "This script requires Administrator privileges!" -Level ERROR
        Write-Host ""
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }

    # Handle uninstall
    if ($Uninstall) {
        Write-Status "Uninstalling ImDisk..." -Level INFO
        
        if (-not (Test-ImDiskInstalled)) {
            Write-Status "ImDisk is not installed." -Level WARN
            exit 0
        }

        # Remove any mounted ImDisk devices first
        Write-Status "Removing mounted ImDisk devices..." -Level INFO
        $devices = & imdisk -l 2>$null
        if ($devices) {
            & imdisk -l | ForEach-Object {
                if ($_ -match "Device\s+(\d+)") {
                    & imdisk -D -u $Matches[1] 2>$null
                }
            }
        }

        # Run uninstaller
        $uninstaller = "$env:SystemRoot\System32\rundll32.exe"
        & $uninstaller setupapi.dll,InstallHinfSection DefaultUninstall 132 "$env:SystemRoot\System32\imdisk.inf"
        
        Start-Sleep -Seconds 2
        
        if (-not (Test-ImDiskInstalled)) {
            Write-Status "ImDisk uninstalled successfully!" -Level SUCCESS
        }
        else {
            Write-Status "Uninstall may require a reboot to complete." -Level WARN
        }
        exit 0
    }

    # Check if already installed
    $installedVersion = Get-ImDiskVersion
    if ($installedVersion) {
        Write-Status "ImDisk version $installedVersion is already installed." -Level INFO
        
        if (-not $RamDiskSize) {
            Write-Status "Use -RamDiskSize parameter to create a RAM disk." -Level INFO
            exit 0
        }
    }
    else {
        # Download and install
        Write-Status "Downloading ImDisk v$ImDiskVersion..." -Level INFO

        # Create temp directory
        if (Test-Path $TempPath) {
            Remove-Item $TempPath -Recurse -Force
        }
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null

        # Download
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($ImDiskUrl, $ZipPath)
            Write-Status "Download complete." -Level SUCCESS
        }
        catch {
            Write-Status "Failed to download from GitHub. Trying alternative..." -Level WARN
            
            # Alternative: SourceForge mirror
            $AltUrl = "https://sourceforge.net/projects/imdisk-toolkit/files/latest/download"
            try {
                Invoke-WebRequest -Uri $AltUrl -OutFile $ZipPath -UseBasicParsing
                Write-Status "Download complete (from SourceForge)." -Level SUCCESS
            }
            catch {
                Write-Status "Download failed: $($_.Exception.Message)" -Level ERROR
                exit 1
            }
        }

        if ($DownloadOnly) {
            $finalPath = Join-Path (Get-Location) "imdisk_$ImDiskVersion.zip"
            Copy-Item $ZipPath $finalPath -Force
            Write-Status "Installer saved to: $finalPath" -Level SUCCESS
            exit 0
        }

        # Extract
        Write-Status "Extracting..." -Level INFO
        Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force

        # Find and run installer
        Write-Status "Installing ImDisk..." -Level INFO
        
        # Look for install script or inf file
        $installBat = Get-ChildItem -Path $ExtractPath -Filter "install.bat" -Recurse | Select-Object -First 1
        $installCmd = Get-ChildItem -Path $ExtractPath -Filter "install.cmd" -Recurse | Select-Object -First 1
        $infFile = Get-ChildItem -Path $ExtractPath -Filter "imdisk.inf" -Recurse | Select-Object -First 1

        if ($installBat) {
            Push-Location $installBat.DirectoryName
            & cmd /c $installBat.FullName /silent 2>&1 | Out-Null
            Pop-Location
        }
        elseif ($installCmd) {
            Push-Location $installCmd.DirectoryName
            & cmd /c $installCmd.FullName /silent 2>&1 | Out-Null
            Pop-Location
        }
        elseif ($infFile) {
            # Use rundll32 to install via INF
            $infPath = $infFile.FullName
            & rundll32.exe setupapi.dll,InstallHinfSection DefaultInstall 132 $infPath
        }
        else {
            # Try running any setup executable
            $setupExe = Get-ChildItem -Path $ExtractPath -Filter "*.exe" -Recurse | 
                Where-Object { $_.Name -match "setup|install" } | 
                Select-Object -First 1
            
            if ($setupExe) {
                & $setupExe.FullName /S /silent /quiet 2>&1 | Out-Null
            }
            else {
                Write-Status "Could not find installer in extracted files." -Level ERROR
                exit 1
            }
        }

        # Wait for installation
        Start-Sleep -Seconds 3

        # Verify installation
        if (Test-ImDiskInstalled) {
            Write-Status "ImDisk installed successfully!" -Level SUCCESS
        }
        else {
            Write-Status "Installation may require a reboot. Checking services..." -Level WARN
            
            # Try to start the driver
            Start-Service ImDisk -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            
            if (Test-ImDiskInstalled) {
                Write-Status "ImDisk is now available." -Level SUCCESS
            }
            else {
                Write-Status "Please reboot and run this script again to create a RAM disk." -Level WARN
                exit 0
            }
        }

        # Cleanup
        Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create RAM disk if requested
    if ($RamDiskSize) {
        Write-Host ""
        Write-Status "Creating RAM disk..." -Level INFO
        Write-Status "  Size: $RamDiskSize" -Level INFO
        Write-Status "  Drive: $($RamDiskLetter):" -Level INFO
        Write-Status "  Type: $(if ($UseAWE) { 'AWEAlloc (locked physical RAM)' } else { 'Virtual Memory' })" -Level INFO
        Write-Status "  Format: $FileSystem" -Level INFO

        # Check if drive letter is in use
        if (Test-Path "$($RamDiskLetter):") {
            Write-Status "Drive $($RamDiskLetter): is already in use!" -Level ERROR
            exit 1
        }

        # Build imdisk command
        $imdiskArgs = @(
            "-a"
            "-s", $RamDiskSize
            "-m", "$($RamDiskLetter):"
            "-p", "/fs:$FileSystem /q /y"
        )

        if ($UseAWE) {
            $imdiskArgs += "-o", "awe"
        }
        else {
            $imdiskArgs += "-t", "vm"
        }

        # Create the RAM disk
        Write-Status "Executing: imdisk $($imdiskArgs -join ' ')" -Level INFO
        
        $result = & imdisk @imdiskArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Start-Sleep -Seconds 2
            
            # Verify
            if (Test-Path "$($RamDiskLetter):") {
                $volume = Get-Volume -DriveLetter $RamDiskLetter -ErrorAction SilentlyContinue
                if ($volume) {
                    $sizeGB = [math]::Round($volume.Size / 1GB, 2)
                    Write-Status "RAM disk created successfully!" -Level SUCCESS
                    Write-Host ""
                    Write-Host "  Drive Letter:  $($RamDiskLetter):" -ForegroundColor Green
                    Write-Host "  Size:          $sizeGB GB" -ForegroundColor Green
                    Write-Host "  File System:   $($volume.FileSystem)" -ForegroundColor Green
                    Write-Host "  Type:          $(if ($UseAWE) { 'Physical RAM (locked)' } else { 'Virtual Memory' })" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Status "Failed to create RAM disk: $result" -Level ERROR
            exit 1
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Installation Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    
    if (-not $RamDiskSize) {
        Write-Host "Quick commands:" -ForegroundColor Cyan
        Write-Host "  Create 4GB RAM disk:  imdisk -a -s 4G -m R: -o awe -p '/fs:ntfs /q /y'" -ForegroundColor White
        Write-Host "  List devices:         imdisk -l" -ForegroundColor White
        Write-Host "  Remove device:        imdisk -D -m R:" -ForegroundColor White
        Write-Host ""
    }
}
catch {
    Write-Status "Error: $($_.Exception.Message)" -Level ERROR
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
#endregion
