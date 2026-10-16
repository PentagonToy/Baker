"""Stage shared artwork and build the public documentation without editing source."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import yaml

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--site-dir', type=Path, required=True)
    args = parser.parse_args()
    workspace, output = args.workspace.resolve(), args.site_dir.resolve()
    for target in (workspace, output):
        if target == ROOT or ROOT.is_relative_to(target) or target.is_relative_to(ROOT):
            raise ValueError('Build artefacts must stay outside the source checkout.')
    staged = workspace / 'docs'
    if staged.exists():
        raise ValueError('Use a fresh staging workspace.')
    if output.exists() and not (output / '.baker-site').exists():
        raise ValueError('Refusing to replace an unmarked output directory.')
    workspace.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / 'docs', staged)
    (staged / 'README.md').rename(staged / 'overview.md')
    for artwork in (ROOT / 'others').rglob('*.svg'):
        target = staged / artwork.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(artwork, target)
    for page in (ROOT / 'docs').rglob('*.md'):
        destination = staged / ('overview.md' if page == ROOT / 'docs/README.md' else page.relative_to(ROOT / 'docs'))
        def artwork_link(match):
            value = match.group(2)
            if '://' in value or value.startswith(('#', 'mailto:')):
                return match.group(0)
            path, separator, anchor = value.partition('#')
            original = (page.parent / path).resolve()
            suffix = separator + anchor
            if original == ROOT / 'docs/README.md':
                target = staged / 'overview.md'
            elif original.is_relative_to(ROOT / 'others'):
                target = staged / original.relative_to(ROOT)
            elif original.is_relative_to(ROOT) and not original.is_relative_to(ROOT / 'docs'):
                return match.group(1) + 'https://github.com/PentagonToy/Baker/blob/main/' + str(original.relative_to(ROOT)) + suffix
            else:
                return match.group(0)
            return match.group(1) + os.path.relpath(target, destination.parent) + suffix
        destination.write_text(re.sub(r'''(\]\(|src=["']|srcset=["'])([^"'\s)>]+)''', artwork_link, page.read_text()))
    settings = yaml.safe_load((ROOT / 'mkdocs.yml').read_text())
    settings['docs_dir'] = 'docs'
    settings['site_dir'] = 'site'
    config = workspace / 'mkdocs.yml'
    config.write_text(yaml.safe_dump(settings, sort_keys=False))
    subprocess.run([sys.executable, '-m', 'zensical', 'build', '--strict', '-f', str(config)], check=True, cwd=workspace)
    generated = workspace / 'site'
    for page in generated.rglob('*.html'):
        html = page.read_text()
        def themed_logo(match):
            light = match.group(0)
            dark = light.replace('baker_logo_light.svg', 'baker_logo_dark.svg')
            return light.replace('<img ', '<img class="baker-logo-light" ') + dark.replace('<img ', '<img class="baker-logo-dark" ')
        def themed_symbol(match):
            light = '<img class="baker-symbol-light" ' + match.group(2) + '>'
            dark = re.sub(r'src="[^"]+"', 'src="' + match.group(1) + '"', light).replace('baker-symbol-light', 'baker-symbol-dark')
            return '<span class="baker-action-symbol">' + light + dark + '</span>'
        html = re.sub(r'<picture><source media="\(prefers-color-scheme: dark\)" srcset="([^"]*assets/symbols/[^"]+)"><img ([^>]+)></picture>', themed_symbol, html)
        html = re.sub(r'<img src="[^"]*baker_logo_light\.svg" alt="Baker">', themed_logo, html)
        html = re.sub(r'<link rel="icon" href="([^"]*baker_logo_light\.svg)">', lambda m: '<link rel="icon" media="(prefers-color-scheme: light)" href="' + m.group(1) + '"><link rel="icon" media="(prefers-color-scheme: dark)" href="' + m.group(1).replace('baker_logo_light.svg', 'baker_logo_dark.svg') + '">', html)
        page.write_text(html)
    if output.exists():
        shutil.rmtree(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(generated, output)
    (output / '.baker-site').write_text('Generated Baker documentation.\n')


if __name__ == '__main__':
    main()
