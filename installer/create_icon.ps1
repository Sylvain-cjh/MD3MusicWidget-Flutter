param(
  [string]$Source = (Join-Path $PSScriptRoot '..\assets\logo_concepts_fresh\mascot-peek-selected.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logoPath = Join-Path $projectRoot 'assets\logo.png'
$appIconPath = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
$trayPngPath = Join-Path $projectRoot 'images\tray_icon.png'
$trayIconPath = Join-Path $projectRoot 'images\tray_icon.ico'

New-Item -ItemType Directory -Force -Path (Split-Path $logoPath), (Split-Path $appIconPath), (Split-Path $trayPngPath) | Out-Null

function New-RoundedPath([System.Drawing.RectangleF]$rect, [float]$radius) {
  $diameter = $radius * 2
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $path.AddArc($rect.Left, $rect.Top, $diameter, $diameter, 180, 90)
  $path.AddArc($rect.Right - $diameter, $rect.Top, $diameter, $diameter, 270, 90)
  $path.AddArc($rect.Right - $diameter, $rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
  $path.AddArc($rect.Left, $rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
  $path.CloseFigure()
  return $path
}

function New-ScaledPngBytes([System.Drawing.Bitmap]$source, [int]$size) {
  $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $bitmap.SetResolution(96, 96)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $size, $size))
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    return $stream.ToArray()
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

function Write-MultiSizeIco([System.Drawing.Bitmap]$source, [string]$path) {
  $sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
  $images = [System.Collections.Generic.List[byte[]]]::new()
  foreach ($size in $sizes) {
    $images.Add([byte[]](New-ScaledPngBytes $source $size))
  }
  $stream = [System.IO.MemoryStream]::new()
  $writer = [System.IO.BinaryWriter]::new($stream)
  try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$sizes.Count)
    $offset = 6 + (16 * $sizes.Count)
    for ($i = 0; $i -lt $sizes.Count; $i++) {
      $encodedSize = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
      $writer.Write([byte]$encodedSize)
      $writer.Write([byte]$encodedSize)
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([uint16]1)
      $writer.Write([uint16]32)
      $writer.Write([uint32]$images[$i].Length)
      $writer.Write([uint32]$offset)
      $offset += $images[$i].Length
    }
    foreach ($image in $images) { $writer.Write($image) }
    [System.IO.File]::WriteAllBytes($path, $stream.ToArray())
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Write-PlatformPng(
  [System.Drawing.Bitmap]$source,
  [int]$size,
  [string]$path,
  [bool]$opaque,
  [double]$contentScale = 1.0
) {
  $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $bitmap.SetResolution(96, 96)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $background = if ($opaque) { [System.Drawing.Color]::FromArgb(255, 250, 246) } else { [System.Drawing.Color]::Transparent }
    $graphics.Clear($background)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $drawSize = [int][Math]::Round($size * $contentScale)
    $inset = [int][Math]::Floor(($size - $drawSize) / 2)
    $graphics.DrawImage($source, [System.Drawing.Rectangle]::new($inset, $inset, $drawSize, $drawSize))
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

$sourceImage = [System.Drawing.Bitmap]::new([System.IO.Path]::GetFullPath($Source))
$master = [System.Drawing.Bitmap]::new(1024, 1024, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$master.SetResolution(96, 96)
$graphics = [System.Drawing.Graphics]::FromImage($master)
try {
  $graphics.Clear([System.Drawing.Color]::Transparent)
  $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

  $destination = [System.Drawing.Rectangle]::new(0, 0, 1024, 1024)
  if ($sourceImage.GetPixel(0, 0).A -lt 255) {
    $graphics.DrawImage(
      $sourceImage,
      $destination,
      [System.Drawing.Rectangle]::new(0, 0, $sourceImage.Width, $sourceImage.Height),
      [System.Drawing.GraphicsUnit]::Pixel
    )
  } else {
    $inset = [Math]::Round([Math]::Min($sourceImage.Width, $sourceImage.Height) * 0.024)
    $crop = [System.Drawing.Rectangle]::new(
      $inset,
      $inset,
      $sourceImage.Width - (2 * $inset),
      $sourceImage.Height - (2 * $inset)
    )
    $mask = New-RoundedPath ([System.Drawing.RectangleF]::new(0.5, 0.5, 1023, 1023)) 206
    try {
      $graphics.SetClip($mask)
      $graphics.DrawImage($sourceImage, $destination, $crop, [System.Drawing.GraphicsUnit]::Pixel)
    } finally {
      $mask.Dispose()
    }
  }
} finally {
  $graphics.Dispose()
  $sourceImage.Dispose()
}

try {
  $master.Save($logoPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $trayBytes = New-ScaledPngBytes $master 256
  [System.IO.File]::WriteAllBytes($trayPngPath, $trayBytes)
  Write-MultiSizeIco $master $appIconPath
  Copy-Item -LiteralPath $appIconPath -Destination $trayIconPath -Force

  foreach ($entry in @(
    @{ Path = 'android\app\src\main\res\mipmap-mdpi\ic_launcher.png'; Size = 48 },
    @{ Path = 'android\app\src\main\res\mipmap-hdpi\ic_launcher.png'; Size = 72 },
    @{ Path = 'android\app\src\main\res\mipmap-xhdpi\ic_launcher.png'; Size = 96 },
    @{ Path = 'android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png'; Size = 144 },
    @{ Path = 'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'; Size = 192 }
  )) {
    Write-PlatformPng $master $entry.Size (Join-Path $projectRoot $entry.Path) $true
  }

  $iosIconDir = Join-Path $projectRoot 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
  $iosManifest = Get-Content -LiteralPath (Join-Path $iosIconDir 'Contents.json') -Raw | ConvertFrom-Json
  foreach ($entry in $iosManifest.images) {
    $baseSize = [double]($entry.size -split 'x')[0]
    $scale = [double]($entry.scale -replace 'x', '')
    $pixelSize = [int][Math]::Round($baseSize * $scale)
    Write-PlatformPng $master $pixelSize (Join-Path $iosIconDir $entry.filename) $true
  }

  $macIconDir = Join-Path $projectRoot 'macos\Runner\Assets.xcassets\AppIcon.appiconset'
  foreach ($file in Get-ChildItem -LiteralPath $macIconDir -Filter 'app_icon_*.png') {
    if ($file.Name -match 'app_icon_(\d+)\.png') {
      Write-PlatformPng $master ([int]$Matches[1]) $file.FullName $false
    }
  }

  $webRoot = Join-Path $projectRoot 'web'
  Write-PlatformPng $master 32 (Join-Path $webRoot 'favicon.png') $false
  Write-PlatformPng $master 192 (Join-Path $webRoot 'icons\Icon-192.png') $false
  Write-PlatformPng $master 512 (Join-Path $webRoot 'icons\Icon-512.png') $false
  Write-PlatformPng $master 192 (Join-Path $webRoot 'icons\Icon-maskable-192.png') $true 0.8
  Write-PlatformPng $master 512 (Join-Path $webRoot 'icons\Icon-maskable-512.png') $true 0.8
} finally {
  $master.Dispose()
}

Write-Output "Generated $logoPath"
Write-Output "Generated $appIconPath"
Write-Output "Generated $trayPngPath"
Write-Output "Generated $trayIconPath"
Write-Output 'Generated Android, iOS, macOS, and web icon sizes from the same source'
