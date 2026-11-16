# ===============================================================================
# Ray CLI Universal Windows Installer (PowerShell)
# Enterprise-grade support for Windows 10/11, Server, VS Code, and Cursor
# Safe for: irm https://secrets.rcmade.io/install.ps1 | iex
# Requires: Windows PowerShell 5.1+ or PowerShell 7+ (64-bit)
# ===============================================================================
$ErrorActionPreference = 'Stop'

$DocsUrl = 'https://secrets.rcmade.io'
$InstallCmd = 'irm https://secrets.rcmade.io/install.ps1 | iex'

# -----------------------------------------------------------------------------
# Host-safe failure control
# irm|iex runs in the caller's session: raw `exit` would close the terminal.
# powershell -File still returns a non-zero process exit code for automation.
# -----------------------------------------------------------------------------
$script:RayInstallExitCode = 0

function Stop-RayInstall {
    param([int]$Code = 1)
    $script:RayInstallExitCode = $Code
    throw '__RAY_INSTALL_STOP__'
}

function Test-RayInstallStop {
    param($ErrorRecord)
    return ($ErrorRecord.Exception.Message -eq '__RAY_INSTALL_STOP__')
}

function Complete-RayInstall {
    if ($script:RayInstallExitCode -eq 0) { return }
    $global:LASTEXITCODE = $script:RayInstallExitCode
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        exit $script:RayInstallExitCode
    }
}

# ASCII glyphs only: reliable under Windows PowerShell 5.1 + irm|iex
$SYM_ARROW = '>'
$SYM_CHECK = '+'
$SYM_WARN  = '!'
$SYM_CROSS = 'x'
$DIVIDER   = '==============================================='

function Write-RayBanner {
    Write-Host ''
    Write-Host '    Ray CLI Windows Installer' -ForegroundColor Cyan
    Write-Host "    $DIVIDER" -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-RayStep {
    param([string]$Message)
    Write-Host "$SYM_ARROW $Message" -ForegroundColor Cyan
}

function Write-RayOk {
    param([string]$Message)
    Write-Host "$SYM_CHECK $Message" -ForegroundColor Green
}

function Write-RayWarn {
    param([string]$Message)
    Write-Host "$SYM_WARN $Message" -ForegroundColor Yellow
}

function Write-RayFail {
    param([string]$Message)
    Write-Host "$SYM_CROSS $Message" -ForegroundColor Red
}

function Write-RayHint {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Read-RayTextFile {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return '' }
    $raw = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $raw) { return '' }
    return $raw.Trim()
}

function Test-RayPolicyBlockMessage {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    return [bool]($Message -match 'Application Control|AppLocker|blocked by policy|cannot be run due to the error|UnauthorizedAccess|Access is denied|SmartScreen')
}

function Show-AdminReinstallHelp {
    Write-Host ''
    Write-Host 'Fix: install into Program Files (allowed by most Windows policies)' -ForegroundColor White
    Write-Host '  1. Open PowerShell as Administrator (right-click > Run as administrator)' -ForegroundColor Gray
    Write-Host '  2. Run:' -ForegroundColor Gray
    Write-Host "       $InstallCmd" -ForegroundColor Cyan
    Write-Host ''
    Write-RayHint 'Program Files is allowed by most AppLocker / Application Control path rules.'
}

function Show-GenericFailureHelp {
    Write-Host ''
    Write-RayWarn 'Next steps:'
    Write-Host '  1. Open PowerShell as Administrator and run the same install command again' -ForegroundColor Gray
    Write-Host "  2. Docs: $DocsUrl" -ForegroundColor Gray
}

function Show-DownloadFailureHelp {
    param([string]$Url)
    Write-Host ''
    Write-RayWarn 'Download tips:'
    Write-Host '  - Check internet access / VPN' -ForegroundColor Gray
    Write-Host '  - If GitHub is blocked, ask IT to allow github.com or set RAY_RELEASE_URL to your mirror' -ForegroundColor Gray
    Write-Host "  - Failed URL: $Url" -ForegroundColor Gray
    Write-Host "  - Docs: $DocsUrl" -ForegroundColor Gray
}

