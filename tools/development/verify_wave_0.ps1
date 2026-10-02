[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $GodotExecutable
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$godotPath = (Resolve-Path -LiteralPath $GodotExecutable).Path
$profileRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('leyforge-wave0-profile-' + [Guid]::NewGuid().ToString('N'))
$profileRoot = [System.IO.Path]::GetFullPath($profileRoot)
$expectedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())

if (-not $profileRoot.StartsWith($expectedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create a validation profile outside the system temporary directory: $profileRoot"
}

$versionOutput = @(& $godotPath --version 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Godot version check failed with exit code $LASTEXITCODE."
}

$version = ($versionOutput | Select-Object -First 1).ToString().Trim()
if ($version -match '^4\.(6\.3|7\.1)(\.|$)') {
    throw "Godot $version is blocked for Leyforge automation."
}

New-Item -ItemType Directory -Path (Join-Path $profileRoot 'appdata') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $profileRoot 'localappdata') -Force | Out-Null
$env:APPDATA = Join-Path $profileRoot 'appdata'
$env:LOCALAPPDATA = Join-Path $profileRoot 'localappdata'

try {
    Write-Output "GODOT_VERSION=$version"
    Write-Output "PROJECT_PATH=$repositoryRoot"

    $editorOutput = @(& $godotPath --headless --editor --path $repositoryRoot --quit 2>&1)
    $editorExitCode = $LASTEXITCODE
    $editorOutput | ForEach-Object { Write-Output $_ }
    if ($editorExitCode -ne 0) {
        throw "Headless editor import failed with exit code $editorExitCode."
    }
    if (($editorOutput -join [Environment]::NewLine) -match 'ERROR:') {
        throw 'Headless editor import reported an error.'
    }

    $startupOutput = @(& $godotPath --headless --path $repositoryRoot 2>&1)
    $startupExitCode = $LASTEXITCODE
    $startupOutput | ForEach-Object { Write-Output $_ }
    $startupText = $startupOutput -join [Environment]::NewLine
    if ($startupExitCode -ne 0) {
        throw "Startup scene failed with exit code $startupExitCode."
    }
    if ($startupText -notmatch 'LEYFORGE_WAVE_0_BOOTSTRAP_READY') {
        throw 'Startup scene did not emit its bootstrap-ready marker.'
    }
    if ($startupText -notmatch 'LEYFORGE_VOXEL_PLUGIN_READY class=VoxelTerrain') {
        throw 'Voxel Tools did not emit its registration marker.'
    }
    if ($startupText -match 'ERROR:') {
        throw 'Startup scene reported an error.'
    }

    Write-Output 'WAVE_0_VALIDATION_PASS'
}
finally {
    if (Test-Path -LiteralPath $profileRoot) {
        Remove-Item -LiteralPath $profileRoot -Recurse -Force
    }
}
