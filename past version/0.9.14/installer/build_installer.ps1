param(
  [string]$Compiler = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$installerSource = Join-Path $PSScriptRoot 'MD3MusicWidget.iss'

if (-not (Test-Path (Join-Path $releaseDir 'music_widget_flutter.exe'))) {
  throw 'Windows Release build is missing. Run flutter build windows --release first.'
}
if (-not (Test-Path (Join-Path $releaseDir 'MusicFetcher.exe'))) {
  throw 'MusicFetcher.exe is missing from the Windows Release bundle.'
}

if (-not $Compiler) {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
  )
  $Compiler = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Compiler -or -not (Test-Path $Compiler)) {
  throw 'Inno Setup 6 Compiler (ISCC.exe) was not found.'
}

& $Compiler $installerSource
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }

$setup = Join-Path $PSScriptRoot 'output\MD3MusicWidget-Setup-0.9.14.exe'
if (-not (Test-Path $setup)) { throw 'Installer output was not created.' }
Get-Item $setup | Select-Object FullName, Length, LastWriteTime
