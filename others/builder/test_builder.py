"""Check installation guards without building, quitting or replacing a real app."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('builder', Path(__file__).with_name('build.py'))
builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)


class SafetyChecks(unittest.TestCase):
    def test_table_reference_rejects_changed_cells(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);actual=root/'actual.jsonl';reference=root/'reference.jsonl'
            page={'nodes':[{'kind':'table','rows':[['a','b']],'caption':'Table 1'}]}
            reference.write_text(json.dumps(page));actual.write_text(json.dumps(page))
            builder.check_table_reference(actual,reference)
            page['nodes'][0]['rows'][0][1]='wrong';actual.write_text(json.dumps(page))
            with self.assertRaises(ValueError):builder.check_table_reference(actual,reference)

    def test_lock_rejects_second_owner(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with builder.lock(root):
                with self.assertRaises(ValueError):
                    with builder.lock(root): pass
                self.assertTrue((root / 'build.lock').exists())
            self.assertFalse((root / 'build.lock').exists())

    def test_failed_final_verification_restores_original(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); install=root/'Baker.app'; app=root/'new.app'; job=root/'job'
            install.mkdir();app.mkdir();job.mkdir()
            (install/'version').write_text('old');(app/'version').write_text('new')
            def run(arguments,**kwargs):
                args=list(map(str,arguments))
                if args[0]=='ditto':shutil.copytree(args[1],args[2])
                elif args[0]=='codesign' and Path(args[-1])==install:raise subprocess.CalledProcessError(1,args)
            with patch.object(builder,'run',side_effect=run),patch.object(builder.subprocess,'run',return_value=subprocess.CompletedProcess([],1)):
                with self.assertRaises(subprocess.CalledProcessError):builder.replace_app(app,install,job)
            self.assertEqual((install/'version').read_text(),'old')
            self.assertEqual((job/'previous-Baker.app/version').read_text(),'old')

    def test_staging_failure_does_not_quit_or_modify_original(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);install=root/'Baker.app';install.mkdir();(install/'version').write_text('old')
            calls=[]
            def fail(arguments,**kwargs):
                calls.append(arguments)
                raise subprocess.CalledProcessError(1,arguments)
            with patch.object(builder,'run',side_effect=fail):
                with self.assertRaises(subprocess.CalledProcessError):builder.replace_app(root/'new.app',install,root/'job')
            self.assertEqual((install/'version').read_text(),'old')
            self.assertFalse(any(args[0]=='osascript' for args in calls))


if __name__=='__main__':unittest.main()