function Expand-RayArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    # Prefer Expand-Archive when available (PS 5+)
    $expandCmd = Get-Command Expand-Archive -ErrorAction SilentlyContinue
    if ($expandCmd) {
        Expand-Archive -Path $ZipPath -DestinationPath $DestinationPath -Force
        return
    }

    # Fallback for locked-down / unusual hosts without the Archive module
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    } catch {
        throw 'This host cannot extract ZIP archives (Expand-Archive and System.IO.Compression unavailable). Install Windows PowerShell 5.1+ and retry.'
    }

    $extractDir = Join-Path $DestinationPath 'extract'
    if (Test-Path $extractDir) {
        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $extractDir)
}

function Get-RayWindowsArch {
    # Normalize CPU arch across native + WOW64 PowerShell hosts
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    if ([string]::IsNullOrWhiteSpace($arch)) {
        try {
            $arch = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).OSArchitecture
        } catch {}
    }
    if ($arch -match 'ARM64|aarch64') { return 'arm64' }
    if ($arch -match 'AMD64|x86_64|64') { return 'x64' }
    if ([Environment]::Is64BitOperatingSystem) { return 'x64' }
    return 'x86'
}

try {
    # TLS bootstrap (no execution-policy changes; irm|iex does not need them)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains 'Tls13') {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls13
        }
    } catch {}

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {}

    Write-RayBanner

    # 0) PowerShell baseline
    if (-not $PSVersionTable -or $PSVersionTable.PSVersion.Major -lt 5) {
        Write-RayFail 'Ray CLI installer requires Windows PowerShell 5.1 or newer.'
        Write-RayHint 'On older Windows, install Windows Management Framework 5.1, then retry.'
        Write-RayHint "Docs: $DocsUrl"
        Stop-RayInstall 1
    }

    # Constrained Language Mode blocks the .NET APIs this installer needs
    if ($ExecutionContext.SessionState.LanguageMode -and "$($ExecutionContext.SessionState.LanguageMode)" -ne 'FullLanguage') {
        Write-RayFail "PowerShell language mode is '$($ExecutionContext.SessionState.LanguageMode)' (too restricted)."
        Write-RayHint 'Ask IT to allow FullLanguage for interactive installs, or allowlist Ray after a manual binary install.'
        Write-RayHint "Docs: $DocsUrl"
        Stop-RayInstall 1
    }

    # 1) Architecture
    $cpuArch = Get-RayWindowsArch
    if ($cpuArch -eq 'x86') {
        Write-RayFail 'Ray CLI requires 64-bit Windows (x64 or ARM64).'
        Stop-RayInstall 1
    }

    $repoOwner = 'Rcmade'
    $repoName = 'ray'
    $version = if ($env:RAY_VERSION) { $env:RAY_VERSION } else { 'latest' }

    # Current public release artifact is the x64 zip. On Windows 11 ARM64 this runs via x64 emulation.
    $archiveName = 'ray-windows-x64.zip'
    $releaseBaseUrl = if ($env:RAY_RELEASE_URL) {
        $env:RAY_RELEASE_URL.TrimEnd('/')
    } elseif ($version -eq 'latest') {
        "https://github.com/$repoOwner/$repoName/releases/latest/download"
    } else {
        "https://github.com/$repoOwner/$repoName/releases/download/$version"
    }
    $downloadUrl = "$releaseBaseUrl/$archiveName"

    # 2) Privilege + install directory
    $isAdmin = $false
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}

    if ($env:RAY_INSTALL_DIR) {
        $installDir = $env:RAY_INSTALL_DIR.TrimEnd('\')
    } elseif ($isAdmin) {
        $pf = $env:ProgramFiles
        if (-not $pf) { $pf = 'C:\Program Files' }
        $installDir = (Join-Path $pf 'Ray\bin').TrimEnd('\')
    } else {
        $baseDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } elseif ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $null }
        if (-not $baseDir) {
            Write-RayFail 'Could not determine a writable user home directory for install.'
            Show-AdminReinstallHelp
            Stop-RayInstall 1
        }
        $installDir = (Join-Path $baseDir '.ray\bin').TrimEnd('\')
    }
    $exePath = Join-Path $installDir 'ray.exe'
    $cmdPath = Join-Path $installDir 'ray.cmd'

    $privilegeLabel = if ($isAdmin) { 'Administrator' } else { 'User' }
    $platformLabel = if ($cpuArch -eq 'arm64') { 'windows-arm64 (x64 binary via emulation)' } else { 'windows-x64' }
    Write-Host "  Platform:     $platformLabel" -ForegroundColor Gray
    Write-Host "  Privilege:    $privilegeLabel" -ForegroundColor Gray
    Write-Host "  PowerShell:   $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "  Version:      $version" -ForegroundColor Gray
    Write-Host "  Install dir:  $installDir" -ForegroundColor Gray
    Write-Host ''

    if ($cpuArch -eq 'arm64') {
        Write-RayWarn 'Windows on ARM detected: installing the x64 build (works via Windows emulation).'
        Write-Host ''
    }

    $tempRoot = [System.IO.Path]::GetTempPath()
    if (-not $tempRoot) {
        Write-RayFail 'Could not resolve TEMP directory.'
        Stop-RayInstall 1
    }
    $tempDir = Join-Path $tempRoot ([System.Guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    } catch {
        Write-RayFail "Cannot create temp directory: $tempDir"
        Write-RayHint $_.Exception.Message
        Stop-RayInstall 1
    }
    $tempZip = Join-Path $tempDir $archiveName

    try {
        # 3) Download
        Write-RayStep "Downloading Ray CLI ($archiveName)..."
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        $downloadSuccess = $false
        $downloadError = ''
        $curlCmd = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
        if ($curlCmd) {
            try {
                & curl.exe -sS -fL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 300 "$downloadUrl" -o "$tempZip"
                if ($LASTEXITCODE -eq 0 -and (Test-Path $tempZip) -and ((Get-Item $tempZip).Length -gt 1000)) {
                    $downloadSuccess = $true
                } else {
                    $downloadError = "curl exited with code $LASTEXITCODE"
                }
            } catch {
                $downloadError = $_.Exception.Message
            }
        }

        if (-not $downloadSuccess) {
            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
                if ((Test-Path $tempZip) -and ((Get-Item $tempZip).Length -gt 1000)) {
                    $downloadSuccess = $true
                } else {
                    throw "Downloaded file empty or missing from $downloadUrl"
                }
            } catch {
                $downloadError = $_.Exception.Message
            }
        }

        $ProgressPreference = $prevProgress

        if (-not $downloadSuccess) {
            Write-RayFail "Failed to download $archiveName"
            if ($downloadError) { Write-RayHint "Details: $downloadError" }
            Show-DownloadFailureHelp -Url $downloadUrl
            Stop-RayInstall 1
        }

        Write-RayOk 'Download complete'

        # 4) Extract + MOTW strip
        Write-RayStep 'Extracting and securing binary...'
        Unblock-File -Path $tempZip -ErrorAction SilentlyContinue
        Expand-RayArchive -ZipPath $tempZip -DestinationPath $tempDir
        Get-ChildItem -Path $tempDir -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

        $extractedExe = Get-ChildItem -Path $tempDir -Filter 'ray*.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '\.old$' } |
            Select-Object -First 1
        if (-not $extractedExe) {
            throw 'Could not find ray executable inside the downloaded archive.'
        }
        Write-RayOk 'Extraction complete'

        # 5) Replace in-use binary safely
        $runningProc = Get-Process -Name 'ray' -ErrorAction SilentlyContinue
        if ($runningProc) {
            Write-RayWarn "Stopping active 'ray' process to allow update..."
            $runningProc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 400
        }

        try {
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        } catch {
            Write-RayFail "Cannot write install directory: $installDir"
            Write-RayHint $_.Exception.Message
            if (-not $isAdmin) { Show-AdminReinstallHelp }
            Stop-RayInstall 1
        }

        if (Test-Path $exePath) {
            $oldExe = "$exePath.old"
            Remove-Item -Path $oldExe -Force -ErrorAction SilentlyContinue
            try {
                Remove-Item -Path $exePath -Force -ErrorAction Stop
            } catch {
                Move-Item -Path $exePath -Destination $oldExe -Force -ErrorAction SilentlyContinue
            }
        }

        $copied = $false
        $copyError = ''
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Copy-Item -Path $extractedExe.FullName -Destination $exePath -Force -ErrorAction Stop
                $copied = $true
                break
            } catch {
                $copyError = $_.Exception.Message
                Start-Sleep -Milliseconds 500
            }
        }
        if (-not $copied) {
            try {
                Copy-Item -Path $extractedExe.FullName -Destination $exePath -Force -ErrorAction Stop
                $copied = $true
            } catch {
                $copyError = $_.Exception.Message
            }
        }
        if (-not $copied) {
            Write-RayFail "Failed to install binary to $exePath"
            if ($copyError) { Write-RayHint "Details: $copyError" }
            if (-not $isAdmin) { Show-AdminReinstallHelp } else { Show-GenericFailureHelp }
            Stop-RayInstall 1
        }
        Unblock-File -Path $exePath -ErrorAction SilentlyContinue

        $cmdContent = "@echo off`r`n`"%~dp0ray.exe`" %*`r`nexit /b %ERRORLEVEL%`r`n"
        [System.IO.File]::WriteAllText($cmdPath, $cmdContent, [System.Text.Encoding]::ASCII)
        Unblock-File -Path $cmdPath -ErrorAction SilentlyContinue
        Write-RayOk "Installed to $exePath"

        # 6) PATH + profile persistence
        Write-RayStep 'Configuring PATH and terminal profiles...'
        $targetScope = if ($isAdmin) { 'Machine' } else { 'User' }
        try {
            $currentRegPath = [Environment]::GetEnvironmentVariable('Path', $targetScope)
            if (-not $currentRegPath) { $currentRegPath = '' }

            $cleanPaths = $currentRegPath -split ';' | Where-Object {
                $p = $_.Trim().TrimEnd('\')
                $p -ne '' -and $p -ne $installDir
            }
            $newRegPath = ($cleanPaths + $installDir) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newRegPath, $targetScope)
        } catch {
            Write-RayWarn "Could not persist PATH in registry ($targetScope): $($_.Exception.Message)"
            Write-RayHint 'Ray will still work in this terminal session.'
        }

        $activePaths = $env:Path -split ';' | Where-Object { $_.Trim().TrimEnd('\') -eq $installDir }
        if (-not $activePaths) {
            $env:Path = "$installDir;$env:Path"
        }

        try {
            Set-Alias -Name ray -Value $exePath -Scope Global -Force -ErrorAction SilentlyContinue
            function global:ray { & "$exePath" @args }
        } catch {}

        try {
            $profilePath = $PROFILE
            if ($profilePath) {
                $profileDir = Split-Path -Parent $profilePath
                if ($profileDir -and -not (Test-Path $profileDir)) {
                    New-Item -ItemType Directory -Path $profileDir -Force -ErrorAction SilentlyContinue | Out-Null
                }
                $profileContent = if (Test-Path $profilePath) { Get-Content $profilePath -Raw -ErrorAction SilentlyContinue } else { '' }
                if (-not $profileContent) { $profileContent = '' }

                if ($profileContent -notmatch [regex]::Escape($installDir)) {
                    $profileEntry = "`n# Ray CLI Environment`nif ((`$env:Path -split ';') -notcontains '$installDir') { `$env:Path = `"$installDir;`$env:Path`" }`n"
                    Add-Content -Path $profilePath -Value $profileEntry -Encoding UTF8 -ErrorAction SilentlyContinue
                }
            }
        } catch {}

        Write-RayOk 'Environment configured'

        # 7) Smoke test with watchdog (Process API; null-safe)
        Write-RayStep 'Verifying installation...'
        $smokePassed = $false
        $installedVersion = 'unknown'
        $smokeError = ''
        $proc = $null

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exePath
            $psi.Arguments = '--version'
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            $psi.ErrorDialog = $false

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi

            try {
                [void]$proc.Start()
            } catch {
                $smokeError = $_.Exception.Message
                if ($_.Exception.InnerException -and $_.Exception.InnerException.Message) {
                    $smokeError = $_.Exception.InnerException.Message
                }
            }

            if ([string]::IsNullOrWhiteSpace($smokeError)) {
                if (-not $proc.WaitForExit(10000)) {
                    try { $proc.Kill() } catch {}
                    $smokeError = 'Verification timed out after 10 seconds.'
                } else {
                    $stdout = ''
                    $stderr = ''
                    try { $stdout = $proc.StandardOutput.ReadToEnd().Trim() } catch {}
                    try { $stderr = $proc.StandardError.ReadToEnd().Trim() } catch {}
                    $code = $proc.ExitCode
                    $versionText = if ($stdout) { $stdout } elseif ($stderr) { $stderr } else { '' }

                    # Success if exit 0 OR we clearly got a version string (ExitCode can be flaky with redirected processes)
                    if (($code -eq 0) -or ($versionText -match '\d+\.\d+')) {
                        if ($versionText) { $installedVersion = $versionText }
                        $smokePassed = $true
                    } else {
                        if ($versionText) { $smokeError = $versionText }
                        else { $smokeError = "ray --version exited with code $code." }
                    }
                }
            }
        } catch {
            $smokeError = $_.Exception.Message
        } finally {
            if ($proc) { try { $proc.Dispose() } catch {} }
        }

        if (-not $smokePassed) {
            Write-Host ''
            $isPolicyBlock = Test-RayPolicyBlockMessage $smokeError

            if ($isPolicyBlock) {
                Write-RayFail 'Windows security policy blocked Ray'
                if ($smokeError) { Write-RayHint "Details: $smokeError" }
                Write-Host ''
                if (-not $isAdmin) {
                    Write-RayWarn 'Diagnosis: policy blocked execution from the user profile (.ray\bin).'
                    Show-AdminReinstallHelp
                } else {
                    Write-RayWarn 'Diagnosis: policy blocked Ray even under Program Files.'
                    Write-Host 'Ask your IT admin to allowlist Ray CLI (ray.exe), then re-run:' -ForegroundColor White
                    Write-Host "  $InstallCmd" -ForegroundColor Cyan
                }
            } else {
                Write-RayFail 'Installation verification failed'
                if ($smokeError) { Write-RayHint "Details: $smokeError" }
                Show-GenericFailureHelp
            }
            Stop-RayInstall 1
        }

        Write-RayOk "Verification passed ($installedVersion)"
        Write-Host ''
        Write-Host "$SYM_CHECK Ray CLI successfully installed!" -ForegroundColor Green
        Write-Host ''
        Write-Host 'Get started:' -ForegroundColor White
        Write-Host '  ray login' -ForegroundColor Cyan
        Write-Host '  ray --help' -ForegroundColor Cyan
        Write-Host ''
        Write-RayHint 'VS Code / Cursor: Ray works in this terminal now. Open a new terminal tab for other tabs.'
        Write-Host ''
    }
    catch {
        if (Test-RayInstallStop $_) {
            # Friendly failure already printed
        } else {
            Write-Host ''
            Write-RayFail "Installation failed: $_"
            Show-GenericFailureHelp
            $script:RayInstallExitCode = 1
        }
    }
    finally {
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    if (Test-RayInstallStop $_) {
        # Friendly failure already printed
    } else {
        Write-Host ''
        Write-RayFail "Installation failed: $_"
        Show-GenericFailureHelp
        $script:RayInstallExitCode = 1
    }
}

Complete-RayInstall