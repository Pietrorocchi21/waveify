#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import os
import re
import sys
from pathlib import Path


def read_version() -> str:
    content = Path('pubspec.yaml').read_text(encoding='utf-8')
    match = re.search(r'^version:\s*([^\s]+)', content, re.MULTILINE)
    if not match:
        raise SystemExit('Could not find version in pubspec.yaml')
    return match.group(1).strip()


def format_pubdate(value: dt.datetime | None = None) -> str:
    if value is None:
        value = dt.datetime.now(dt.timezone.utc)
    return value.strftime('%a, %d %b %Y %H:%M:%S GMT')


def build_item(title: str, version: str, url: str, os_name: str, signature: str) -> str:
    short_version = version.split('+', 1)[0]
    signature_attr = 'sparkle:dsaSignature' if os_name == 'windows' else 'sparkle:edSignature'
    return (
        '        <item>\n'
        f'            <title>{title}</title>\n'
        f'            <sparkle:version>{version}</sparkle:version>\n'
        f'            <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>\n'
        f'            <pubDate>{format_pubdate()}</pubDate>\n'
        '            <enclosure '
        f'url="{url}" '
        f'{signature_attr}="{signature}" '
        f'sparkle:os="{os_name}" '
        'length="0" '
        'type="application/octet-stream" />\n'
        '        </item>\n'
    )


def main() -> int:
    app_name = os.environ.get('APP_NAME', 'Waveify')
    app_version = os.environ.get('APP_VERSION') or read_version()
    appcast_url = os.environ.get('APPCAST_URL', 'https://github.com/pietrorocchi21/waveify/releases/latest/download/appcast.xml')
    windows_url = os.environ.get('WINDOWS_URL')
    macos_url = os.environ.get('MACOS_URL')
    windows_signature = os.environ.get('WINDOWS_SIGNATURE', '').strip()
    macos_signature = os.environ.get('MACOS_SIGNATURE', '').strip()

    items = []

    if windows_url:
        if not windows_signature:
            raise SystemExit('WINDOWS_SIGNATURE secret is required for the Windows update feed.')
        items.append(build_item(f'Version {app_version}', app_version, windows_url, 'windows', windows_signature))

    if macos_url:
        if not macos_signature:
            raise SystemExit('MACOS_SIGNATURE secret is required for the macOS update feed.')
        items.append(build_item(f'Version {app_version}', app_version, macos_url, 'macos', macos_signature))

    if not items:
        raise SystemExit('At least one desktop asset URL must be supplied.')

    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        '    <channel>\n'
        f'        <title>{app_name}</title>\n'
        f'        <description>Most recent updates to {app_name}</description>\n'
        '        <language>en</language>\n'
        f'        <link>{appcast_url}</link>\n'
        + ''.join(items) +
        '    </channel>\n'
        '</rss>\n'
    )
    print(xml, end='')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
