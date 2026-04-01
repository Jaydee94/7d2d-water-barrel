<#
.SYNOPSIS
    Compiles the AutomatedWaterBarrel mod and deploys it to a local dedicated server for testing.

.DESCRIPTION
    Builds the mod DLL against the game's managed assemblies, then copies the entire mod
    folder into the dedicated server's Mods directory. The script also supports a short
    local iteration loop: optional server restart, startup smoke test via log inspection,
    and filtered log tailing for the mod's own messages.

    When started from PowerShell inside WSL, the script re-invokes itself through the
    Windows PowerShell host so the Windows .NET SDK and Windows game/server paths can be
    used without any manual path hunting.

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

.PARAMETER Restart
    If specified, stops any running 7DaysToDieServer.exe instances first and then starts
    the dedicated server after deployment.

.PARAMETER SmokeTest
    Waits for the server log to contain the mod startup marker after launch/restart.

.PARAMETER Playtest
    Builds the mod, deploys it, restarts the local dedicated server, waits for the
    mod startup marker, and then returns so you can test manually with your game client.

.PARAMETER TailLog
    Follows the newest server log and prints only lines matching the log pattern.

.PARAMETER TailLogSeconds
    Number of seconds to follow the server log before returning. Defaults to 30.

.PARAMETER LogPattern
    Regex used when tailing logs. Defaults to 'AutomatedWaterBarrel'.

.PARAMETER SmokeTestTimeoutSeconds
    Number of seconds to wait for the startup marker in the server log. Defaults to 45.

.EXAMPLE
    .\Deploy-Mod.ps1

    Build and deploy using default Steam paths.

.EXAMPLE
    .\Deploy-Mod.ps1 -Restart -SmokeTest

    Build, deploy, restart the local dedicated server, and verify the mod loads.

.EXAMPLE
    .\Deploy-Mod.ps1 -Playtest

    Build, deploy, restart the local dedicated server, wait for the mod startup marker,
    and then return so you can join with your client and test manually.

.EXAMPLE
    .\Deploy-Mod.ps1 -Restart -SmokeTest -TailLog

    Build, deploy, restart, verify startup, and then follow the mod log for a short
    functional test in-game.
#>

[CmdletBinding()]
param(
    [string]$GamePath   = "C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die",
    [string]$ServerPath = "C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die Dedicated Server",
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$Launch,
    [switch]$Restart,
    [switch]$SmokeTest,
    [switch]$Playtest,
    [switch]$TailLog,
    [ValidateRange(5, 600)]
    [int]$TailLogSeconds = 30,
    [string]$LogPattern = 'AutomatedWaterBarrel',
    [ValidateRange(5, 300)]
    [int]$SmokeTestTimeoutSeconds = 45
)

function Test-IsWslPowerShell {
    return $PSVersionTable.PSEdition -eq 'Core' -and
           [System.Environment]::GetEnvironmentVariable('WSL_DISTRO_NAME')
}

function Convert-ToWindowsPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^[A-Za-z]:\\') {
        return $Path
    }

    $wslPath = Get-Command wslpath -ErrorAction SilentlyContinue
    if (-not $wslPath) {
        throw 'wslpath was not found. Install WSL path tools or pass Windows-style paths.'
    }

    return (& $wslPath.Source '-w' $Path).Trim()
}

function Invoke-WindowsSelf {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) {
        throw 'powershell.exe was not found in WSL. Run this script from Windows PowerShell or install PowerShell bridging in WSL.'
    }

    $windowsScriptPath = Convert-ToWindowsPath -Path $PSCommandPath
    $relayArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $windowsScriptPath,
        '-Configuration', $Configuration,
        '-GamePath', (Convert-ToWindowsPath -Path $GamePath),
        '-ServerPath', (Convert-ToWindowsPath -Path $ServerPath),
        '-TailLogSeconds', $TailLogSeconds,
        '-LogPattern', $LogPattern,
        '-SmokeTestTimeoutSeconds', $SmokeTestTimeoutSeconds
    )

    if ($Launch) {
        $relayArgs += '-Launch'
    }
    if ($Restart) {
        $relayArgs += '-Restart'
    }
    if ($SmokeTest) {
        $relayArgs += '-SmokeTest'
    }
    if ($Playtest) {
        $relayArgs += '-Playtest'
    }
    if ($TailLog) {
        $relayArgs += '-TailLog'
    }

    & $windowsPowerShell.Source @relayArgs
    exit $LASTEXITCODE
}

