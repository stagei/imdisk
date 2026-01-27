<#
.SYNOPSIS
    Security verification script for ImDisk source code and binaries.

.DESCRIPTION
    Performs automated security checks on the ImDisk codebase to detect
    potentially malicious code patterns, verify signatures, and validate
    the build process.

.EXAMPLE
    .\Verify-Security.ps1
    Runs all security checks and outputs a report.

.EXAMPLE
    .\Verify-Security.ps1 -OutputFile "security-report.txt"
    Runs checks and saves report to file.

.NOTES
    Author: Security Verification Automation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath = (Join-Path $PSScriptRoot "ImDisk"),

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = (Join-Path $PSScriptRoot "install"),

    [Parameter(Mandatory = $false)]
    [string]$OutputFile
)

$ErrorActionPreference = 'Continue'
$script:PassCount = 0
$script:FailCount = 0
$script:WarnCount = 0
$script:Results = @()

#region Helper Functions
function Write-Check {
    param(
        [string]$Name,
        [string]$Status,  # PASS, FAIL, WARN, INFO
        [string]$Details
    )
    
    $colors = @{
        PASS = "Green"
        FAIL = "Red"
        WARN = "Yellow"
        INFO = "Cyan"
    }
    
    $symbols = @{
        PASS = "[✓]"
        FAIL = "[✗]"
        WARN = "[!]"
        INFO = "[i]"
    }
    
    switch ($Status) {
        "PASS" { $script:PassCount++ }
        "FAIL" { $script:FailCount++ }
        "WARN" { $script:WarnCount++ }
    }
    
    $script:Results += [PSCustomObject]@{
        Check = $Name
        Status = $Status
        Details = $Details
    }
    
    Write-Host "$($symbols[$Status]) " -NoNewline -ForegroundColor $colors[$Status]
    Write-Host "$Name" -NoNewline
    if ($Details) {
        Write-Host " - " -NoNewline -ForegroundColor Gray
        Write-Host $Details -ForegroundColor $colors[$Status]
    }
    else {
        Write-Host ""
    }
}

function Search-Pattern {
    param(
        [string]$Path,
        [string]$Pattern,
        [string[]]$Include = @("*.c", "*.cpp", "*.h", "*.hpp", "*.cs", "*.vb")
    )
    
    $results = @()
    foreach ($ext in $Include) {
        $files = Get-ChildItem -Path $Path -Filter $ext -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $matches = Select-String -Path $file.FullName -Pattern $Pattern -ErrorAction SilentlyContinue
            if ($matches) {
                $results += $matches
            }
        }
    }
    return $results
}
#endregion

#region Main Script
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       ImDisk Security Verification Script                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source Path:  $SourcePath" -ForegroundColor Gray
Write-Host "Install Path: $InstallPath" -ForegroundColor Gray
Write-Host "Scan Time:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Section 1: Source Origin Verification
# ============================================================================
Write-Host "─── Source Origin ───────────────────────────────────────────" -ForegroundColor White

# Check git remote
$gitDir = Join-Path $PSScriptRoot ".git"
if (Test-Path $gitDir) {
    Push-Location $PSScriptRoot
    $remoteUrl = & git remote get-url origin 2>$null
    Pop-Location
    
    if ($remoteUrl -match "github\.com[:/]stagei/imdisk") {
        Write-Check "Git remote configured" "PASS" "stagei/imdisk"
    }
    elseif ($remoteUrl -match "github\.com[:/]LTRData/ImDisk") {
        Write-Check "Git remote configured" "PASS" "Official LTRData/ImDisk"
    }
    else {
        Write-Check "Git remote configured" "WARN" $remoteUrl
    }
}
else {
    Write-Check "Git repository" "WARN" "Not a git repository"
}

# Check if source exists
if (Test-Path $SourcePath) {
    Write-Check "Source code present" "PASS" $SourcePath
}
else {
    Write-Check "Source code present" "FAIL" "Not found: $SourcePath"
}

# ============================================================================
# Section 2: Suspicious Pattern Detection
# ============================================================================
Write-Host ""
Write-Host "─── Malicious Pattern Scan ──────────────────────────────────" -ForegroundColor White

