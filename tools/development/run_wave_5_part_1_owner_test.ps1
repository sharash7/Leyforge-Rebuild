[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_-]{1,64}$')]
    [string] $WorldId = 'wave5-w51-owner-test',
    [ValidateRange(0,2147483647)]
    [int] $Seed = 184552221,
    [string] $RuntimeLogPath = ''
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$runnerRoot = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed'
$consolePath = (Resolve-Path -LiteralPath (Join-Path $runnerRoot 'godot.windows.editor.x86_64.console.exe')).Path
$graphicalPath = (Resolve-Path -LiteralPath (Join-Path $runnerRoot 'godot.windows.editor.x86_64.exe')).Path

# Import the actual owner checkout before launch so new global classes are
# registered. This touches only Godot's ignored project import/cache files.
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $consolePath
$info.WorkingDirectory = $repositoryRoot
$info.Arguments = '--headless --editor --path "' + $repositoryRoot + '" --quit'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$import = New-Object Diagnostics.Process
$import.StartInfo = $info
[void] $import.Start()
$stdout = $import.StandardOutput.ReadToEndAsync()
$stderr = $import.StandardError.ReadToEndAsync()
if (-not $import.WaitForExit(180000)) {
    $import.Kill()
    $import.WaitForExit()
    Write-Output ($stdout.Result + $stderr.Result)
    throw 'Owner class import timed out; graphical launch cancelled.'
}
$importText = $stdout.Result + $stderr.Result
Write-Output $importText
if ($import.ExitCode -ne 0 -or $importText -match '(?m)^\s*(SCRIPT ERROR|ERROR:)') {
    throw "Owner class import failed (exit $($import.ExitCode)); graphical launch cancelled."
}
Write-Output 'W5_1_OWNER_IMPORT_PASS'
$arguments = @('--path', ('"' + $repositoryRoot + '"'))
if ($RuntimeLogPath) {
    $absoluteLog = [IO.Path]::GetFullPath($RuntimeLogPath)
    $arguments += @('--log-file', ('"' + $absoluteLog + '"'))
}
$arguments += @('--', "--world-id=$WorldId", "--seed=$Seed")
# This is the requested interactive graphical game, not a background helper.
$game = Start-Process -FilePath $graphicalPath -WorkingDirectory $repositoryRoot -ArgumentList $arguments -PassThru
Write-Output "W5_1_OWNER_LAUNCH_STARTED pid=$($game.Id) world=$WorldId seed=$Seed"
