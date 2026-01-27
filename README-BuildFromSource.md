# Building ImDisk from Source

This guide explains how to build ImDisk from source for internal use.

## Overview

Instead of downloading pre-compiled binaries, you can build ImDisk from source and use it locally. This allows for:
- **Security**: Review source code for malicious code before compilation
- **Code Signing**: Automatically sign binaries with FkSign (Azure Trusted Signing) after build
- Custom modifications and forks
- Internal distribution without external dependencies
- Version control of your specific build
- Subprojects and extensions

## Quick Start

```powershell
# Build ImDisk from source
.\Build-ImDiskFromSource.ps1

# Install the local build
cd C:\opt\src\imdisk\install
.\Install-LocalImDisk.ps1

# Verify installation
imdisk -l
```

## Directory Structure

After building, you'll have:

```
C:\opt\src\imdisk\
├── ImDisk\              # Source code (cloned from GitHub)
├── build\               # Build output
│   ├── cli\            # Command-line tools
│   └── gui\            # GUI applications
├── install\             # Installed binaries
│   ├── bin\            # Executables (imdisk.exe)
│   └── Install-LocalImDisk.ps1
└── subprojects\         # Your custom projects/extensions
```

## Prerequisites

### Required
- **Git** - For cloning the repository
- **Visual Studio** or **Visual Studio Build Tools** - For building C#/.NET projects
- **.NET Framework SDK** - For GUI applications
- **FkSign module** - For code signing (automatically available in GlobalFunctions)

### Optional (for driver)
- **Windows Driver Kit (WDK)** - Only needed if building the kernel driver
- **Visual Studio** with C++ workload - For driver compilation

## Building

### Basic Build (CLI Tools Only)

```powershell
.\Build-ImDiskFromSource.ps1 -BuildCli
```

### Full Build (CLI + GUI + Signing)

```powershell
.\Build-ImDiskFromSource.ps1 -BuildCli -BuildGui -SignBinaries
```

### Build Without Signing

```powershell
.\Build-ImDiskFromSource.ps1 -SignBinaries:$false
```

### Force Rebuild

```powershell
.\Build-ImDiskFromSource.ps1 -Force
```

### Custom Paths

```powershell
.\Build-ImDiskFromSource.ps1 `
    -SourcePath "C:\opt\src\imdisk" `
    -BuildPath "C:\opt\src\imdisk\build" `
    -InstallPath "C:\opt\src\imdisk\install"
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SourcePath` | `C:\opt\src\imdisk` | Where to clone source code |
| `-BuildPath` | `C:\opt\src\imdisk\build` | Where build output goes |
| `-InstallPath` | `C:\opt\src\imdisk\install` | Where binaries are installed |
| `-RepositoryUrl` | `https://github.com/LTRData/ImDisk.git` | Git repository URL |
| `-Branch` | `master` | Git branch/tag to checkout |
| `-Force` | `$false` | Force re-clone and rebuild |
| `-BuildDriver` | `$false` | Build kernel driver (requires WDK) |
| `-BuildCli` | `$true` | Build command-line tools |
| `-BuildGui` | `$true` | Build GUI applications |
| `-SignBinaries` | `$true` | Sign compiled binaries using FkSign after build |

## Using Local Build

After building, `New-RamDisk.ps1` will automatically detect and use the local build if it exists at:
```
C:\opt\src\imdisk\install\bin\imdisk.exe
```

The script checks for local build first, then falls back to system-installed version, then downloads if neither exists.

## Subprojects

You can add custom projects under `C:\opt\src\imdisk\subprojects\`:

```
C:\opt\src\imdisk\subprojects\
├── CustomRamDiskManager\    # Your custom PowerShell module
├── ImDiskExtensions\        # C# extensions
└── Documentation\           # Internal docs
```

## Forking and Modifications

To use a forked version:

```powershell
.\Build-ImDiskFromSource.ps1 `
    -RepositoryUrl "https://github.com/YourOrg/ImDisk.git" `
    -Branch "your-feature-branch"
```

## Troubleshooting

### MSBuild Not Found
Install Visual Studio Build Tools:
- Download from: https://visualstudio.microsoft.com/downloads/
- Select "Build Tools for Visual Studio"
- Install "Desktop development with C++" workload

### Git Not Found
Install Git for Windows:
- Download from: https://git-scm.com/download/win

### Driver Build Fails
The kernel driver requires Windows Driver Kit (WDK):
- Download from: https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk
- Requires Visual Studio with C++ workload

### Build Errors
1. Ensure all prerequisites are installed
2. Check Visual Studio version compatibility
3. Review build output for specific errors
4. Try cleaning and rebuilding: `-Force`

## Security Benefits

### Code Review
Building from source allows you to:
- Review all source code before compilation
- Check for malicious code or backdoors
- Understand exactly what the software does
- Audit changes in your fork

### Code Signing
After compilation, binaries are automatically signed using:
- **FkSign** (Azure Trusted Signing)
- Felleskjøpet's trusted certificate
- SHA256 signatures with timestamping

This ensures:
- Windows recognizes binaries as trusted
- No security warnings when executing
- Compliance with security policies
- Traceability of signed binaries

## Integration with New-RamDisk.ps1

The `New-RamDisk.ps1` script automatically:
1. Checks for local build at `C:\opt\src\imdisk\install\bin\imdisk.exe`
2. Adds it to PATH if found
3. Falls back to system installation if not found
4. Downloads installer only if neither exists

No changes needed to your existing scripts!

## Author

Geir Helge Starholm, www.dEdge.no
