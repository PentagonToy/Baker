"""Model-free geometry checks and optional original-corpus acceptance checks."""
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import unittest

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[1] / 'Sources/Baker/Resources/document_reconstruction.py'
spec = importlib.util.spec_from_file_location('reconstruction', SOURCE)
worker = importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)


class ReconstructionTests(unittest.TestCase):
    def test_column_order_with_spanning_figure(self):
        nodes = [{'id':i,'kind':kind,'box':box} for i,kind,box in [
            (0,'heading',[52,400,480,430]), (1,'heading',[520,50,940,80]),
            (2,'text',[52,450,480,490]), (3,'text',[520,90,940,130]),
            (4,'figure',[40,600,950,800]), (5,'text',[52,100,480,140])]]
        ordered=worker.reading_order(nodes,1000)
        self.assertLess(ordered.index(nodes[0]),ordered.index(nodes[1]))
        self.assertEqual(ordered[-1]['id'],4)

    def test_native_selection_uses_centres(self):
        chars=[{'text':v,'box':[x,10,x+8,20],'size':10,'baseline':20,'row':0} for v,x in [('A',0),('B',20),('C',40)]]
        self.assertEqual(worker.native_text(chars,[10,0,35,30]),'B')
        self.assertEqual(worker.native_text(chars,[0,0,50,30],[[20,0,30,30]]),'AC')

    def test_native_script_and_uncertain_mapping(self):
        chars=[{'text':'H','box':[0,0,8,10],'size':10,'baseline':10,'row':0},
               {'text':'2','box':[8,5,12,12],'size':6,'baseline':14,'row':0},
               {'text':'O','box':[12,0,20,10],'size':10,'baseline':10,'row':0}]
        self.assertEqual(worker.native_text(chars,[-1,-1,21,15]),'H$_{2}$O')
        self.assertFalse(worker.compatible_native('ðZÞ','(Z)'))
        self.assertFalse(worker.compatible_native('unrelated phrase','hydrogen'))

    def test_raised_correspondence_marker_keeps_superscript(self):
        chars=[{'text':c,'box':[-18+i*6,0,-12+i*6,10],'size':10,'baseline':10,'row':0} for i,c in enumerate('Name')]+[
               {'text':'a','box':[8,-2,12,5],'size':7,'baseline':6,'row':0,'flags':1},
               {'text':',','box':[12,-2,14,5],'size':7,'baseline':6,'row':0,'flags':1},
               {'text':'*','box':[14,-2,19,5],'size':8.7,'baseline':6,'row':0,'flags':1,'font':'AdvCORRESAST'}]
        self.assertEqual(worker.native_text(chars,[-20,-3,20,11]),'Name$^{a,*}$')

    def test_front_matter_recovers_clipped_name_without_adjacent_blocks(self):
        text='Jonathan Regele'
        raw=[{'c':c,'bbox':[i*6,10,i*6+6,20],'origin':[i*6,20]} for i,c in enumerate(text)]
        page={'page':1,'size':[0,0,300,300],'raster_size':[300,300],
              'native':{'blocks':[{'bbox':[0,10,len(text)*6,20],
              'lines':[{'spans':[{'font':'Roman','size':10,'flags':0,'chars':raw},{'font':'Roman','size':7,'flags':1,'chars':[{'c':'a','bbox':[len(text)*6-1,8,len(text)*6+1,15],'origin':[len(text)*6,15]}]}]}]}]}}
        chars=worker.native_characters(page)
        element={'box':[8,9,len(text)*6+2,21]}
        self.assertEqual(worker.front_matter_text(page,chars,element,'onathan Regele'),text+'$^{a}$')
        page['page']=2
        self.assertEqual(worker.front_matter_text(page,chars,element,'onathan Regele'),'onathan Regele')
        page['page']=1
        self.assertEqual(worker.front_matter_text(page,chars,element,'Different paragraph'),'Different paragraph')

    def test_numeric_style_uses_native_font_without_changing_values(self):
        chars=[{'text':c,'box':[i*5,0,i*5+5,10],'font':'Roman','flags':0} for i,c in enumerate('Le=1.8')]
        self.assertEqual(worker.native_numeric_style(r'Le={\bf1}.8',chars),'Le=1.8')
        self.assertEqual(worker.native_numeric_style(r'Le=\mathbf{1.8}',chars),'Le=1.8')
        self.assertEqual(worker.native_numeric_style(r'Le=\mathbf{0.6}',chars),r'Le=\mathbf{0.6}')
        chars[-1]['flags']=16
        self.assertEqual(worker.native_numeric_style(r'Le=\mathbf{1.8}',chars),r'Le=\mathbf{1.8}')

    def test_render_keeps_math_and_escapes_prose(self):
        self.assertEqual(worker.inline_tex('50% $x_{2}$ & water'),r'50\% $x_{2}$ \& water')
        d={'nodes':[{'kind':'equation','text':r'\partial_t u=0','label':'21a'},
                    {'kind':'text','text':'Literal # & $x$'}]}
        self.assertIn(r'\tag{21a}',worker.latex(d))
        self.assertIn('$$\n',worker.markdown(d))

    def test_spanning_table_headers_are_not_flattened(self):
        table={'kind':'table','rows':[['Method','Scores',''],['','en','zh'],['GOT','0.972','0.980']],
               'header_rows':2,'spans':[{'row':0,'column':0,'rowspan':2,'colspan':1},
                                      {'row':0,'column':1,'rowspan':1,'colspan':2},
                                      {'row':1,'column':1,'rowspan':1,'colspan':1},
                                      {'row':1,'column':2,'rowspan':1,'colspan':1}]}
        html=worker.html_table(table)
        self.assertIn('rowspan="2"',html);self.assertIn('colspan="2"',html)
        tex=worker.latex({'nodes':[table]})
        self.assertIn(r'\multirow{2}',tex);self.assertIn(r'\multicolumn{2}',tex)
        self.assertIn('0.972',tex)

    def test_native_caption_recovers_a_detector_omission(self):
        chars=[{'c':c,'bbox':[i*5,100,i*5+5,110],'origin':[i*5,110]} for i,c in enumerate('Table 1: Values')]
        page={'page':1,'size':[0,0,300,300],'raster_size':[300,300],'layout':[],
              'native':{'blocks':[{'bbox':[0,100,100,112],'lines':[{'spans':[{'font':'Roman','flags':0,'size':10,'chars':chars}]}]}]},
              'elements':[{'type':'TABLE','box':[0,10,100,90],'score':1,'text':'','meta':{'cells':[],'markdown':['| Value |']}}]}
        result=worker.reconstruct(page)
        table=next(n for n in result['nodes'] if n['kind']=='table')
        self.assertEqual(table['caption'],'Table 1: Values')

    @unittest.skipUnless(os.getenv('BAKER_DOCUMENT_FIXTURES'), 'Set BAKER_DOCUMENT_FIXTURES to the cached original corpus.')
    def test_original_corpus_failures(self):
        root=Path(os.environ['BAKER_DOCUMENT_FIXTURES'])
        results=[worker.reconstruct(json.loads(p.read_text())) for p in sorted(root.glob('*.json'))]
        self.assertEqual(len(results),11)
        first=worker.markdown(results[0])
        self.assertIn('Jonathan D. Regele $^{a}$',first)
        self.assertIn('Heinz Pitsch $^{c}$',first)
        self.assertIn('Guillaume Blanquart $^{a,*}$',first)
        self.assertNotIn('⇑',first)
        self.assertNotIn('* $^{a}$ California',first)
        labels=[n['label'] for page in results for n in page['nodes'] if n['kind']=='equation' and n.get('label')]
        expected=[str(i) for i in range(1,29) if i!=21]+['21a','21b','21c','21d']
        self.assertCountEqual(labels,expected)
        self.assertTrue(all(not page['diagnostics']['unmatched_labels'] for page in results))
        page6=worker.markdown(results[5])
        self.assertLess(page6.index('4. One-dimensional'),page6.index('4.1. Numerical'))
        self.assertIn('Fig. 6. Comparison',page6)
        lists=[n for n in results[2]['nodes'] if n['kind']=='list']
        self.assertTrue(lists);self.assertEqual(len(lists[0]['text'].splitlines()),2)
        table=next(n for n in results[2]['nodes'] if n['kind']=='table')['rows']
        self.assertEqual(table[2][0],'O$_{2}$')
        self.assertEqual(table[5][0],'C$_{3}$H$_{8}$')
        self.assertIn(r'\phi',table[0][1]);self.assertIn(r'\phi',table[0][2])
        self.assertEqual(table[4][1],'–')


if __name__=='__main__': unittest.main()
