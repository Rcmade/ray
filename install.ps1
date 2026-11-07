# ═══════════════════════════════════════════════════════════════════════════════
# Ray CLI Universal Windows Installer (PowerShell)
# ═══════════════════════════════════════════════════════════════════════════════
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "    Ray CLI Windows Installer" -ForegroundColor Cyan
Write-Host "    ═════════════════════════" -ForegroundColor DarkCyan
Write-Host ""

$repoOwner = "Rcmade"
$repoName = "ray"
$version = if ($env:RAY_VERSION) { $env:RAY_VERSION } else { "latest" }

$archiveName = "ray-windows-x64.zip"
$downloadUrl = if ($version -eq "latest") {
    "https://github.com/$repoOwner/$repoName/releases/latest/download/$archiveName"
} else {
    "https://github.com/$repoOwner/$repoName/releases/download/$version/$archiveName"
}

$installDir = Join-Path $env:USERPROFILE ".ray\bin"
$exePath = Join-Path $installDir "ray.exe"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$tempZip = Join-Path $tempDir $archiveName

try {
    Write-Host "→ Downloading Ray CLI for Windows (x64)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing

    Write-Host "→ Extracting..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force

    $extractedExe = Get-ChildItem -Path $tempDir -Filter "ray*.exe" -Recurse | Select-Object -First 1
    if (-not $extractedExe) {
        throw "Could not find ray executable inside archive."
    }

    Copy-Item -Path $extractedExe.FullName -Destination $exePath -Force
    Unblock-File -Path $exePath -ErrorAction SilentlyContinue
    Write-Host "→ Installed to: $exePath" -ForegroundColor Green

    # Configure User PATH
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -split ';' -notcontains $installDir) {
        Write-Host "→ Adding $installDir to User PATH..." -ForegroundColor Cyan
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
        $env:Path = "$env:Path;$installDir"
    }

    Write-Host ""
    Write-Host "✓ Ray CLI successfully installed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Get started with:" -ForegroundColor White
    Write-Host "  ray login" -ForegroundColor Cyan
    Write-Host "  ray --help" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Error "Installation failed: $_"
    Write-Host "Alternative: Install via NPM using: npm install -g @rcmade/ray" -ForegroundColor Yellow
    exit 1
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
