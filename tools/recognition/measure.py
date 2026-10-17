"""Measure a task-owned local process tree, including compressed macOS footprint."""
import argparse
import ctypes
import json
from pathlib import Path
import subprocess
import time

import psutil


class Usage(ctypes.Structure):
    _fields_=[('uuid',ctypes.c_ubyte*16)]+[('field'+str(i),ctypes.c_uint64) for i in range(18)]


def main(args):
    library=ctypes.CDLL('/usr/lib/libproc.dylib')
    def footprint(pid):
        usage=Usage()
        return usage.field7 if library.proc_pid_rusage(pid,2,ctypes.byref(usage))==0 else 0
    samples=[];children=set();started=time.monotonic()
    with args.log.open('w') as stream:
        process=subprocess.Popen(args.command,stdout=stream,stderr=stream)
        while process.poll() is None:
            try:
                tree=[psutil.Process(process.pid)]+psutil.Process(process.pid).children(recursive=True)
                children.update(p.pid for p in tree[1:])
                samples.append({'seconds':time.monotonic()-started,'footprint':sum(footprint(p.pid) for p in tree)})
            except psutil.Error:pass
            time.sleep(.2)
    args.output.write_text(json.dumps({'status':process.returncode,'seconds':time.monotonic()-started,'peak_tree_footprint':max((s['footprint'] for s in samples),default=0),'surviving_children':[p for p in children if psutil.pid_exists(p)],'command':args.command,'samples':samples},indent=2))
    raise SystemExit(process.returncode)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--log',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('command',nargs=argparse.REMAINDER);main(p.parse_args())
