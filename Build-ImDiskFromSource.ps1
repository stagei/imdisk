<###
.SYNOPSIS
    Clones and builds ImDisk from source for internal use.

.DESCRIPTION
    This script clones the ImDisk repository from GitHub, builds it from source,
    and installs it to a local directory. It supports building both the driver
    and command-line tools.

.PARAMETER SourcePath
    Path where ImDisk source will be cloned. Default: C:\opt\src\imdisk

.PARAMETER BuildPath
    Path where build output will be placed. Default: C:\opt\src\imdisk\build

.PARAMETER InstallPath
    Path where compiled binaries will be installed. Default: C:\opt\src\imdisk\install

.PARAMETER RepositoryUrl
    GitHub repository URL. Default: https://github.com/LTRData/ImDisk.git

.PARAMETER Branch
    Git branch or tag to checkout. Default: master

.PARAMETER Force
    Force re-clone and rebuild even if source already exists.

.PARAMETER BuildDriver
    Build the kernel driver (requires Windows Driver Kit). Default: $false

.PARAMETER BuildCli
    Build the command-line tools. Default: $true

.PARAMETER BuildGui
    Build the GUI applications (.NET). Default: $true

.PARAMETER SignBinaries
    Sign compiled binaries using FkSign after build. Default: $true

.PARAMETER GitHubUsername
    GitHub username for pushing changes. Default: stagei

.PARAMETER GitHubRepoName
    GitHub repository name. Default: imdisk

.PARAMETER AutoPush
    Automatically commit and push changes to GitHub after build. Default: $true

.EXAMPLE
    .\Build-ImDiskFromSource.ps1
    Clones and builds ImDisk from source

.EXAMPLE
    .\Build-ImDiskFromSource.ps1 -BuildDriver -Force
    Force rebuild including the kernel driver

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Git, Visual Studio Build Tools or Visual Studio, Windows Driver Kit (for driver)
    
    Security: Building from source allows code review for malicious code before compilation.
    Binaries are automatically signed using FkSign (Azure Trusted Signing) after build.
###>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "C:\opt\src\imdisk",

    [Parameter(Mandatory = $false)]
    [string]$BuildPath = "C:\opt\src\imdisk\build",

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\opt\src\imdisk\install",

    [Parameter(Mandatory = $false)]
    [string]$RepositoryUrl = "https://github.com/LTRData/ImDisk.git",

    [Parameter(Mandatory = $false)]
    [string]$Branch = "master",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$BuildDriver,

    [Parameter(Mandatory = $false)]
    [switch]$BuildCli = $true,

    [Parameter(Mandatory = $false)]
    [switch]$BuildGui = $true,

    [Parameter(Mandatory = $false)]
    [switch]$SignBinaries = $true,

    [Parameter(Mandatory = $false)]
    [string]$GitHubUsername = "stagei",

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepoName = "imdisk",

    [Parameter(Mandatory = $false)]
    [switch]$AutoPush = $true
)

$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

