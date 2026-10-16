"""Explicit provisioning of the pinned MFR model; never called by recognition."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import urllib.request

REPOSITORY = "breezedeus/pix2text-mfr-1.5"
REVISION = "1cef9f0bdcd6a4c63df7de1311fb0894593340cc"
FILES = {'README.md': {'bytes': 9441,
               'sha256': '7ae7136c49c64378ff09a86b750ef9c2007ad8e91e148be391e3480bfd9dce97'},
 'config.json': {'bytes': 1573,
                 'sha256': 'fe4076f08f6ca75940f6af9268d51928b834979a69bc2145dacee62633a5d53d'},
 'decoder_model.onnx': {'bytes': 32026253,
                        'sha256': '917deb98e91a0453c5f234f58a0f32f9fb037de8527c7eb4ed394daf9e692f2a'},
 'encoder_model.onnx': {'bytes': 87510770,
                        'sha256': '080a3f660f08bc9ebcacdd96e34be6b6400f8c7e62d7cd0dd8251badc37f610b'},
 'generation_config.json': {'bytes': 211,
                            'sha256': '7363c031c6142d35a276815b0e285cc289dfb9f51d0b7c63de8f3ed65cc8d8ad'},
 'preprocessor_config.json': {'bytes': 450,
                              'sha256': '36a945a7cc645688b9ef64dabae16979cf5f7c1c448569cc306694edc0598b9b'},
 'special_tokens_map.json': {'bytes': 964,
                             'sha256': '8c785abebea9ae3257b61681b4e6fd8365ceafde980c21970d001e834cf10835'},
 'tokenizer.json': {'bytes': 113168,
                    'sha256': '4ffbeb2143e6a38324bb6111b7a8109530d38a076a8439aa5777535f0a32758a'},
 'tokenizer_config.json': {'bytes': 1244,
                           'sha256': 'f5cc321e8545940295fba11e9a59f4f2a208a23af3d63cc8c355c78593645b99'}}


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def provision(destination, verify_only=False):
    destination = destination.expanduser().resolve()
    if not verify_only:
        destination.mkdir(parents=True, exist_ok=True)
    for name, expected in FILES.items():
        target = destination / name
        if not target.exists():
            if verify_only:
                raise ValueError(f"Missing model file: {name}")
            url = f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}"
            temporary = None
            try:
                with urllib.request.urlopen(url, timeout=120) as response, tempfile.NamedTemporaryFile(dir=destination, delete=False) as stream:
                    temporary = Path(stream.name)
                    size = 0
                    while chunk := response.read(1024 * 1024):
                        size += len(chunk)
                        if size > expected["bytes"]:
                            raise ValueError(f"Download exceeds pinned size: {name}")
                        stream.write(chunk)
                if size != expected["bytes"] or digest(temporary) != expected["sha256"]:
                    raise ValueError(f"Downloaded model hash does not match: {name}")
                temporary.replace(target)
            finally:
                if temporary is not None and temporary.exists():
                    temporary.unlink()
        if target.stat().st_size != expected["bytes"] or digest(target) != expected["sha256"]:
            raise ValueError(f"Existing model file differs from pinned revision: {target}")
    if not verify_only:
        manifest = {"repository": REPOSITORY, "revision": REVISION, "licence_evidence": "README.md frontmatter declares MIT; upstream has no separate LICENSE file", "files": FILES}
        (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        settings = {"model_dir": str(destination), "threads": 2, "max_new_tokens": 256, "timeout_seconds": 45, "max_image_pixels": 12000000}
        (destination / "baker-config.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true", help="Verify local hashes without any network access or writes.")
    args = parser.parse_args()
    directory = provision(args.destination, args.verify_only)
    print(f"Verified MFR 1.5 revision {REVISION}: {directory}")


if __name__ == "__main__":
    main()
