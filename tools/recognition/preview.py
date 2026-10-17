"""Run the isolated PDF candidate, with a file chooser when opened by double click."""
import argparse
from datetime import datetime
from pathlib import Path
import subprocess
import sys
import uuid


def main(args):
    engine=Path(__file__).resolve().parents[1]
    interactive=args.source is None
    source=args.source
    if interactive:
        result=subprocess.run(['/usr/bin/osascript','-e','POSIX path of (choose file with prompt "Choose a PDF for the Baker OCR preview" of type {"com.adobe.pdf"})'],capture_output=True,text=True)
        if result.returncode:
            if '-128' in result.stderr:return
            raise RuntimeError(result.stderr.strip())
        source=Path(result.stdout.strip())
    source=source.resolve(strict=True)
    output=args.output or engine.parent/'preview-results'/(source.stem+'-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6])
    command=[str(engine/'python/bin/python3.12'),'-I','-B',str(engine/'worker/pdf_candidate.py'),
             '--source',str(source),'--output',str(output),'--model',str(engine/'model'),
             '--adapter',str(engine/'adapter'),'--layout',str(engine/'layout.onnx'),
             '--code',str(engine/'code'),'--reconstruction',str(engine/'worker/document_reconstruction.py')]
    subprocess.run(command,check=True)
    print('Saved Markdown, LaTeX and figures to:',output,flush=True)
    if interactive:subprocess.run(['/usr/bin/open',str(output)],check=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path);parser.add_argument('--output',type=Path)
    main(parser.parse_args())
