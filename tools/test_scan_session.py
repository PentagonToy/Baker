#!/usr/bin/env python3
"""Check scan cancellation and setup layout with fake capture and reader input."""
import argparse
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path,required=True)
out=p.parse_args().output.resolve()
if out==root or root in out.parents:p.error('Keep generated evidence outside the repository')
out.mkdir(parents=True,exist_ok=True)
parts=[root/'Sources/BakerCore'/n for n in ['BakerError.swift','OCRLanguages.swift','ScanOptions.swift','ScanDocument.swift']]
parts += [root/'Sources/Baker'/n for n in ['ScanSession.swift','ScanSetup.swift','Typography.swift','Motion.swift','BakerSegmentedPicker.swift']]
source='\n'.join(f.read_text().replace('import BakerCore','') for f in parts)
theme=(root/'Sources/Baker/DocumentProgress.swift').read_text().split('@MainActor enum BakerTheme')[1].split('struct DocumentProgressView')[0]
source+='\n@MainActor enum BakerTheme'+theme
method=(root/'Sources/Baker/Workbench+Output.swift').read_text().split('    func cancelJob()')[1].split('    func acceptExport')[0]
source+='\nextension Workbench {func cancelJob()'+method+'}\n'
source+=(root/'Tests/BakerScanSessionRegression/main.swift').read_text()
script=out/'checks.swift';script.write_text(source)
r=subprocess.run(['swift',str(script),str(out)],capture_output=True,text=True,timeout=120)
(out/'checks.log').write_text(r.stdout+r.stderr)
print((r.stdout+r.stderr)[-6000:])
raise SystemExit(r.returncode)
