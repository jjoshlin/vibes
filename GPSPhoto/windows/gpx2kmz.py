"""Convert GPX tracks to KMZ for Google Earth.

usage: python gpx2kmz.py <folder or .gpx> [...] [--force]

Writes <name>.kmz next to each <name>.gpx (skips ones already converted unless
--force). Each KMZ has the track as a time-stamped gx:Track (Google Earth's time
slider replays it), a coloured line per segment, and start/end pins.
"""
import glob, os, sys, zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

GPX = '{http://www.topografix.com/GPX/1/1}'


def load_root(path):
    """Parse GPX, repairing files cut off by a power loss (NUL padding, missing
    closing tags) by keeping everything up to the last complete track point."""
    data = open(path, 'rb').read()
    try:
        return ET.fromstring(data), False
    except ET.ParseError:
        text = data.replace(b'\x00', b'')
        end = text.rfind(b'</trkpt>')
        if end < 0:
            raise
        text = text[:end + len(b'</trkpt>')] + b'\n</trkseg></trk></gpx>\n'
        return ET.fromstring(text), True


def read_gpx(path):
    root, repaired = load_root(path)
    if repaired:
        print(f'REPAIR {os.path.basename(path)} (truncated file, kept complete points)')
    ns = GPX if root.tag.startswith(GPX) else ''
    segs = []
    for seg in root.iter(ns + 'trkseg'):
        pts = []
        for p in seg.iter(ns + 'trkpt'):
            ele = p.find(ns + 'ele')
            t = p.find(ns + 'time')
            pts.append((float(p.get('lat')), float(p.get('lon')),
                        float(ele.text) if ele is not None else 0.0,
                        t.text if t is not None else None))
        if pts:
            segs.append(pts)
    return segs


def kml(name, segs):
    pts = [p for s in segs for p in s]
    first, last = pts[0], pts[-1]
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">',
           f'<Document><name>{escape(name)}</name>',
           '<Style id="trk"><LineStyle><color>ff00a5ff</color><width>4</width></LineStyle>'
           '<IconStyle><Icon><href>http://maps.google.com/mapfiles/kml/shapes/track.png</href></Icon></IconStyle></Style>',
           '<Style id="start"><IconStyle><color>ff00ff00</color><Icon><href>http://maps.google.com/mapfiles/kml/paddle/grn-circle.png</href></Icon></IconStyle></Style>',
           '<Style id="end"><IconStyle><color>ff0000ff</color><Icon><href>http://maps.google.com/mapfiles/kml/paddle/red-square.png</href></Icon></IconStyle></Style>',
           f'<Placemark><name>Start {escape(first[3] or "")}</name><styleUrl>#start</styleUrl>'
           f'<Point><coordinates>{first[1]},{first[0]},0</coordinates></Point></Placemark>',
           f'<Placemark><name>End {escape(last[3] or "")}</name><styleUrl>#end</styleUrl>'
           f'<Point><coordinates>{last[1]},{last[0]},0</coordinates></Point></Placemark>']
    for i, seg in enumerate(segs, 1):
        out.append(f'<Placemark><name>Segment {i} ({len(seg)} pts)</name><styleUrl>#trk</styleUrl>')
        if all(p[3] for p in seg):
            out.append('<gx:Track><altitudeMode>clampToGround</altitudeMode>')
            out += [f'<when>{p[3]}</when>' for p in seg]
            out += [f'<gx:coord>{p[1]} {p[0]} {p[2]}</gx:coord>' for p in seg]
            out.append('</gx:Track>')
        else:
            out.append('<LineString><tessellate>1</tessellate><coordinates>')
            out.append(' '.join(f'{p[1]},{p[0]},0' for p in seg))
            out.append('</coordinates></LineString>')
        out.append('</Placemark>')
    out.append('</Document></kml>')
    return '\n'.join(out)


def convert(gpx, force=False):
    kmz = os.path.splitext(gpx)[0] + '.kmz'
    if os.path.exists(kmz) and not force:
        return None
    segs = read_gpx(gpx)
    if not segs:
        print(f'SKIP   {os.path.basename(gpx)} (no track points)')
        return None
    name = os.path.splitext(os.path.basename(gpx))[0]
    with zipfile.ZipFile(kmz, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('doc.kml', kml(name, segs))
    print(f'KMZ    {os.path.basename(kmz)}  ({sum(map(len, segs))} pts, {len(segs)} seg)')
    return kmz


def main():
    args = [a for a in sys.argv[1:] if a != '--force']
    force = '--force' in sys.argv
    files = []
    for a in args:
        files += sorted(glob.glob(os.path.join(a, '*.gpx'))) if os.path.isdir(a) else [a]
    for f in files:
        try:
            convert(f, force)
        except ET.ParseError as e:
            print(f'ERROR  {os.path.basename(f)}: {e}')


if __name__ == '__main__':
    main()
