param(
    [string]$Executable = 'build/windows/x64/runner/Release/waveify.exe',
    [string]$OutputDirectory = 'build/windows-smoke'
)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path $Executable).Path
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$output = (Resolve-Path $OutputDirectory).Path
$report = Join-Path $output 'self-test.json'
$process = $null
try {
    $video = (Resolve-Path (Join-Path $PSScriptRoot '../test/support/media/moving-pattern.mp4')).Path
    $process = Start-Process -FilePath $exe -ArgumentList '--self-test', "--self-test-output=$report", ('--self-test-video="{0}"' -f $video) -PassThru
    if (-not $process.WaitForExit(60000)) { throw 'Native self-test timed out after 60 seconds' }
    if ($process.ExitCode -ne 0) { throw "Native self-test exited with $($process.ExitCode)" }
    if (-not (Test-Path $report)) { throw 'Native self-test did not write its JSON report' }
    $result = Get-Content $report -Raw | ConvertFrom-Json
    if ($result.cloud_configured -ne $true) { throw 'Windows release is missing public cloud configuration for online accounts' }
    if ($result.status -ne 'passed') { throw "Native self-test did not pass: $(Get-Content $report -Raw)" }
    if ($result.checks.native_muted_video -ne 'passed') { throw 'Native muted video playback failed' }
    $frameReport = Join-Path $output 'first-frame.json'
    Remove-Item $frameReport -ErrorAction SilentlyContinue
    $process = Start-Process -FilePath $exe -ArgumentList "--startup-report=$frameReport" -PassThru
    $deadline = (Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited) { throw "Application exited during startup: $($process.ExitCode)" }
    } while ($process.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline)
    if ($process.MainWindowHandle -eq 0) { throw 'Application did not create a visible main window' }
    while (-not (Test-Path $frameReport) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited) { throw 'Application exited before rendering its first frame' }
    }
    if (-not (Test-Path $frameReport)) { throw 'Flutter did not render the application within 30 seconds' }
    $frame = Get-Content $frameReport -Raw | ConvertFrom-Json
    if ($frame.window_fits_work_area -ne $true) { throw 'Application window extends beyond the screen work area' }
    Start-Sleep -Seconds 5
    $process.Refresh()
    if ($process.HasExited) { throw 'Application exited after creating its main window' }
    @{ status = 'passed'; processId = $process.Id; windowTitle = $process.MainWindowTitle; windowHandle = $process.MainWindowHandle.ToInt64() } |
        ConvertTo-Json | Set-Content (Join-Path $output 'startup.json')
    # Screenshot is supplementary; some hosted runners have no capturable desktop.
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Windows.Forms
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            $bitmap.Save((Join-Path $output 'startup.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    } catch { $_ | Out-String | Set-Content (Join-Path $output 'screenshot-error.txt') }
} catch {
    $_ | Out-String | Set-Content (Join-Path $output 'failure.txt')
    throw
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
