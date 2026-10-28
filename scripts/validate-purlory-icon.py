#!/usr/bin/env python3
"""Validate the app icon reference and every required macOS representation."""
import pathlib
import plistlib
import struct
import sys
import zlib

# ICNS type -> physical pixel dimension (including retina representations).
SIZES = {'icp4': 16, 'ic11': 32, 'icp5': 32, 'ic12': 64, 'ic07': 128,
         'ic13': 256, 'ic08': 256, 'ic14': 512, 'ic09': 512, 'ic10': 1024}

def validate(app):
    app = pathlib.Path(app)
    for path in [app, app / 'Contents', app / 'Contents/Resources', app / 'Contents/Info.plist',
                 app / 'Contents/Resources/AppIcon.icns']:
        if path.is_symlink():
            raise ValueError('Symlink in icon resource path')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIconFile') not in {'AppIcon', 'AppIcon.icns'}:
        raise ValueError('Unexpected CFBundleIconFile')
    data = (app / 'Contents/Resources/AppIcon.icns').read_bytes()
    if len(data) < 8 or data[:4] != b'icns' or struct.unpack('>I', data[4:8])[0] != len(data):
        raise ValueError('Invalid ICNS header or length')
    found = set()
    offset = 8
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError('Truncated ICNS entry')
        kind = data[offset:offset+4].decode('ascii')
        length = struct.unpack('>I', data[offset+4:offset+8])[0]
        if length < 8 or offset + length > len(data):
            raise ValueError('Invalid ICNS entry length')
        payload = data[offset+8:offset+length]
        if kind in SIZES:
            if kind in found or payload[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError('Duplicate or non-PNG icon representation')
            cursor = 8
            chunks = []
            compressed = bytearray()
            while cursor < len(payload):
                if cursor + 12 > len(payload):
                    raise ValueError('Truncated PNG')
                count = struct.unpack('>I', payload[cursor:cursor+4])[0]
                chunk = payload[cursor+4:cursor+8]
                end = cursor + 8 + count
                if end + 4 > len(payload):
                    raise ValueError('Truncated PNG chunk')
                content = payload[cursor+8:end]
                crc = struct.unpack('>I', payload[end:end+4])[0]
                if zlib.crc32(chunk + content) & 0xffffffff != crc:
                    raise ValueError('Corrupt PNG checksum')
                if chunk == b'IHDR':
                    if len(content) != 13 or struct.unpack('>II', content[:8]) != (SIZES[kind], SIZES[kind]):
                        raise ValueError('Incorrect icon dimensions')
                if chunk == b'IDAT':
                    compressed.extend(content)
                chunks.append(chunk)
                cursor = end + 4
            if not chunks or chunks[0] != b'IHDR' or chunks[-1] != b'IEND' or not compressed:
                raise ValueError('Incomplete PNG')
            if not zlib.decompress(compressed):
                raise ValueError('Empty PNG image')
            found.add(kind)
        offset += length
    if found != set(SIZES):
        raise ValueError('Missing macOS icon representations: ' + ', '.join(sorted(set(SIZES) - found)))

if __name__ == '__main__':
    try:
        validate(sys.argv[1])
    except (OSError, ValueError, KeyError, IndexError, struct.error, zlib.error) as error:
        sys.exit(f'Icon validation failed: {error}')
    print('Validated macOS icon representations and bundle reference')
