"""Model-free checks for the page-scoped layout prediction cache."""
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import weakref
import unittest

sys.dont_write_bytecode = True
source = Path(__file__).resolve().parents[1] / 'Sources/Baker/Resources/document_worker.py'
spec = importlib.util.spec_from_file_location('document_worker', source)
worker = importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)


class Predictor:
    marker = 'underlying predictor'
    def __init__(self): self.calls = []
    def predict(self, source, *args, **kwargs):
        self.calls.append((source, args, kwargs)); return ['fresh']


class LayoutCacheTests(unittest.TestCase):
    def test_same_page_same_parameters_reuses_prediction(self):
        original = Predictor()
        cached = worker.PageLayoutPrediction(original, ['page pixels'], 'cached')
        self.assertEqual(cached.predict(['page pixels'], imgsz=1024, conf=.2), ['cached'])
        self.assertEqual(original.calls, [])
        self.assertEqual(cached.marker, 'underlying predictor')

    def test_different_pixels_and_parameters_fall_back(self):
        original = Predictor(); cached = worker.PageLayoutPrediction(original, ['page pixels'], 'cached')
        for image, kwargs in [(['other page'], {}), (['page pixels'], {'conf':.4}),
                              (['page pixels'], {'imgsz':640}), (['page pixels'], {'augment':True})]:
            self.assertEqual(cached.predict(image, **kwargs), ['fresh'])
        self.assertEqual(len(original.calls), 4)

    def test_positional_options_are_forwarded(self):
        original = Predictor(); cached = worker.PageLayoutPrediction(original, 'page', 'cached')
        self.assertEqual(cached.predict('page', 'different option'), ['fresh'])
        self.assertEqual(original.calls[0][1], ('different option',))


class DeferredTableTests(unittest.TestCase):
    def test_only_first_table_loads_model(self):
        calls=[]
        class Table:
            def recognize(self,*args,**kwargs):return (args,kwargs)
        def create():calls.append('load');return Table()
        table=worker.DeferredTableOCR(create)
        self.assertEqual(calls,[])
        self.assertEqual(table.recognize('crop',confidence=True),(('crop',),{'confidence':True}))
        table.recognize('second crop')
        self.assertEqual(calls,['load'])
        self.assertIsNone(table.factory)

    def test_failed_load_is_not_silently_ignored(self):
        def create():raise RuntimeError('Missing table weights')
        table=worker.DeferredTableOCR(create)
        with self.assertRaisesRegex(RuntimeError,'Missing table weights'):table.recognize('crop')
        self.assertIsNone(table.engine)


class PageMemoryTests(unittest.TestCase):
    def test_completed_predictions_release_images_but_keep_models(self):
        class Image: pass
        image=Image(); reference=weakref.ref(image)
        weights=object()
        runner=SimpleNamespace(results=[image],batch=[image],dataset=[image],plotted_img=image,model=weights)
        detector=SimpleNamespace(predictor=runner)
        engine=SimpleNamespace(layout_parser=SimpleNamespace(predictor=detector),text_formula_ocr=SimpleNamespace(mfd=SimpleNamespace(model=detector)))
        del image
        worker.release_page_buffers(engine)
        self.assertIsNone(reference())
        self.assertIs(runner.model,weights)
        self.assertIs(engine.layout_parser.predictor,detector)
        worker.release_page_buffers(engine)

    def test_not_yet_loaded_detectors_are_supported(self):
        engine=SimpleNamespace(layout_parser=SimpleNamespace(predictor=SimpleNamespace()),text_formula_ocr=SimpleNamespace(mfd=None))
        worker.release_page_buffers(engine)


if __name__ == '__main__': unittest.main()
