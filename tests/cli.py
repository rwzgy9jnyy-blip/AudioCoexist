"""Exercise the production CLI as separate host processes in a temporary root."""

import concurrent.futures
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import threading
import unittest


EXECUTABLE = str(Path(sys.argv.pop(1)).resolve())


class ControlTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="AudioCoexist-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.preferences = self.root / "var/mobile/Library/Preferences/com.codex.audiocoexistserver.plist"
        self.environment = dict(os.environ, ASC_TEST_ROOT=str(self.root))

    def invoke(self, *arguments):
        return subprocess.run(
            [EXECUTABLE, *arguments], env=self.environment,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15,
        )

    def write(self, settings):
        self.preferences.parent.mkdir(parents=True, exist_ok=True)
        self.preferences.write_bytes(plistlib.dumps(settings))

    def read(self):
        return plistlib.loads(self.preferences.read_bytes())

    def test_arguments(self):
        for arguments in [("off", "extra"), ("status", "extra"), ("unknown",)]:
            result = self.invoke(*arguments)
            self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.preferences.exists())
        self.assertIn("enabled=1 recording=1", self.invoke().stdout)
        self.assertEqual(self.invoke("dump").returncode, 0)

    def test_roundtrip_and_permissions(self):
        self.assertEqual(self.invoke("off").returncode, 0)
        self.assertIn("enabled=0 recording=1", self.invoke("status").stdout)
        self.assertEqual(self.invoke("record-off").returncode, 0)
        self.assertIn("enabled=0 recording=0", self.invoke("status").stdout)
        self.assertEqual(self.invoke("on").returncode, 0)
        self.assertEqual(self.invoke("record-on").returncode, 0)
        self.assertIn("enabled=1 recording=1", self.invoke("status").stdout)
        self.assertEqual(self.preferences.stat().st_mode & 0o777, 0o644)
        self.assertEqual(Path(str(self.preferences) + ".lock").stat().st_mode & 0o777, 0o600)

    def test_malformed_preferences(self):
        for settings in [[], {"Enabled": [], "Recording": {}}, {"Enabled": "unknown"}]:
            self.write(settings)
            result = self.invoke("status")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("enabled=1 recording=1", result.stdout)
        self.write({"Enabled": "false", "Recording": "YES"})
        self.assertIn("enabled=0 recording=1", self.invoke("status").stdout)
        self.assertEqual(self.invoke("off").returncode, 0)

    def test_write_failures_and_symlink_lock(self):
        self.preferences.parent.mkdir(parents=True)
        self.preferences.mkdir()
        self.assertEqual(self.invoke("off").returncode, 1)
        self.assertEqual(list(self.preferences.parent.glob("*.plist.??????")), [])
        self.preferences.rmdir()
        lock = Path(str(self.preferences) + ".lock")
        lock.unlink()
        victim = self.root / "untouched"
        victim.write_text("unchanged")
        lock.symlink_to(victim)
        self.assertEqual(self.invoke("off").returncode, 1)
        self.assertEqual(victim.read_text(), "unchanged")

    def test_concurrent_updates_preserve_both_keys(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            for _ in range(20):
                self.write({"Enabled": True, "Recording": True, "Marker": "preserved"})
                barrier = threading.Barrier(2)

                def update(action):
                    barrier.wait(timeout=10)
                    result = self.invoke(action)
                    self.assertEqual(result.returncode, 0, result.stderr)

                futures = [pool.submit(update, action) for action in ["off", "record-off"]]
                for future in futures:
                    future.result(timeout=20)
                self.assertEqual(self.read(), {"Enabled": False, "Recording": False, "Marker": "preserved"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
