"""Exercise the real Ollama subprocess against a local HTTP server; no models needed."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'lib/ollama/client.py'
CONTEXT = {
    'schema': 'meister.context/v1', 'module': 'Finder',
    'evidence': [{'id': 'E1', 'text': 'Finder does not respond'}],
    'previous_attempt': '',
}
DIAGNOSIS = {
    'schema': 'meister.diagnosis/v1', 'cause': 'Finder reagiert nicht.',
    'evidence': ['E1'], 'missing_information': [],
    'next_check': 'Finder-Status erneut lesen.', 'action': 'restart_finder',
    'parameters': [],
}


class OllamaHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def respond(self):
                size = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(size)
                self.server.requests.append((self.command, self.path, body))
                time.sleep(self.server.delay)
                payload = self.server.response
                raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
                try:
                    self.send_response(self.server.status)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(raw)))
                    self.end_headers()
                    self.wfile.write(raw)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            do_GET = respond
            do_POST = respond

        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def setUp(self):
        self.server.requests = []
        self.server.delay = 0
        self.server.status = 200
        self.server.response = {'response': 'Ergebnis', 'done': True}

    def invoke(self, text='Explain Finder', purpose='explain', check=False, **settings):
        env = {key: value for key, value in os.environ.items()
               if not key.startswith('MEISTER_OLLAMA_')}
        env.update(MEISTER_OLLAMA_URL=f'http://127.0.0.1:{self.server.server_port}',
                   MEISTER_OLLAMA_MODEL='test-model',
                   NO_PROXY='127.0.0.1', no_proxy='127.0.0.1')
        env.update(settings)
        command = [sys.executable, str(CLIENT)]
        command.extend(['--check'] if check else ['--purpose', purpose])
        return subprocess.run(command, input=text, text=True, capture_output=True,
                              env=env, timeout=10, check=False)

    def assert_failure(self, result, code, kind):
        self.assertEqual(result.returncode, code, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertEqual(json.loads(result.stderr)['status'], kind)
        self.assertNotIn('Traceback', result.stderr)

    def test_available_model_name_and_latest_tag(self):
        for field, name in [('name', 'test-model'), ('name', 'test-model:latest'),
                            ('model', 'test-model:latest')]:
            with self.subTest(field=field, name=name):
                self.server.response = {'models': [{field: name}]}
                result = self.invoke(check=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '')
                self.assertEqual(self.server.requests[-1][:2], ('GET', '/api/tags'))

    def test_missing_or_similar_model_is_not_silently_selected(self):
        for models in [[], [{'name': 'test-model:other'}], [{'name': 'test-model-extra:latest'}]]:
            with self.subTest(models=models):
                self.server.response = {'models': models}
                self.assert_failure(self.invoke(check=True), 69, 'model-not-installed')
        self.assertTrue(all(path == '/api/tags' for _, path, _ in self.server.requests))

    def test_explicit_model_tag_does_not_match_latest(self):
        self.server.response = {'models': [{'name': 'test-model:latest'}]}
        self.assert_failure(self.invoke(check=True, MEISTER_OLLAMA_MODEL='test-model:7b'),
                            69, 'model-not-installed')

    def test_malformed_tags_fails(self):
        self.server.response = {'models': {}}
        self.assert_failure(self.invoke(check=True), 65, 'invalid-response')

    def test_structured_payload_and_response(self):
        for purpose in ['ai-heal', 'ai-diagnose']:
            with self.subTest(purpose=purpose):
                self.server.response = {'response': json.dumps(DIAGNOSIS), 'done': True}
                result = self.invoke(json.dumps(CONTEXT), purpose)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), DIAGNOSIS)
                method, path, raw = self.server.requests[-1]
                self.assertEqual((method, path), ('POST', '/api/generate'))
                payload = json.loads(raw)
                self.assertFalse(payload['stream'])
                schema = payload['format']
                self.assertFalse(schema['additionalProperties'])
                self.assertEqual(set(schema['required']), set(DIAGNOSIS))
                self.assertEqual(schema['properties']['evidence']['items']['enum'], ['E1'])
                self.assertEqual(schema['properties']['parameters']['maxItems'], 0)
                self.assertIn('untrusted', payload['system'])

    def test_free_text_purposes_do_not_force_json(self):
        for purpose in ['query', 'explain', 'today', 'suggest']:
            with self.subTest(purpose=purpose):
                result = self.invoke(purpose=purpose)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, 'Ergebnis')
                self.assertNotIn('format', json.loads(self.server.requests[-1][2]))

    def test_invalid_http_or_api_envelope_is_not_success(self):
        for response, status, code, kind in [
            (b'not JSON', 200, 65, 'invalid-response'),
            ([], 200, 69, 'server-error'),
            ({'error': 'secret-server-error'}, 200, 69, 'server-error'),
            ({'error': 'secret-server-error'}, 500, 69, 'http-or-transport-error'),
        ]:
            with self.subTest(response=response, status=status):
                self.server.response, self.server.status = response, status
                result = self.invoke()
                self.assert_failure(result, code, kind)
                self.assertNotIn('secret-server-error', result.stderr)

    def test_empty_and_wrong_type_response(self):
        for response in [None, '', '   ', 42, [], {}]:
            with self.subTest(response=response):
                self.server.response = {'response': response, 'done': True}
                self.assert_failure(self.invoke(), 65, 'empty-response')

    def test_incomplete_response_never_reaches_stdout(self):
        for details in [{}, {'done': False}, {'done': 'true'},
                        {'done': True, 'done_reason': 'length'}]:
            with self.subTest(details=details):
                self.server.response = {'response': 'partial unsafe output', **details}
                self.assert_failure(self.invoke(), 65, 'incomplete-response')

    def test_timeout_is_bounded_and_distinguishable(self):
        self.server.delay = 1.2
        start = time.monotonic()
        self.assert_failure(self.invoke(MEISTER_OLLAMA_TIMEOUT='1'), 75, 'timeout')
        self.assertLess(time.monotonic() - start, 4)
        # Let the timed-out handler finish before the next test mutates its fixture.
        time.sleep(0.3)

    def test_untrusted_diagnosis_rejected(self):
        variants = [
            {'evidence': ['E999']}, {'action': 'rm -rf /'},
            {'action': 'restart_dock'}, {'parameters': ['--force']},
            {'unexpected': 'field'}, {'missing_information': ['unknown permission']},
        ]
        for changes in variants:
            with self.subTest(changes=changes):
                self.server.response = {'response': json.dumps({**DIAGNOSIS, **changes}), 'done': True}
                self.assert_failure(self.invoke(json.dumps(CONTEXT), 'ai-heal'), 65, 'invalid-diagnosis')
        self.server.response = {'response': '/usr/bin/killall Finder', 'done': True}
        self.assert_failure(self.invoke(json.dumps(CONTEXT), 'ai-heal'), 65, 'invalid-diagnosis')

    def test_previously_failed_action_cannot_be_repeated(self):
        context = {**CONTEXT, 'previous_attempt': '/usr/bin/killall Finder'}
        self.server.response = {'response': json.dumps(DIAGNOSIS), 'done': True}
        self.assert_failure(self.invoke(json.dumps(context), 'ai-heal'), 65, 'invalid-diagnosis')

    def test_invalid_context_rejected_before_network(self):
        for context in ['not-json', '[]', '{}', json.dumps({**CONTEXT, 'evidence': []}),
                        json.dumps({**CONTEXT, 'evidence': [{'text': 'missing ID'}]})]:
            with self.subTest(context=context):
                self.assert_failure(self.invoke(context, 'ai-heal'), 64, 'invalid-context')
        self.assertEqual(self.server.requests, [])

    def test_redaction_applies_to_request_response_and_metadata(self):
        self.server.response = {'response': 'token=synthetic-output-secret', 'done': True,
                                'eval_count': 12, 'load_duration': 55,
                                'total_duration': 'synthetic-metadata-secret',
                                'prompt_eval_count': True, 'eval_duration': -1}
        result = self.invoke('password=synthetic-input-secret /Users/example/Documents')
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(self.server.requests[-1][2])
        self.assertNotIn('synthetic-input-secret', payload['prompt'])
        self.assertNotIn('/Users/example', payload['prompt'])
        self.assertNotIn('synthetic-output-secret', result.stdout)
        self.assertNotIn('synthetic-metadata-secret', result.stderr)
        self.assertEqual(json.loads(result.stderr), {'backend': 'ollama', 'status': 'ok',
                                                    'eval_count': 12, 'load_duration': 55})

    def test_explicit_configuration_reaches_http_payload(self):
        result = self.invoke(MEISTER_OLLAMA_MODEL='custom:7b', MEISTER_OLLAMA_KEEP_ALIVE='2m',
                             MEISTER_OLLAMA_NUM_CTX='4096', MEISTER_OLLAMA_NUM_PREDICT='512')
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(self.server.requests[-1][2])
        self.assertEqual(payload['model'], 'custom:7b')
        self.assertEqual(payload['keep_alive'], '2m')
        self.assertEqual(payload['options'], {'temperature': 0, 'num_ctx': 4096, 'num_predict': 512})

    def test_invalid_numeric_configuration_rejected_before_network(self):
        for key, value in [('MEISTER_OLLAMA_TIMEOUT', 'nan'), ('MEISTER_OLLAMA_TIMEOUT', '0'),
                           ('MEISTER_OLLAMA_TIMEOUT', '301'), ('MEISTER_OLLAMA_NUM_CTX', '4096.5'),
                           ('MEISTER_OLLAMA_NUM_CTX', '128'), ('MEISTER_OLLAMA_NUM_PREDICT', 'inf')]:
            with self.subTest(key=key, value=value):
                self.assert_failure(self.invoke(**{key: value}), 64, 'invalid-config')
        self.assertEqual(self.server.requests, [])

    def test_url_and_model_validation_never_echo_secrets(self):
        for url in ['file:///tmp/model', 'http://user:synthetic-secret@localhost',
                    'http://localhost?token=synthetic-secret', 'http://localhost#fragment']:
            with self.subTest(url=url):
                result = self.invoke(MEISTER_OLLAMA_URL=url)
                self.assert_failure(result, 64, 'invalid-url')
                self.assertNotIn('synthetic-secret', result.stderr)
        for model in ['', 'a\nb', 'x' * 201]:
            with self.subTest(model=model):
                self.assert_failure(self.invoke(MEISTER_OLLAMA_MODEL=model), 64, 'invalid-model')
        self.assertEqual(self.server.requests, [])

    def test_prompt_boundaries(self):
        for prompt in ['', '   ', 'x' * 32769]:
            with self.subTest(size=len(prompt)):
                self.assert_failure(self.invoke(prompt), 64, 'input-too-large-or-empty')
        self.assertEqual(self.server.requests, [])
        result = self.invoke('x' * 32768)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(json.loads(self.server.requests[-1][2])['prompt']), 32768)

    def test_structured_redaction_preserves_json_string_boundaries(self):
        ctx = {**CONTEXT, 'evidence': [{'id': 'E1', 'text': 'Finder password=synthetic-input-secret'}]}
        diagnosis = {'schema': 'meister.diagnosis/v1', 'cause': 'Finder token=synthetic-output-secret',
                     'evidence': ['E1'], 'missing_information': [], 'next_check': 'Status prüfen',
                     'action': 'none', 'parameters': []}
        self.server.response = {'response': json.dumps(diagnosis), 'done': True}
        result = self.invoke(json.dumps(ctx), 'ai-heal')
        self.assertEqual(result.returncode, 0, result.stderr)
        received = json.loads(json.loads(self.server.requests[-1][2])['prompt'])
        self.assertEqual(received['evidence'][0]['text'], 'Finder password=[redacted]')
        self.assertEqual(json.loads(result.stdout)['cause'], 'Finder token=[redacted]')
        self.assertNotIn('synthetic-output-secret', result.stdout + result.stderr)

    def test_thinking_mode_defaults_to_final_answer_and_accepts_explicit_override(self):
        for mode, expected in [(None, False), ('false', False), ('true', True), ('low', 'low'), ('auto', None)]:
            options = {} if mode is None else {'MEISTER_OLLAMA_THINK': mode}
            result = self.invoke(**options)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(self.server.requests[-1][2])
            if mode == 'auto':
                self.assertNotIn('think', payload)
            else:
                self.assertEqual(payload['think'], expected)
        self.server.requests.clear()
        self.assert_failure(self.invoke(MEISTER_OLLAMA_THINK='invalid'), 64, 'invalid-config')
        self.assertEqual(self.server.requests, [])


if __name__ == '__main__':
    unittest.main()
