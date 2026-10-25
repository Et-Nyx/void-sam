"""Host-safe checks; never run the desktop installer with --apply on Void."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "desktop user"
        self.home.mkdir()
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{self.bin}:{os.environ['PATH']}")
        self.mock("id", "echo 1000\n")

    def mock(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run(["sh", str(ROOT / "scripts" / name), *args],
                              env=self.env, text=True, capture_output=True,
                              cwd=self.temp.name)

    def configure(self, *args):
        return self.run_script("configure-user.sh", *args)

    def test_shell_syntax(self):
        for path in [*ROOT.glob("scripts/*.sh"), ROOT / "config/xinitrc"]:
            result = subprocess.run(["sh", "-n", str(path)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_dry_run_has_no_side_effects(self):
        # A called package manager would create evidence and fail the test.
        self.mock("xbps-install", 'touch "$HOME/unexpected"; exit 1\n')
        for script in ("install-desktop.sh", "configure-user.sh"):
            result = self.run_script(script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("DRY RUN", result.stdout)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_invalid_arguments(self):
        for script in ("install-desktop.sh", "configure-user.sh"):
            for args in [("--force",), ("--apply", "extra")]:
                self.assertEqual(self.run_script(script, *args).returncode, 2)
        self.assertEqual(list(self.home.iterdir()), [])

    def test_install_and_repeat(self):
        for _ in range(2):
            result = self.configure("--apply")
            self.assertEqual(result.returncode, 0, result.stderr)
        for target, source in [(".xinitrc", "xinitrc"),
                               (".icewm/menu", "icewm/menu"),
                               (".icewm/toolbar", "icewm/toolbar")]:
            self.assertEqual((self.home / target).read_bytes(),
                             (ROOT / "config" / source).read_bytes())
        self.assertTrue(os.access(self.home / ".xinitrc", os.X_OK))

    def test_existing_config_is_preserved_before_any_copy(self):
        icewm = self.home / ".icewm"
        icewm.mkdir()
        menu = icewm / "menu"
        menu.write_text("personal menu\n")
        result = self.configure("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(menu.read_text(), "personal menu\n")
        self.assertFalse((self.home / ".xinitrc").exists())
        self.assertFalse((icewm / "toolbar").exists())

    def test_identical_xinitrc_gets_execute_permission(self):
        target = self.home / ".xinitrc"
        target.write_bytes((ROOT / "config/xinitrc").read_bytes())
        target.chmod(0o600)
        result = self.configure("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.access(target, os.X_OK))

    def test_refuse_symlinked_directory(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (self.home / ".icewm").symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.configure("--apply").returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse((self.home / ".xinitrc").exists())

    def test_refuse_dangling_file_symlink(self):
        (self.home / ".xinitrc").symlink_to(self.home / "missing")
        self.assertNotEqual(self.configure("--apply").returncode, 0)
        self.assertFalse((self.home / ".icewm").exists())

    def test_refuse_non_directory_icewm(self):
        (self.home / ".icewm").write_text("keep")
        self.assertNotEqual(self.configure("--apply").returncode, 0)
        self.assertFalse((self.home / ".xinitrc").exists())

    def test_refuse_root_user_configuration(self):
        self.mock("id", "echo 0\n")
        result = self.configure("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without sudo", result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])

    @unittest.skipIf('ID=void' in Path('/etc/os-release').read_text(),
                     'Never exercise system installation on a Void test host')
    def test_installer_refuses_non_void_before_package_changes(self):
        self.mock("xbps-install", 'touch "$HOME/unexpected"\n')
        result = self.run_script("install-desktop.sh", "--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Requires Void Linux", result.stderr)
        self.assertEqual(list(self.home.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