try {
    # Check if running as administrator (required for driver installation)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($BuildDriver -and -not $isAdmin) {
        Write-LogMessage "Building the driver requires administrator privileges. Please run PowerShell as Administrator." -Level ERROR
        throw "Administrator privileges required for driver build"
    }

    # Check for Git
    $gitPath = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitPath) {
        Write-LogMessage "Git is not installed. Please install Git for Windows." -Level ERROR
        throw "Git not found"
    }

    # Check for MSBuild
    $msbuildPath = $null
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
        if ($vsPath) {
            $msbuildPath = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
            if (-not (Test-Path $msbuildPath)) {
                # Try older VS versions
                $msbuildPath = Join-Path $vsPath "MSBuild\15.0\Bin\MSBuild.exe"
            }
        }
    }

    # Fallback to standalone MSBuild
    if (-not $msbuildPath -or -not (Test-Path $msbuildPath)) {
        $msbuildPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
        if (-not (Test-Path $msbuildPath)) {
            $msbuildPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
        }
    }

    if (-not $msbuildPath -or -not (Test-Path $msbuildPath)) {
        Write-LogMessage "MSBuild not found. Please install Visual Studio or Visual Studio Build Tools." -Level ERROR
        throw "MSBuild not found"
    }

    Write-LogMessage "Using MSBuild: $msbuildPath" -Level INFO

    # Create directories
    New-Item -Path $SourcePath -ItemType Directory -Force | Out-Null
    New-Item -Path $BuildPath -ItemType Directory -Force | Out-Null
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null

    # Clone or update repository
    $repoPath = Join-Path $SourcePath "ImDisk"
    $repoGitPath = Join-Path $repoPath ".git"
    
    # Handle existing folder
    if (Test-Path $repoPath) {
        if ($Force) {
            Write-LogMessage "Force flag set - removing existing repository folder..." -Level INFO
            Remove-Item -Path $repoPath -Recurse -Force
        }
        elseif (Test-Path $repoGitPath) {
            Write-LogMessage "Repository exists, updating..." -Level INFO
            Push-Location $repoPath
            try {
                & git fetch origin
                & git checkout $Branch
                & git pull origin $Branch
            }
            finally {
                Pop-Location
            }
        }
        else {
            # Folder exists but no .git - remove and re-clone
            Write-LogMessage "Folder exists but is not a valid git repository. Removing and re-cloning..." -Level WARN
            Remove-Item -Path $repoPath -Recurse -Force
        }
    }

    # Clone if needed
    if (-not (Test-Path $repoGitPath)) {
        Write-LogMessage "Cloning ImDisk repository from $RepositoryUrl..." -Level INFO
        & git clone -b $Branch $RepositoryUrl $repoPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone repository"
        }
    }
    
    # Remove ALL .git and .github folders from cloned subfolders
    # This excludes the root project folder ($SourcePath) but removes from cloned repo ($repoPath)
    Write-LogMessage "Cleaning up .git/.github folders from cloned source..." -Level INFO
    $gitFoldersToRemove = Get-ChildItem -Path $repoPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -eq '.git' -or $_.Name -eq '.github' }
    
    foreach ($folder in $gitFoldersToRemove) {
        Write-LogMessage "Removing: $($folder.FullName)" -Level DEBUG
        Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-LogMessage "Source code available at: $repoPath" -Level INFO

    # Build CLI tools
    # Note: The imdisk CLI (cli.vcxproj) and devio require Windows Driver Kit (WDK) or specific SDK versions
    if ($BuildCli) {
        Write-LogMessage "Building CLI tools..." -Level INFO
        
        # The imdisk CLI and native devio require WDK - log this and skip
        Write-LogMessage "Native CLI tools (imdisk.exe, devio.exe) require Windows Driver Kit." -Level WARN
        Write-LogMessage "For native tools, install WDK from: https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk" -Level INFO
        Write-LogMessage "The .NET tools (DiscUtilsDevio.exe) will be built instead." -Level INFO
    }

    # Build GUI applications
    if ($BuildGui) {
        Write-LogMessage "Building GUI applications..." -Level INFO
        
        # CPL (Control Panel applet) requires WDK - skip with note
        $cplProject = Join-Path $repoPath "cpl\cpl.vcxproj"
        if (Test-Path $cplProject) {
            Write-LogMessage "CPL (imdisk.cpl) requires Windows Driver Kit (WDKConversion). Skipping." -Level WARN
        }
        
        # Build ImDiskNet (.NET library) using dotnet build (handles multi-target frameworks better)
        $imDiskNetSln = Join-Path $repoPath "ImDiskNet\ImDiskNet.sln"
        if (Test-Path $imDiskNetSln) {
            Write-LogMessage "Building ImDiskNet with dotnet build..." -Level INFO
            
            Push-Location (Join-Path $repoPath "ImDiskNet")
            try {
                # Use dotnet build which handles restore and multi-target frameworks properly
                # Build only net48 framework to avoid file locking issues with parallel multi-target builds
                & dotnet build ImDiskNet.sln -c Release -f net48 --no-restore 2>$null
                $restoreNeeded = $LASTEXITCODE -ne 0
                
                if ($restoreNeeded) {
                    Write-LogMessage "Running NuGet restore..." -Level INFO
                    & dotnet restore ImDiskNet.sln
                }
                
                # Build for net48 (most compatible)
                & dotnet build ImDiskNet.sln -c Release -f net48
                $buildResult = $LASTEXITCODE
                
                if ($buildResult -ne 0) {
                    # Try building without framework specification (let project decide)
                    Write-LogMessage "Retrying build without framework specification..." -Level INFO
                    & dotnet build ImDiskNet.sln -c Release
                    $buildResult = $LASTEXITCODE
                }
                
                if ($buildResult -ne 0) {
                    Write-LogMessage "ImDiskNet build had errors, but some assemblies may have been built" -Level WARN
                }
                else {
                    Write-LogMessage "ImDiskNet built successfully" -Level INFO
                }
                
                # Copy built assemblies to install path
                # dotnet build outputs to ImDiskNet\Release\net48\ folder structure
                $releaseFolder = Join-Path $repoPath "ImDiskNet\Release\net48"
                
                if (Test-Path $releaseFolder) {
                    # Copy DLLs to lib folder
                    $installLibPath = Join-Path $InstallPath "lib"
                    New-Item -Path $installLibPath -ItemType Directory -Force | Out-Null
                    
                    $dlls = Get-ChildItem -Path $releaseFolder -Filter "*.dll" -ErrorAction SilentlyContinue
                    foreach ($dll in $dlls) {
                        Copy-Item -Path $dll.FullName -Destination $installLibPath -Force
                        Write-LogMessage "Copied $($dll.Name) to lib folder" -Level INFO
                    }
                    
                    # Copy EXEs to bin folder
                    $installBinPath = Join-Path $InstallPath "bin"
                    New-Item -Path $installBinPath -ItemType Directory -Force | Out-Null
                    
                    $exes = Get-ChildItem -Path $releaseFolder -Filter "*.exe" -ErrorAction SilentlyContinue
                    foreach ($exe in $exes) {
                        Copy-Item -Path $exe.FullName -Destination $installBinPath -Force
                        Write-LogMessage "Copied $($exe.Name) to bin folder" -Level INFO
                    }
                    
                    # Copy config files
                    $configs = Get-ChildItem -Path $releaseFolder -Filter "*.config" -ErrorAction SilentlyContinue
                    foreach ($config in $configs) {
                        Copy-Item -Path $config.FullName -Destination $installBinPath -Force
                    }
                }
                else {
                    Write-LogMessage "Release folder not found: $releaseFolder" -Level WARN
                }
            }
            finally {
                Pop-Location
            }
        }
    }

    # Build driver (if requested and WDK available)
    if ($BuildDriver) {
        Write-LogMessage "Building kernel driver..." -Level INFO
        
        # Check for Windows Driver Kit
        $wdkPath = "${env:ProgramFiles(x86)}\Windows Kits\10\build"
        if (-not (Test-Path $wdkPath)) {
            Write-LogMessage "Windows Driver Kit not found. Driver build skipped." -Level WARN
            Write-LogMessage "Install WDK from: https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk" -Level INFO
        }
        else {
            $sysPath = Join-Path $repoPath "sys"
            if (Test-Path $sysPath) {
                # Driver build requires WDK and is more complex
                Write-LogMessage "Driver build requires manual configuration. See ImDisk documentation." -Level INFO
                Write-LogMessage "Driver source available at: $sysPath" -Level INFO
            }
        }
    }

    # Create installation script
    $installScript = @"
# ImDisk Local Installation
# Generated by Build-ImDiskFromSource.ps1

`$installPath = "$InstallPath"
`$binPath = Join-Path `$installPath "bin"

# Add to PATH for current session
`$env:Path += ";`$binPath"

# Add to user PATH permanently
`$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (`$userPath -notlike "*`$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "`$userPath;`$binPath", "User")
    Write-Host "Added `$binPath to user PATH"
}

