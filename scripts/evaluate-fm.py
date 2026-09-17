#!/usr/bin/env python3
"""Evaluate diagnosis JSON. Offline validates the harness, not model quality."""
import argparse
import datetime
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def invoke(command, *, text, timeout, env=None):
    start = time.monotonic()
    try:
        result = subprocess.run(command, input=text, text=True, capture_output=True,
                                timeout=timeout, check=False, env=env)
        match = re.search(r"fm-error kind=([a-z_-]+)", result.stderr)
        error_kind = match.group(1) if match else None
        if result.returncode != 0 and error_kind is None:
            for line in result.stderr.splitlines():
                try:
                    metadata = json.loads(line)
                except ValueError:
                    continue
                if (isinstance(metadata, dict) and metadata.get('backend') == 'ollama'
                        and isinstance(metadata.get('status'), str)
                        and re.fullmatch(r'[a-z_-]+', metadata['status'])
                        and metadata['status'] != 'ok'):
                    error_kind = metadata['status']
                    break
        return result.returncode, result.stdout, time.monotonic() - start, error_kind
    except subprocess.TimeoutExpired:
        return 124, '', time.monotonic() - start, 'timeout'
    except OSError:
        return 127, '', time.monotonic() - start, 'helper_unavailable'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, default=ROOT / 'tests/fixtures/fm_cases.json')
    parser.add_argument('--contract', type=Path, default=ROOT / 'lib/fm/contract.py')
    parser.add_argument('--case', action='append', dest='case_ids', help='Evaluate this case ID (repeatable)')
    parser.add_argument('--limit', type=int, help='Evaluate at most N selected cases')
    parser.add_argument('--include-responses', action='store_true', help='Include validated model diagnoses for manual review')
    parser.add_argument('--live', action='store_true', help='Query the selected backend without executing repairs')
    parser.add_argument('--backend', choices=['apple', 'ollama'], default='apple')
    parser.add_argument('--model', help='Model name (default: system for Apple; MEISTER_OLLAMA_MODEL or qwen3-coder:30b for Ollama)')
    parser.add_argument('--helper', type=Path, help='Compiled Apple helper (required for live Apple) or Ollama Python client override')
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--output', type=Path, default=ROOT / 'artifacts/fm-evaluation.json')
    parser.add_argument('--outcomes', type=Path, help='Optional externally verified outcome records')
    args = parser.parse_args()
    if not args.contract.is_file():
        parser.error(f'contract validator missing: {args.contract}')
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    model = args.model or ('system' if args.backend == 'apple' else
                           os.environ.get('MEISTER_OLLAMA_MODEL', 'qwen3-coder:30b'))
    helper = args.helper or (ROOT / 'lib/ollama/client.py' if args.backend == 'ollama' else None)
    if args.live and (not helper or not helper.is_file()):
        parser.error('--live requires an existing helper; use --helper for the compiled Apple helper')
    model_env = dict(os.environ, MEISTER_OLLAMA_MODEL=model) if args.backend == 'ollama' else None
    dataset = json.loads(args.fixtures.read_text())
    if args.limit is not None and args.limit <= 0:
        parser.error('--limit must be positive')
    cases = dataset['cases']
    if args.case_ids:
        unknown = set(args.case_ids) - {case['id'] for case in cases}
        if unknown:
            parser.error('unknown case IDs: ' + ', '.join(sorted(unknown)))
        cases = [case for case in cases if case['id'] in args.case_ids]
    if args.limit is not None:
        cases = cases[:args.limit]
    outcomes = json.loads(args.outcomes.read_text()) if args.outcomes else {}
    if not isinstance(outcomes, dict):
        parser.error('--outcomes must contain an object keyed by fixture id')
    results = []
    with tempfile.TemporaryDirectory(prefix='meister-fm-eval-') as temporary:
        context_path = Path(temporary) / 'context.json'
        for case in cases:
            context_path.write_text(json.dumps(case['context']))
            if args.live:
                prompt = json.dumps(case['context'])
                command = ([sys.executable, str(helper.resolve()), '--purpose', 'ai-heal']
                           if args.backend == 'ollama' else
                           [str(helper.resolve()), '--purpose', 'ai-heal', '--model', model])
                rc, raw, latency, error_kind = invoke(command, text=prompt,
                                                     timeout=args.timeout, env=model_env)
            else:
                rc, raw, latency, error_kind = 0, json.dumps(case['reference_response']), None, None
            valid_rc, _, _, _ = invoke([sys.executable, str(args.contract), 'validate',
                                    '--context', str(context_path)], text=raw, timeout=10)
            schema_ok = rc == 0 and valid_rc == 0
            try:
                response = json.loads(raw)
                if not isinstance(response, dict):
                    response = {}
            except (ValueError, TypeError):
                response = {}
            expected = case['expected']
            evidence = response.get('evidence', [])
            cause = str(response.get('cause', '')).casefold()
            action = response.get('action')
            evidence_ok = schema_ok and isinstance(evidence, list) and all(
                ref in evidence for ref in expected['evidence'])
            action_ok = schema_ok and action == expected['action']
            diagnosis_ok = schema_ok and any(term.casefold() in cause for term in expected['diagnosis_terms_any'])
            no_fix_ok = schema_ok and (action == 'none') == expected['no_fix']
            outcome = outcomes.get(case['id'])
            # A model's claim of success is never accepted as observed verification.
            measured = (isinstance(outcome, dict) and outcome.get('verified') is True
                        and isinstance(outcome.get('success'), bool)
                        and isinstance(outcome.get('evidence'), str) and bool(outcome['evidence'].strip()))
            results.append({'diagnosis': response if args.include_responses and schema_ok else None, 'id': case['id'], 'origin': case['origin'], 'helper_exit': rc,
                            'latency_seconds': latency, 'error_kind': error_kind, 'schema_correct': schema_ok,
                            'evidence_correct': evidence_ok, 'action_correct': action_ok,
                            'diagnosis_terms_match': diagnosis_ok, 'no_fix_correct': no_fix_ok,
                            'outcome': {'status': 'externally_verified' if measured else 'unmeasured',
                                        'success': outcome['success'] if measured else None},
                            'passed': all([schema_ok, evidence_ok, action_ok, diagnosis_ok, no_fix_ok])})
    n = len(results)
    rates = {key: sum(bool(row[key]) for row in results) / n if n else None
             for key in ['schema_correct', 'evidence_correct', 'action_correct',
                         'diagnosis_terms_match', 'no_fix_correct']}
    report = {'schema': 'meister.fm-evaluation-result/v1',
              'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'mode': ('live_ollama_model' if args.backend == 'ollama' else
                       'live_system_model' if model == 'system' else 'live_apple_model')
                      if args.live else 'offline_harness_only',
              'backend': args.backend if args.live else None,
              'live_evaluation_attempted': args.live,
              'model_quality_measured': args.live and any(row['helper_exit'] == 0 and row['schema_correct'] for row in results),
              'repair_execution': False,
              'model': model if args.live else None, 'cases': results,
              'summary': {'attempted_model_queries': n if args.live else 0,
                          'successful_model_responses': sum(row['helper_exit'] == 0 for row in results) if args.live else 0,
                          'validated_model_responses': sum(row['schema_correct'] for row in results) if args.live else 0,
                          'total': n, 'passed': sum(row['passed'] for row in results), **rates,
                          'verified_outcomes': sum(row['outcome']['status'] == 'externally_verified' for row in results)}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    os.chmod(args.output, 0o600)
    print(f"{report['mode']}: {report['summary']['passed']}/{n} cases passed; {args.output}")
    if not args.live:
        print('Offline checks validate reference fixtures and the harness; model quality is unmeasured.')
    return 0 if n and all(row['passed'] for row in results) else 1


if __name__ == '__main__':
    sys.exit(main())
