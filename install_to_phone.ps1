# ShreyX Music - Smart Phone Deployer (ADB + MTP)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$apk = "$PSScriptRoot\build\app\outputs\flutter-apk\app-release.apk"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " ShreyX Music - Phone Deployer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if (-not (Test-Path $apk)) {
    Write-Host "Error: APK not found at $apk" -ForegroundColor Red
    exit 1
}

$shell = New-Object -ComObject Shell.Application

Write-Host "Listening for phone unlock / connection (Press Ctrl+C to cancel)..." -ForegroundColor Yellow

$done = $false
for ($i = 0; $i -lt 120; $i++) {
    # 1. Check ADB
    $devices = & $adb devices 2>$null
    if ($devices -match "(?<id>[A-Za-z0-9]+)\s+device\b") {
        $devId = $Matches['id']
        Write-Host "`n[ADB] Device detected: $devId" -ForegroundColor Green
        Write-Host "[ADB] Installing release APK..." -ForegroundColor Cyan
        & $adb install -r $apk
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[ADB] Installation successful!" -ForegroundColor Green
            Write-Host "[ADB] Setting up port forward tcp:8080 for ShreyX Vibe..." -ForegroundColor Cyan
            & $adb reverse tcp:8080 tcp:8080
            Write-Host "[ADB] Launching ShreyX Music..." -ForegroundColor Cyan
            & $adb shell monkey -p com.shreyx.player -c android.intent.category.LAUNCHER 1
            $done = $true
            break
        }
    } elseif ($devices -match "unauthorized") {
        Write-Host -NoNewline " [ADB: Please tap 'Allow' on your phone screen] "
    }

    # 2. Check MTP (Storage)
    try {
        $myComputer = $shell.NameSpace(0x11)
        $phone = $myComputer.Items() | Where-Object { $_.Name -match "S24|Galaxy|Shreyash" }
        if ($phone) {
            $phoneFolder = $phone.GetFolder
            $storage = $phoneFolder.Items() | Where-Object { $_.Name -match "Internal storage|Phone" }
            if ($storage) {
                Write-Host "`n[MTP] Storage accessible! Copying APK to phone Download folder..." -ForegroundColor Green
                $storageFolder = $storage.GetFolder
                $download = $storageFolder.Items() | Where-Object { $_.Name -match "Download" }
                if ($download) {
                    $targetFolder = $download.GetFolder
                    $targetFolder.CopyHere($apk, 16) # 16 = Respond 'Yes to All' for any dialog
                    Write-Host "[MTP] APK copied to phone's 'Download' folder as app-release.apk!" -ForegroundColor Green
                    # If ADB also worked, great. If not, user has the file ready to tap.
                    if (-not $done) {
                        Write-Host "[MTP] You can open My Files -> Downloads on your phone and tap to install!" -ForegroundColor Cyan
                    }
                }
            }
        }
    } catch {
        # ignore MTP read errors
    }

    if ($done) { break }
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 2
}

if (-not $done) {
    Write-Host "`nListening timed out. Run .\install_to_phone.ps1 again after unlocking your phone." -ForegroundColor Yellow
}
