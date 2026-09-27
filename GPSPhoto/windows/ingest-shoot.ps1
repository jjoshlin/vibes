# ingest-shoot.ps1 - copy a Nikon card into the next numbered folder, then geotag.
# Replaces Nikon Transfer 2 for the copy step but keeps its folder counter and its
# file naming, so NT2 and this script can be used interchangeably.
#
#   .\ingest-shoot.ps1                 # card auto-detected, prefix/number from NT2
#   .\ingest-shoot.ps1 -Prefix "Sulphur hoco " -WhatIf    # show the plan only
#   .\ingest-shoot.ps1 -NoGeotag -NoGps                   # copy only
#
# Naming (same as NT2 "prefix + date/time to the minute"):
#   <Prefix>_MM_dd_yyyy_HH_mm_.NEF       first shot in that minute
#   <Prefix>_MM_dd_yyyy_HH_mm__01.NEF    next shots in the same minute, capture order
param(
    [string]$Source,                     # card DCIM folder; auto-detected if omitted
    [string]$Root     = 'I:\nikon',
    [string]$Prefix,                     # default: NT2's current rename prefix
    [int]   $Folder   = 0,               # default: NT2's next folder number
    [string]$GpxDir   = 'I:\gps\ingest',
    [switch]$NoGps,                      # skip pulling tracks from the Pi
    [switch]$NoGeotag,
    [switch]$WhatIf
)

$ExifTool = "$env:LOCALAPPDATA\Programs\ExifTool\ExifTool.exe"
if (-not (Test-Path $ExifTool)) { $ExifTool = 'exiftool' }
$Common   = 'HKCU:\Software\Nikon\Common\Transfer'
$Exts     = '.NEF', '.NRW', '.JPG', '.JPEG', '.HIF', '.HEIF', '.TIF', '.MOV', '.MP4'

# --- 1. Where from, where to ---------------------------------------------------
if (Get-Process NktTransfer2 -ErrorAction SilentlyContinue) {
    Write-Host 'Nikon Transfer 2 is running; it may advance the folder counter under us.' -ForegroundColor Yellow
    Write-Host 'Close it first, or pass -Folder <number> explicitly.' -ForegroundColor Yellow
    if (-not $WhatIf -and $Folder -le 0) { return }
}
if (-not $Source) {
    $vol = Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\DCIM") } |
           Select-Object -First 1
    if (-not $vol) { Write-Host 'No card with a DCIM folder found.' -ForegroundColor Red; return }
    $Source = "$($vol.DriveLetter):\DCIM"
}
$renFolder = Get-Item 'HKCU:\Software\Nikon\NkFramework\Nikon Transfer 2\Services\RenameFolder'
$renFile   = Get-Item 'HKCU:\Software\Nikon\NkFramework\Nikon Transfer 2\Services\RenameFile'
if ($Folder -le 0) { $Folder = [int]$renFolder.GetValue('StartNumber') }
if (-not $Prefix)  { $Prefix = [string]$renFile.GetValue('Prefix') }
$Dest = Join-Path $Root ('{0:D4}' -f $Folder)
Write-Host "Card:   $Source"
Write-Host "Folder: $Dest"
Write-Host "Prefix: '$Prefix'"

# --- 2. Read capture times (one ExifTool call for the whole card) --------------
$files = Get-ChildItem $Source -Recurse -File | Where-Object { $Exts -contains $_.Extension.ToUpper() }
if (-not $files) { Write-Host 'No photos on the card.' -ForegroundColor Yellow; return }
$json  = & $ExifTool -j -q -DateTimeOriginal -SubSecTimeOriginal -CreateDate -FileName -Directory -d '%Y:%m:%d %H:%M:%S' $Source -r 2>$null | Out-String
$meta  = $json | ConvertFrom-Json | Where-Object { $Exts -contains ([IO.Path]::GetExtension($_.FileName).ToUpper()) }

