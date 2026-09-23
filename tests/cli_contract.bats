#!/usr/bin/env bats
# Run only read-only probes and disabled preview fixtures in temporary MEISTER_DIR.

@test "read-only CLI version leaves an existing run lock untouched" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" "$BATS_TEST_TMPDIR" <<'PY'
import os,pathlib,subprocess,sys
script=pathlib.Path(sys.argv[1]).resolve(); fixture=pathlib.Path(sys.argv[2])/'fixture'
state=fixture/'.meister'; state.mkdir(parents=True)
lock=state/'meister.lock'; lock.write_text(str(os.getpid()))
lockdir=state/'meister.lock.d'; lockdir.mkdir(); (lockdir/'owner').write_text(f'{os.getpid()}:other-token\n')
env={**os.environ,'MEISTER_DIR':str(state)}
p=subprocess.run(['/bin/bash',str(script),'--version'],env=env,capture_output=True,text=True,timeout=15)
assert p.returncode==0, p.stderr
assert lock.read_text()==str(os.getpid())
assert (lockdir/'owner').read_text()==f'{os.getpid()}:other-token\n'
assert not (state/'last.json').exists()
PY
}

@test "autofix and ai preview produce honest reports through their real handlers" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" "$BATS_TEST_TMPDIR" <<'PY'
import json,os,pathlib,subprocess,sys
script=pathlib.Path(sys.argv[1]).resolve(); fixture=pathlib.Path(sys.argv[2])/'fixture'
state=fixture/'.meister'; state.mkdir(parents=True)
keys=['AUTOFIX_FIREWALL','AUTOFIX_OLD_BOTTLES','AUTOFIX_ORPHAN_LAUNCHD','AUTOFIX_GIT_PUSH','GIT_AUTO_PUSH','AUTOFIX_INBOX_ARCHIVE']
(state/'config').write_text(''.join(f'{k}=false\n' for k in keys))
bindir=fixture/'bin'; bindir.mkdir()
# A missing AI runtime is an expected, safe no-model fixture; never compile.
(bindir/'xcrun').write_text('#!/bin/sh\nexit 1\n'); (bindir/'xcrun').chmod(0o755)
env={**os.environ,'MEISTER_DIR':str(state),'MEISTER_LIB':str(script.parent/'lib'),'PATH':f'{bindir}:{os.environ["PATH"]}'}
for command in ['autofix','ai']:
 p=subprocess.run(['/bin/bash',str(script),command,'--dry-run'],env=env,capture_output=True,text=True,timeout=15)
 assert p.returncode==0, (p.stdout,p.stderr)
 report=json.loads((state/'last.json').read_text())
 assert report['dry_run'] and report['profile']==command and report['status']=='completed',report
 assert report['fix']==report['verified_repair_count']==0 and report['freed_bytes'] is None
 assert not (state/'meister.lock').exists() and not (state/'meister.lock.d').exists()
assert len(list((state/'runs').glob('*.json')))==2
assert not (state/'history.log').exists()
PY
}

@test "health and AI diagnosis inspections preserve prior report and live lock" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" "$BATS_TEST_TMPDIR" <<'PY'
import os,pathlib,subprocess,sys
script=pathlib.Path(sys.argv[1]).resolve(); fixture=pathlib.Path(sys.argv[2])/'fixture'
state=fixture/'.meister'; state.mkdir(parents=True)
(state/'last.json').write_text('{"old":"report"}\n')
(state/'history.log').write_text('existing-history\n')
(state/'config').write_text('AUTO_DETECT=false\n')
lock=state/'meister.lock'; lock.write_text(str(os.getpid()))
lockdir=state/'meister.lock.d'; lockdir.mkdir(); (lockdir/'owner').write_text(f'{os.getpid()}:other-token\n')
bindir=fixture/'bin'; bindir.mkdir()
(bindir/'xcrun').write_text('#!/bin/sh\nexit 1\n'); (bindir/'xcrun').chmod(0o755)
env={**os.environ,'MEISTER_DIR':str(state),'MEISTER_LIB':str(script.parent/'lib'),'PATH':f'{bindir}:{os.environ["PATH"]}'}
for args in [['-H'],['ai','--diagnose-only']]:
 p=subprocess.run(['/bin/bash',str(script),*args],env=env,capture_output=True,text=True,timeout=15)
 assert p.returncode==(69 if args[0]=="ai" else 0),(p.stdout,p.stderr)
 if args[0]=="ai":
  assert "keine Modell-Diagnose erstellt" in p.stdout
  assert not (state/"diagnoses").exists()
 assert (state/'last.json').read_text()=='{"old":"report"}\n'
 assert (state/'history.log').read_text()=='existing-history\n'
 assert lock.read_text()==str(os.getpid())
 assert (lockdir/'owner').read_text()==f'{os.getpid()}:other-token\n'
