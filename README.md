# ImDisk Build System

A PowerShell-based build system that clones, builds, signs, and deploys ImDisk from source with automatic GitHub synchronization.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Build-ImDiskFromSource.ps1                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. CLONE              2. CLEAN              3. BUILD                       │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │ LTRData/     │ ──▶ │ Remove .git  │ ──▶ │ dotnet build │                │
│  │ ImDisk       │     │ .github      │     │ net48        │                │
│  └──────────────┘     └──────────────┘     └──────────────┘                │
│         │                                          │                        │
│         ▼                                          ▼                        │
│  4. SIGN               5. DEPLOY             6. PUSH                        │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                │
│  │ FkSign       │ ──▶ │ install/     │ ──▶ │ GitHub       │                │
│  │ Azure TSS    │     │ bin/ lib/    │     │ stagei/imdisk│                │
│  └──────────────┘     └──────────────┘     └──────────────┘                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
C:\opt\src\imdisk\
├── .cursorrules                    # AI rules for clean-room development
├── .git/                           # YOUR repository (stagei/imdisk)
├── .gitignore
├── Build-ImDiskFromSource.ps1      # Main build script
├── LEGAL-NOTICE.md                 # GPL-2.0 licensing guidance
├── README.md                       # This file
├── README-BuildFromSource.md       # Original build documentation
│
├── ImDisk/                         # CLONED from LTRData (no .git)
│   ├── cli/                        # Native CLI (requires WDK)
│   ├── cpl/                        # Control Panel applet (requires WDK)
│   ├── devio/                      # Device I/O library
│   ├── ImDiskNet/                  # .NET libraries (what we build)
│   │   ├── DevioNet/               # .NET device I/O
│   │   ├── ImDiskNet/              # .NET ImDisk API
│   │   └── DiscUtilsDevio/         # Disk utilities tool
│   ├── sys/                        # Kernel driver (requires WDK)
│   └── svc/                        # Windows service
│
├── build/                          # Build artifacts
│   ├── cli/
│   └── gui/
│
└── install/                        # DEPLOYED binaries (signed)
    ├── bin/
    │   └── DiscUtilsDevio.exe      # Main tool
    ├── lib/
    │   ├── DevioNet.dll
    │   ├── ImDiskNet.dll
    │   ├── DiscUtils.*.dll         # VHD/VHDX/VMDK support
    │   └── ...                     # 21 DLLs total
    └── Install-LocalImDisk.ps1     # PATH setup script
```

## How It Works

### Phase 1: Clone

```powershell
# Clones from upstream (LTRData/ImDisk)
git clone -b master https://github.com/LTRData/ImDisk.git C:\opt\src\imdisk\ImDisk
```

- Downloads the latest ImDisk source code
- Checks out specified branch (default: `master`)
- Handles existing folders (update or force re-clone)

### Phase 2: Clean

```powershell
# Remove all .git and .github folders from cloned source
Get-ChildItem -Path $repoPath -Directory -Recurse -Force | 
    Where-Object { $_.Name -eq '.git' -or $_.Name -eq '.github' } |
    Remove-Item -Recurse -Force
```

- Removes nested `.git` folders from cloned repo
- Preserves YOUR repository at root level
- Ensures clean source for building

### Phase 3: Build

```powershell
# Build .NET components
dotnet restore ImDiskNet.sln
dotnet build ImDiskNet.sln -c Release -f net48
```

**What Gets Built:**

| Component | Output | Description |
|-----------|--------|-------------|
| ImDiskNet | `ImDiskNet.dll` | .NET API for ImDisk operations |
| DevioNet | `DevioNet.dll` | .NET device I/O library |
| DiscUtilsDevio | `DiscUtilsDevio.exe` | Command-line disk image tool |

**What Requires WDK (Not Built):**

| Component | Why Skipped |
|-----------|-------------|
| imdisk.exe | Requires Windows Driver Kit |
| imdisk.sys | Kernel driver - requires WDK + signing |
| imdisk.cpl | Control Panel applet - requires WDK |

### Phase 4: Sign

```powershell
# Sign all binaries with Azure Trusted Signing
foreach ($binary in $binariesToSign) {
    Start-FkSignFile -FilePath $binary.FullName
}
```

- Uses FkSign module (Azure Trusted Signing)
- Signs all `.exe` and `.dll` files
- Produces production-ready signed binaries

### Phase 5: Deploy

Files are copied to the `install/` folder:

```
install/
├── bin/                    # Executables
│   ├── DiscUtilsDevio.exe  # Main tool (34 KB, signed)
│   └── *.config            # Configuration files
└── lib/                    # Libraries
    ├── DevioNet.dll        # Device I/O
    ├── ImDiskNet.dll       # ImDisk API
    ├── DiscUtils.*.dll     # Format support (VHD, VHDX, VMDK, etc.)
    └── System.*.dll        # .NET dependencies
