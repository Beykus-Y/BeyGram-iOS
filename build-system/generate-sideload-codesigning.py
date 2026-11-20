#!/usr/bin/env python3
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser(description='Generate self-signed fake codesigning directory for sideload IPA builds.')
    parser.add_argument('--bundleId', required=True)
    parser.add_argument('--teamId', default='C67CF9S4VU')
    parser.add_argument('--certsDir', default='build-system/fake-codesigning/certs')
    parser.add_argument('--outDir', required=True)
    args = parser.parse_args()

    profiles_dir = os.path.join(args.outDir, 'profiles')
    certs_out_dir = os.path.join(args.outDir, 'certs')
    os.makedirs(profiles_dir, exist_ok=True)
    os.makedirs(certs_out_dir, exist_ok=True)

    for fn in os.listdir(args.certsDir):
        src = os.path.join(args.certsDir, fn)
        if os.path.isfile(src):
            shutil.copyfile(src, os.path.join(certs_out_dir, fn))

    cer_path = os.path.join(args.certsDir, 'Public.cer')
    p12_path = os.path.join(args.certsDir, 'SelfSigned.p12')
    with open(cer_path, 'rb') as f:
        cer_der = f.read()

    plist_data = {
        'AppIDName': 'BeyGram',
        'ApplicationIdentifierPrefix': [args.teamId],
        'CreationDate': datetime(2026, 1, 1, 0, 0, 0, tzinfo=timezone.utc),
        'DeveloperCertificates': [cer_der],
        'Entitlements': {
            'application-identifier': f'{args.teamId}.{args.bundleId}',
            'com.apple.developer.team-identifier': args.teamId,
            'com.apple.security.application-groups': [f'group.{args.bundleId}'],
            'get-task-allow': False,
            'keychain-access-groups': [f'{args.teamId}.*'],
        },
        'ExpirationDate': datetime(2035, 1, 1, 0, 0, 0, tzinfo=timezone.utc),
        'IsXcodeManaged': False,
        'Name': f'BeyGram Sideload {args.bundleId}',
        'Platform': ['iOS'],
        'TeamIdentifier': [args.teamId],
        'TeamName': 'BeyGram',
        'TimeToLive': 3650,
        'UUID': str(uuid.uuid4()),
        'Version': 1,
    }

    with tempfile.TemporaryDirectory() as tmp:
        plist_path = os.path.join(tmp, 'profile.plist')
        pem_path = os.path.join(tmp, 'signing.pem')
        with open(plist_path, 'wb') as f:
            plistlib.dump(plist_data, f)

        try:
            subprocess.check_call([
                'openssl', 'pkcs12',
                '-legacy',
                '-in', p12_path,
                '-passin', 'pass:',
                '-nodes',
                '-out', pem_path,
            ])
        except subprocess.CalledProcessError:
            subprocess.check_call([
                'openssl', 'pkcs12',
                '-in', p12_path,
                '-passin', 'pass:',
                '-nodes',
                '-out', pem_path,
            ])

        out_profile = os.path.join(profiles_dir, 'Telegram.mobileprovision')
        subprocess.check_call([
            'openssl', 'smime',
            '-sign',
            '-in', plist_path,
            '-signer', pem_path,
            '-inkey', pem_path,
            '-nodetach',
            '-outform', 'DER',
            '-out', out_profile,
        ])

    print(f'Generated sideload codesigning profile at {out_profile} for {args.teamId}.{args.bundleId}')


if __name__ == '__main__':
    main()