PY
}

@test "all profile previews plan modules without invoking maintenance programs" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" "$BATS_TEST_TMPDIR" <<'PY'
import json,os,pathlib,subprocess,sys
script=pathlib.Path(sys.argv[1]).resolve(); fixture=pathlib.Path(sys.argv[2])/'fixture'
state=fixture/'.meister'; state.mkdir(parents=True)
bindir=fixture/'bin'; bindir.mkdir()
for command in ['brew','sudo','xcrun','mas','mdimport','purge','osascript','terminal-notifier','git']:
 stub=bindir/command
 stub.write_text('#!/bin/sh\nprintf "%s\\n" "$0 $*" >> "$MEISTER_DIR/unexpected"\nexit 99\n')
 stub.chmod(0o755)
env={**os.environ,'MEISTER_DIR':str(state),'MEISTER_LIB':str(script.parent/'lib'),'PATH':f'{bindir}:{os.environ["PATH"]}'}
for args in [['--auto'],['--quick'],['--deep'],['-a']]:
 p=subprocess.run(['/bin/bash',str(script),*args,'-n'],env=env,capture_output=True,text=True,timeout=20)
 assert p.returncode==0,(p.stdout,p.stderr)
 assert not (state/'unexpected').exists(),(state/'unexpected').read_text()
 r=json.loads((state/'last.json').read_text())
 assert r['report_kind']=='execution_plan' and r['dry_run'] and r['status']=='completed',r
 assert r['score'] is None and r['freed_bytes'] is None
 assert r['fix']==r['verified_repair_count']==0 and r['fixes']==r['would_fix']==[]
 assert r['planned_modules'] and all(m['status']=='PLAN' for m in r['modules'])
assert not (state/'history.log').exists()
PY
}

@test "state directory override rejects relative paths and parent traversal" {
  for state in relative/state /tmp/../unexpected /; do
    run env MEISTER_DIR="$state" /bin/bash "$BATS_TEST_DIRNAME/../MeisterAI.sh" --version
    [ "$status" = 2 ]
    [[ "$output" == *'MEISTER_DIR must be an absolute state directory'* ]]
  done
}

@test "AI report renders saved evidence without model access or changing report" {
  python3 - "$BATS_TEST_DIRNAME/../MeisterAI.sh" "$BATS_TEST_TMPDIR" <<'PY'
import json,os,pathlib,subprocess,sys
script=pathlib.Path(sys.argv[1]).resolve(); root=pathlib.Path(sys.argv[2]); state=root/'state'; state.mkdir()
data={'schema':'meister.last/v1','run_id':'fixture','status':'completed','dry_run':False,'verified_repair_count':0,'fixes':['update requested'],'warnings':['verification pending'],'errors':[],'ai_diagnoses':['/fixture/diagnosis.json']}
report=json.dumps(data); (state/'last.json').write_text(report)
env={**os.environ,'MEISTER_DIR':str(state),'MEISTER_LIB':str(script.parent/'lib')}
p=subprocess.run(['/bin/bash',str(script),'ai','report'],env=env,capture_output=True,text=True,timeout=15)
assert p.returncode==0,(p.stdout,p.stderr)
assert 'Verifizierte Reparaturen: 0' in p.stdout
assert 'Offen [warnings/0]: verification pending' in p.stdout
assert 'Diagnosebeleg [ai_diagnoses/0]' in p.stdout
assert (state/'last.json').read_text()==report
assert not (state/'meister-fm').exists() and not (state/'diagnoses').exists()
PY
}
