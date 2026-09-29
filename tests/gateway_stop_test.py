#!/usr/bin/env python3
"""Exercise offline commands through bin/claw with an isolated Docker stub."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a = sys.argv[1:]
with open(os.environ['TRACE'], 'a') as out:
    out.write(json.dumps(a) + '\n')
mode = os.environ['MODE']
if a[0] == 'compose':
    a = a[a.index('-f') + 2:]
    while a and a[0] == '-f':
        a = a[2:]
    if a[:2] == ['stop', 'claw']:
        if mode == 'stop-error': sys.exit(1)
    elif a[:4] == ['ps', '--all', '--quiet', 'claw']:
        if mode == 'list-error': sys.exit(1)
        if mode != 'absent': print('synthetic-container')
    elif a[:2] == ['config', '--services']:
        print('claw')
    elif a[0] == 'run':
        if 'doctor' in a and mode == 'doctor-error': sys.exit(1)
        if mode == 'backup-error': sys.exit(1)
elif a[0] == 'inspect':
    if '.State.Restarting' in a[2]:
        if mode == 'inspect-error': sys.exit(1)
        print({'running': 'true false', 'restarting': 'false true'}.get(mode, 'false false'))
    else:
        print('false')
'''


class GatewayStopTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ('bin', 'hosting/local', 'instance', 'stub', 'data/state'):
            (self.root / directory).mkdir(parents=True)
        shutil.copy(ROOT / 'bin/claw', self.root / 'bin/claw')
        (self.root / 'hosting/local/profile.env').write_text('CLAW_AUTH_MODE=token\n')
        (self.root / 'instance/claw.env').write_text('CLAW_PROFILE=local\nCLAW_INSTANCE=teamclaw\n')
        (self.root / 'data/state/openclaw.json').write_text('{}')
        stub = self.root / 'stub/docker'
        stub.write_text(STUB)
        stub.chmod(0o755)
        # Avoid host ownership changes in cmd_init during deploy tests.
        for directory in ('workspace', 'workspaces', 'auth-profile-secrets', 'gh-config', 'backups'):
            (self.root / 'data' / directory).mkdir()

    def run_claw(self, command, mode):
        trace = self.root / 'trace'
        trace.write_text('')
        env = {'PATH': str(self.root / 'stub') + os.pathsep + os.environ['PATH'],
               'HOME': str(self.root), 'TRACE': str(trace), 'MODE': mode,
               'CLAW_DATA': str(self.root / 'data'), 'CLAW_PROFILE': 'local',
               'CLAW_INSTANCE': 'teamclaw', 'CLAW_BUILD': 'no',
               'OPENCLAW_GATEWAY_TOKEN': 'synthetic-token'}
        result = subprocess.run([str(self.root / 'bin/claw'), command], env=env,
                                capture_output=True, text=True)
        calls = [json.loads(line) for line in trace.read_text().splitlines()]
        return result, calls

    def test_failures_prevent_offline_containers(self):
        for command in ('doctor', 'backup', 'deploy'):
            for mode in ('stop-error', 'list-error', 'inspect-error', 'running', 'restarting'):
                with self.subTest(command=command, mode=mode):
                    result, calls = self.run_claw(command, mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any('run' in call for call in calls), calls)
                    self.assertFalse(any('start' in call or 'up' in call for call in calls), calls)

    def test_stopped_gateway_allows_doctor(self):
        result, calls = self.run_claw('doctor', 'stopped')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any('doctor' in call for call in calls))

    def test_first_boot_allows_doctor(self):
        result, calls = self.run_claw('doctor', 'absent')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any('doctor' in call for call in calls))

    def test_doctor_failure_propagates(self):
        result, _ = self.run_claw('doctor', 'doctor-error')
        self.assertNotEqual(result.returncode, 0)

    def test_backup_failure_propagates(self):
        result, _ = self.run_claw('backup', 'backup-error')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
