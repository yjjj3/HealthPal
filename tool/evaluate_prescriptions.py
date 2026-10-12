#!/usr/bin/env python3
"""Offline Flutter-hosted production scan-service evaluator. No API transport."""
import argparse, json, os, pathlib, shutil, subprocess, sys, hashlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--golden', default='test/fixtures/prescription_eval/golden.json')
p.add_argument('--predictions', required=True)
p.add_argument('--output', required=True)
p.add_argument('--flutter', default=shutil.which('flutter'))
a = p.parse_args()
if not a.flutter:
    p.error('Existing Flutter executable required; use --flutter. Nothing is installed.')
out = pathlib.Path(a.output).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
# Stale results cannot masquerade as success after a failed run.
if out.exists(): out.unlink()
env = dict(os.environ, FLUTTER_SUPPRESS_ANALYTICS='true', HEALTHPAL_EVAL_GOLDEN=str(pathlib.Path(a.golden).resolve()), HEALTHPAL_EVAL_PREDICTIONS=str(pathlib.Path(a.predictions).resolve()), HEALTHPAL_EVAL_OUTPUT=str(out))
env['HEALTHPAL_EVAL_SCHEMA'] = str(out.with_suffix('.schema.json'))
command = [a.flutter, '--no-version-check', 'test', '--no-pub', 'test/prescription_eval_driver_test.dart']
log = out.with_suffix('.log')
with log.open('w') as stream:
    run = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
if run.returncode or not out.exists():
    print(f'Offline evaluation failed (exit {run.returncode}); log: {log}', file=sys.stderr)
    sys.exit(run.returncode or 1)
result = json.loads(out.read_text())
result['provenance'] = {'baseline': subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(), 'command':['flutter',*command[1:]], 'liveRequests':0, 'inputSha256':{key: hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() for key,path in [('golden',a.golden),('predictions',a.predictions)]}, 'sourceSha256':{path:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in ['lib/services/prescription_scan_service.dart','lib/models/ai/prescription_recognition.dart','lib/services/ai/ai_client.dart','functions/gateway.js']}}
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['origin','casesDenominator','completeCaseSet','jsonParseableCount','schemaValidCount','serviceAcceptedCount','wholeExactRawCount','wholeExactNormalizedCount']},ensure_ascii=False))
print(f'Result: {out}; raw execution log: {log}')
# Data/coverage failure is different from intentionally wrong scorer fixtures.
sys.exit(0 if result['completeCaseSet'] else 2)
