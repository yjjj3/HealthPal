"""Generate public demo configuration only in CI; never replace real files."""
import json
import os
from pathlib import Path

if os.environ.get("CI") != "true":
    raise SystemExit("This script is only for CI demo configuration.")
options = Path("lib/firebase_options.dart")
if not options.exists():
    options.write_text("""import 'package:firebase_core/firebase_core.dart';
class DefaultFirebaseOptions {
  static const currentPlatform = FirebaseOptions(
    apiKey: 'demo-healthpal-ci-public-placeholder',
    appId: '1:123456789:android:abcdef123456',
    messagingSenderId: '123456789', projectId: 'demo-healthpal',
  );
}
""")
config = Path("android/app/google-services.json")
if not config.exists():
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text(json.dumps({
        "project_info": {"project_number": "123456789", "project_id": "demo-healthpal", "storage_bucket": "demo-healthpal.appspot.com"},
        "client": [{"client_info": {"mobilesdk_app_id": "1:123456789:android:abcdef123456", "android_client_info": {"package_name": "com.example.health_management_app"}}, "api_key": [{"current_key": "demo-healthpal-ci-public-placeholder"}]}],
        "configuration_version": "1",
    }))
