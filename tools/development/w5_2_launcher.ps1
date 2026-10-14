# Shared import/launch mechanism; both owner launchers serialize cache refresh.
function Start-W52Game {
    param([string[]] $SessionArguments, [string] $RuntimeLogPath = '', [string] $GodotRoot = '', [string] $InviteCode = '')
    $repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    $runnerRoot = if ($GodotRoot) { $GodotRoot } else { $env:LEYFORGE_GODOT_ROOT }
    if (-not $runnerRoot) {
        $bundled = Join-Path $repositoryRoot 'runtime'
        $runnerRoot = if (Test-Path (Join-Path $bundled 'godot.windows.editor.x86_64.console.exe')) { $bundled } else { Join-Path (Split-Path $repositoryRoot -Parent) 'leyforge/.local/Godot_v4.8-dev-a9c94-shutdown-fixed' }
    }
    $consolePath = Join-Path $runnerRoot 'godot.windows.editor.x86_64.console.exe'
    $graphicalPath = Join-Path $runnerRoot 'godot.windows.editor.x86_64.exe'
    if ((Get-FileHash -LiteralPath $consolePath).Hash -ne '06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A' -or
        (Get-FileHash -LiteralPath $graphicalPath).Hash -ne '87D0A6077ABE38B905F973B23D9F27FD4F3B7A8DB2309DFD6807FAD7DFF582C8') { throw 'Launcher requires the approved shutdown-fixed runtime pair.' }
    if ($SessionArguments -contains '--session=JOIN' -and -not $InviteCode) {
        # Inherited value supports isolated automation; interactive users enter a masked prompt.
        $InviteCode = $env:LEYFORGE_INVITE
        if (-not $InviteCode) {
            $secure = Read-Host 'Invite Code' -AsSecureString
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $InviteCode = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
        }
        if ($InviteCode -notmatch '^(?:[A-Fa-f0-9]{32}|[A-Fa-f0-9]{4}(?:-[A-Fa-f0-9]{4}){7})$') { throw 'Invalid invite format (32 hex characters, optionally grouped by four).' }
    }
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
        # Shell launch detaches game output from any redirected launcher pipe.
        # Environment changes are process-local and restored immediately; no registry writes.
        $previousInvite = $env:LEYFORGE_INVITE
        try {
            if ($InviteCode) { $env:LEYFORGE_INVITE = $InviteCode }
            $game = Start-Process -FilePath $graphicalPath -ArgumentList $arguments -WorkingDirectory $repositoryRoot -WindowStyle Normal -PassThru
        } finally {
            if ($null -eq $previousInvite) { Remove-Item Env:LEYFORGE_INVITE -ErrorAction SilentlyContinue }
            else { $env:LEYFORGE_INVITE = $previousInvite }
            $previousInvite = $null
        }
        $InviteCode = $null
        Write-Output "W5_2_OWNER_LAUNCH_STARTED pid=$($game.Id)"
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        $sha.Dispose()
        $InviteCode = $null
    }
}