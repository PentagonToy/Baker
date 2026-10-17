"""Verify and unpack a pinned PDF engine without executing downloaded code."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def unpack(archive, descriptor, stage):
    if stage.exists():
        raise ValueError('Installation staging folder already exists')
    if archive.stat().st_size != descriptor['archive_bytes'] or sha256(archive) != descriptor['archive_sha256']:
        raise ValueError('PDF engine download failed its integrity check')
    with tarfile.open(archive, 'r:gz') as bundle:
        members = bundle.getmembers()
        if len(members) > 30000:
            raise ValueError('Too many archive entries')
        names = set()
        total = 0
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != 'PDFEngine' or member.name in names:
                raise ValueError('Invalid archive path')
            names.add(member.name)
            if not (member.isfile() or member.isdir() or member.issym()):
                raise ValueError('Unsupported archive entry')
            if member.issym():
                # Only internal relative links are permitted, even before extraction.
                target = path.parent / member.linkname
                depth = 0
                if PurePosixPath(member.linkname).is_absolute():
                    raise ValueError('Absolute archive link')
                for part in target.parts:
                    depth += -1 if part == '..' else 0 if part == '.' else 1
                    if depth < 1:
                        raise ValueError('Archive link leaves engine')
            if member.mode & 0o7000:
                raise ValueError('Privileged archive permissions')
            total += member.size
        if total != descriptor['unpacked_bytes']:
            raise ValueError('Unexpected unpacked engine size')
        stage.mkdir(parents=True, mode=0o700)
        bundle.extractall(stage, filter='data')
    root = stage / 'PDFEngine'
    manifest = root / 'payload-manifest.json'
    if sha256(manifest) != descriptor['manifest_sha256']:
        raise ValueError('PDF engine inventory failed its integrity check')
    inventory = json.loads(manifest.read_text())
    actual = {str(p.relative_to(root)) for p in root.rglob('*') if p.is_symlink() or p.is_file()}
    if actual != set(inventory['files']) | {'payload-manifest.json'}:
        raise ValueError('PDF engine contains unexpected or missing files')
    for name, entry in inventory['files'].items():
        path = root / name
        if not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('PDF engine link leaves installation')
        if entry['kind'] == 'symlink':
            if not path.is_symlink() or str(path.readlink()) != entry['target']:
                raise ValueError('PDF engine link mismatch: ' + name)
        elif path.is_symlink() or path.stat().st_size != entry['bytes'] or sha256(path) != entry['sha256']:
            raise ValueError('PDF engine file mismatch: ' + name)
    if inventory['engine_id'] != descriptor['engine_id']:
        raise ValueError('PDF engine version mismatch')
    (root / 'installation.json').write_text(json.dumps({'engine_id': descriptor['engine_id'], 'archive_sha256': descriptor['archive_sha256']}))
    return root


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['archive', 'descriptor', 'stage']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        print(unpack(args.archive, json.loads(args.descriptor.read_text()), args.stage))
    except Exception as error:
        parser.exit(1, str(error) + '\n')