if (Test-IsWslPowerShell) {
    Invoke-WindowsSelf
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "    [OK]  $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "    [ERR] $Msg" -ForegroundColor Red }
function Write-Warn  { param([string]$Msg) Write-Host "    [WARN] $Msg" -ForegroundColor Yellow }

function Resolve-DotNetCommand {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnet) {
        return $dotnet.Source
    }

    foreach ($candidate in @(
        'C:\Program Files\dotnet\dotnet.exe',
        'C:\Program Files (x86)\dotnet\dotnet.exe'
    )) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw '.NET SDK not found. Install it on Windows or add dotnet to PATH.'
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @(
        'C:\Program Files (x86)\Steam',
        'C:\Program Files\Steam'
    )) {
        if (Test-Path $candidate) {
            [void]$roots.Add($candidate)
        }
    }

    try {
        $registrySteamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($registrySteamPath) {
            $normalizedPath = $registrySteamPath -replace '/', '\\'
            if (Test-Path $normalizedPath) {
                [void]$roots.Add($normalizedPath)
            }
        }
    }
    catch {
    }

    return $roots | Select-Object -Unique
}

function Get-SteamLibraryRoots {
    $libraries = New-Object System.Collections.Generic.List[string]

    foreach ($steamRoot in Get-SteamRoots) {
        [void]$libraries.Add($steamRoot)

        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path $libraryFile)) {
            continue
        }

        foreach ($line in Get-Content -Path $libraryFile -ErrorAction SilentlyContinue) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $libraryPath = $matches[1] -replace '\\\\', '\'
                if (Test-Path $libraryPath) {
                    [void]$libraries.Add($libraryPath)
                }
            }
        }
    }

    return $libraries | Select-Object -Unique
}

function Resolve-SteamAppInstallPath {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$FallbackPath
    )

    foreach ($libraryRoot in Get-SteamLibraryRoots) {
        $manifestPath = Join-Path $libraryRoot "steamapps\appmanifest_$AppId.acf"
        if (-not (Test-Path $manifestPath)) {
            continue
        }

        $installDir = $null
        foreach ($line in Get-Content -Path $manifestPath -ErrorAction SilentlyContinue) {
            if ($line -match '"installdir"\s+"([^"]+)"') {
                $installDir = $matches[1]
                break
            }
        }

        if (-not $installDir) {
            continue
        }

        $candidate = Join-Path $libraryRoot (Join-Path 'steamapps\common' $installDir)
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $FallbackPath
}

