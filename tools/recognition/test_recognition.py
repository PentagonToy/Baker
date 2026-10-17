"""Checks for data separation and document structure used by the experiments."""
from pathlib import Path
from types import SimpleNamespace
import json
import tempfile
import unittest

from evaluate import Grid,normalise,evaluate,score
from pdf_candidate import reliable_native,without_redundant_figure_containers,restore_native_scripts,publication_notice,sparse_native_rows,recover_author_band
from prepare_training import main as prepare_training
from pdf_text import join_lines,finish_flow,front_matter,attach_equation_labels,deduplicate_text


class RecognitionChecks(unittest.TestCase):
    def test_fraction_grouping_is_not_erased_by_metric(self):
        self.assertNotEqual(normalise(r'\frac{a}{bc}','formula'),normalise(r'\frac{ab}{c}','formula'))
        self.assertEqual(normalise(r'\[x^{2}\]','formula'),normalise('x^2','formula'))
        self.assertNotEqual(normalise(r'\sin x','formula'),normalise(r'\sinx','formula'))
        self.assertNotEqual(normalise(r'\leftarrow','formula'),normalise('arrow','formula'))
        self.assertNotEqual(normalise(r'\text{a b}','formula'),normalise(r'\text{ab}','formula'))
        self.assertEqual(normalise(r'\left(x\right)','formula'),normalise('(x)','formula'))

    def test_table_spans_keep_column_positions(self):
        grid=Grid();grid.feed('<table><tr><td rowspan="2">A</td><td colspan="2">B</td></tr><tr><td>C</td><td>D</td></tr></table>')
        self.assertEqual(grid.cells,{(0,0):'A',(1,0):'A',(0,1):'B',(0,2):'B',(1,1):'C',(1,2):'D'})
        self.assertEqual(grid.spans[0],{'row':0,'column':0,'rowspan':2,'colspan':1})
        target='<table><tr><td colspan="2">A</td></tr></table>'
        other='<table><tr><td>A</td><td>A</td></tr></table>'
        value=score({'target':target,'kind':'table'},other)
        self.assertTrue(value['exact_grid']);self.assertFalse(value['exact_spans']);self.assertFalse(value['exact'])

    def test_native_guard_rejects_encoded_math_and_missing_text(self):
        def chars(text,font='Times-Roman'):return [{'text':c,'font':font} for c in text]
        self.assertTrue(reliable_native(chars('Suomi: lämpötila 18,6 astetta.')))
        self.assertTrue(reliable_native(chars('시료 온도는 293 K입니다.')))
        for value in [[],chars('x','Symbol'),chars('\ue000'),chars('ð22Þ'),chars('∂u/∂t')]:self.assertFalse(reliable_native(value))

    def test_two_panels_survive_a_duplicate_container(self):
        panels=[{'class':'figure','box':b,'score':.8} for b in [[0,0,100,50],[0,0,48,50],[52,0,100,50]]]
        self.assertEqual(without_redundant_figure_containers(panels),panels[1:])

    def test_native_scripts_do_not_change_other_words_or_existing_math(self):
        self.assertEqual(restore_native_scripts('H2-air ($\\phi=0.4$)',{'H2':'H$_{2}$'}),'H$_{2}$-air ($\\phi=0.4$)')
        self.assertEqual(restore_native_scripts('CH2 $H2$',{'H2':'H$_{2}$'}),'CH2 $H2$')

    def test_wrapped_words_and_real_hyphens_remain_distinct(self):
        words={'different','diffusion','nonunity'};compounds={'non-unity'}
        self.assertEqual(join_lines(['A dif-','ferent non-','unity case.'],words,compounds),'A different non-unity case.')
        page={'nodes':[{'id':0,'kind':'text','text':'Capture diffu-'},{'id':1,'kind':'text','text':'* Corresponding author.'},{'id':2,'kind':'text','text':'sion effects.'}]}
        finish_flow(page,{1},words,compounds)
        self.assertEqual([n['text'] for n in page['nodes']],['Capture diffusion effects.','* Corresponding author.'])
        self.assertTrue(publication_notice('2012. All rights reserved.'))
        self.assertFalse(publication_notice('A result published by another research group.'))

    def test_metrics_report_missing_predictions_and_reject_duplicates(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=root/'manifest.jsonl';predictions=root/'predictions.jsonl'
            rows=[{'id':name,'kind':'text','target':'abc','split':'test','language':'en'} for name in ['a','b']]
            manifest.write_text('\n'.join(map(json.dumps,rows)))
            prediction=json.dumps({'id':'a','prediction':'abc','seconds':1,'finish_reason':'length'})
            predictions.write_text(prediction+'\n')
            report=evaluate(manifest,predictions,['test'])
            self.assertEqual(report['coverage']['missing_ids'],['b']);self.assertEqual(report['groups'][0]['exact'],0)
            predictions.write_text(prediction+'\n'+prediction+'\n')
            with self.assertRaises(ValueError):evaluate(manifest,predictions)

    def test_sparse_repair_preserves_native_lines_and_limits_replacement(self):
        from PIL import Image
        chars=[{'row':i,'text':f'[{i}] Reference','font':'Times','box':[10,i*18+2,20,i*18+14]} for i in range(10)]
        chars[4]['text']='damaged\x06';calls=[]
        def recognise(crop,task,limit):
            calls.append(crop.size);return SimpleNamespace(text='repaired',finish_reason='stop')
        reconstruction=SimpleNamespace(native_text=lambda row,box:''.join(c['text'] for c in row))
        result=sparse_native_rows(chars,[0,0,100,200],Image.new('RGB',(100,200),'white'),reconstruction,recognise,set(),set())
        self.assertEqual(result[1],1);self.assertIn('repaired',result[0]);self.assertIn('[9] Reference',result[0]);self.assertEqual(len(calls),1)
        self.assertLess(calls[0][1],50)
        chars[0]['font']='Symbol'
        self.assertIsNone(sparse_native_rows(chars,[0,0,100,200],None,reconstruction,recognise,set(),set()))
        chars[0]['font']='Times'
        chars[5]['font']='Symbol'
        self.assertIsNone(sparse_native_rows(chars,[0,0,100,200],None,reconstruction,recognise,set(),set()))

    def test_abstract_stays_with_its_text_beside_a_metadata_sidebar(self):
        data=[('heading','Title',[0,0,300,10]),('heading','a r t i c l e i n f o',[0,20,70,25]),('heading','a b s t r a c t',[100,20,160,25]),('text','Received in 2012',[0,30,70,40]),('heading','Keywords:',[0,45,70,50]),('text','Abstract content.',[100,30,300,90]),('text','Keywords: diffusion',[0,55,70,70]),('heading','1. Introduction',[0,110,300,120])]
        page={'page':1,'nodes':[{'id':i,'kind':kind,'text':text,'box':box} for i,(kind,text,box) in enumerate(data)]}
        front_matter(page)
        texts=[n['text'] for n in page['nodes']]
        self.assertEqual(texts[-3:],['Abstract','Abstract content.','1. Introduction'])
        self.assertIn('Article information',texts);self.assertNotIn('Keywords:',texts)

    def test_right_margin_labels_bind_to_the_correct_column(self):
        page={'nodes':[{'id':0,'kind':'equation','text':'x','box':[0,0,100,30]}, {'id':1,'kind':'equation','text':'y','box':[300,0,400,30]}, {'id':2,'kind':'label','raw_class':'formula_caption','text':'1','box':[190,5,210,25]}, {'id':3,'kind':'label','raw_class':'formula_caption','text':'2','box':[490,5,510,25]}]}
        attach_equation_labels(page)
        self.assertEqual([n.get('label') for n in page['nodes']],['1','2'])

    def test_author_recovery_uses_native_membership_and_rejects_body_overlap(self):
        def char(text,x,y):return {'text':text,'font':'Times','box':[x,y,x+30,y+8]}
        blocks=[{'chars':[char('First author',10,30),char('University A',10,45)]},{'chars':[char('Second author',100,30),char('University B',100,45)]},{'chars':[char('Body before abstract',100,75),char('Body after abstract',100,95)]}]
        reconstruction=SimpleNamespace(native_characters=lambda raw:raw['native']['blocks'][0]['chars'],native_text=lambda chars,box:' '.join(c['text'] for c in chars))
        page={'page':1,'nodes':[{'id':0,'kind':'heading','text':'A sufficiently long research paper title','box':[0,0,200,20]},{'id':1,'kind':'text','text':'Duplicated author detection','box':[10,30,80,55]},{'id':2,'kind':'heading','text':'Abstract','box':[0,80,50,90]},{'id':3,'kind':'text','text':'Body stays in its own node','box':[100,75,200,120]}]}
        recover_author_band(page,{'native':{'blocks':blocks}},reconstruction)
        self.assertEqual([n['text'] for n in page['nodes'][1:3]],['First author University A','Second author University B'])
        self.assertEqual(page['nodes'][-1]['text'],'Body stays in its own node')

    def test_clipped_duplicate_headings_do_not_remove_another_column(self):
        full={'id':0,'kind':'heading','text':'4.2.3 Formatted document OCR performance','box':[0,0,300,30]}
        clipped={'id':1,'kind':'heading','text':'.2.3 Formatted document OCR performa','box':[4,0,300,30]}
        other={**full,'id':2,'box':[350,0,650,30]}
        body={'id':3,'kind':'text','text':full['text']+' followed by substantial, distinct paragraph content that must remain.','box':[0,0,300,120]}
        page={'nodes':[full,clipped,other,body]};deduplicate_text(page)
        self.assertEqual([n['id'] for n in page['nodes']],[0,2,3])
        upper={**full,'kind':'text','text':'The coefficient D is positive.'}
        lower={**upper,'id':4,'text':'The coefficient d is positive.'}
        page={'nodes':[upper,lower]};deduplicate_text(page);self.assertEqual(len(page['nodes']),2)

    def test_distillation_excludes_test_and_incorrect_teacher(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);image=root/'source.png';image.write_bytes(b'image identity')
            rows=[dict(id=name,split=split,image=str(image),kind='text',target='correct') for name,split in [('a','train'),('b','train'),('v','validation'),('t','test')]]
            manifest=root/'manifest.jsonl';manifest.write_text('\n'.join(json.dumps(r) for r in rows))
            predictions=root/'teacher.jsonl';predictions.write_text('\n'.join(json.dumps(dict(id=r['id'],prediction='wrong' if r['id']=='b' else 'correct',seconds=1)) for r in rows))
            prepare_training(SimpleNamespace(manifest=manifest,teachers=[predictions],output=root/'training'))
            selected=list(map(json.loads,(root/'training/train.jsonl').read_text().splitlines()))
            self.assertEqual([r['id'] for r in selected],['a'])
            self.assertNotIn('t',[r['id'] for r in json.loads((root/'training/audit.json').read_text())])

    def test_training_retains_valid_authored_command_boundaries(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);image=root/'source.png';image.write_bytes(b'image identity')
            row={'id':'formula','split':'train','image':str(image),'kind':'formula','target':r'\log x+\sin y'}
            manifest=root/'manifest.jsonl';manifest.write_text(json.dumps(row)+'\n')
            predictions=root/'teacher.jsonl';predictions.write_text(json.dumps({'id':'formula','prediction':r'\log x + \sin y','seconds':1})+'\n')
            prepare_training(SimpleNamespace(manifest=manifest,teachers=[predictions],output=root/'training'))
            selected=json.loads((root/'training/train.jsonl').read_text())
            self.assertEqual(selected['messages'][-1]['content'],'$$\n'+row['target']+'\n$$')


if __name__=='__main__':unittest.main()
