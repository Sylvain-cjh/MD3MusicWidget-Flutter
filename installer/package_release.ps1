param(
  [string]$OutputDir = (Join-Path $PSScriptRoot 'output')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$installerText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MD3MusicWidget.iss'))
$versionMatch = [regex]::Match($installerText, '#define\s+MyAppVersion\s+"([^"]+)"')
if (-not $versionMatch.Success) { throw 'Unable to read MyAppVersion.' }
$version = $versionMatch.Groups[1].Value
$packageName = "MD3MusicWidget-Portable-$version"
$portablePath = Join-Path $OutputDir "$packageName.zip"
$temporaryPath = "$portablePath.tmp"

$requiredNames = @(
  "MD3MusicWidget-Setup-$version.exe",
  "$packageName.zip",
  "MD3MusicWidget-GitHub-Source-$version.zip"
)
$fetcherSourceName = "MusicFetcher-GitHub-Source-$version.zip"
$names = @($requiredNames)
if (Test-Path -LiteralPath (Join-Path $OutputDir $fetcherSourceName)) {
  $names += $fetcherSourceName
}
foreach ($name in $requiredNames) {
  if ($name -eq "$packageName.zip") { continue }
  if (-not (Test-Path -LiteralPath (Join-Path $OutputDir $name))) {
    throw "Release artifact is missing: $name"
  }
}
foreach ($name in @('music_widget_flutter.exe', 'MusicFetcher.exe', 'runtime\MusicFetcher.exe')) {
  if (-not (Test-Path -LiteralPath (Join-Path $releaseDir $name))) {
    throw "Windows Release file is missing: $name"
  }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
$archiveStream = [IO.File]::Open($temporaryPath, [IO.FileMode]::Create)
try {
  $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    $readme = @(
      "MD3 Music Widget $version Portable Edition",
      '',
      '1. Extract the entire ZIP before running the app.',
      '2. Launch music_widget_flutter.exe.',
      '3. Requires Windows 10 2004 or later, x64, and .NET 8 Runtime x64.',
      '4. If .NET 8 is missing, the app offers the official online installer.',
      '5. Keep MusicFetcher.exe, runtime, data, and all other files together.',
      '6. Click the tray icon to disable mouse passthrough.'
    ) -join "`r`n"
    $entry = $archive.CreateEntry("$packageName/README.txt", [IO.Compression.CompressionLevel]::Optimal)
    $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
    try { $writer.Write($readme) } finally { $writer.Dispose() }

    foreach ($file in (Get-ChildItem -LiteralPath $releaseDir -Recurse -File)) {
      $relative = $file.FullName.Substring($releaseDir.Length).TrimStart('\', '/') -replace '\\', '/'
      $entry = $archive.CreateEntry("$packageName/$relative", [IO.Compression.CompressionLevel]::Optimal)
      $source = [IO.File]::OpenRead($file.FullName)
      $destination = $entry.Open()
      try { $source.CopyTo($destination) } finally { $destination.Dispose(); $source.Dispose() }
    }
  } finally { $archive.Dispose() }
} finally { $archiveStream.Dispose() }

Move-Item -LiteralPath $temporaryPath -Destination $portablePath -Force
$manifestPath = Join-Path $OutputDir "SHA256SUMS-$version.txt"
$lines = foreach ($name in $names) {
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $OutputDir $name)).Hash
  "$hash  $name"
}
[IO.File]::WriteAllLines($manifestPath, $lines, [Text.UTF8Encoding]::new($false))

Get-Item -LiteralPath $portablePath, $manifestPath | Select-Object FullName, Length, LastWriteTime
