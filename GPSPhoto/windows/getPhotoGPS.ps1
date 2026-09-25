# getPhotoGPS.ps1 - move GPX tracks from PI_GPS into I:\gps\ingest
# Each file is renamed  track_YYYYMMDD_HHMMSSZ_ingested_YYYYMMDD.gpx
# Files are deleted from the Pi only after the copy is verified by size.
# The track the logger is still writing is copied but never deleted.

$Pi           = 'pigps@pigps.local'
$Dest         = 'I:\gps\ingest'
$RemoveFromPi = $true            # $false = copy only, leave everything on the Pi
$Stamp        = Get-Date -Format 'yyyyMMdd'
$Ssh          = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')

if (-not (Test-Path 'I:\')) { Write-Host "Drive I: not found." -ForegroundColor Red; return }
New-Item -ItemType Directory -Force $Dest | Out-Null

# 1. List tracks on the Pi (name:size) and find the file being written right now
$list = ssh @Ssh $Pi 'cd ~/tracks && stat -c %n:%s *.gpx 2>/dev/null; echo ACTIVE:$(ls -1t *.gpx 2>/dev/null | head -1):$(systemctl is-active pigps-logger)'
if ($LASTEXITCODE -ne 0 -and -not $list) { Write-Host "Cannot reach $Pi" -ForegroundColor Red; return }

$remote = @{}
$active = $null
foreach ($line in $list) {
    if ($line -like 'ACTIVE:*') {
        $p = $line.Split(':')
        if ($p[2] -eq 'active' -and $p[1]) { $active = $p[1] }
    } elseif ($line -match '^(.+\.gpx):(\d+)$') {
        $remote[$Matches[1]] = [int64]$Matches[2]
    }
}
if ($remote.Count -eq 0) { Write-Host "No tracks on the Pi." -ForegroundColor Yellow; return }

# 2. Copy everything to a temporary staging folder
$Staging = Join-Path $env:TEMP ("pigps_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $Staging | Out-Null
scp @Ssh "${Pi}:tracks/*.gpx" $Staging
if ($LASTEXITCODE -ne 0) { Write-Host "scp failed." -ForegroundColor Red; return }

# 3. Verify, rename with ingest date, move into $Dest
$done = @()
foreach ($name in $remote.Keys | Sort-Object) {
    $src = Join-Path $Staging $name
    if (-not (Test-Path $src)) { Write-Host "MISSING  $name" -ForegroundColor Red; continue }

    $base   = [IO.Path]::GetFileNameWithoutExtension($name)
    $target = Join-Path $Dest "${base}_ingested_$Stamp.gpx"
    $ok     = (Get-Item $src).Length -eq $remote[$name]
    Move-Item $src $target -Force

    if ($name -eq $active) {
        Write-Host "COPIED   $name  (still being logged, left on Pi)" -ForegroundColor Cyan
    } elseif ($ok) {
        Write-Host "OK       $name" -ForegroundColor Green
        $done += $name
    } else {
        Write-Host "SIZE?    $name  (copied, left on Pi)" -ForegroundColor Yellow
    }
}
Remove-Item $Staging -Recurse -Force -ErrorAction SilentlyContinue

# 4. Remove verified files from the Pi
if ($RemoveFromPi -and $done.Count) {
    ssh @Ssh $Pi ('rm -f ' + (($done | ForEach-Object { "tracks/$_" }) -join ' '))
    if ($LASTEXITCODE -eq 0) { Write-Host "Removed $($done.Count) file(s) from the Pi." }
}

explorer $Dest
