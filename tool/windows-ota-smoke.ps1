param(
    [string]$Installer,
    [string]$BaselineInstaller = '',
    [string]$TestHost = 'build/windows/x64/runner/Release/waveify.exe',
    [string]$OutputDirectory = 'build/windows-smoke/ota'
)
$ErrorActionPreference = 'Stop'
$setup = (Resolve-Path $Installer).Path
$hostExe = (Resolve-Path $TestHost).Path
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$output = (Resolve-Path $OutputDirectory).Path
$installPath = Join-Path $env:RUNNER_TEMP 'Waveify OTA è test'
$target = Join-Path $installPath 'waveify.exe'
$cache = Join-Path $output 'cache'
New-Item -ItemType Directory -Force $cache | Out-Null
$cachedSetup = Join-Path $cache 'Waveify-update.exe'
Copy-Item $setup $cachedSetup
$hash = (Get-FileHash -LiteralPath $cachedSetup -Algorithm SHA256).Hash.ToLowerInvariant()
$report = Join-Path $output 'preservation.json'
$startup = Join-Path $output 'restarted.json'
$initial = if ($BaselineInstaller) { (Resolve-Path $BaselineInstaller).Path } else { $setup }
$before = Start-Process $initial -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installPath`"" -Wait -PassThru
if ($before.ExitCode -ne 0) { throw 'Baseline installation failed' }
$beforeVersion = (Get-Item $target).VersionInfo.ProductVersion
try {
    # The host creates real persistent library/settings data, then starts the
    # exact production helper. It replaces the baseline and relaunches the app.
    $argsForHost = @('--ota-self-test', "--ota-installer=`"$cachedSetup`"", "--ota-sha256=$hash",
        "--ota-target=`"$target`"", "--ota-report=`"$report`"", "--ota-startup=`"$startup`"")
    $process = Start-Process $hostExe -ArgumentList $argsForHost -PassThru
    if (-not $process.WaitForExit(30000)) { throw 'Update host did not hand off to helper' }
    if ($process.ExitCode -ne 0) { throw "Update host failed: $($process.ExitCode)" }
    $deadline = (Get-Date).AddSeconds(120)
    while ((-not (Test-Path $report) -or -not (Test-Path $startup)) -and (Get-Date) -lt $deadline) {
        if (Test-Path (Join-Path $cache 'install-error.txt')) { throw 'Production update helper failed; see diagnostics' }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-Path $report) -or -not (Test-Path $startup)) { throw 'Updated application did not restart in time' }
    $preserved = Get-Content $report -Raw | ConvertFrom-Json
    $frame = Get-Content $startup -Raw | ConvertFrom-Json
    if ($preserved.status -ne 'passed' -or $frame.status -ne 'passed' -or $frame.window_fits_work_area -ne $true) { throw 'Update lost data or did not render correctly' }
    $afterVersion = (Get-Item $target).VersionInfo.ProductVersion
    @{ status = 'passed'; fromVersion = $beforeVersion; toVersion = $afterVersion;
        libraryPreserved = $preserved.library_preserved; settingsPreserved = $preserved.settings_preserved;
        restarted = $true } | ConvertTo-Json | Set-Content (Join-Path $output 'update.json')
} catch {
    $_ | Out-String | Set-Content (Join-Path $output 'failure.txt')
    throw
} finally {
    if (Test-Path $startup) {
        $frame = Get-Content $startup -Raw | ConvertFrom-Json
        if ($frame.pid) { Stop-Process -Id $frame.pid -Force -ErrorAction SilentlyContinue }
    }
    $uninstall = Join-Path $installPath 'unins000.exe'
    if (Test-Path $uninstall) { Start-Process $uninstall -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait }
    Remove-Item $cachedSetup -ErrorAction SilentlyContinue
}
