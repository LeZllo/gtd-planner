"""Portable packaging regression tests; Swift and macOS signing are mocked.

Run with: python3 -B -m unittest discover -s Tests/BuildScriptTests -v
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


MOCK_TOOL = r'''
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
mode = os.environ["MOCK_MODE"]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps({
        "name": name, "args": args,
        "swift_cache": os.environ.get("SWIFT_MODULECACHE_PATH"),
        "clang_cache": os.environ.get("CLANG_MODULE_CACHE_PATH"),
        "old_app_exists": Path(os.environ["MOCK_OLD_APP"]).exists(),
    }) + "\n")
if name == "mkdir":
    for arg in args:
        if arg != "-p" and not arg.startswith("/private/tmp/gtd-planner-"):
            Path(arg).mkdir(parents=True, exist_ok=True)
elif name == "swift":
    if "--show-bin-path" in args:
        if mode == "query_failure":
            sys.exit(13)
        print("" if mode == "empty_path" else os.environ["MOCK_BIN_DIR"])
    else:
        if mode == "build_failure":
            sys.exit(12)
        executable = Path(os.environ["MOCK_BIN_DIR"]) / "GTDPlanner"
        executable.parent.mkdir(parents=True, exist_ok=True)
        if mode != "missing_executable":
            executable.write_text("new executable")
            executable.chmod(0o644 if mode == "not_executable" else 0o755)
        print("Build complete! (mock)")
elif name == "codesign":
    if mode == "sign_failure" and "--force" in args:
        sys.exit(14)
    if mode == "verify_failure" and "--verify" in args:
        sys.exit(15)
'''


class BuildAppTests(unittest.TestCase):
    def run_build(self, mode, shell):
        with tempfile.TemporaryDirectory(prefix="gtd packaging test ") as directory:
            base = Path(directory).resolve()
            project = base / "GTD Planner 测试"
            project.mkdir()
            script = Path(__file__).resolve().parents[2] / "build-app.sh"
            shutil.copy2(script, project / script.name)
            (project / "Info.plist").write_text("new Info.plist")
            app = project / "GTD Planner.app"
            app.mkdir()
            old_app = app / "previous-build-marker"
            old_app.write_text("keep until verified")
            bin_dir = base / "nonstandard output" / "out" / "Products" / "Release"
            tools = base / "mock tools"
            tools.mkdir()
            for name in ("swift", "codesign", "xattr", "mkdir"):
                tool = tools / name
                tool.write_text("#!" + sys.executable + "\n" + MOCK_TOOL)
                tool.chmod(0o755)
            log = base / "calls.jsonl"
            env = os.environ.copy()
            env.update(
                PATH=str(tools) + os.pathsep + env.get("PATH", ""),
                MOCK_MODE=mode, MOCK_LOG=str(log), MOCK_BIN_DIR=str(bin_dir),
                MOCK_OLD_APP=str(old_app),
            )
            result = subprocess.run(
                [shell, str(project / script.name)], env=env,
                capture_output=True, text=True, check=False,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            swift_calls = [call for call in calls if call["name"] == "swift"]
            expected = ["build", "-c", "release", "--scratch-path",
                        "/private/tmp/gtd-planner-build", "--package-path", str(project)]
            self.assertEqual(swift_calls[0]["args"], expected)
            if mode != "build_failure":
                self.assertEqual(swift_calls[1]["args"], expected + ["--show-bin-path"])
            for call in swift_calls:
                self.assertEqual(call["swift_cache"], "/private/tmp/gtd-planner-swift-module-cache")
                self.assertEqual(call["clang_cache"], "/private/tmp/gtd-planner-clang-cache")
            signatures = [call for call in calls if call["name"] == "codesign"]
            if mode == "success":
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((app / "Contents/MacOS/GTDPlanner").read_text(), "new executable")
                self.assertEqual((app / "Contents/Info.plist").read_text(), "new Info.plist")
                self.assertTrue((app / "Contents/Resources").is_dir())
                self.assertFalse(old_app.exists())
                self.assertIn("Built: " + str(app), result.stdout)
                self.assertEqual([call["args"] for call in signatures], [
                    ["--force", "--sign", "-", "--timestamp=none", str(bin_dir / "GTDPlanner")],
                    ["--verify", "--strict", str(bin_dir / "GTDPlanner")],
                ])
                self.assertTrue(all(call["old_app_exists"] for call in signatures))
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(old_app.exists())
                self.assertNotIn("Built:", result.stdout)
                if mode not in ("sign_failure", "verify_failure"):
                    self.assertEqual(signatures, [])
                if mode in ("empty_path", "missing_executable", "not_executable"):
                    self.assertIn("did not produce an executable", result.stderr)

    def test_dynamic_output_and_whitespace_paths(self):
        shells = [path for name in ("zsh", "bash") if (path := shutil.which(name))]
        if not shells:
            self.skipTest("zsh or bash is required")
        for shell in shells:
            with self.subTest(shell=shell):
                self.run_build("success", shell)

    def test_failures_preserve_previous_app(self):
        shell = shutil.which("zsh") or shutil.which("bash")
        if not shell:
            self.skipTest("zsh or bash is required")
        for mode in ("build_failure", "query_failure", "empty_path", "missing_executable",
                     "not_executable", "sign_failure", "verify_failure"):
            with self.subTest(mode=mode):
                self.run_build(mode, shell)


if __name__ == "__main__":
    unittest.main()
