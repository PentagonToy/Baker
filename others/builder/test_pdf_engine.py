"""Reject corrupt and unsafe PDF engine archives before activation."""
import importlib.util,io,json,hashlib,tarfile,tempfile,unittest
from pathlib import Path
source=Path(__file__).resolve().parents[2]/'Sources/Baker/Resources/pdf_engine_install.py'
spec=importlib.util.spec_from_file_location('installer',source);installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)
class Checks(unittest.TestCase):
 def make(self,root,extras=()):
  manifest={'engine_id':'pdf-engine-v1.0.0','files':{'file':{'kind':'file','bytes':2,'sha256':hashlib.sha256(b'ok').hexdigest()}}}
  body=json.dumps(manifest).encode();archive=root/'bundle.tar.gz'
  with tarfile.open(archive,'w:gz') as t:
   for name,data in [('PDFEngine/file',b'ok'),('PDFEngine/payload-manifest.json',body)]:
    entry=tarfile.TarInfo(name);entry.size=len(data);t.addfile(entry,io.BytesIO(data))
   for e,data in extras:t.addfile(e,io.BytesIO(data) if data else None)
  d={'engine_id':'pdf-engine-v1.0.0','archive_bytes':archive.stat().st_size,'archive_sha256':installer.sha256(archive),'unpacked_bytes':2+len(body)+sum(e.size for e,_ in extras),'manifest_sha256':hashlib.sha256(body).hexdigest()}
  return archive,d
 def test_valid_and_receipt(self):
  with tempfile.TemporaryDirectory() as f:
   r=Path(f);a,d=self.make(r);p=installer.unpack(a,d,r/'stage');self.assertEqual((p/'file').read_text(),'ok');self.assertEqual(json.loads((p/'installation.json').read_text())['archive_sha256'],d['archive_sha256'])
 def test_existing_stage(self):
  with tempfile.TemporaryDirectory() as f:
   r=Path(f);a,d=self.make(r);(r/'stage').mkdir()
   with self.assertRaises(ValueError):installer.unpack(a,d,r/'stage')
 def test_corrupt_archive(self):
  with tempfile.TemporaryDirectory() as f:
   r=Path(f);a,d=self.make(r);a.write_bytes(a.read_bytes()+b'x')
   with self.assertRaises(ValueError):installer.unpack(a,d,r/'stage')
 def test_wrong_manifest(self):
  with tempfile.TemporaryDirectory() as f:
   r=Path(f);a,d=self.make(r);d['manifest_sha256']='0'*64
   with self.assertRaises(ValueError):installer.unpack(a,d,r/'stage')
 def test_paths_and_types(self):
  for name,kind,target,mode in [('PDFEngine/../../outside',tarfile.REGTYPE,'',0o644),('/outside',tarfile.REGTYPE,'',0o644),('PDFEngine/link',tarfile.SYMTYPE,'../../outside',0o644),('PDFEngine/link',tarfile.SYMTYPE,'/outside',0o644),('PDFEngine/hardlink',tarfile.LNKTYPE,'PDFEngine/file',0o644),('PDFEngine/fifo',tarfile.FIFOTYPE,'',0o644),('PDFEngine/privileged',tarfile.REGTYPE,'',0o4755),('PDFEngine/file',tarfile.REGTYPE,'',0o644),('PDFEngine/extra',tarfile.REGTYPE,'',0o644)]:
   with self.subTest(name=name,kind=kind,mode=mode),tempfile.TemporaryDirectory() as f:
    r=Path(f);e=tarfile.TarInfo(name);e.type=kind;e.linkname=target;e.mode=mode;a,d=self.make(r,[(e,b'')])
    with self.assertRaises((ValueError,tarfile.FilterError)):installer.unpack(a,d,r/'stage')
    self.assertFalse((r/'outside').exists())
 def test_size_limit(self):
  with tempfile.TemporaryDirectory() as f:
   r=Path(f);a,d=self.make(r);d['unpacked_bytes']=1
   with self.assertRaises(ValueError):installer.unpack(a,d,r/'stage')
class PackageChecks(unittest.TestCase):
 def test_unchanged_payload_has_stable_archive_hash(self):
  spec=importlib.util.spec_from_file_location('packager',Path(__file__).with_name('package_pdf_engine.py'))
  packager=importlib.util.module_from_spec(spec);spec.loader.exec_module(packager)
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);source=root/'source';source.mkdir()
   inventory={}
   for name in ['python/bin/python3.12','worker/pdf_candidate.py','model/model.safetensors','adapter/adapters.safetensors','layout.onnx','PROVENANCE.json']:
    path=source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'fixture')
    inventory[name]={'bytes':7,'sha256':hashlib.sha256(b'fixture').hexdigest()}
   (source/'manifest.json').write_text(json.dumps({'minimum_macos':'26.2','files':inventory}))
   (source/'document-engine.json').write_text(json.dumps({'engine':'baker-small-ocr-1'}))
   first=packager.package(source,root/'first')
   second=packager.package(source,root/'second')
   self.assertEqual(first['archive_sha256'],second['archive_sha256'])
   self.assertEqual(first['manifest_sha256'],second['manifest_sha256'])
   installed=installer.unpack(root/'first/Baker-PDF-Engine-1.0.0-arm64.tar.gz',first,root/'installed')
   self.assertTrue((installed/'installation.json').is_file())

if __name__ == '__main__': unittest.main()

