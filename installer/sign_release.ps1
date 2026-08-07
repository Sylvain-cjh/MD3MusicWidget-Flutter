param(
  [string]$CertificateThumbprint = '',
  [string]$TimestampServer = '',
  [ValidateSet('All', 'Release', 'Setup')]
  [string]$Target = 'All'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$setupPath = Join-Path $PSScriptRoot 'output\MD3MusicWidget-Setup-0.9.16.exe'
$certificatePath = Join-Path $PSScriptRoot 'output\MD3MusicWidget-CodeSigning.cer'
$subject = 'CN=MD3 Music Widget, O=syj'

$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signTool = Get-ChildItem -Path $sdkRoot -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
  Sort-Object FullName -Descending |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $signTool) {
  $signTool = Get-ChildItem -Path $sdkRoot -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $signTool) { throw 'Windows SDK SignTool.exe was not found.' }

$certificate = $null
if ($CertificateThumbprint) {
  $certificate = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
  if (-not $certificate) { throw "Certificate $CertificateThumbprint was not found in CurrentUser\My." }
} else {
  $certificate = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -eq $subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1
}

if (-not $certificate) {
  $certificate = New-SelfSignedCertificate `
    -Subject $subject `
    -Type CodeSigningCert `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -NotAfter (Get-Date).AddYears(3)
}

New-Item -ItemType Directory -Force -Path (Split-Path $certificatePath) | Out-Null
Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null

$targets = @()
if ($Target -in @('All', 'Release')) {
  $targets += Join-Path $releaseDir 'music_widget_flutter.exe'
  $targets += Join-Path $releaseDir 'MusicFetcher.exe'
  $runtimeFetcher = Join-Path $releaseDir 'runtime\MusicFetcher.exe'
  if (Test-Path $runtimeFetcher) { $targets += $runtimeFetcher }
}
if ($Target -in @('All', 'Setup')) { $targets += $setupPath }

foreach ($path in $targets) {
  if (-not (Test-Path $path)) { throw "Signing target is missing: $path" }
  if ($TimestampServer) {
    & $signTool sign /sha1 $certificate.Thumbprint /fd SHA256 /tr $TimestampServer /td SHA256 $path
  } else {
    & $signTool sign /sha1 $certificate.Thumbprint /fd SHA256 $path
  }
  if ($LASTEXITCODE -ne 0) { throw "SignTool failed for $path." }
}

Write-Output "Certificate: $($certificate.Subject)"
Write-Output "Thumbprint: $($certificate.Thumbprint)"
Write-Output "Public certificate: $certificatePath"
foreach ($path in $targets) {
  $signature = Get-AuthenticodeSignature -LiteralPath $path
  [pscustomobject]@{
    Path = $path
    Status = $signature.Status
    Signer = $signature.SignerCertificate.Subject
    Thumbprint = $signature.SignerCertificate.Thumbprint
  }
}
