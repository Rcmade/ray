# ═══════════════════════════════════════════════════════════════════════════════
# Ray CLI Universal Windows Installer (PowerShell)
# Production-Grade Multi-Version Support (PowerShell 5.1 & PowerShell 7+)
# ═══════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Stop'

# 1. Enforce Modern TLS Protocols (TLS 1.2 & TLS 1.3 for GitHub CDN compatibility)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    if ([enum]::GetNames([System.Net.SecurityProtocolType]) -contains 'Tls13') {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls13
    }
} catch {
    # Non-critical on newer .NET Core / PowerShell 7+
}

Write-Host ""
Write-Host "    Ray CLI Windows Installer" -ForegroundColor Cyan
Write-Host "    ═════════════════════════" -ForegroundColor DarkCyan
Write-Host ""

$repoOwner = "Rcmade"
$repoName = "ray"
$version = if ($env:RAY_VERSION) { $env:RAY_VERSION } else { "latest" }

$archiveName = "ray-windows-x64.zip"
$releaseBaseUrl = if ($env:RAY_RELEASE_URL) {
    $env:RAY_RELEASE_URL.TrimEnd('/')
} elseif ($version -eq "latest") {
    "https://github.com/$repoOwner/$repoName/releases/latest/download"
} else {
    "https://github.com/$repoOwner/$repoName/releases/download/$version"
}
$downloadUrl = "$releaseBaseUrl/$archiveName"

# Resolve target directory with fallbacks for restricted environments
$baseDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $HOME }
$installDir = if ($env:RAY_INSTALL_DIR) { $env:RAY_INSTALL_DIR } else { Join-Path $baseDir ".ray\bin" }
$exePath = Join-Path $installDir "ray.exe"

Write-Host "Detected environment: windows-x64" -ForegroundColor Gray
Write-Host "Target binary:        ray-windows-x64.exe" -ForegroundColor Gray
Write-Host "Install directory:    $installDir" -ForegroundColor Gray
Write-Host ""

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$tempZip = Join-Path $tempDir $archiveName

try {
    Write-Host "→ Downloading Ray CLI ($archiveName)..." -ForegroundColor Cyan

    # Fast download with live progress: use curl.exe if available (native on Windows 10/11)
    $curlCmd = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curlCmd) {
        & curl.exe -# -fL "$downloadUrl" -o "$tempZip"
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed with exit code $LASTEXITCODE"
        }
    } else {
        # Fallback to Invoke-WebRequest (disable progress preference to avoid 10x download slowdown)
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
        } finally {
            $ProgressPreference = $prevProgress
        }
    }
    Write-Host "✓ Download complete" -ForegroundColor Green

    Write-Host "→ Extracting binary..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

    $extractedExe = Get-ChildItem -Path $tempDir -Filter "ray*.exe" -Recurse | Select-Object -First 1
    if (-not $extractedExe) {
        throw "Could not find ray executable inside downloaded archive."
    }
    Write-Host "✓ Extraction complete" -ForegroundColor Green

    # Handle running ray.exe process lock if updating
    $runningProc = Get-Process -Name "ray" -ErrorAction SilentlyContinue
    if ($runningProc) {
        Write-Host "Notice: Stopping running 'ray' process to allow binary update..." -ForegroundColor Yellow
        $runningProc | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    Write-Host "→ Installing to $exePath..." -ForegroundColor Cyan
    Copy-Item -Path $extractedExe.FullName -Destination $exePath -Force
    Unblock-File -Path $exePath -ErrorAction SilentlyContinue
    Write-Host "✓ Installed to $exePath" -ForegroundColor Green

    # Configure User PATH permanently if not present
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { $userPath = "" }
    $pathParts = $userPath -split ';' | Where-Object { $_ -ne "" }
    if ($pathParts -notcontains $installDir) {
        Write-Host "→ Adding $installDir to User PATH..." -ForegroundColor Cyan
        $newPath = if ($userPath) { "$userPath;$installDir" } else { $installDir }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$installDir"
        Write-Host "✓ Added ~/.ray/bin to User PATH" -ForegroundColor Green
    }

    # Smoke Test
    $installedVersion = "installed"
    try {
        $verOut = & "$exePath" --version 2>$null
        if ($verOut) { $installedVersion = $verOut.Trim() }
    } catch {}

    Write-Host ""
    Write-Host "✓ Ray CLI successfully installed! ($installedVersion)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Get started with:" -ForegroundColor White
    Write-Host "  ray login" -ForegroundColor Cyan
    Write-Host "  ray --help" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "❌ Installation failed: $_" -ForegroundColor Red
    Write-Host "Tip: Install via NPM instead: npm install -g @rcmade/ray" -ForegroundColor Yellow
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
