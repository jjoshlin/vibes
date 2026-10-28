"""Geotag photos that fell into GPS gaps, but only when it's safe.

usage: python geotag_gaps.py <folder> [--gpx-dir I:\\gps\\ingest] [--max-gap-min 180]
                             [--max-move-m 150] [--dry-run]

Run after the normal ExifTool geotag. For each photo still without GPS it finds the
last fix before and the first fix after the capture time. If both exist, are at most
--max-gap-min apart and less than --max-move-m from each other (you stayed put:
indoors, under trees, or the logger skipped points while you stood still), the photo
gets the position interpolated between them. Otherwise it is left alone and the
reason is reported. Writes EXIF GPS with ExifTool (keeps *_original backups unless
--overwrite).
"""
import bisect, glob, json, math, os, re, subprocess, sys, tempfile
from datetime import datetime, timezone

EXIFTOOL = os.path.expandvars(r'%LOCALAPPDATA%\Programs\ExifTool\ExifTool.exe')
if not os.path.exists(EXIFTOOL):
    EXIFTOOL = 'exiftool'
PT = re.compile(rb'<trkpt lat="([-\d.]+)" lon="([-\d.]+)">[\s\S]*?<time>([^<]+)</time>')


def opt(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def utc(s):
    s = s.strip().replace('Z', '+00:00')
    s = re.sub(r'^(\d{4}):(\d\d):(\d\d)', r'\1-\2-\3', s)
    return datetime.fromisoformat(s).astimezone(timezone.utc).timestamp()


def dist_m(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371000 * math.asin(math.sqrt(h))


def main():
    folder = [a for a in sys.argv[1:] if not a.startswith('--') and
              sys.argv[sys.argv.index(a) - 1] not in ('--gpx-dir', '--max-gap-min', '--max-move-m')][0]
    gpx_dir = opt('--gpx-dir', r'I:\gps\ingest')
    max_gap = float(opt('--max-gap-min', 180)) * 60
    max_move = float(opt('--max-move-m', 150))
    dry = '--dry-run' in sys.argv

    pts = []
    for g in glob.glob(os.path.join(gpx_dir, '*.gpx')):
        data = open(g, 'rb').read().replace(b'\x00', b'')
        for m in PT.finditer(data):
            try:
                pts.append((utc(m.group(3).decode()), float(m.group(1)), float(m.group(2))))
            except ValueError:
                pass
    pts.sort()
    times = [p[0] for p in pts]
    print(f'{len(pts)} GPS fixes loaded')

    out = subprocess.run([EXIFTOOL, '-j', '-q', '-if', 'not $GPSLatitude', '-SubSecDateTimeOriginal',
                          '-DateTimeOriginal', '-OffsetTimeOriginal', '-FileName', '-Directory',
                          '-ext', 'NEF', '-ext', 'JPG', '-ext', 'HIF', folder],
                         capture_output=True, text=True, encoding='utf-8')
    photos = json.loads(out.stdout or '[]')
    print(f'{len(photos)} photos without GPS')

    fixes, skipped = [], {}
    for p in photos:
        ts = p.get('SubSecDateTimeOriginal') or (
            p.get('DateTimeOriginal', '') + (p.get('OffsetTimeOriginal') or ''))
        try:
            t = utc(ts)
        except ValueError:
            skipped['no usable capture time/offset'] = skipped.get('no usable capture time/offset', 0) + 1
            continue
        i = bisect.bisect_left(times, t)
        if i == 0 or i == len(pts):
            skipped['outside all tracks'] = skipped.get('outside all tracks', 0) + 1
            continue
        a, b = pts[i - 1], pts[i]
        gap, move = b[0] - a[0], dist_m(a[1:], b[1:])
        if gap > max_gap:
            k = f'gap > {max_gap / 60:.0f} min (logger off / no fix)'
            skipped[k] = skipped.get(k, 0) + 1
            continue
        if move > max_move:
            k = f'moved > {max_move:.0f} m across the gap'
            skipped[k] = skipped.get(k, 0) + 1
            continue
        f = (t - a[0]) / gap if gap else 0
        lat, lon = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
        fixes.append((os.path.join(p['Directory'], p['FileName']), lat, lon, gap, move))

    print(f'{len(fixes)} can be placed safely')
    for reason, n in skipped.items():
        print(f'  left untagged: {n:4d}  {reason}')
    if dry or not fixes:
        return
    keep = ['-overwrite_original'] if '--overwrite' in sys.argv else []
    lines = []
    for path, lat, lon, _, _ in fixes:      # one ExifTool -execute block per photo
        lines += keep + [f'-GPSLatitude={abs(lat):.7f}', f'-GPSLatitudeRef={"N" if lat >= 0 else "S"}',
                         f'-GPSLongitude={abs(lon):.7f}', f'-GPSLongitudeRef={"E" if lon >= 0 else "W"}',
                         '-GPSMapDatum=WGS-84', path, '-execute']
    with tempfile.NamedTemporaryFile('w', suffix='.args', delete=False, encoding='utf-8') as fh:
        fh.write('\n'.join(lines))
        argfile = fh.name
    subprocess.run([EXIFTOOL, '-q', '-m', '-@', argfile])
    os.remove(argfile)
    print(f'wrote GPS to {len(fixes)} photos')


if __name__ == '__main__':
    main()
