#!/usr/bin/env python3
"""Generate the Windows update manifest from the exact verified release installer."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import quote


def manifest(installer, version, repository, notes=''):
    if not re.fullmatch(r'\d+\.\d+\.\d+\+\d+', version):
        raise ValueError('Version must include major.minor.patch+build.')
    if repository.lower() != 'pietrorocchi21/waveify':
        raise ValueError('Installer repository does not match the client trust policy.')
    installer = Path(installer)
    if installer.suffix != '.exe' or not installer.is_file() or installer.stat().st_size == 0:
        raise ValueError('A nonempty Windows installer is required.')
    digest = hashlib.sha256()
    with installer.open('rb') as data:
        while block := data.read(1024 * 1024):
            digest.update(block)
    return {'schemaVersion': 1, 'version': version, 'platform': 'windows-x64',
            'url': f'https://github.com/{repository}/releases/download/{quote("v" + version, safe="")}/{quote(installer.name, safe="")}',
            'sha256': digest.hexdigest(), 'size': installer.stat().st_size, 'notes': notes}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installer', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--repository', default='Pietrorocchi21/waveify')
    parser.add_argument('--notes', default='')
    args = parser.parse_args()
    print(json.dumps(manifest(args.installer, args.version, args.repository, args.notes), ensure_ascii=False, indent=2))
