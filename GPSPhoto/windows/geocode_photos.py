"""Fill Location / City / State / Country for geotagged photos.

usage: python geocode_photos.py <folder> [--dry-run] [--offline]

For each spot (photos grouped on a ~50 m grid) one reverse-geocode lookup:
  * I:\\gps\\places.csv       -> your own place names (name,lat,lon,radius_m)
  * Photon (komoot, OSM data) -> nearest named venue/park/landmark within 200 m
  * OpenStreetMap Nominatim  -> street, ZIP, state, country
  * Zippopotam.us            -> postal city for that ZIP ("city by zip code")
  * ExifTool's built-in GeoNames database -> fallback when offline / no answer
Results are cached in I:\\gps\\geocode_cache.json, so a spot is only looked up once.

Written into each file (Lightroom reads XMP, NX Studio / Windows read IPTC):
  XMP-iptcCore:Location  IPTC:Sub-location            e.g. "The Grove, 123 Main St"
  XMP-photoshop:City     IPTC:City                    postal city of the ZIP
  XMP-photoshop:State    IPTC:Province-State
  XMP-photoshop:Country  IPTC:Country-PrimaryLocationName
  XMP-iptcCore:CountryCode IPTC:Country-PrimaryLocationCode
"""
import json, os, subprocess, sys, tempfile, time, urllib.parse, urllib.request

EXIFTOOL = os.path.expandvars(r'%LOCALAPPDATA%\Programs\ExifTool\ExifTool.exe')
if not os.path.exists(EXIFTOOL):
    EXIFTOOL = 'exiftool'
CACHE = r'I:\gps\geocode_cache.json'
UA = 'PI_GPS-photo-geotag/1.0 (personal photo library; github.com/jjoshlin/vibes)'
GRID = 0.0005                     # ~55 m cells: one lookup per spot
ALPHA3 = {'US': 'USA', 'CA': 'CAN', 'MX': 'MEX', 'GB': 'GBR', 'FR': 'FRA', 'DE': 'DEU',
          'IT': 'ITA', 'ES': 'ESP', 'JP': 'JPN', 'AU': 'AUS', 'NZ': 'NZL', 'IE': 'IRL'}
EXTS = ('.nef', '.jpg', '.jpeg', '.hif', '.heif', '.tif')


def et_json(args):
    out = subprocess.run([EXIFTOOL, '-j', '-n', '-q', *args], capture_output=True, text=True, encoding='utf-8')
    return json.loads(out.stdout or '[]')


def http_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en'})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def nominatim(lat, lon):
    q = urllib.parse.urlencode({'format': 'jsonv2', 'lat': f'{lat:.6f}', 'lon': f'{lon:.6f}',
                                'zoom': 18, 'addressdetails': 1})
    time.sleep(1.1)                                   # usage policy: max 1 request/s
    return http_json('https://nominatim.openstreetmap.org/reverse?' + q)


PLACES = r'I:\gps\places.csv'      # your own names: name,lat,lon,radius_m (checked first)


def my_place(lat, lon):
    if not os.path.exists(PLACES):
        return None
    import csv
    best = None
    for row in csv.reader(open(PLACES, encoding='utf-8-sig')):
        if len(row) < 3 or row[0].strip().lower() == 'name' or row[0].startswith('#'):
            continue
        try:
            plat, plon = float(row[1]), float(row[2])
            rad = float(row[3]) if len(row) > 3 and row[3].strip() else 150
        except ValueError:
            continue
        d = (((plat - lat) * 111320) ** 2 + ((plon - lon) * 111320 * 0.864) ** 2) ** 0.5
        if d <= rad and (best is None or d < best[0]):
            best = (d, row[0].strip())
    return best[1] if best else None


def nearest_place(lat, lon, radius_km=0.2):
    """Closest named venue/park/shop/landmark (not a street) via Photon (OSM data)."""
    try:
        q = urllib.parse.urlencode({'lat': f'{lat:.6f}', 'lon': f'{lon:.6f}', 'limit': 15,
                                    'radius': radius_km, 'lang': 'en'})
        feats = http_json('https://photon.komoot.io/reverse?' + q).get('features', [])
    except Exception:
        return None
    best = None
    for f in feats:
        p = f.get('properties', {})
        if not p.get('name') or p.get('osm_key') in ('highway', 'place', 'boundary', 'landuse', 'railway'):
            continue
        lo, la = f['geometry']['coordinates'][:2]
        d = ((la - lat) * 111320) ** 2 + ((lo - lon) * 111320 * 0.864) ** 2
        if best is None or d < best[0]:
            best = (d, p['name'])
    return best[1] if best else None

