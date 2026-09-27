# photos2kmz.ps1 - Google Earth view of a geotagged shoot.
# Builds one KMZ with every geotagged photo as a thumbnail pin (click for a larger
# preview, file name and time), the GPS track of the shoot, and time stamps so
# Google Earth's time slider replays it.
#
#   .\photos2kmz.ps1 -Folder I:\nikon\1134
#   .\photos2kmz.ps1 -Folder I:\nikon\1134 -Out D:\shoot.kmz
param(
    [Parameter(Mandatory)][string]$Folder,
    [string]$GpxDir = 'I:\gps\ingest',
    [string]$Out
)
$ExifTool = "$env:LOCALAPPDATA\Programs\ExifTool\ExifTool.exe"
if (-not (Test-Path $ExifTool)) { $ExifTool = 'exiftool' }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function Esc($s) { [Security.SecurityElement]::Escape([string]$s) }

$name = Split-Path $Folder -Leaf
if (-not $Out) { $Out = Join-Path $GpxDir "$name photos.kmz" }
$work = Join-Path $env:TEMP "photos2kmz_$name"
if (Test-Path $work) { Get-ChildItem $work -File | ForEach-Object { [IO.File]::Delete($_.FullName) } }
New-Item -ItemType Directory -Force "$work\files" | Out-Null

# 1. Positions and times of the geotagged photos
$meta = & $ExifTool -j -n -q -if '$GPSLatitude' -GPSLatitude -GPSLongitude -GPSAltitude `
        -SubSecDateTimeOriginal -DateTimeOriginal -FileName -XMP-iptcCore:Location -XMP-photoshop:City -XMP-photoshop:State -ext NEF -ext JPG -ext HIF $Folder 2>$null |
        Out-String | ConvertFrom-Json
if (-not $meta) { Write-Host "No geotagged photos in $Folder" -ForegroundColor Yellow; return }

# 2. The camera's embedded preview JPEG, one ExifTool call for the folder
& $ExifTool -q -b -PreviewImage -w "$work\files\%f.jpg" -ext NEF -ext HIF $Folder 2>$null
& $ExifTool -q -b -ThumbnailImage -w "$work\files\%f.jpg" -ext JPG $Folder 2>$null

# 3. Track(s) overlapping the shoot, from the ingested GPX files
$tLo = ($meta | ForEach-Object { $_.SubSecDateTimeOriginal } | ForEach-Object {
          [datetimeoffset]::Parse(($_ -replace '^(\d{4}):(\d\d):(\d\d)', '$1-$2-$3')) } |
        Sort-Object | Select-Object -First 1).UtcDateTime
$tHi = ($meta | ForEach-Object { $_.SubSecDateTimeOriginal } | ForEach-Object {
          [datetimeoffset]::Parse(($_ -replace '^(\d{4}):(\d\d):(\d\d)', '$1-$2-$3')) } |
        Sort-Object | Select-Object -Last 1).UtcDateTime
$lines = @()
foreach ($g in (Get-ChildItem $GpxDir -Filter *.gpx -ErrorAction SilentlyContinue)) {
    $txt = (Get-Content $g.FullName -Raw) -replace "`0", ''
    $pts = [regex]::Matches($txt, '<trkpt lat="([-\d.]+)" lon="([-\d.]+)">[\s\S]*?<time>([^<]+)</time>')
    if ($pts.Count -lt 2) { continue }
    $first = [datetime]::Parse($pts[0].Groups[3].Value).ToUniversalTime()
    $last  = [datetime]::Parse($pts[$pts.Count - 1].Groups[3].Value).ToUniversalTime()
    if ($last -lt $tLo.AddHours(-1) -or $first -gt $tHi.AddHours(1)) { continue }
    $coords = ($pts | ForEach-Object { "$($_.Groups[2].Value),$($_.Groups[1].Value),0" }) -join ' '
    $lines += "<Placemark><name>$(Esc $g.BaseName)</name><styleUrl>#track</styleUrl><LineString><tessellate>1</tessellate><coordinates>$coords</coordinates></LineString></Placemark>"
}

# 4. KML
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<kml xmlns="http://www.opengis.net/kml/2.2"><Document>')
[void]$sb.AppendLine("<name>$(Esc $name) photos</name>")
[void]$sb.AppendLine('<Style id="track"><LineStyle><color>ff00a5ff</color><width>3</width></LineStyle></Style>')
[void]$sb.AppendLine("<Folder><name>Track</name>$($lines -join "`n")</Folder>")
[void]$sb.AppendLine("<Folder><name>Photos ($($meta.Count))</name>")
$n = 0
foreach ($m in ($meta | Sort-Object SubSecDateTimeOriginal)) {
    $base = [IO.Path]::GetFileNameWithoutExtension($m.FileName)
    $img  = "files/$base.jpg"
    if (-not (Test-Path "$work\$($img -replace '/', '\')")) { continue }
    $dto  = [datetimeoffset]::Parse(($m.SubSecDateTimeOriginal -replace '^(\d{4}):(\d\d):(\d\d)', '$1-$2-$3'))
    $local = $dto.ToString('yyyy-MM-dd HH:mm:ss')
    # "Place - City, State" (inside CDATA, so plain text; no XML escaping)
    $cityState = @($m.City, $m.State) | Where-Object { $_ }
    $where = @($m.Location, ($cityState -join ', ')) | Where-Object { $_ }
    $where = ($where -join ' - ') -replace ']]>', ''
    $id = "p$n"; $n++
    [void]$sb.AppendLine(@"
<Placemark><name></name>
<Style><IconStyle><scale>1.4</scale><Icon><href>$(Esc $img)</href></Icon></IconStyle><LabelStyle><scale>0</scale></LabelStyle>
<BalloonStyle><text>`$[description]</text></BalloonStyle></Style>
<description><![CDATA[<img src="$img" width="640"/><br/><b>$local</b><br/>$where<br/>$($m.FileName)]]></description>
<TimeStamp><when>$($dto.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ'))</when></TimeStamp>
<Point><coordinates>$($m.GPSLongitude),$($m.GPSLatitude),0</coordinates></Point></Placemark>
"@)
}
[void]$sb.AppendLine('</Folder></Document></kml>')
[IO.File]::WriteAllText("$work\doc.kml", $sb.ToString(), (New-Object Text.UTF8Encoding $false))

# 5. Zip doc.kml first (Google Earth reads the first .kml), then the images
if (Test-Path $Out) { [IO.File]::Delete($Out) }
$zip = [IO.Compression.ZipFile]::Open($Out, 'Create')
[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$work\doc.kml", 'doc.kml')
Get-ChildItem "$work\files" -File | ForEach-Object {
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "files/$($_.Name)", 'NoCompression')
}
$zip.Dispose()
Write-Host ("KMZ    {0}  ({1} photos, {2} track(s), {3:N0} MB)" -f $Out, $n, $lines.Count, ((Get-Item $Out).Length / 1MB)) -ForegroundColor Green
