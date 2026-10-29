# Windows twin of tool/bootstrap.sh.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
flutter create --org com.oryvex --project-name oryvexcore --platforms windows .
$cmake = "windows/CMakeLists.txt"
if (Test-Path $cmake) {
  (Get-Content $cmake) -replace 'set\(BINARY_NAME "oryvexcore"\)', 'set(BINARY_NAME "OryvexVPN")' | Set-Content $cmake
}
git checkout -- test/widget_test.dart 2>$null
flutter pub get
Write-Host "desktop bootstrap done"
