"""Extract a small code-only plugin ZIP without links or path traversal."""
import json
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile

archive, target = map(Path, sys.argv[1:])
with zipfile.ZipFile(archive) as z:
    items = z.infolist()
    if not items or len(items) > 256 or sum(i.file_size for i in items) > 16 * 1024 * 1024:
        raise ValueError('Plugin archive exceeds the package limits')
    names = set()
    for item in items:
        name = item.filename
        path = PurePosixPath(name)
        mode = item.external_attr >> 16
        if (not name or name.startswith('/') or '\\' in name or '..' in path.parts
                or '\0' in name or ':' in name or name in names or str(path) != name.rstrip('/')
                or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR))):
            raise ValueError('Invalid plugin archive entry')
        names.add(name)
    for item in items:
        if item.filename.startswith('__MACOSX/') or PurePosixPath(item.filename).name == '.DS_Store':
            continue
        destination = target / item.filename
        if item.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            # Bound the actual decompressed read as well as the central directory.
            with z.open(item) as source:
                data = source.read(16 * 1024 * 1024 + 1)
            if len(data) != item.file_size or len(data) > 16 * 1024 * 1024:
                raise ValueError('Invalid plugin entry size')
            destination.write_bytes(data)
            destination.chmod(0o700 if item.external_attr >> 16 & 0o111 else 0o600)
print(json.dumps({'ok': True}))