$items = foreach ($m in $meta) {
    $dt = if ($m.DateTimeOriginal) { $m.DateTimeOriginal } else { $m.CreateDate }
    $t  = [datetime]::ParseExact($dt, 'yyyy:MM:dd HH:mm:ss', $null)
    $ss = if ($m.SubSecTimeOriginal) { [double]("0." + $m.SubSecTimeOriginal) } else { 0 }
    [pscustomobject]@{
        Path = Join-Path ($m.Directory -replace '/', '\') $m.FileName
        Time = $t.AddSeconds($ss)
        Ext  = [IO.Path]::GetExtension($m.FileName).ToUpper()
    }
}

# --- 3. Names: first shot in a minute bare, the rest _01, _02 ... ---------------
$plan = @()
foreach ($g in ($items | Sort-Object Time, Path | Group-Object { $_.Time.ToString('MM_dd_yyyy_HH_mm') + $_.Ext })) {
    $i = 0
    foreach ($it in $g.Group) {
        $base = "{0}_{1}_" -f $Prefix, $it.Time.ToString('MM_dd_yyyy_HH_mm')
        $name = if ($i -eq 0) { "$base$($it.Ext)" } else { "{0}_{1:D2}{2}" -f $base, $i, $it.Ext }
        $plan += [pscustomobject]@{ Src = $it.Path; Dst = Join-Path $Dest $name; Size = (Get-Item $it.Path).Length }
        $i++
    }
}
Write-Host "$($plan.Count) files to ingest"
if ($WhatIf) { $plan | Select-Object -First 15 @{n='From';e={Split-Path $_.Src -Leaf}}, @{n='To';e={Split-Path $_.Dst -Leaf}} | Format-Table -AutoSize; return }

# --- 4. Copy, skipping files already there with the same size, verify size -----
New-Item -ItemType Directory -Force $Dest | Out-Null
$copied = 0; $skipped = 0; $bad = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($p in $plan) {
    if ((Test-Path $p.Dst) -and (Get-Item $p.Dst).Length -eq $p.Size) { $skipped++; continue }
    Copy-Item $p.Src $p.Dst -Force
    if ((Get-Item $p.Dst).Length -eq $p.Size) { $copied++ } else { $bad += $p.Dst }
}
$sw.Stop()
$gb = ($plan | Measure-Object Size -Sum).Sum / 1GB
Write-Host ("Copied {0}, already there {1}, failed {2}  ({3:N1} GB in {4:N0} s)" -f $copied, $skipped, $bad.Count, $gb, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
if ($bad) { $bad | ForEach-Object { Write-Host "SIZE MISMATCH $_" -ForegroundColor Red }; return }

# --- 5. Advance Nikon Transfer's counter so NT2 continues after this folder -----
$next = [int]$renFolder.GetValue('StartNumber')
if ($Folder -ge $next) {
    Set-ItemProperty $renFolder.PSPath -Name StartNumber -Value ($Folder + 1)
    Set-ItemProperty "$Common\Destination"       -Name PrimaryPath       -Value $Root -ErrorAction SilentlyContinue
    Set-ItemProperty "$Common\TransferredFolder" -Name LatestPrimaryPath -Value $Dest -ErrorAction SilentlyContinue
    Write-Host "Nikon Transfer: next folder is now $('{0:D4}' -f ($Folder + 1)), destination $Root"
}

# --- 6. Pull tracks from the Pi, then geotag ------------------------------------
if (-not $NoGps) {
    $get = Join-Path $PSScriptRoot 'getPhotoGPS.ps1'
    if (Test-Path $get) {
        Write-Host "`nPulling GPS tracks from the Pi..."
        $src = (Get-Content $get -Raw) -replace '(?m)^explorer \$Dest\s*$', ''
        & ([scriptblock]::Create($src))   # child scope: its $Dest must not replace ours
    }
}
if ($NoGeotag) { return }
$gpx = Get-ChildItem $GpxDir -Filter *.gpx -ErrorAction SilentlyContinue
if (-not $gpx) { Write-Host "No GPX files in $GpxDir; skipping geotag." -ForegroundColor Yellow; return }

# Match on the camera's own capture time incl. its UTC offset; only interpolate
# across gaps up to 5 min and never extrapolate more than 60 s past a track.
$argFile = Join-Path $env:TEMP 'ingest-geotag.args'
$geoArgs = @('-api', 'GeoMaxIntSecs=300', '-api', 'GeoMaxExtSecs=60') +
        ($gpx | ForEach-Object { '-geotag'; $_.FullName }) +
        @('-geotime<SubSecDateTimeOriginal', '-ext', 'NEF', '-ext', 'JPG', '-ext', 'HIF', $Dest)
[IO.File]::WriteAllLines($argFile, $geoArgs)
Write-Host "`nGeotagging $Dest from $($gpx.Count) track(s)..."
& $ExifTool -@ $argFile 2>&1 | Where-Object { $_ -notmatch 'Warning: No track points' } | Select-Object -Last 6
$tagged = (& $ExifTool -q -q -if '$GPSLatitude' -p '$FileName' -ext NEF -ext JPG -ext HIF $Dest 2>$null | Measure-Object).Count
Write-Host "$tagged of $($plan.Count) photos now have GPS." -ForegroundColor Green
$p2k = Join-Path $PSScriptRoot 'photos2kmz.ps1'
if (Test-Path $p2k) { & $p2k -Folder $Dest -GpxDir $GpxDir }
Write-Host "ExifTool kept the untouched originals as *_original; delete them once you're happy:"
Write-Host "  & '$ExifTool' -delete_original! '$Dest'"
