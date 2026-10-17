"""Create authored OCR examples with separate training and evaluation content."""
import argparse
import hashlib
import json
from pathlib import Path
import textwrap

from PIL import Image, ImageDraw, ImageFont


TEXT = {
    'en': ['The bakery opens at seven. Fresh bread costs 4.75 euros.', 'The sample remained stable after 120 seconds at 293 K.', 'Save the original image before editing the annotation.', 'Measure the flame speed and retain every decimal place.', 'A quiet street leads to the library beside the river.', 'Batch 847 contains twelve measurements and three controls.', 'The sensor recorded 18.6 degrees on Thursday morning.', 'Keep the reference number AX-5097 with the final report.'],
    'de': ['Die Bäckerei öffnet um sieben Uhr. Frisches Brot kostet 4,75 Euro.', 'Die Probe blieb nach 120 Sekunden bei 293 K stabil.', 'Speichern Sie das Originalbild vor der Bearbeitung.', 'Messen Sie die Flammengeschwindigkeit mit allen Dezimalstellen.', 'Eine ruhige Straße führt zur Bibliothek am Fluss.', 'Die Prüfung umfasst zwölf Messungen und drei Kontrollen.', 'Der Sensor zeigte am Donnerstagmorgen 18,6 Grad an.', 'Die Kennung AX-5097 gehört in den abschließenden Bericht.'],
    'ko': ['빵집은 아침 일곱 시에 문을 엽니다. 빵 가격은 4.75유로입니다.', '시료는 293 K에서 120초 동안 안정적으로 유지되었습니다.', '주석을 편집하기 전에 원본 이미지를 저장하세요.', '화염 속도를 측정하고 소수점 아래 숫자를 보존하세요.', '강 옆의 도서관으로 조용한 길이 이어집니다.', '이번 실험에는 측정값 열두 개와 대조군 세 개가 있습니다.', '목요일 아침 센서의 온도는 18.6도였습니다.', '최종 보고서에 참조 번호 AX-5097을 기록하세요.'],
    'sv': ['Bageriet öppnar klockan sju. Färskt bröd kostar 4,75 euro.', 'Provet förblev stabilt efter 120 sekunder vid 293 K.', 'Spara originalbilden innan du ändrar anteckningen.', 'Mät flamhastigheten och behåll alla decimaler.', 'En lugn gata leder till biblioteket vid ån.', 'Försöket omfattar tolv mätningar och tre kontroller.', 'Sensorn visade 18,6 grader på torsdagsmorgonen.', 'Behåll referensnumret AX-5097 i den slutliga rapporten.'],
    'da': ['Bageriet åbner klokken syv. Frisk brød koster 4,75 euro.', 'Prøven forblev stabil efter 120 sekunder ved 293 K.', 'Gem originalbilledet, før du redigerer bemærkningen.', 'Mål flammehastigheden, og bevar alle decimaler.', 'En stille gade fører til biblioteket ved åen.', 'Forsøget omfatter tolv målinger og tre kontrolprøver.', 'Sensoren viste 18,6 grader torsdag morgen.', 'Behold referencenummeret AX-5097 i den endelige rapport.'],
    'fi': ['Leipomo avataan seitsemältä. Tuore leipä maksaa 4,75 euroa.', 'Näyte pysyi vakaana 120 sekunnin ajan 293 K:ssa.', 'Tallenna alkuperäinen kuva ennen merkintöjen muokkaamista.', 'Mittaa liekin nopeus ja säilytä kaikki desimaalit.', 'Rauhallinen katu johtaa joen vieressä olevaan kirjastoon.', 'Kokeessa on kaksitoista mittausta ja kolme vertailunäytettä.', 'Anturi näytti torstaiaamuna 18,6 astetta.', 'Säilytä viitenumero AX-5097 lopullisessa raportissa.'],
}
FORMULAS = [
    r'x^2+3x+2=0', r'v=at+v_0', r'E=mc^2', r'a^2+b^2=c^2',
    r'\frac{a+b}{c+d}', r'\sqrt{x^2+y^2}', r'\alpha+\beta=\gamma', r'y=\sin(x)+\cos(x)',
    r'\sum_{i=1}^{n}i', r'\int_0^1 x^2\,dx', r'\frac{dy}{dx}=2x', r'\lim_{x\to0}\frac{\sin x}{x}=1',
    r'pV=nRT', r'F=ma', r'\rho=\frac{m}{V}', r'\lambda=\frac{c}{f}',
    r'\log(xy)=\log x+\log y', r'\sigma^2=\frac{1}{n}\sum_{i=1}^n(x_i-\mu)^2',
    r'\frac{\partial u}{\partial t}=\nu\frac{\partial^2u}{\partial x^2}', r'\nabla\cdot\mathbf{u}=0',
    r'\frac{1}{1+x^2}', r'\sqrt[3]{x+y}', r'\theta=\frac{\pi}{6}', r'a_n=a_0r^n',
    r'\int_{-1}^{1}e^{-x^2}\,dx', r'\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
    r'\frac{\partial T}{\partial t}+u\frac{\partial T}{\partial x}=0', r'\sum_{k=0}^{\infty}\frac{x^k}{k!}=e^x',
    r'\mathbf{F}=q(\mathbf{E}+\mathbf{v}\times\mathbf{B})', r'\nabla^2\phi=0',
    r'\frac{d^2y}{dx^2}+\omega^2y=0', r'P(A\mid B)=\frac{P(B\mid A)P(A)}{P(B)}',
]


