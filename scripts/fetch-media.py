#!/usr/bin/env python3
"""Fetch the pinned release's media without adding large files to Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
from urllib.request import urlopen
import zipfile


MEDIA = {
    'assets/cloud-swift.mp4': 'CloudSwift.mp4',
    'assets/cloud-cirrus.mp4': 'CloudCirrus.mp4',
    'assets/audio/clock-minute.wav': 'ClockMinute.wav',
}
CHUNK = 1024 * 1024


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(CHUNK), b''):
            value.update(block)
    return value.hexdigest()


def validate_manifest(root, manifest):
    if not isinstance(manifest, dict):
        raise ValueError('Expected a media manifest object')
    version = manifest.get('version', '')
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid release version')
    expected_url = (f'https://github.com/pushipu/cool-clock/releases/download/v{version}/'
                    f'Cool-Clock-{version}-saver.zip')
    if manifest.get('url') != expected_url:
        raise ValueError('Unexpected release URL')
    files = manifest.get('files', [])
    if not isinstance(files, list) or len(files) != len(MEDIA):
        raise ValueError('Expected exactly three media files')
    seen = set()
    for item in files:
        if not isinstance(item, dict):
            raise ValueError('Expected a media file object')
        name = item.get('path', '')
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or name not in MEDIA or name in seen:
            raise ValueError('Unexpected media path')
        seen.add(name)
        target = root / name
        if target.is_symlink():
            raise ValueError(f'Refusing symbolic link: {name}')
        try:
            target.resolve().relative_to(root / 'assets')
        except ValueError:
            raise ValueError(f'Media path leaves assets: {name}') from None
        if item.get('member') != f'Cool Clock.saver/Contents/Resources/{MEDIA[name]}':
            raise ValueError('Unexpected archive member')
        if type(item.get('size')) is not int or item['size'] <= 0:
            raise ValueError('Invalid media size')
    for checksum in [manifest.get('sha256')] + [item.get('sha256') for item in files]:
        if not isinstance(checksum, str) or not re.fullmatch('[0-9a-f]{64}', checksum):
            raise ValueError('Invalid SHA-256 checksum')
    return files


def fetch_media(root, manifest, archive=None):
    root = Path(root).resolve()
    files = validate_manifest(root, manifest)
    missing = []
    for item in files:
        target = root / item['path']
        if target.exists():
            if not target.is_file() or target.stat().st_size != item['size'] or digest(target) != item['sha256']:
                raise ValueError(f"Existing file differs; move it aside first: {item['path']}")
        else:
            missing.append(item)
    if not missing:
        return []
    (root / 'assets').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.media-', dir=root / 'assets') as directory:
        staging = Path(directory)
        if archive is None:
            archive = staging / 'release.zip'
            with urlopen(manifest['url'], timeout=60) as response, archive.open('wb') as output:
                shutil.copyfileobj(response, output, CHUNK)
        archive = Path(archive)
        if digest(archive) != manifest['sha256']:
            raise ValueError('Release archive SHA-256 does not match')
        with zipfile.ZipFile(archive) as source:
            for index, item in enumerate(files):
                if source.namelist().count(item['member']) != 1:
                    raise ValueError(f"Missing or duplicate archive member: {item['member']}")
                info = source.getinfo(item['member'])
                if info.file_size != item['size']:
                    raise ValueError(f"Media size does not match: {item['path']}")
                with source.open(info) as media, (staging / str(index)).open('wb') as output:
                    shutil.copyfileobj(media, output, CHUNK)
                if digest(staging / str(index)) != item['sha256']:
                    raise ValueError(f"Media SHA-256 does not match: {item['path']}")
        # All members are verified before installation; link cannot clobber a file.
        for index, item in enumerate(files):
            if item not in missing:
                continue
            target = root / item['path']
            target.parent.mkdir(parents=True, exist_ok=True)
            os.link(staging / str(index), target)
    return [item['path'] for item in missing]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Use a local release ZIP instead of downloading')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    try:
        manifest = json.loads((root / 'assets/release-media.json').read_text())
        installed = fetch_media(root, manifest, args.archive)
    except (OSError, ValueError, zipfile.BadZipFile, KeyError, TypeError) as error:
        parser.exit(1, f'Media preparation failed: {error}\n')
    print(f'Media verified; installed {len(installed)} file(s).')


if __name__ == '__main__':
    main()
