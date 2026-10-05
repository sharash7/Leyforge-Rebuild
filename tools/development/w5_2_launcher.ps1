# Shared import/launch mechanism; both owner launchers serialize cache refresh.
function Start-W52Game {
    param([string[]] $SessionArguments, [string] $RuntimeLogPath = '')
    $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $runnerRoot = 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed'
    $consolePath = Join-Path $runnerRoot 'godot.windows.editor.x86_64.console.exe'
    $graphicalPath = Join-Path $runnerRoot 'godot.windows.editor.x86_64.exe'
    $sha = [Security.Cryptography.SHA256]::Create()
    $suffix = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($repositoryRoot.ToLowerInvariant()))).Replace('-','').Substring(0,24)
    $mutex = New-Object Threading.Mutex($false, ("Local\Leyforge-W52-Import-" + $suffix))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(180000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Timed out waiting for class import lock; launch cancelled.' }
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
        if (-not $import.WaitForExit(180000)) { $import.Kill(); throw 'Import timed out; launch cancelled.' }
        $text = $stdout.Result + $stderr.Result
        Write-Output $text
        if ($import.ExitCode -ne 0 -or $text -match '(?m)^\s*(SCRIPT ERROR|ERROR:)') { throw 'Import failed; launch cancelled.' }
        Write-Output 'W5_2_OWNER_IMPORT_PASS'
        $arguments = @('--path', ('"' + $repositoryRoot + '"'))
        if ($RuntimeLogPath) { $arguments += @('--log-file', ('"' + [IO.Path]::GetFullPath($RuntimeLogPath) + '"')) }
        foreach ($arg in $SessionArguments) { if ($arg.Contains('"')) { throw 'Invalid quote in launch argument.' } }
        $arguments += '--'
        $arguments += @($SessionArguments | ForEach-Object { '"' + $_ + '"' })
        # The owner explicitly requested an interactive game window.
        $game = Start-Process -FilePath $graphicalPath -WorkingDirectory $repositoryRoot -ArgumentList $arguments -PassThru
        Write-Output "W5_2_OWNER_LAUNCH_STARTED pid=$($game.Id)"
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        $sha.Dispose()
    }
}