def build(output):
    output.mkdir(parents=True, exist_ok=False)
    images=output/'images'; images.mkdir(); rows=[]
    latin='/System/Library/Fonts/Supplemental/Arial.ttf'
    korean='/System/Library/Fonts/AppleSDGothicNeo.ttc'
    def save(name, image, target, kind, split, language='und'):
        path=images/(name+'.png'); image.convert('RGB').save(path)
        rows.append(dict(id=name,image=str(path.resolve()),target=target,kind=kind,split=split,language=language,origin='Baker authored synthetic example',licence='MIT',group=name,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    for language, texts in TEXT.items():
        for i, target in enumerate(texts):
            split='train' if i<4 else 'validation' if i<6 else 'test'
            font=ImageFont.truetype(korean if language=='ko' else latin, 26 if i%2 else 30)
            lines=textwrap.wrap(target,width=32 if language=='ko' else 48)
            image=Image.new('RGB',(850,60+len(lines)*45),(248,246,239) if i%3==0 else 'white')
            ImageDraw.Draw(image).multiline_text((24,22),'\n'.join(lines),font=font,fill=(24,25,27),spacing=10)
            save(f'text-{language}-{i}',image,target,'text',split,language)
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    import numpy as np
    for i, target in enumerate(FORMULAS):
        figure=Figure(figsize=(8,1.8),dpi=140); canvas=FigureCanvasAgg(figure)
        figure.text(.03,.46,'$'+target+'$',fontsize=27,va='center');canvas.draw()
        image=Image.fromarray(np.asarray(canvas.buffer_rgba()).copy()).convert('RGB')
        save(f'formula-{i:02}',image,target,'formula','train' if i<18 else 'validation' if i<24 else 'test')
    for i in range(24):
        header=['Sample','Temperature','Speed']; data=[header]+[[f'R{i+1}-{j+1}',f'{270+i*3+j:.1f}',f'{(i+1)*.13+j*.07:.2f}'] for j in range(3+i%3)]
        font=ImageFont.truetype(latin,24); image=Image.new('RGB',(760,56*len(data)+28),'white');draw=ImageDraw.Draw(image)
        for y, row in enumerate(data):
            for x, value in enumerate(row):
                box=(12+x*245,12+y*56,12+(x+1)*245,12+(y+1)*56)
                draw.rectangle(box,fill=(239,235,225) if y==0 else 'white',outline='black',width=1)
                draw.text((box[0]+10,box[1]+12),value,font=font,fill='black')
        html='<table>'+''.join('<tr>'+''.join('<td>'+v+'</td>' for v in row)+'</tr>' for row in data)+'</table>'
        save(f'table-{i:02}',image,html,'table','train' if i<12 else 'validation' if i<16 else 'test','en')
    (output/'manifest.jsonl').write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in rows))
    (output/'provenance.json').write_text(json.dumps({'purpose':'Small feasibility corpus, not a release-quality benchmark','source':'Self-authored text, formulae and tables; no paper or captured user document enters training','split':'Content-disjoint IDs; augmentations must inherit their source split','rows':len(rows)},indent=2))
    print({split:sum(r['split']==split for r in rows) for split in ['train','validation','test']})


if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,required=True)
    build(p.parse_args().output)
