"""Transport regression: the helper consumes raw context JSON, not a prose prompt."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EvaluationTransportTests(unittest.TestCase):
    def test_live_transport_is_raw_context_and_measures_only_responses(self):
        fixture = json.loads((ROOT / 'tests/fixtures/fm_cases.json').read_text())['cases'][0]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            fixtures = path / 'fixtures.json'
            fixtures.write_text(json.dumps({'cases': [fixture]}))
            validator = path / 'validator.py'
            validator.write_text('import json,sys\njson.load(sys.stdin)\n')
            helper = path / 'helper'
            helper.write_text('#!' + sys.executable + '\nimport json,sys\n'
                              'assert sys.argv[1:]==["--purpose","ai-heal","--model","system"]\n'
                              'ctx=json.load(sys.stdin)\n'
                              'assert {"schema","module","error","evidence","facts","previous_attempt","os"} <= ctx.keys()\n'
                              'assert ctx["schema"] == "meister.context/v1"\n'
                              'assert ctx["evidence"][0]["id"] == "E1"\n'
                              'print(' + repr(json.dumps(fixture['reference_response'])) + ')\n')
            helper.chmod(0o700)
            report = path / 'report.json'
            command = [sys.executable, str(ROOT / 'scripts/evaluate-fm.py'), '--live',
                       '--helper', str(helper), '--fixtures', str(fixtures),
                       '--contract', str(validator), '--output', str(report)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            measured = json.loads(report.read_text())
            self.assertEqual(measured['summary']['successful_model_responses'], 1)
            self.assertTrue(measured['model_quality_measured'])
            helper.write_text('#!' + sys.executable + '\nimport sys\nsys.exit(2)\n')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            failed = json.loads(report.read_text())
            self.assertTrue(failed['live_evaluation_attempted'])
            self.assertFalse(failed['model_quality_measured'])
            self.assertEqual(failed['summary']['attempted_model_queries'], 1)
            self.assertEqual(failed['summary']['successful_model_responses'], 0)


    def test_ollama_transport_model_selection_and_safe_errors(self):
        fixture = json.loads((ROOT / 'tests/fixtures/fm_cases.json').read_text())['cases'][0]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            fixtures = path / 'fixtures.json'
            fixtures.write_text(json.dumps({'cases': [fixture]}))
            helper = path / 'client.py'
            helper.write_text('import json,os,sys\n'
                              'assert sys.argv[1:]==["--purpose","ai-heal"]\n'
                              'assert os.environ["MEISTER_OLLAMA_MODEL"] == os.environ["EXPECTED_MODEL"]\n'
                              'ctx=json.load(sys.stdin)\n'
                              'assert ctx["schema"] == "meister.context/v1"\n'
                              'assert ctx["evidence"][0]["id"] == "E1"\n'
                              'print(' + repr(json.dumps(fixture['reference_response'])) + ')\n')
            report = path / 'report.json'
            command = [sys.executable, str(ROOT / 'scripts/evaluate-fm.py'), '--live',
                       '--backend', 'ollama', '--helper', str(helper), '--fixtures', str(fixtures),
                       '--output', str(report), '--include-responses']
            for cli_model, configured_model, expected in [
                    ('explicit:8b', 'configured:8b', 'explicit:8b'),
                    (None, 'configured:8b', 'configured:8b'),
                    (None, None, 'qwen3-coder:30b')]:
                with self.subTest(model=expected):
                    env = dict(os.environ, EXPECTED_MODEL=expected)
                    env.pop('MEISTER_OLLAMA_MODEL', None)
                    if configured_model:
                        env['MEISTER_OLLAMA_MODEL'] = configured_model
                    result = subprocess.run(command + (['--model', cli_model] if cli_model else []),
                                            env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                    measured = json.loads(report.read_text())
                    self.assertEqual(measured['mode'], 'live_ollama_model')
                    self.assertEqual(measured['backend'], 'ollama')
                    self.assertEqual(measured['model'], expected)
                    self.assertTrue(measured['model_quality_measured'])
                    self.assertFalse(measured['repair_execution'])
                    self.assertEqual(measured['cases'][0]['diagnosis'], fixture['reference_response'])
            helper.write_text('import sys\n'
                              "print('{\"backend\":\"ollama\",\"status\":\"model-unavailable\"}', file=sys.stderr)\n"
                              'sys.exit(69)\n')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
            failed = json.loads(report.read_text())
            self.assertFalse(failed['model_quality_measured'])
            self.assertEqual(failed['cases'][0]['error_kind'], 'model-unavailable')
            self.assertEqual(failed['cases'][0]['helper_exit'], 69)
            self.assertIsNone(failed['cases'][0]['diagnosis'])

if __name__ == '__main__':
    unittest.main()
