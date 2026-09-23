# Trega - Windows setup script
# Run once on your PC to clone (or update) the repo and prepare the Flutter app.
# From PowerShell:  powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
# If your folder isn't at the default location, pass it explicitly:
#   powershell -ExecutionPolicy Bypass -File <path>\setup-windows.ps1 -TargetDir "<repo root>"

param(
  [string]$TargetDir = "$env:USERPROFILE\Downloads\trega"
)

$ErrorActionPreference = "Stop"
$repoUrl = "https://github.com/dhruvesh1707/tregaXmuse.git"

function Need($cmd, $hint) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Host "Missing '$cmd'. $hint" -ForegroundColor Red
    exit 1
  }
  Write-Host "found: $cmd" -ForegroundColor Green
}

Write-Host "== 1. Checking tools ==" -ForegroundColor Cyan
Need flutter "Install Flutter: https://docs.flutter.dev/get-started/install/windows"
Need git     "Install Git: https://git-scm.com/download/win"
Need dart    "dart ships with Flutter - make sure Flutter's bin is on PATH"

Write-Host "`n== 2. Getting the repo ==" -ForegroundColor Cyan
if (Test-Path (Join-Path $TargetDir ".git")) {
  Write-Host "Repo already cloned - pulling latest..."
  git -C $TargetDir pull
} elseif ((Test-Path $TargetDir) -and ((Get-ChildItem $TargetDir -Force | Measure-Object).Count -gt 0)) {
  # ZIP download from GitHub: link the folder to the repo in place.
  Write-Host "Folder exists but is not a git repo (ZIP download) - linking it to GitHub..."
  git -C $TargetDir init -q
  git -C $TargetDir remote add origin $repoUrl 2>$null
  git -C $TargetDir fetch origin -q
  git -C $TargetDir checkout -f -B main origin/main
  Write-Host "Linked. Future runs will just 'git pull'." -ForegroundColor Green
} else {
  Write-Host "Cloning into $TargetDir ..."
  git clone $repoUrl $TargetDir
}

$app = Join-Path $TargetDir "trega_app"
if (-not (Test-Path (Join-Path $app "pubspec.yaml"))) {
  Write-Host "trega_app not found under $TargetDir" -ForegroundColor Red
  exit 1
}
Set-Location $app

Write-Host "`n== 3. Platform folders (android/ios/web) ==" -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $app "android"))) {
  Write-Host "Generating platform folders (project name 'trega' -> com.trega.trega)..."
  flutter create --org com.trega --project-name trega .
} else {
  Write-Host "android/ already exists - skipping flutter create"
}

Write-Host "`n== 4. flutterfire CLI ==" -ForegroundColor Cyan
if (-not (Get-Command flutterfire -ErrorAction SilentlyContinue)) {
  Write-Host "Installing flutterfire_cli..."
  dart pub global activate flutterfire_cli
}
$pubBin = Join-Path $env:LOCALAPPDATA "Pub\Cache\bin"
if ($env:Path -notlike "*$pubBin*") {
  Write-Host "" 
  Write-Host "flutterfire installed but NOT on PATH." -ForegroundColor Yellow
  Write-Host "Add this to your PATH, then restart the terminal and re-run this script:" -ForegroundColor Yellow
  Write-Host "  $pubBin" -ForegroundColor Yellow
  exit 1
}

Write-Host "`n== 5. Firebase config (interactive - pick Android, iOS, Web) ==" -ForegroundColor Cyan
flutterfire configure --project=tregaxmuse

Write-Host "`n== 6. Packages + analyze ==" -ForegroundColor Cyan
flutter pub get
flutter analyze

Write-Host "`nDone. Next: enable Phone Auth + Firestore + Storage in the Firebase console," -ForegroundColor Green
Write-Host "create the 9 composite indexes, and set the 4 function secrets (see trega_functions README)." -ForegroundColor Green
