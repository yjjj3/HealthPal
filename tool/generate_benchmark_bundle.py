"""stdlib-only bundle of reviewed synthetic PNG bytes; does not render/OCR/network."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'lib/services/ai/benchmark/frozen_images.dart')
    args = parser.parse_args()
    source = ROOT / 'test/fixtures/prescription_images'
    manifest = json.loads((source / 'manifest.json').read_text())
    assert manifest['synthetic'] is True
    assert len(manifest['cases']) == 16
    text = ('// Generated from frozen synthetic fixtures; no patient data.\n'
            '// Source: test/fixtures/prescription_images/manifest.json\n'
            'const frozenImages = <String, ({String sha256, String base64})>{\n')
    for row in manifest['cases']:
        data = (source / row['image']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row['sha256']
        encoded = base64.b64encode(data).decode('ascii')
        text += f"  '{row['caseId']}': (sha256: '{row['sha256']}', base64: '{encoded}'),\n"
    args.output.write_text(text + '};\n')

if __name__ == '__main__':
    main()
