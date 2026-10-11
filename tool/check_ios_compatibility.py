"""Compile Widget sources against the supported iOS floor; never run an app."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
project = json.loads(subprocess.check_output([
    'plutil', '-convert', 'json', '-o', '-',
    str(ROOT / 'ios/Runner.xcodeproj/project.pbxproj'),
], text=True))['objects']
for target in project.values():
    if target.get('isa') != 'PBXNativeTarget' or target['name'] not in ('Runner', 'HealthWidgetExtension'):
        continue
    configs = project[target['buildConfigurationList']]['buildConfigurations']
    for config in configs:
        settings = project[config]['buildSettings']
        if settings.get('IPHONEOS_DEPLOYMENT_TARGET') != '16.0':
            raise SystemExit(f"{target['name']} {project[config]['name']}: expected iOS 16.0")

sources = sorted(str(p) for p in (ROOT / 'ios/HealthWidget').glob('*.swift'))
with tempfile.TemporaryDirectory(prefix='healthpal-swift-') as cache:
    for sdk, target in (
        ('iphonesimulator', 'arm64-apple-ios16.0-simulator'),
        ('iphoneos', 'arm64-apple-ios16.0'),
    ):
        sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
        subprocess.run([
            'xcrun', 'swiftc', '-typecheck', '-warnings-as-errors',
            '-module-cache-path', cache, '-sdk', sdk_path, '-target', target, *sources,
        ], check=True)
        print(f'{target}: Widget typecheck passed (not a full app build)')
