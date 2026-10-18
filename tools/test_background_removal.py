#!/usr/bin/env python3
"""Check smooth-background removal against authored alpha masks and an optional private sample."""
import argparse
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont
import math

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--sample', type=Path)
a = p.parse_args()
out = a.output.resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep private samples and generated evidence outside the checkout')
out.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 26)
for name in ['light', 'dark', 'filled', 'noise']:
    w, h = 640, 240
    background = Image.new('RGBA', (w, h))
    colours = []
    for y in range(h):
        for x in range(w):
            u, v = x/(w-1), y/(h-1)
            if name == 'dark':
                rgb = (20+18*v*v, 28+12*u+8*v, 40+10*u*v)
            else:
                rgb = (240-22*v*v+6*u, 253-24*v*v*(1-u), 255-14*v*v)
            noise = ((x*17+y*31)%5)-2 if name == 'noise' else 0
            colours.append(tuple(max(0,min(255,round(c)+noise)) for c in rgb)+(255,))
    background.putdata(colours)
    foreground = Image.new('RGBA', (w, h))
    d = ImageDraw.Draw(foreground)
    ink = 'white' if name == 'dark' else 'black'
    d.text((20, 20), 'A smooth slide background', font=font, fill=ink)
    d.text((190, 83), 'f(x, y) = x² + y²', font=font, fill=ink)
    d.line([(40, 140), (40, 205), (600, 205)], fill=ink, width=1)
    d.line([(50, 180), (170, 150), (310, 190), (470, 155)], fill='#0072B2', width=2)
    d.ellipse((560, 180, 562, 182), fill=ink)
    d.line([(50, 225), (580, 225)], fill=(255,255,255,51) if name == 'dark' else (0,0,0,51), width=1)
    if name == 'filled':
        d.rectangle((340, 125, 600, 195), fill='#D55E00')
    Image.alpha_composite(background, foreground).save(out/(name+'.png'))
    foreground.save(out/(name+'-foreground.png'))
source='\n'.join((ROOT/'Sources/BakerCore'/f).read_text() for f in ['BakerError.swift', 'PaperBackground.swift', 'ImageBackgroundRemoval.swift'])
source += (ROOT/'Tests/BakerBackgroundRegression/main.swift').read_text()
script=out/'background.swift';script.write_text(source)
args=['swift',str(script),str(out)]
if a.sample:
    args.append(str(a.sample.resolve()))
r=subprocess.run(args,capture_output=True,text=True,timeout=180)
(out/'checks.log').write_text(r.stdout+r.stderr)
print(r.stdout if r.returncode==0 else (r.stdout+r.stderr)[-4000:])
raise SystemExit(r.returncode)
