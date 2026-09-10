#!/usr/bin/env python3
"""Run isolated CloudKit integration checks using a provisioned Development build."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path,
                        help='Signed, CloudKit-provisioned Development .app')
    args = parser.parse_args()
    app = args.app.resolve()
    root = Path(__file__).resolve().parent.parent
    run('codesign', '--verify', '--strict', str(app))
    result = run('codesign', '--display', '--entitlements', ':-', str(app),
                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    entitlements = plistlib.loads(result.stdout)
    if entitlements.get('com.apple.developer.icloud-container-environment') != 'Development':
        parser.error('Requires Development CloudKit entitlements; Production is never used.')
    if 'CloudKit' not in entitlements.get('com.apple.developer.icloud-services', []):
        parser.error('This app is not provisioned for CloudKit.')
    profile = app / 'Contents/embedded.provisionprofile'
    if not profile.is_file():
        parser.error('The app has no embedded provisioning profile.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='tenuo-sync-check-') as temporary:
        work = Path(temporary)
        prefix = work / 'certificate'
        run('codesign', '--display', f'--extract-certificates={prefix}', str(app))
        identity = hashlib.sha1(Path(str(prefix) + '0').read_bytes()).hexdigest()
        bundle = work / 'Tenuo Sync Check.app'
        contents = bundle / 'Contents'
        executable = contents / 'MacOS/SyncCheck'
        executable.parent.mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': info['CFBundleIdentifier'],
            'CFBundleExecutable': 'SyncCheck', 'CFBundlePackageType': 'APPL',
            'CFBundleName': 'Tenuo Sync Check', 'LSUIElement': True,
        }))
        shutil.copy2(profile, contents / profile.name)
        signing = work / 'entitlements.plist'
        signing.write_bytes(plistlib.dumps(entitlements))
        sources = sorted((root / 'Tenuo/Core').glob('*.swift')) + [
            root / 'Tenuo/System/CloudProfileTransport.swift',
            root / 'Tenuo/System/ProfileSyncController.swift',
            root / 'tools/SyncCheck.swift',
        ]
        print('Compiling production sync code with two isolated clients…', flush=True)
        run('xcrun', 'swiftc', '-D', 'DEBUG', '-parse-as-library',
            *map(str, sources), '-o', str(executable))
        run('codesign', '--force', '--sign', identity, '--entitlements', str(signing),
            '--options', 'runtime', '--timestamp=none', str(bundle))
        run(str(executable))


if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f'Sync check failed: {error}')
