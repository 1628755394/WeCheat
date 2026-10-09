# Desktop and Web share the Dart parser for cc-switch JSON and Codex TOML.
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $projectRoot
try {
  & dart run tool/export_ccswitch.dart
  if ($LASTEXITCODE -ne 0) { throw 'cc-switch export failed' }
} finally {
  Pop-Location
}