```

### Phase 6: GitHub Push

```powershell
# Auto-commit and push after build
git add -A
git commit -m "Build update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
git push -u origin main
```

- Automatically stages all changes
- Commits with timestamp
- Pushes to your GitHub repository
- Creates repo if it doesn't exist (using `gh` CLI)

## Usage

### Basic Build

```powershell
.\Build-ImDiskFromSource.ps1
```

### Force Rebuild

```powershell
.\Build-ImDiskFromSource.ps1 -Force
```

### Skip Signing

```powershell
.\Build-ImDiskFromSource.ps1 -SignBinaries:$false
```

### Skip GitHub Push

```powershell
.\Build-ImDiskFromSource.ps1 -AutoPush:$false
```

### All Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SourcePath` | `C:\opt\src\imdisk` | Where source is cloned |
| `-BuildPath` | `C:\opt\src\imdisk\build` | Build output location |
| `-InstallPath` | `C:\opt\src\imdisk\install` | Final binaries location |
| `-RepositoryUrl` | `https://github.com/LTRData/ImDisk.git` | Upstream repo |
| `-Branch` | `master` | Git branch to build |
| `-Force` | `$false` | Force re-clone |
| `-BuildDriver` | `$false` | Build kernel driver (needs WDK) |
| `-BuildCli` | `$true` | Build CLI tools |
| `-BuildGui` | `$true` | Build GUI/.NET tools |
| `-SignBinaries` | `$true` | Sign with FkSign |
| `-GitHubUsername` | `stagei` | Your GitHub username |
| `-GitHubRepoName` | `imdisk` | Your repo name |
| `-AutoPush` | `$true` | Auto-push to GitHub |

## Built Binaries

### DiscUtilsDevio.exe

A command-line tool for working with disk images:

```powershell
# Mount a VHD file
DiscUtilsDevio.exe --mount C:\Images\disk.vhd

# List supported formats
DiscUtilsDevio.exe --help
```

**Supported Formats:**
- VHD (Virtual Hard Disk)
- VHDX (Hyper-V format)
- VMDK (VMware)
- VDI (VirtualBox)
- DMG (Apple Disk Image)
- XVA (Citrix XenServer)

### Library DLLs

| DLL | Purpose |
|-----|---------|
| `ImDiskNet.dll` | .NET wrapper for ImDisk API |
| `DevioNet.dll` | Device I/O operations |
| `DiscUtils.Core.dll` | Core disk utilities |
| `DiscUtils.Vhd.dll` | VHD format support |
| `DiscUtils.Vhdx.dll` | VHDX format support |
| `DiscUtils.Vmdk.dll` | VMDK format support |
| `DiscUtils.Vdi.dll` | VDI format support |
| `DiscUtils.Dmg.dll` | DMG format support |
| `DiscUtils.Xva.dll` | XVA format support |

## Requirements

### Required

- **Git** - For cloning source
- **Visual Studio** or **Build Tools** - MSBuild
- **.NET SDK** - For building .NET components
- **PowerShell 7+** - Script execution

### Optional

- **Windows Driver Kit (WDK)** - For kernel driver/native tools
- **FkSign module** - For code signing
- **GitHub CLI (gh)** - For auto repo creation

## Workflow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        User runs script                          │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Check Prerequisites                          │
│                   (Git, MSBuild, Admin?)                         │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Clone/Update ImDisk                           │
│               github.com/LTRData/ImDisk                          │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                  Remove .git/.github folders                     │
│              (Keep YOUR repo, remove cloned repo's)              │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                    dotnet restore + build                        │
│                  ImDiskNet.sln (net48)                           │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Copy to install/bin and install/lib              │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Sign binaries (FkSign)                        │
│                   Azure Trusted Signing                          │
└─────────────────────────────────┬────────────────────────────────┘
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                   git add + commit + push                        │
│               github.com/stagei/imdisk                           │
└──────────────────────────────────────────────────────────────────┘
```

## Future Development

This repository includes `.cursorrules` for clean-room implementation of a new virtual disk tool. See `LEGAL-NOTICE.md` for licensing considerations.

## Links

- **Your Repository**: https://github.com/stagei/imdisk
- **Upstream Source**: https://github.com/LTRData/ImDisk
- **License**: GPL-2.0 (upstream), see `LEGAL-NOTICE.md`

---

*Last updated: January 27, 2026*
