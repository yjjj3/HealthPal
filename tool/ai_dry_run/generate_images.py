#!/usr/bin/env python3
"""Synthetic image benchmark; Pillow only, no OCR/network. Run from repo root."""
import argparse, hashlib, json, pathlib, platform
from PIL import Image, ImageDraw, ImageFont, __version__ as pillow_version

ROOT = pathlib.Path(__file__).resolve().parents[2]
WIDTH, HEIGHT = 1024, 1536
DEFAULT_FONT = '/System/Library/Fonts/STHeiti Medium.ttc'
LABELS = {'name':'名稱', 'englishName':'英文名稱', 'brandName':'合成商品標記', 'appearance':'合成外觀', 'dosage':'測試劑量', 'unit':'測試單位', 'frequency':'測試頻率', 'timing':'測試時機', 'route':'測試途徑', 'durationDays':'測試天數', 'totalQuantity':'測試數量', 'clinicalUse':'合成用途文字', 'sideEffects':'合成警語A', 'precautions':'合成警語B', 'storageMethod':'合成保存文字', 'hospitalName':'合成機構', 'doctorName':'合成署名', 'departmentName':'合成部門', 'prescriptionDate':'合成開立日期', 'followUpDate':'合成回訪日期'}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def wrap(draw, text, font, width):
    lines = []
    for paragraph in str(text).split('\n'):
        current = ''
        for ch in paragraph:
            if current and draw.textlength(current + ch, font=font) > width:
                lines.append(current); current = ''
            current += ch
        lines.append(current)
    return lines

def generate(font_path, output):
    font_path = pathlib.Path(font_path)
    if not font_path.is_file(): raise SystemExit('Existing CJK font required; no font is downloaded.')
    golden_path = ROOT/'test/fixtures/prescription_eval/golden.json'
    golden = json.loads(golden_path.read_text())
    output.mkdir(parents=True, exist_ok=True)
    fonts = {size:ImageFont.truetype(str(font_path), size, index=0) for size in [18,20,22,24,30,40]}
    records = []
    for c in golden['cases']:
        image = Image.new('RGB',(WIDTH,HEIGHT),'white'); d=ImageDraw.Draw(image)
        d.rectangle((0,0,WIDTH,145),fill='#8c1028')
        d.text((35,20),'合成測試／非真實處方',font=fonts[40],fill='white')
        d.text((35,78),'不得醫療使用 — SYNTH 無真藥對應',font=fonts[30],fill='white')
        d.text((35,160),c['caseId']+'  '+c['scenario'],font=fonts[24],fill='black')
        truth = c['truth']; visibility={}; transformations={}
        expected = json.loads(json.dumps(truth))
        rows=truth['medicines']
        for i,row in enumerate(rows):
            x=35+i*490; y=208
            d.text((x,y),'合成藥品列 '+str(i+1),font=fonts[24],fill='#8c1028');y+=38
            for key,value in row.items():
                path=f'medicines.{i}.{key}'
                state='visible' if value is not None else 'blank'
                masked=c['caseId']=='S11' and key in ['dosage','unit','frequency']
                if masked: state='geometric_occlusion'
                visibility[path]={'state':state,'sourceValue':value}
                d.text((x,y),LABELS[key],font=fonts[18],fill='#444444')
                y+=23
                lines=wrap(d,value,fonts[22],445) if value is not None else ['']
                if masked:
                    # Opaque geometry, not the literal word "unreadable" or blur.
                    d.rectangle((x,y,x+430,y+25),fill='#222222')
                else:
                    for line in lines:
                        d.text((x,y),line,font=fonts[22],fill='black');y+=26
                    if value is None: d.line((x,y-3,x+430,y-3),fill='#bbbbbb',width=1)
                y+=10 if not masked else 36
                if y>1250: raise ValueError('Layout overflow: '+path)
            if row['name'] is None and row['englishName']:
                expected['medicines'][i]['name']=row['englishName']
                transformations[f'medicines.{i}.name']={'kind':'english_name_fallback','from':f'medicines.{i}.englishName','expected':row['englishName']}
        # Hospital block uses three columns, two rows; unknown is actual blank.
        for j,(key,value) in enumerate(truth['hospitalInfo'].items()):
            x=35+(j%3)*325;y=1280+(j//3)*70
            d.text((x,y),LABELS[key],font=fonts[18],fill='#444444')
            d.text((x,y+25),str(value) if value is not None else '',font=fonts[22],fill='black')
            if value is None:d.line((x,y+52,x+290,y+52),fill='#bbbbbb',width=1)
            visibility['hospitalInfo.'+key]={'state':'visible' if value is not None else 'blank','sourceValue':value}
        d.text((35,1470),'全為虛構欄位；人工確認必要；尚未執行 OCR／模型。',font=fonts[24],fill='#8c1028')
        path=output/(c['caseId']+'.png');image.save(path,format='PNG',optimize=False,compress_level=9)
        if path.stat().st_size>1024*1024: raise ValueError('Image over 1 MiB')
        records.append({'caseId':c['caseId'],'image':path.name,'sha256':sha(path),'width':WIDTH,'height':HEIGHT,'bytes':path.stat().st_size,'sourceImageTruth':{'medicines':truth['medicines'],'hospitalInfo':truth['hospitalInfo']},'expectedOutputContract':{'fieldTruth':{'medicines':expected['medicines'],'hospitalInfo':expected['hospitalInfo']},'successError':None,'confidence':'self_reported_0_to_1_not_scored','schemaSource':'../prescription_eval/production-response-schema.json'},'visibility':visibility,'transformations':transformations,'humanConfirmation':c['humanConfirmation']})
    manifest={'version':1,'synthetic':True,'ocrExecuted':False,'liveExecuted':False,'sourceGoldenSha256':sha(golden_path),'generatorSha256':sha(pathlib.Path(__file__)),'parameters':{'width':WIDTH,'height':HEIGHT,'format':'PNG','compressLevel':9,'fontIndex':0,'fontSizes':sorted(fonts),'fontFile':font_path.name,'fontSha256':sha(font_path),'pillowVersion':pillow_version,'pythonVersion':platform.python_version()},'hardRepeats':['S03','S11','S12','S16'],'candidateLogicalSamples':20,'attemptLimit':20,'cases':records}
    (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    print('Generated 16 synthetic images; no OCR/live executed.')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--font',default=DEFAULT_FONT);p.add_argument('--output',default=str(ROOT/'test/fixtures/prescription_images'));a=p.parse_args();generate(a.font,pathlib.Path(a.output))
