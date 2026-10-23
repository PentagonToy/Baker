"""Verify a pinned formula archive and extract only its declared regular files."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile


def unpack(archive, manifest, stage):
    descriptor = manifest['archive']
    expected = {**manifest['files'], **descriptor['files']}
    if stage.exists() or not 0 < len(expected) <= 128:
        raise ValueError('Invalid formula installation stage or inventory')
    if archive.stat().st_size != descriptor['bytes']:
        raise ValueError('Formula archive size differs')
    with archive.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != descriptor['sha256']:
            raise ValueError('Formula archive hash differs')
    if sum(v['bytes'] for v in expected.values()) > 256_000_000:
        raise ValueError('Formula payload exceeds its size limit')
    try:
        with tarfile.open(archive, 'r:gz') as bundle:
            seen = set()
            for member in bundle:
                path = PurePosixPath(member.name)
                if (member.name not in expected or member.name in seen or not member.isfile()
                        or path.is_absolute() or '..' in path.parts or str(path) != member.name):
                    raise ValueError('Unexpected formula archive entry')
                info = expected[member.name]
                if member.size != info['bytes']:
                    raise ValueError('Formula file size differs')
                target = stage / member.name
                target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                digest = hashlib.sha256()
                with bundle.extractfile(member) as source, target.open('xb') as output:
                    for chunk in iter(lambda: source.read(1024 * 1024), b''):
                        digest.update(chunk)
                        output.write(chunk)
                if digest.hexdigest() != info['sha256']:
                    raise ValueError('Formula file hash differs')
                target.chmod(0o600)
                seen.add(member.name)
            if seen != set(expected):
                raise ValueError('Formula archive is incomplete')
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--stage', type=Path, required=True)
    args = parser.parse_args()
    unpack(args.archive, json.loads(args.manifest.read_text()), args.stage)
