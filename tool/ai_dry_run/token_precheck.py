#!/usr/bin/env python3
"""Inventory only: never installs a tokenizer or downloads an encoding cache."""
import hashlib, importlib.util, json, pathlib, re, argparse
ROOT=pathlib.Path(__file__).resolve().parents[2]
def precheck():
    source=(ROOT/'lib/services/prescription_scan_service.dart').read_text()
    prompt=re.search(r"_prescriptionPrompt = '''([\s\S]*?)''';",source).group(1)
    schema_path=ROOT/'test/fixtures/prescription_eval/production-response-schema.json'
    schema=schema_path.read_text()
    manifest=json.loads((ROOT/'test/fixtures/prescription_images/manifest.json').read_text())
    installed={k:importlib.util.find_spec(k) is not None for k in ['tiktoken','tokenizers']}
    # An installed module alone does not prove a locally cached GPT-4o encoding.
    # No get_encoding()/from_pretrained() call: those can silently download.
    return {'status':'unverified','installedTokenizerModules':installed,'encodingExecuted':False,'cacheDownloaded':False,'reason':'No verified local GPT-4o tokenizer/cache execution; character/byte inventories are not token counts.','modelAlias':'gpt-4o','nonImageTokenAssumption':10000,'assumptionVerified':False,'promptSha256':hashlib.sha256(prompt.encode()).hexdigest(),'schemaSha256':hashlib.sha256(schema_path.read_bytes()).hexdigest(),'inputInventory':[{'caseId':c['caseId'],'promptUtf8Bytes':len(prompt.encode()),'schemaUtf8Bytes':len(schema.encode()),'imageBytes':c['bytes'],'imageWidth':c['width'],'imageHeight':c['height'],'inputTokensMeasured':None,'outputTokensMeasured':None} for c in manifest['cases']]}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args();pathlib.Path(a.output).write_text(json.dumps(precheck(),indent=2)+'\n');print('Token precheck unverified; no tokenizer/cache downloaded.')