def zip_city(cc, zipcode):
    try:
        d = http_json(f'https://api.zippopotam.us/{cc.lower()}/{urllib.parse.quote(zipcode[:5])}')
        return d['places'][0]['place name']
    except Exception:
        return None


def offline(path):
    d = et_json(['-api', 'geolocation', '-GeolocationCity', '-GeolocationRegion',
                 '-GeolocationCountry', '-GeolocationCountryCode', path])
    d = d[0] if d else {}
    return {'city': d.get('GeolocationCity'), 'state': d.get('GeolocationRegion'),
            'country': d.get('GeolocationCountry'), 'cc': d.get('GeolocationCountryCode'),
            'location': None, 'zip': None, 'source': 'offline'}


def lookup(lat, lon, sample_path, use_net):
    if use_net:
        try:
            n = nominatim(lat, lon)
            a = n.get('address', {})
            street = ' '.join(x for x in (a.get('house_number'), a.get('road')) if x)
            location = my_place(lat, lon) or nearest_place(lat, lon) or street or None
            cc = (a.get('country_code') or '').upper() or None
            zipc = a.get('postcode')
            city = (zip_city(cc, zipc) if (cc and zipc) else None) or \
                   a.get('city') or a.get('town') or a.get('village') or a.get('hamlet')
            info = {'location': location, 'city': city, 'state': a.get('state'),
                    'country': a.get('country'), 'cc': cc, 'zip': zipc, 'source': 'osm'}
            if not info['city'] or not info['state']:          # patch gaps offline
                off = offline(sample_path)
                for k in ('city', 'state', 'country', 'cc'):
                    info[k] = info[k] or off[k]
            return info
        except Exception as e:
            print(f'  online lookup failed ({e}); using offline data')
    return offline(sample_path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry, use_net = '--dry-run' in sys.argv, '--offline' not in sys.argv
    folder = args[0]
    photos = [p for p in et_json(['-GPSLatitude', '-GPSLongitude', '-FileName', '-Directory', folder])
              if 'GPSLatitude' in p and p['FileName'].lower().endswith(EXTS)]
    if not photos:
        print('No geotagged photos found.'); return

    cells = {}
    for p in photos:
        key = (round(p['GPSLatitude'] / GRID), round(p['GPSLongitude'] / GRID))
        cells.setdefault(key, []).append(p)
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    print(f'{len(photos)} photos at {len(cells)} spots')

    for key, group in sorted(cells.items(), key=lambda kv: kv[1][0]['FileName']):
        lat = sum(p['GPSLatitude'] for p in group) / len(group)
        lon = sum(p['GPSLongitude'] for p in group) / len(group)
        ck = f'{key[0]},{key[1]}'
        sample = os.path.join(group[0]['Directory'], group[0]['FileName'])
        info = cache.get(ck)
        if not info or (use_net and info.get('source') == 'offline'):
            info = lookup(lat, lon, sample, use_net)
            cache[ck] = info
        print(f"  {len(group):4d} photos  {lat:.5f},{lon:.5f}  "
              f"{info['location'] or '-'} | {info['city']} {info.get('zip') or ''} | {info['state']} | {info['country']}")
        if dry:
            continue
        tags = []
        def put(names, value):
            if value:
                tags.extend(f'-{n}={value}' for n in names)
        put(('XMP-iptcCore:Location', 'IPTC:Sub-location'), info['location'])
        put(('XMP-photoshop:City', 'IPTC:City'), info['city'])
        put(('XMP-photoshop:State', 'IPTC:Province-State'), info['state'])
        put(('XMP-photoshop:Country', 'IPTC:Country-PrimaryLocationName'), info['country'])
        put(('XMP-iptcCore:CountryCode',), info['cc'])
        put(('IPTC:Country-PrimaryLocationCode',), ALPHA3.get(info['cc'] or ''))   # IPTC wants 3 letters
        files = [os.path.join(p['Directory'], p['FileName']) for p in group]
        with tempfile.NamedTemporaryFile('w', suffix='.args', delete=False, encoding='utf-8') as f:
            f.write('\n'.join(['-charset', 'iptc=UTF8', '-IPTC:CodedCharacterSet=UTF8', *tags, *files]))
            argfile = f.name
        subprocess.run([EXIFTOOL, '-q', '-m', '-@', argfile])   # -m: legacy IPTC truncation is fine
        os.remove(argfile)

    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(cache, open(CACHE, 'w'), indent=1)


if __name__ == '__main__':
    main()
