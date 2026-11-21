"""Versioned streaming authenticated encryption for private export archives."""
import os
import struct
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b'WAVEIFY\x01'
CHUNK = 64 * 1024


def _cipher(passphrase, salt):
    if len(passphrase) < 20 or len(passphrase) > 1024:
        raise ValueError('Backup passphrase must contain 20–1024 characters.')
    key = Scrypt(salt=salt, length=32, n=32768, r=8, p=1).derive(passphrase.encode())
    return AESGCM(key)


def _create(path):
    return os.fdopen(os.open(Path(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb')


def encrypt(source, destination, passphrase):
    salt, nonce = os.urandom(16), os.urandom(8)
    header = MAGIC + salt + nonce
    cipher = _cipher(passphrase, salt)
    with open(source, 'rb') as src, _create(destination) as out:
        out.write(header)
        counter = 0
        while True:
            chunk = src.read(CHUNK)
            final = not chunk
            flag = bytes([int(final)])
            index = struct.pack('>I', counter)
            encrypted = cipher.encrypt(nonce + index, chunk, header + index + flag)
            out.write(flag + struct.pack('>I', len(encrypted)) + encrypted)
            if final:
                break
            counter += 1


def decrypt(source, destination, passphrase, max_bytes=2 * 1024**3):
    created = False
    try:
        with open(source, 'rb') as src, _create(destination) as out:
            created = True
            header = src.read(len(MAGIC) + 24)
            if len(header) != len(MAGIC) + 24 or not header.startswith(MAGIC):
                raise ValueError('Unsupported backup format.')
            cipher = _cipher(passphrase, header[len(MAGIC):len(MAGIC) + 16])
            nonce, counter, total = header[-8:], 0, 0
            while True:
                record = src.read(5)
                if len(record) != 5 or record[0] not in (0, 1):
                    raise ValueError('Incomplete or invalid encrypted archive.')
                size = struct.unpack('>I', record[1:])[0]
                if size < 16 or size > CHUNK + 16:
                    raise ValueError('Invalid encrypted block size.')
                payload = src.read(size)
                index = struct.pack('>I', counter)
                chunk = cipher.decrypt(nonce + index, payload, header + index + record[:1])
                total += len(chunk)
                if total > max_bytes:
                    raise ValueError('Backup exceeds configured size limit.')
                if record[0] == 1:
                    if chunk or src.read(1):
                        raise ValueError('Invalid archive terminator.')
                    break
                out.write(chunk)
                counter += 1
    except BaseException:
        if created:
            Path(destination).unlink(missing_ok=True)
        raise