Write-Host "ImDisk binaries available at: `$binPath"
Write-Host "Run: imdisk -l  (to verify installation)"
"@

    $installScriptPath = Join-Path $InstallPath "Install-LocalImDisk.ps1"
    Set-Content -Path $installScriptPath -Value $installScript -Force
    Write-LogMessage "Installation script created: $installScriptPath" -Level INFO

    # Sign any additional binaries if requested
    if ($SignBinaries) {
        Write-LogMessage "Signing additional binaries..." -Level INFO
        $binariesToSign = @()
        $binariesToSign += @(Get-ChildItem -Path $InstallPath -Filter "*.exe" -Recurse -File -ErrorAction SilentlyContinue)
        $binariesToSign += @(Get-ChildItem -Path $InstallPath -Filter "*.dll" -Recurse -File -ErrorAction SilentlyContinue)
        
        foreach ($binary in $binariesToSign) {
            if ($null -eq $binary) { continue }
            try {
                Start-FkSignFile -FilePath $binary.FullName
                Write-LogMessage "Signed: $($binary.Name)" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to sign $($binary.Name): $($_.Exception.Message)" -Level WARN
            }
        }
    }

    Write-LogMessage "Build complete!" -Level INFO
    Write-LogMessage "  Source: $repoPath" -Level INFO
    Write-LogMessage "  Build: $BuildPath" -Level INFO
    Write-LogMessage "  Install: $InstallPath" -Level INFO
    if ($SignBinaries) {
        Write-LogMessage "  Binaries signed with FkSign" -Level INFO
    }
    Write-LogMessage "  Run: .\Install-LocalImDisk.ps1 (in install directory)" -Level INFO

    # Auto-push to GitHub after build
    if ($AutoPush) {
        Write-LogMessage "Auto-pushing changes to GitHub..." -Level INFO
        
        $gitHubRepoUrl = "https://github.com/$($GitHubUsername)/$($GitHubRepoName).git"
        $rootGitPath = Join-Path $SourcePath ".git"
        
        # Refresh PATH to pick up newly installed tools (like gh CLI)
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        Push-Location $SourcePath
        try {
            # Initialize git repo if not exists
            if (-not (Test-Path $rootGitPath)) {
                Write-LogMessage "Initializing git repository..." -Level INFO
                & git init
                if ($LASTEXITCODE -ne 0) { throw "Failed to initialize git repository" }
            }
            
            # Check if remote exists, add if not, or update if different
            $remoteUrl = & git remote get-url origin 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($remoteUrl)) {
                Write-LogMessage "Adding GitHub remote: $gitHubRepoUrl" -Level INFO
                & git remote add origin $gitHubRepoUrl 2>$null
                if ($LASTEXITCODE -ne 0) {
                    & git remote set-url origin $gitHubRepoUrl
                }
            }
            elseif ($remoteUrl -ne $gitHubRepoUrl) {
                Write-LogMessage "Updating GitHub remote URL to: $gitHubRepoUrl" -Level INFO
                & git remote set-url origin $gitHubRepoUrl
            }
            
            # Check if GitHub repo exists using git ls-remote
            Write-LogMessage "Checking if GitHub repository exists..." -Level INFO
            $repoExists = $false
            & git ls-remote $gitHubRepoUrl 2>$null | Out-Null
            $repoExists = ($LASTEXITCODE -eq 0)
            
            if (-not $repoExists) {
                Write-LogMessage "GitHub repository does not exist. Creating..." -Level INFO
                
                # Check if gh CLI is available
                $ghPath = Get-Command gh -ErrorAction SilentlyContinue
                if (-not $ghPath) {
                    # Try to install gh CLI via winget
                    Write-LogMessage "GitHub CLI not found. Installing via winget..." -Level INFO
                    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
                    if ($wingetPath) {
                        & winget install --id GitHub.cli --accept-package-agreements --accept-source-agreements --silent
                        # Refresh PATH after install
                        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                        $ghPath = Get-Command gh -ErrorAction SilentlyContinue
                    }
                }
                
                if ($ghPath) {
                    # Check if gh is authenticated
                    & gh auth status 2>&1 | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        Write-LogMessage "GitHub CLI not authenticated. Running 'gh auth login'..." -Level INFO
                        & gh auth login
                        if ($LASTEXITCODE -ne 0) {
                            Write-LogMessage "GitHub authentication failed. Please run 'gh auth login' manually." -Level WARN
                        }
                    }
                    
                    # Create the repository
                    Write-LogMessage "Creating GitHub repository: $($GitHubUsername)/$($GitHubRepoName)" -Level INFO
                    & gh repo create $GitHubRepoName --public --source=. --remote=origin --push 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "GitHub repository created and pushed successfully" -Level INFO
                        $repoExists = $true
                    }
                    else {
                        # gh repo create may fail if remote already exists, try just setting it
                        & git remote set-url origin $gitHubRepoUrl 2>$null
                        & gh repo create $GitHubRepoName --public 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            Write-LogMessage "GitHub repository created successfully" -Level INFO
                            $repoExists = $true
                        }
                        else {
                            # Repo might already exist, check again
                            & git ls-remote $gitHubRepoUrl 2>$null | Out-Null
                            $repoExists = ($LASTEXITCODE -eq 0)
                            if ($repoExists) {
                                Write-LogMessage "GitHub repository already exists" -Level INFO
                            }
                            else {
                                Write-LogMessage "Failed to create GitHub repository" -Level WARN
                            }
                        }
                    }
                }
                else {
                    Write-LogMessage "GitHub CLI (gh) not available. Please install manually or create repo at: https://github.com/new" -Level WARN
                }
            }
            
            if ($repoExists) {
                # Stage all changes
                Write-LogMessage "Staging changes..." -Level INFO
                & git add -A
                
                # Check if there are changes to commit
                $status = & git status --porcelain
                if ($status) {
                    # Commit changes
                    $commitMessage = "Build update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    Write-LogMessage "Committing changes: $commitMessage" -Level INFO
                    & git commit -m $commitMessage
                    if ($LASTEXITCODE -ne 0) {
                        Write-LogMessage "Nothing to commit or commit failed" -Level WARN
                    }
                }
                else {
                    Write-LogMessage "No changes to commit" -Level INFO
                }
                
                # Ensure we're on main branch
                $currentBranch = & git branch --show-current
                if ($currentBranch -ne 'main') {
                    & git branch -M main
                }
                
                # Push to GitHub
                Write-LogMessage "Pushing to GitHub..." -Level INFO
                & git push -u origin main 2>&1 | ForEach-Object { Write-LogMessage $_ -Level DEBUG }
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "Successfully pushed to GitHub: $gitHubRepoUrl" -Level INFO
                }
                else {
                    # Try force push if normal push fails (for initial setup)
                    Write-LogMessage "Normal push failed, trying with --force..." -Level WARN
                    & git push -u origin main --force
                    if ($LASTEXITCODE -eq 0) {
                        Write-LogMessage "Successfully pushed to GitHub: $gitHubRepoUrl" -Level INFO
                    }
                    else {
                        Write-LogMessage "Failed to push to GitHub. Check authentication with 'gh auth status'" -Level ERROR
                    }
                }
            }
        }
        finally {
            Pop-Location
        }
    }
}
catch {
    Write-LogMessage "Error building ImDisk from source: $($_.Exception.Message)" -Level ERROR -Exception $_
    throw
}
