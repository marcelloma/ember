"""Verify the SNES portrait assets; optionally retrieve missing originals."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
from PIL import Image

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--download', action='store_true', help='Download missing covers using their source URLs')
args = parser.parse_args()
sources = json.loads((root / 'assets/covers/snes/sources.json').read_text())
for source in sources:
    path = root / 'assets/covers' / source['file']
    if not path.exists() and args.download:
        path.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(source['image'], timeout=45).read()
        path.write_bytes(data)
    if not path.exists():
        raise SystemExit(f"Missing {path}. Download the original from {source['page']}")
    with Image.open(path) as image:
        image.load()
        if image.size != (600, 900):
            raise SystemExit(f'Expected a 600 x 900 portrait: {path} has {image.size}')
    if hashlib.sha256(path.read_bytes()).hexdigest() != source['sha256']:
        raise SystemExit(f'Checksum mismatch: {path}')
    print(f"OK  {source['id']}  600 x 900  ({source['author']})")