function Get-ServerProcesses {
    param([Parameter(Mandatory = $true)][string]$ServerExePath)

    $normalizedServerExePath = [System.IO.Path]::GetFullPath($ServerExePath)
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='7DaysToDieServer.exe'" -ErrorAction SilentlyContinue)
    $exactMatches = @(
        $processes | Where-Object {
            $_.ExecutablePath -and
            [string]::Equals(
                [System.IO.Path]::GetFullPath($_.ExecutablePath),
                $normalizedServerExePath,
                [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    if ($exactMatches.Count -gt 0) {
        return $exactMatches
    }

    return @(
        Get-Process -Name '7DaysToDieServer' -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.Path -or
                [string]::Equals(
                    [System.IO.Path]::GetFullPath($_.Path),
                    $normalizedServerExePath,
                    [System.StringComparison]::OrdinalIgnoreCase)
            }
    )
}

function Stop-DedicatedServer {
    param([Parameter(Mandatory = $true)][string]$ServerExePath)

    $processes = @(Get-ServerProcesses -ServerExePath $ServerExePath)
    if ($processes.Count -eq 0) {
        Write-Ok 'No running dedicated server process found.'
        return
    }

    foreach ($process in $processes) {
        Write-Host "    Stopping PID $($process.ProcessId): $($process.ExecutablePath)"
        Stop-Process -Id $process.ProcessId -Force
    }

    Start-Sleep -Seconds 2
    Write-Ok 'Dedicated server stopped.'
}

function Get-ServerLogFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    $files = New-Object System.Collections.Generic.List[object]

    $candidateDirectories = @(
        $ServerPath,
        (Join-Path $ServerPath '7DaysToDieServer_Data'),
        (Join-Path $env:APPDATA '7DaysToDie\logs')
    )

    foreach ($directory in $candidateDirectories) {
        if (-not [string]::IsNullOrWhiteSpace($directory) -and (Test-Path $directory)) {
            Get-ChildItem -Path $directory -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'output_log|Player|server|log' } |
                ForEach-Object {
                    $priority = 4
                    if ($_.Name -match '^output_log_dedi') {
                        $priority = 0
                    } elseif ($_.DirectoryName -eq $ServerPath) {
                        $priority = 1
                    } elseif ($_.DirectoryName -like '*7DaysToDieServer_Data*') {
                        $priority = 2
                    } elseif ($_.Name -match 'dedi|dedicated|server') {
                        $priority = 3
                    } elseif ($_.Name -match 'launcher') {
                        $priority = 5
                    } elseif ($_.Name -match 'client') {
                        $priority = 6
                    }

                    $isFresh = $_.LastWriteTime -ge $NotBefore
                    [void]$files.Add([pscustomobject]@{
                        FileInfo = $_
                        Priority = $priority
                        IsFresh  = $isFresh
                    })
                }
        }
    }

    $freshFiles = $files | Where-Object { $_.IsFresh }
    if ($freshFiles) {
        return $freshFiles |
            Sort-Object -Property Priority, @{ Expression = { $_.FileInfo.LastWriteTime }; Descending = $true }, @{ Expression = { $_.FileInfo.FullName }; Descending = $false } |
            ForEach-Object { $_.FileInfo }
    }

    return $files |
        Sort-Object -Property Priority, @{ Expression = { $_.FileInfo.LastWriteTime }; Descending = $true }, @{ Expression = { $_.FileInfo.FullName }; Descending = $false } |
        ForEach-Object { $_.FileInfo }
}

function Resolve-ServerLauncher {
    param([Parameter(Mandatory = $true)][string]$ServerPath)

    $launchers = @(
        (Join-Path $ServerPath 'StartDedicatedServer.bat'),
        (Join-Path $ServerPath 'startdedicated.bat'),
        (Join-Path $ServerPath '7DaysToDieServer.exe')
    )

    return $launchers | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-LatestServerLogFile {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    return Get-ServerLogFiles -ServerPath $ServerPath -NotBefore $NotBefore | Select-Object -First 1
}

function Wait-ForServerLogPattern {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [string]$ServerExePath,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastReportedFile = $null
    $lastProgressSecond = -1

    Write-Host "    Waiting up to $TimeoutSeconds seconds for: $Pattern"

    do {
        $elapsedSeconds = [int][Math]::Floor(((Get-Date) - ($deadline.AddSeconds(-$TimeoutSeconds))).TotalSeconds)
        $logFile = Get-LatestServerLogFile -ServerPath $ServerPath -NotBefore $NotBefore
        if ($logFile -and $logFile.FullName -ne $lastReportedFile) {
            Write-Host "    Observing log file: $($logFile.FullName)"
            $lastReportedFile = $logFile.FullName
        }

        if ($logFile) {
            $match = Select-String -Path $logFile.FullName -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($match) {
                Write-Ok "Startup marker found after $elapsedSeconds seconds."
                Write-Host "    Match: $($match.Line)"
                return $logFile
            }
        }

        if (($elapsedSeconds % 5) -eq 0 -and $elapsedSeconds -ne $lastProgressSecond) {
            $lastProgressSecond = $elapsedSeconds
            Write-Host "    Still waiting... ${elapsedSeconds}s/${TimeoutSeconds}s"

            if ($ServerExePath) {
                $processCount = @(Get-ServerProcesses -ServerExePath $ServerExePath).Count
                Write-Host "    Server process count: $processCount"
            }
        }

        if ($ServerExePath -and $elapsedSeconds -ge 10 -and @(Get-ServerProcesses -ServerExePath $ServerExePath).Count -eq 0) {
            if ($elapsedSeconds -eq 10) {
                Write-Warn 'The dedicated server process could not be confirmed yet. Continuing to watch the log until timeout.'
            }
        }

        Start-Sleep -Seconds 1
    }
    while ((Get-Date) -lt $deadline)

    return $null
}

function Follow-ServerLog {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][int]$DurationSeconds,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    $logFile = Get-LatestServerLogFile -ServerPath $ServerPath -NotBefore $NotBefore
    if (-not $logFile) {
        Write-Warn 'No server log file was found to follow.'
        return
    }

    Write-Step 'Following server log'
    Write-Host "    File: $($logFile.FullName)"
    Write-Host "    Filter: $Pattern"
    Write-Host "    Duration: $DurationSeconds seconds"

    foreach ($line in Get-Content -Path $logFile.FullName -Tail 20 -ErrorAction SilentlyContinue) {
        if ($line -match $Pattern) {
            Write-Host $line
        }
    }

    $deadline = (Get-Date).AddSeconds($DurationSeconds)
    $stream = [System.IO.File]::Open($logFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

    try {
        $reader = New-Object System.IO.StreamReader($stream)
        [void]$stream.Seek(0, [System.IO.SeekOrigin]::End)

        while ((Get-Date) -lt $deadline) {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line -match $Pattern) {
                    Write-Host $line
                }
            }

            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }

    Write-Ok "Stopped log tail after $DurationSeconds seconds."
}

function Write-PlaytestInstructions {
    Write-Step 'Ready for manual client test'
    Write-Host '    The dedicated server remains running after this script exits.'
    Write-Host '    1. Start your normal 7 Days to Die client and join the local dedicated server.'
    Write-Host '    2. Place a Dew Collector and an Automated Water Barrel within 5 blocks.'
    Write-Host '    3. Wait for the collector to produce water.'
    Write-Host '    4. Confirm the water item moves into the barrel and the collector output slot clears.'
    Write-Host '    5. If needed, rerun with -TailLog to watch [AutomatedWaterBarrel] lines live.'
}

if ($Playtest) {
    $Restart = $true
    $SmokeTest = $true
}

if ($Restart) {
    $Launch = $true
}

$ServerLaunchTime = [datetime]::MinValue

# ---------------------------------------------------------------------------
# Step 1 – Validate prerequisites
# ---------------------------------------------------------------------------
Write-Step 'Checking prerequisites'

$DotNetCommand = Resolve-DotNetCommand
Write-Ok ".NET SDK found: $(& $DotNetCommand --version)"

$ResolvedGamePath = Resolve-SteamAppInstallPath -AppId '251570' -FallbackPath $GamePath
if (-not [string]::Equals($ResolvedGamePath, $GamePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Ok "Auto-detected game path: $ResolvedGamePath"
    $GamePath = $ResolvedGamePath
}

$ResolvedServerPath = Resolve-SteamAppInstallPath -AppId '294420' -FallbackPath $ServerPath
if (-not [string]::Equals($ResolvedServerPath, $ServerPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Ok "Auto-detected server path: $ResolvedServerPath"
    $ServerPath = $ResolvedServerPath
}

$ProjectFile = Join-Path $PSScriptRoot 'WaterBarrelMod.csproj'
if (-not (Test-Path $ProjectFile)) {
    Write-Fail "Project file not found: $ProjectFile"
    exit 1
}
Write-Ok "Project file: $ProjectFile"

$ManagedDir = Join-Path $GamePath '7DaysToDie_Data\Managed'
if (-not (Test-Path $ManagedDir)) {
    Write-Fail "Game managed directory not found: $ManagedDir"
    Write-Fail 'Set -GamePath to your 7 Days to Die installation (client or dedicated server).'
    exit 1
}
Write-Ok "Game managed directory: $ManagedDir"

if (-not (Test-Path $ServerPath)) {
    Write-Fail "Dedicated server path not found: $ServerPath"
    Write-Fail 'Set -ServerPath to your 7 Days to Die dedicated server installation.'
    exit 1
}
Write-Ok "Server path: $ServerPath"

$ServerExe = Join-Path $ServerPath '7DaysToDieServer.exe'
$ServerLauncher = Resolve-ServerLauncher -ServerPath $ServerPath
if (($Launch -or $Restart) -and -not $ServerLauncher) {
    Write-Fail "No dedicated server launcher found in: $ServerPath"
    exit 1
}

if (($Launch -or $Restart) -and -not (Test-Path $ServerExe)) {
    Write-Fail "Server executable not found: $ServerExe"
    exit 1
}

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

& $DotNetCommand @BuildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Build failed (exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}
Write-Ok 'Build succeeded.'

# ---------------------------------------------------------------------------
# Step 3 – Deploy to dedicated server
# ---------------------------------------------------------------------------
Write-Step 'Deploying mod to dedicated server'

$ModName   = 'AutomatedWaterBarrel'
$SourceDir = $PSScriptRoot
$DestDir   = Join-Path $ServerPath "Mods\$ModName"

if (Test-Path $DestDir) {
    Write-Host "    Removing existing mod folder: $DestDir"
    Remove-Item $DestDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DestDir | Out-Null

$ItemsToCopy = @(
    'ModInfo.xml',
    'AutomatedWaterBarrel.dll',
    'Config'
)

foreach ($item in $ItemsToCopy) {
    $source = Join-Path $SourceDir $item
    if (-not (Test-Path $source)) {
        Write-Fail "Expected file/folder not found: $source"
        exit 1
    }

    Copy-Item -Path $source -Destination $DestDir -Recurse -Force
    Write-Ok "Copied: $item"
}

Write-Ok "Mod deployed to: $DestDir"

# ---------------------------------------------------------------------------
# Step 4 – (Optional) Restart or launch dedicated server
# ---------------------------------------------------------------------------
if ($Restart) {
    Write-Step 'Restarting dedicated server'
    Stop-DedicatedServer -ServerExePath $ServerExe
}

if ($Launch) {
    Write-Step 'Launching dedicated server'
    Write-Host "    Starting: $ServerLauncher"
    $ServerLaunchTime = Get-Date
    if ($ServerLauncher.EndsWith('.bat', [System.StringComparison]::OrdinalIgnoreCase)) {
        $startedProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', $ServerLauncher) -WorkingDirectory $ServerPath -PassThru
    } else {
        $startedProcess = Start-Process -FilePath $ServerLauncher -WorkingDirectory $ServerPath -PassThru
    }

    if ($startedProcess) {
        Write-Ok "Dedicated server launcher started (PID $($startedProcess.Id))."
    } else {
        Write-Ok 'Dedicated server started.'
    }
} else {
    Write-Host "`n    To start the server manually, run:" -ForegroundColor Yellow
    Write-Host "    & `"$ServerLauncher`"" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 5 – (Optional) Smoke test and log follow
# ---------------------------------------------------------------------------
if ($SmokeTest) {
    Write-Step 'Running startup smoke test'

    $startupMarker = '[AutomatedWaterBarrel] Mod loaded'
    $logFile = Wait-ForServerLogPattern -ServerPath $ServerPath -Pattern $startupMarker -TimeoutSeconds $SmokeTestTimeoutSeconds -ServerExePath $ServerExe -NotBefore $ServerLaunchTime

    if ($logFile -and (Select-String -Path $logFile.FullName -Pattern $startupMarker -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
        Write-Ok "Found startup marker in: $($logFile.FullName)"
    } else {
        Write-Warn "Did not find '$startupMarker' within $SmokeTestTimeoutSeconds seconds."
        Write-Warn 'The server may still be starting, or the log location may differ on this machine.'
    }

    if ($Playtest) {
        if ($logFile -and (Select-String -Path $logFile.FullName -Pattern $startupMarker -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
            Write-Ok 'Server startup looks good for a manual client playtest.'
        } else {
            Write-Warn 'Startup could not be confirmed from logs, but the server may still be usable for a manual test.'
        }

        Write-PlaytestInstructions
    }
}

if ($TailLog) {
    Follow-ServerLog -ServerPath $ServerPath -Pattern $LogPattern -DurationSeconds $TailLogSeconds -NotBefore $ServerLaunchTime
}

Write-Host "`nDone." -ForegroundColor Green
