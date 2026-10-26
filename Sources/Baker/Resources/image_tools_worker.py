"""Bounded, local raster-to-SVG conversion. Input must already contain all masks/crops."""
import argparse
from pathlib import Path
import re
import signal
import subprocess
import sys
import xml.etree.ElementTree as ET

MAX_PIXELS = 4_000_000
MAX_SVG = 8 * 1024 * 1024
MAX_PATHS = 50_000
child = None


def stop(signum, _frame):
    if child is not None and child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)


def sanitise(text, width, height):
    if len(text.encode('utf-8')) > MAX_SVG:
        raise ValueError('The vector result is too complex. Crop a smaller area.')
    # Engines emit a fixed SVG declaration; never retain a DTD or permit entity expansion.
    text = re.sub(r'<!DOCTYPE[^>]*>', '', text)
    if '<!ENTITY' in text.upper() or '<!DOCTYPE' in text.upper():
        raise ValueError('Unexpected vector declarations')
    root = ET.fromstring(text)
    allowed = {'svg', 'g', 'path', 'metadata', 'title', 'desc', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'line'}
    paths = 0
    for element in root.iter():
        tag = element.tag.split('}')[-1]
        if tag not in allowed:
            raise ValueError('Unexpected vector content')
        if tag == 'path':
            paths += 1
        for name, value in element.attrib.items():
            key = name.lower().split('}')[-1]
            if key.startswith('on') or key in {'href', 'src'} or 'url(' in value.lower() or 'javascript:' in value.lower():
                raise ValueError('External or active vector content is not allowed')
    if root.tag.split('}')[-1] != 'svg' or not 1 <= paths <= MAX_PATHS:
        raise ValueError('No usable vector paths, or too many paths')
    root.set('width', str(width)); root.set('height', str(height))
    root.set('viewBox', f'0 0 {width} {height}')
    ET.register_namespace('', 'http://www.w3.org/2000/svg')
    result = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    if len(result) > MAX_SVG:
        raise ValueError('The vector result is too large')
    return result


def main():
    global child
    from PIL import Image
    p = argparse.ArgumentParser()
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--tools', type=Path, required=True)
    p.add_argument('--mode', choices=['colour', 'monochrome'], required=True)
    a = p.parse_args()
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    if a.input.stat().st_size > 32 * 1024 * 1024:
        raise ValueError('The image is too large')
    with Image.open(a.input) as source:
        width, height = source.size
        if width * height > MAX_PIXELS or max(width, height) > 8192:
            raise ValueError('Crop this image to 4 megapixels or less before vectorising.')
        image = source.convert('RGBA')
    if a.mode == 'colour':
        sys.path.insert(0, str(a.tools/'python'))
        import vtracer
        # Keep small scientific marks and colours; do not use generic speckle cleanup.
        text = vtracer.convert_raw_image_to_svg(a.input.read_bytes(), img_format='png', colormode='color',
            hierarchical='stacked', mode='spline', filter_speckle=0, color_precision=8,
            layer_difference=0, length_threshold=3.5, path_precision=3)
    else:
        # Composite only the supplied flattened pixels; transparent RGB never enters the trace.
        white = Image.new('RGBA', image.size, 'white'); white.alpha_composite(image)
        bitmap = a.output.with_suffix('.pbm')
        raw = a.output.with_suffix('.raw.svg')
        try:
            white.convert('L').point(lambda v: 0 if v < 230 else 255).convert('1', dither=Image.Dither.NONE).save(bitmap)
            child = subprocess.Popen([str(a.tools/'bin/potrace'), '--svg', '--turdsize', '0', '--opttolerance', '0.1',
                '--resolution', '72', '--output', str(raw), str(bitmap)], stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if child.wait(timeout=30) != 0:
                raise ValueError('The monochrome trace did not complete')
            if raw.stat().st_size > MAX_SVG:
                raise ValueError('The vector result is too complex. Crop a smaller area.')
            text = raw.read_text()
        finally:
            if child is not None and child.poll() is None:
                child.kill(); child.wait()
            bitmap.unlink(missing_ok=True); raw.unlink(missing_ok=True)
    a.output.write_bytes(sanitise(text, width, height))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error)[:500], file=sys.stderr)
        raise SystemExit(1)
