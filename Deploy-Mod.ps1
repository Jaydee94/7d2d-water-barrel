<#
.SYNOPSIS
    Compiles the AutomatedWaterBarrel mod and deploys it to a local dedicated server for testing.

.DESCRIPTION
    Builds the mod DLL against the game's managed assemblies, then copies the entire mod
    folder into the dedicated server's Mods directory. Optionally starts the dedicated
    server after a successful deployment.

    The -GamePath parameter points to the 7 Days to Die installation that provides the
    reference DLLs required for compilation (Assembly-CSharp.dll, 0Harmony.dll,
    UnityEngine.CoreModule.dll). This can be either the game client or the dedicated
    server installation — both ship the same managed assemblies.

.PARAMETER GamePath
    Path to the 7 Days to Die installation used for build references.
    Defaults to the Steam default client path on Windows.

.PARAMETER ServerPath
    Path to the 7 Days to Die dedicated server where the mod will be deployed.
    Defaults to the Steam default dedicated server path on Windows.

.PARAMETER Configuration
    Build configuration to use. Defaults to 'Release'.

.PARAMETER Launch
    If specified, starts the dedicated server after a successful deployment.

.EXAMPLE
    .\Deploy-Mod.ps1

    Build and deploy using default Steam paths.

.EXAMPLE
    .\Deploy-Mod.ps1 -GamePath "D:\Games\7DaysToDie" -ServerPath "D:\Servers\7DaysToDie"

    Build against a custom game path and deploy to a custom server path.

.EXAMPLE
    .\Deploy-Mod.ps1 -Launch

    Build, deploy, and then start the dedicated server.
#>

[CmdletBinding()]
param(
    [string]$GamePath   = "C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die",
    [string]$ServerPath = "C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die Dedicated Server",
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "    [OK]  $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "    [ERR] $Msg" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Step 1 – Validate prerequisites
# ---------------------------------------------------------------------------
Write-Step "Checking prerequisites"

# .NET SDK
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Fail ".NET SDK not found. Install from https://dotnet.microsoft.com/download"
    exit 1
}
Write-Ok ".NET SDK found: $(dotnet --version)"

# Project file
$ProjectFile = Join-Path $PSScriptRoot "WaterBarrelMod.csproj"
if (-not (Test-Path $ProjectFile)) {
    Write-Fail "Project file not found: $ProjectFile"
    exit 1
}
Write-Ok "Project file: $ProjectFile"

# Game path (required for reference DLLs)
$ManagedDir = Join-Path $GamePath "7DaysToDie_Data\Managed"
if (-not (Test-Path $ManagedDir)) {
    Write-Fail "Game managed directory not found: $ManagedDir"
    Write-Fail "Set -GamePath to your 7 Days to Die installation (client or dedicated server)."
    exit 1
}
Write-Ok "Game managed directory: $ManagedDir"

# Server path (deploy target)
if (-not (Test-Path $ServerPath)) {
    Write-Fail "Dedicated server path not found: $ServerPath"
    Write-Fail "Set -ServerPath to your 7 Days to Die dedicated server installation."
    exit 1
}
Write-Ok "Server path: $ServerPath"

# ---------------------------------------------------------------------------
# Step 2 – Compile
# ---------------------------------------------------------------------------
Write-Step "Building mod ($Configuration)"

$BuildArgs = @(
    'build', $ProjectFile,
    '-c', $Configuration,
    "-p:GamePath=$GamePath",
    '--nologo'
)

& dotnet @BuildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Build failed (exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}
Write-Ok "Build succeeded."

# ---------------------------------------------------------------------------
# Step 3 – Deploy to dedicated server
# ---------------------------------------------------------------------------
Write-Step "Deploying mod to dedicated server"

$ModName       = "AutomatedWaterBarrel"
$SourceDir     = $PSScriptRoot
$DestDir       = Join-Path $ServerPath "Mods\$ModName"

# Create or clean the destination mod folder
if (Test-Path $DestDir) {
    Write-Host "    Removing existing mod folder: $DestDir"
    Remove-Item $DestDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DestDir | Out-Null

# Files and folders to copy into the mod directory
$ItemsToCopy = @(
    'ModInfo.xml',
    'AutomatedWaterBarrel.dll',
    'Config'
)

foreach ($Item in $ItemsToCopy) {
    $Source = Join-Path $SourceDir $Item
    if (-not (Test-Path $Source)) {
        Write-Fail "Expected file/folder not found: $Source"
        exit 1
    }
    Copy-Item -Path $Source -Destination $DestDir -Recurse -Force
    Write-Ok "Copied: $Item"
}

Write-Ok "Mod deployed to: $DestDir"

# ---------------------------------------------------------------------------
# Step 4 – (Optional) Launch dedicated server
# ---------------------------------------------------------------------------
if ($Launch) {
    Write-Step "Launching dedicated server"

    $ServerExe = Join-Path $ServerPath "7DaysToDieServer.exe"
    if (-not (Test-Path $ServerExe)) {
        Write-Fail "Server executable not found: $ServerExe"
        exit 1
    }

    Write-Host "    Starting: $ServerExe"
    Start-Process -FilePath $ServerExe -WorkingDirectory $ServerPath
    Write-Ok "Dedicated server started."
} else {
    Write-Host "`n    To start the server manually, run:" -ForegroundColor Yellow
    Write-Host "    & `"$(Join-Path $ServerPath '7DaysToDieServer.exe')`"" -ForegroundColor Yellow
}

Write-Host "`nDone." -ForegroundColor Green
