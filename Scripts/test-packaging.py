#!/usr/bin/env python3
"""Exercise installer output safety without Xcode, network access or mounting DMGs."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lumaview-package-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        scripts = self.root / "Scripts"
        scripts.mkdir()
        source = Path(__file__).resolve().parent
        shutil.copyfile(source / "create-dmg-layout.sh", scripts / "create-dmg-layout.sh")
        self.script = scripts / "create-dmg-layout.sh"
        self.app = self.root / "Example.app"
        self.app.mkdir()
        self.output = self.root / "output" / "Example.dmg"
        self.output.parent.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.tools = self.root / "build" / "dmg-tools" / "bin"
        self.tools.mkdir(parents=True)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        self.env["PACKAGING_PYTHON"] = str(self.bin / "chosen-python")
        self.env["PROBE_MARKER"] = str(self.root / "python-used")
        self.env["FINAL_DMG"] = str(self.output)
        self.executable(self.bin / "chosen-python", """
Path(os.environ['PROBE_MARKER']).write_text('chosen')
sys.exit(0)
""")
        self.executable(self.tools / "python3", """
if sys.argv[1:3] == ['-m', 'pip'] or 'version_info' in ' '.join(sys.argv):
    sys.exit(0)
if sys.argv[1] == '-c':
    code = sys.argv[2]
    sys.argv = ['-c'] + sys.argv[3:]
    exec(code)
""")
        self.executable(self.bin / "swift", "Path(sys.argv[-1]).write_bytes(b'background')")
        self.executable(self.tools / "dmgbuild", """
Path(sys.argv[-1]).write_bytes(b'complete installer')
if os.environ.get('RACE_OUTPUT'):
    Path(os.environ['FINAL_DMG']).write_bytes(b'concurrent installer')
sys.exit(1 if os.environ.get('FAIL_BUILD') else 0)
""")
        self.executable(self.bin / "hdiutil", "sys.exit(1 if os.environ.get('FAIL_VERIFY') else 0)")

    def executable(self, path, body):
        path.write_text(f"#!{sys.executable}\nimport os, sys\nfrom pathlib import Path\n" + body)
        path.chmod(0o755)

    def run_layout(self, **environment):
        result = subprocess.run(
            ["/bin/zsh", str(self.script), str(self.app), "output/Example.dmg", "Example"],
            cwd=self.root, env=dict(self.env, **environment), capture_output=True, text=True,
        )
        self.assertEqual(list(self.output.parent.glob(".lumaview-dmg-layout.*")), [])
        return result

    def test_existing_installer_is_preserved_before_invoking_tools(self):
        self.output.write_bytes(b'original installer')
        result = self.run_layout()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_bytes(), b'original installer')
        self.assertFalse((self.root / "python-used").exists())

    def test_existing_checksum_is_preserved(self):
        checksum = Path(str(self.output) + ".sha256")
        checksum.write_text("original hash")
        self.assertNotEqual(self.run_layout().returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertEqual(checksum.read_text(), "original hash")

    def test_dangling_symlink_is_not_replaced(self):
        self.output.symlink_to(self.root / "missing")
        self.assertNotEqual(self.run_layout().returncode, 0)
        self.assertTrue(self.output.is_symlink())

    def test_requested_python_relative_output_and_success_cleanup(self):
        result = self.run_layout()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "python-used").read_text(), "chosen")
        self.assertEqual(self.output.read_bytes(), b'complete installer')

    def test_failed_build_never_publishes_partial_image(self):
        self.assertNotEqual(self.run_layout(FAIL_BUILD="1").returncode, 0)
        self.assertFalse(self.output.exists())

    def test_failed_verification_never_publishes_image(self):
        self.assertNotEqual(self.run_layout(FAIL_VERIFY="1").returncode, 0)
        self.assertFalse(self.output.exists())

    def test_concurrent_installer_is_not_overwritten(self):
        self.assertNotEqual(self.run_layout(RACE_OUTPUT="1").returncode, 0)
        self.assertEqual(self.output.read_bytes(), b'concurrent installer')

    def test_package_entry_points_resolve_output_from_callers_directory(self):
        source = Path(__file__).resolve().parent
        self.executable(self.bin / "xcodebuild", """
import plistlib
derived = Path(sys.argv[sys.argv.index('-derivedDataPath') + 1])
app = derived / 'Build/Products/Release/LumaView.app/Contents'
app.mkdir(parents=True)
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0'}))
""")
        self.executable(self.bin / "codesign", "sys.exit(0)")
        self.executable(self.bin / "lipo", "print('arm64 x86_64')")
        self.executable(self.bin / "security", "print('1) fake \\\"Developer ID Application: Test\\\"')")
        self.executable(self.bin / "xcrun", "sys.exit(0)")
        self.executable(self.script, """
Path(os.environ['LAYOUT_DEST_FILE']).write_text(sys.argv[2])
sys.exit(74)  # Stop before any disk-image mounting or publication.
""")
        caller = self.root / "caller"
        caller.mkdir()
        marker = self.root / "destination"
        for name, suffix in [("package-dmg.sh", "universal"), ("release-notarized-dmg.sh", "universal-notarized")]:
            with self.subTest(script=name):
                script = self.root / "Scripts" / name
                shutil.copyfile(source / name, script)
                result = subprocess.run(
                    ["/bin/zsh", str(script)], cwd=caller, capture_output=True, text=True,
                    env=dict(self.env, OUTPUT_DIR="artifacts", LAYOUT_DEST_FILE=str(marker),
                             DEVELOPER_ID_APPLICATION="Developer ID Application: Test", NOTARYTOOL_PROFILE="test"),
                )
                self.assertEqual(result.returncode, 74, result.stderr)
                self.assertEqual(marker.read_text(), str(caller / "artifacts" / f"LumaView-1.0-{suffix}.dmg"))


if __name__ == "__main__":
    unittest.main()
