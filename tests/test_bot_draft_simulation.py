from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BotDraftSimulation(unittest.TestCase):
    def test_actual_lua_selector_beats_random_quality_gate(self):
        result = subprocess.run(
            [
                sys.executable,
                "-X",
                "utf8",
                "scripts/simulate_bot_draft.py",
                "--rounds",
                "100",
                "--seed",
                "20260904",
                "--top",
                "2",
            ],
            cwd=ROOT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("actual selector=game/dota_addons/overforged", result.stdout)
        self.assertIn("duplicate violations=0", result.stdout)
        self.assertIn("weak-cap violations=0", result.stdout)
        self.assertIn("zero-role picks=0", result.stdout)
        self.assertIn("QUALITY GATE: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