if (Test-Path $SourcePath) {
    # Process injection patterns
    $injection = Search-Pattern -Path $SourcePath -Pattern "CreateRemoteThread|VirtualAllocEx|WriteProcessMemory|NtCreateThreadEx"
    if ($injection.Count -eq 0) {
        Write-Check "Process injection code" "PASS" "None found"
    }
    else {
        Write-Check "Process injection code" "FAIL" "$($injection.Count) matches found"
        $injection | ForEach-Object { Write-Host "       $($_.Path):$($_.LineNumber)" -ForegroundColor Red }
    }

    # Suspicious network patterns (excluding expected proxy code)
    $network = Search-Pattern -Path $SourcePath -Pattern "UrlDownloadToFile|InternetOpen[^(]*\(|WinHttpOpen"
    if ($network.Count -eq 0) {
        Write-Check "Suspicious network downloads" "PASS" "None found"
    }
    else {
        Write-Check "Suspicious network downloads" "WARN" "$($network.Count) matches - review required"
    }

    # Command execution - focus on suspicious patterns, not general system() calls
    $exec = Search-Pattern -Path $SourcePath -Pattern "WinExec\s*\(|ShellExecute.*http|CreateProcess.*cmd\.exe"
    if ($exec.Count -eq 0) {
        Write-Check "Suspicious command execution" "PASS" "None found"
    }
    else {
        Write-Check "Suspicious command execution" "WARN" "$($exec.Count) matches - review required"
    }

    # Autorun registry
    $autorun = Search-Pattern -Path $SourcePath -Pattern "SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run"
    if ($autorun.Count -eq 0) {
        Write-Check "Autorun registry entries" "PASS" "None found"
    }
    else {
        Write-Check "Autorun registry entries" "FAIL" "$($autorun.Count) matches found"
    }

    # Crypto addresses (Bitcoin, Ethereum, Monero)
    $crypto = Search-Pattern -Path $SourcePath -Pattern "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$|^0x[a-fA-F0-9]{40}$|^4[0-9AB][1-9A-HJ-NP-Za-km-z]{93}$"
    if ($crypto.Count -eq 0) {
        Write-Check "Cryptocurrency addresses" "PASS" "None found"
    }
    else {
        Write-Check "Cryptocurrency addresses" "FAIL" "$($crypto.Count) matches found"
    }

    # Base64 blobs (potential hidden payloads)
    $base64 = Search-Pattern -Path $SourcePath -Pattern "[A-Za-z0-9+/]{100,}={0,2}"
    if ($base64.Count -eq 0) {
        Write-Check "Large Base64 encoded data" "PASS" "None found"
    }
    else {
        Write-Check "Large Base64 encoded data" "WARN" "$($base64.Count) matches - may be legitimate"
    }

    # Keylogger patterns - exclude legitimate UI key checks (VK_ constants = normal UI)
    $keylog = Search-Pattern -Path $SourcePath -Pattern "SetWindowsHookEx.*WH_KEYBOARD|GetAsyncKeyState\s*\([^V]"
    if ($keylog.Count -eq 0) {
        Write-Check "Keylogger patterns" "PASS" "None found"
    }
    else {
        Write-Check "Keylogger patterns" "WARN" "$($keylog.Count) matches - review required"
    }
    
    # Note: GetAsyncKeyState(VK_*) for UI shortcuts is legitimate and expected

    # Screen capture
    $screencap = Search-Pattern -Path $SourcePath -Pattern "BitBlt.*GetDesktopWindow|GetDC\(NULL\)"
    if ($screencap.Count -eq 0) {
        Write-Check "Screen capture code" "PASS" "None found"
    }
    else {
        Write-Check "Screen capture code" "WARN" "$($screencap.Count) matches - review required"
    }
}
else {
    Write-Check "Pattern scan" "FAIL" "Source path not found"
}

# ============================================================================
# Section 3: Binary Signature Verification
# ============================================================================
Write-Host ""
Write-Host "─── Binary Signature Verification ───────────────────────────" -ForegroundColor White

if (Test-Path $InstallPath) {
    $binaries = Get-ChildItem -Path $InstallPath -Include *.exe, *.dll -Recurse -ErrorAction SilentlyContinue
    
    if ($binaries.Count -gt 0) {
        $validCount = 0
        $invalidBinaries = @()
        
        foreach ($binary in $binaries) {
            $sig = Get-AuthenticodeSignature -FilePath $binary.FullName
            if ($sig.Status -eq 'Valid') {
                $validCount++
            }
            else {
                $invalidBinaries += $binary.Name
            }
        }
        
        if ($validCount -eq $binaries.Count) {
            Write-Check "All binaries signed" "PASS" "$validCount/$($binaries.Count) valid signatures"
        }
        elseif ($validCount -gt 0) {
            Write-Check "Binary signatures" "WARN" "$validCount/$($binaries.Count) valid - unsigned: $($invalidBinaries -join ', ')"
        }
        else {
            Write-Check "Binary signatures" "FAIL" "No valid signatures found"
        }
        
        # Check certificate issuer
        $firstSigned = $binaries | Where-Object { 
            (Get-AuthenticodeSignature $_.FullName).Status -eq 'Valid' 
        } | Select-Object -First 1
        
        if ($firstSigned) {
            $sig = Get-AuthenticodeSignature $firstSigned.FullName
            $issuer = $sig.SignerCertificate.Issuer
            if ($issuer -match "Microsoft") {
                Write-Check "Certificate issuer" "PASS" "Microsoft trusted chain"
            }
            else {
                Write-Check "Certificate issuer" "INFO" $issuer
            }
        }
    }
    else {
        Write-Check "Binaries found" "WARN" "No binaries in install path"
    }
}
else {
    Write-Check "Install path" "WARN" "Not found - run build first"
}

# ============================================================================
# Section 4: License Verification
# ============================================================================
Write-Host ""
Write-Host "─── License Verification ────────────────────────────────────" -ForegroundColor White

$licensePath = Join-Path $SourcePath "LICENSE.md"
if (Test-Path $licensePath) {
    $licenseContent = Get-Content $licensePath -Raw
    if ($licenseContent -match "MIT|Permission is hereby granted") {
        Write-Check "License file" "PASS" "MIT License detected"
    }
    else {
        Write-Check "License file" "INFO" "Non-MIT license - review required"
    }
}
else {
    Write-Check "License file" "WARN" "LICENSE.md not found"
}

$readmePath = Join-Path $SourcePath "README.md"
if (Test-Path $readmePath) {
    Write-Check "README present" "PASS" "Documentation available"
}
else {
    Write-Check "README present" "WARN" "No README found"
}

# ============================================================================
# Section 5: Network Behavior Check
# ============================================================================
Write-Host ""
Write-Host "─── Expected Network Code ───────────────────────────────────" -ForegroundColor White

if (Test-Path $SourcePath) {
    # Check proxy service code exists (expected)
    $svcPath = Join-Path $SourcePath "svc"
    if (Test-Path $svcPath) {
        Write-Check "Proxy service code" "INFO" "Present (expected for remote disk feature)"
    }
    
    # Check devio path
    $devioPath = Join-Path $SourcePath "devio"
    if (Test-Path $devioPath) {
        Write-Check "Device I/O library" "INFO" "Present (expected for disk I/O)"
    }
    
    # Verify network code is only in expected locations
    $tcpOutside = Get-ChildItem -Path $SourcePath -Include *.c, *.cpp -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notmatch "svc|devio" } |
        ForEach-Object { Select-String -Path $_.FullName -Pattern "socket\s*\(|connect\s*\(" -ErrorAction SilentlyContinue }
    
    if ($tcpOutside.Count -eq 0) {
        Write-Check "Network code isolation" "PASS" "Network code only in expected modules"
    }
    else {
        Write-Check "Network code isolation" "WARN" "Network code found outside svc/devio"
    }
}

# ============================================================================
# Section 6: File Integrity
# ============================================================================
Write-Host ""
Write-Host "─── File Integrity ──────────────────────────────────────────" -ForegroundColor White

# Check for hidden files/scripts
if (Test-Path $SourcePath) {
    $hiddenExe = Get-ChildItem -Path $SourcePath -Include *.exe, *.dll, *.scr, *.bat, *.cmd, *.ps1, *.vbs -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Attributes -match "Hidden" }
    
    if ($hiddenExe.Count -eq 0) {
        Write-Check "Hidden executables" "PASS" "None found"
    }
    else {
        Write-Check "Hidden executables" "FAIL" "$($hiddenExe.Count) hidden files found"
    }

    # Check for double extensions (e.g., file.exe.txt - common malware trick)
    # Exclude common legitimate patterns like .exe.config, .dll.config
    $doubleExt = Get-ChildItem -Path $SourcePath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { 
            $_.Name -match "\.(exe|dll|scr|bat|cmd|ps1|vbs)\.[^.]+$" -and
            $_.Name -notmatch "\.(exe|dll)\.config$" -and
            $_.Name -notmatch "\.h\.in$" -and
            $_.Name -notmatch "\.rc\.h$"
        }
    
    if ($doubleExt.Count -eq 0) {
        Write-Check "Double extensions" "PASS" "None found"
    }
    else {
        Write-Check "Double extensions" "WARN" "$($doubleExt.Count) files - review: $($doubleExt.Name -join ', ')"
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor White
Write-Host ""

$totalChecks = $script:PassCount + $script:FailCount + $script:WarnCount

if ($script:FailCount -eq 0) {
    Write-Host "  VERIFICATION RESULT: " -NoNewline
    Write-Host "PASSED" -ForegroundColor Green -NoNewline
    Write-Host " ✓" -ForegroundColor Green
}
else {
    Write-Host "  VERIFICATION RESULT: " -NoNewline
    Write-Host "FAILED" -ForegroundColor Red -NoNewline
    Write-Host " ✗" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Passed:   $($script:PassCount)" -ForegroundColor Green
Write-Host "  Warnings: $($script:WarnCount)" -ForegroundColor Yellow
Write-Host "  Failed:   $($script:FailCount)" -ForegroundColor Red
Write-Host "  Total:    $totalChecks checks" -ForegroundColor Gray
Write-Host ""

# Output to file if requested
if ($OutputFile) {
    $report = @"
ImDisk Security Verification Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: $SourcePath
Install: $InstallPath

SUMMARY
=======
Passed:   $($script:PassCount)
Warnings: $($script:WarnCount)
Failed:   $($script:FailCount)

DETAILS
=======
$($script:Results | Format-Table -AutoSize | Out-String)
"@
    $report | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "Report saved to: $OutputFile" -ForegroundColor Cyan
}

# Return exit code
if ($script:FailCount -gt 0) {
    exit 1
}
else {
    exit 0
}
#endregion
