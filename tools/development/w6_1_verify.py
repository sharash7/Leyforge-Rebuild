"""W6.1 graphical UI checks plus the unchanged complete W5.9 final chain."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile
import time
import sys
sys.stdout.reconfigure(encoding='utf-8',errors='replace')

parser = argparse.ArgumentParser()
parser.add_argument('--runner', required=True, type=Path)
parser.add_argument('--focused-only', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
runner = args.runner
stamp = time.strftime('%Y%m%dT%H%M%S', time.gmtime()) + str(time.time_ns() % 1000000000)
evidence = repo / '.verification/wave6/w6_1' / ('run-' + stamp)
evidence.mkdir(parents=True)
work = Path(tempfile.mkdtemp(prefix='lf61-'))
project = work / 'project'
processes = {}
checks = []
secret = secrets.token_hex(16)
gate = dict(passed=False, certified=False, manual_acceptance='OWNER UI ACCEPTANCE REQUIRED',
            starting_commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),
            temp_project=str(project), focused_only=args.focused_only)
def write(path, value):
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def check(value, label):
    checks.append(dict(label=label, passed=bool(value)))
    if not value: raise RuntimeError(label)
def git(*a):
    return subprocess.check_output(['git','-C',str(repo),*a])
def inventory():
    tracked=set(git('ls-files').decode().splitlines())
    paths=git('ls-files','--cached','--others','--exclude-standard','--','project.godot','src','content','scenes','tests','tools','addons','docs','AGENTS.md').decode().splitlines()
    return [p for p in paths if (not p.endswith('.gd.uid') or p in tracked) and '/__pycache__/' not in p and not p.endswith('.pyc')]
def start(name, arguments, graphical=False):
    env=os.environ.copy()
    for key in ['APPDATA','LOCALAPPDATA']:
        env[key]=str(work/(name+'-'+key));Path(env[key]).mkdir(exist_ok=True)
    env['LEYFORGE_INVITE']=secret;env['LEYFORGE_TEST_INVITE']=secret
    env['LEYFORGE_TEST_ONE_WAY_MSEC']='0'
    exe=runner.with_name('godot.windows.editor.x86_64.exe') if graphical else runner
    log=(evidence/(name+'.log')).open('w',encoding='utf-8')
    proc=subprocess.Popen([str(exe),*map(str,arguments)],env=env,cwd=project,stdout=log,stderr=subprocess.STDOUT)
    processes[name]=(proc,log)
def finish(name, timeout=180):
    proc,log=processes[name]
    code=proc.wait(timeout=timeout);log.flush()
    text=(evidence/(name+'.log')).read_text(encoding='utf-8',errors='replace')
    check(code==0 and not re.search(r'(?m)^\s*(SCRIPT ERROR|ERROR:)',text),name+' clean exit: '+text[-1500:] if code or 'SCRIPT ERROR' in text else name+' clean exit')
def read(name):
    try:return json.loads((evidence/(name+'.json')).read_text(encoding='utf-8-sig'))
    except (ValueError,OSError):return {}
def wait(name, condition, timeout=90):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        report=read(name)
        if report and not report.get('passed',True):raise RuntimeError(name+': '+str(report.get('failures')))
        if report and condition(report):return report
        if processes[name][0].poll() is not None:
            finish(name);raise RuntimeError(name+' exited before expected report')
        time.sleep(.1)
    raise RuntimeError(name+' timeout: '+str(read(name))[-1800:])
def command(name, **value):
    count=len(read(name).get('commands',[]))
    pending=evidence/(name+'.command.pending')
    write(pending,value);pending.replace(evidence/(name+'.command.json'))
    return wait(name,lambda r:len(r.get('commands',[]))>count)['commands'][-1]
def ready(name):
    return wait(name,lambda r:r.get('ready') and r.get('resource_ready') and r.get('survival_ready'))
def stop(name):
    (evidence/(name+'.stop')).write_text('stop');finish(name)
try:
    check(digest(runner)=='06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A','approved console')
    graphical=runner.with_name('godot.windows.editor.x86_64.exe')
    check(digest(graphical)=='87D0A6077ABE38B905F973B23D9F27FD4F3B7A8DB2309DFD6807FAD7DFF582C8','approved graphical')
    write(evidence/'runner_manifest.json',dict(console=digest(runner),graphical=digest(graphical)))
    paths=inventory();raw={};manifest={}
    for relative in paths:
        source=repo/relative;data=source.read_bytes();raw[relative]=digest(source)
        if relative in ['project.godot','scenes/main/wave_1_playground.tscn']:data=git('show','HEAD:'+relative)
        if source.suffix in ('.gd','.ps1','.py','.md','.json','.tscn','.godot','.tres','.txt','.cfg','.gdextension','.svg'):data=data.replace(b'\r\n',b'\n')
        target=project/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);manifest[relative]=digest(target)
    write(evidence/'source_manifest.json',manifest);write(evidence/'working_source_manifest.json',raw)
    main=project/'src/game/app/wave_1_playground.gd'
    main.write_text(main.read_text(encoding='utf-8').replace('LfeNetworkSession.new()', 'load("res://tests/networking/w5_9_measured_session.gd").new()'),encoding='utf-8')
    with (project/'project.godot').open('a',encoding='utf-8') as f:f.write('\n[autoload]\nW58FixtureInvite="*res://tests/networking/w5_8_regression_bridge.gd"\n')
    write(evidence/'test_instrumentation.json',dict(project_sha256=digest(project/'project.godot'),credential_bridge='existing test-only autoload',session_constructor_sha256=digest(main),normal_runtime_unchanged=True))
    start('import',['--headless','--editor','--path',project,'--quit']);finish('import')
    start('drop_frames',['--path',project,'--script','res://tests/networking/w6_1_drop_frames.gd','--','--output='+str(evidence/'drop_frames.json')],True)
    finish('drop_frames')
    drop_frames=read('drop_frames')
    check(drop_frames.get('passed') and len(drop_frames.get('checks',[]))==12,'real rendered drop follow: normal frames and repeated 131/200/400 ms stalls; strict step/lag/convergence bounds')
    for name,mode in [('host','HOST'),('client','JOIN')]:
        start(name,['--path',project,'--script','res://tests/ui/w6_1_process.gd','--','--session='+mode,'--proof-dir='+str(evidence),'--proof-name='+name,'--port=25662','--world-id=wave6-ui-fixture','--seed=184552221'],True)
        ready(name)
    check(read('host')['pid']!=read('client')['pid'] and read('client')['no_authority'],'separate graphical HOST/JOIN; disposable client truth')
    arena=command('host',op='arena');y=arena['y']
    actor=read('client')['player_id']
    command('host',op='survival_items',player_id=actor)
    command('host',op='actor_position',player_id=actor,position=[.5,y+.05,3.5]);ready('client')
    for width,height in [(1920,1080),(1280,720),(960,540)]:
        command('client',op='repair_key',code=73)
        wait('client',lambda r:r.get('ui_open'))
        command('client',op='w61_layout',width=width,height=height)
        command('client',op='repair_key',code=4194305)
        wait('client',lambda r:not r.get('ui_open'))
        for kind,content in [('workbench','leyforge:workbench'),('storage','leyforge:storage_box'),('kiln','leyforge:kiln')]:
            fixture=command('host',op='w59_fixture',cell=[0,y,0],content=content)
            check(fixture['added'],'isolated '+kind+' fixture')
            time.sleep(.6)
            opened=command('client',op='repair_interact',cell=[0,y,0],key=kind=='storage')
            check(opened['ui_open'],kind+' normal RMB/E opens')
            layout=command('client',op='w61_layout',width=width,height=height)
            if kind=='workbench':check(layout['grid_size']==3,'Workbench 3x3')
            command('client',op='repair_key',code=4194305)
            wait('client',lambda r:not r.get('ui_open'))
    command('host',op='w59_seed_personal',player_id=actor,content='leyforge:oak_heartwood',quantity=8)
    time.sleep(.6)
    command('client',op='repair_key',code=67);wait('client',lambda r:r.get('ui_open'))
    command('client',op='w61_layout',width=960,height=540,logical=True)
    before=read('host')['totals']['leyforge:oak_heartwood']
    command('client',op='w61_feedback')
    time.sleep(.6)
    check(read('host')['totals']['leyforge:oak_heartwood']==before,'split/quick return/rejected equipment conserve HOST matter')
    command('client',op='w57_leave');wait('client',lambda r:r.get('ended_visible') and not r.get('terrain_exists') and not r.get('player_exists'))
    check(not read('client')['terrain_exists'] and not read('client')['player_exists'],'menu teardown removes world references')
    command('client',op='w57_reconnect');ready('client')
    command('client',op='repair_key',code=73);wait('client',lambda r:r.get('ui_open'))
    command('client',op='w61_layout',width=960,height=540,logical=True)
    command('client',op='w57_pending')
    stop('host')
    lost=wait('client',lambda r:r.get('ended_visible') and not r.get('terrain_exists') and not r.get('player_exists'))
    check(not lost['inventory_exists'],'HOST loss with pending menu clears inventory reference')
    stop('client')
    gate['focused_graphical']=True
    if not args.focused_only:
        prior=set((repo/'.verification/wave5/w5_9').glob('run-*'))
        with (evidence/'w5_9-full.log').open('w',encoding='utf-8') as log:
            result=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(repo/'tools/development/verify_wave_5_part_9.ps1'),'-GodotExecutable',str(runner)],cwd=repo,stdout=log,stderr=subprocess.STDOUT)
        created=set((repo/'.verification/wave5/w5_9').glob('run-*'))-prior
        check(len(created)==1,'one fresh W5.9 receipt')
        prior_run=created.pop();gate['w5_9_evidence']=str(prior_run)
        receipt=json.loads((prior_run/'gate.json').read_text(encoding='utf-8-sig'))
        check(result.returncode==0 and all(receipt.get(k) for k in ['passed','certified','snapshot_matches_source','secret_redaction']),'complete source-matched W5.9 chain')
        check(json.loads((prior_run/'source_manifest.json').read_text())==manifest,'W6.1 and complete regression source inventories match')
        gate['full_regressions']=True
    check(inventory()==paths and all(digest(repo/p)==h for p,h in raw.items()),'source unchanged throughout gate')
    check(all(secret not in f.read_text(encoding='utf-8',errors='replace') for f in evidence.glob('*') if f.suffix in ['.json','.log']),'invite redaction')
    gate.update(passed=True,certified=not args.focused_only,snapshot_matches_source=True,secret_redaction=True)
except Exception as error:
    gate['failure']=str(error);print('W6_1_FAILURE: '+str(error),flush=True)
finally:
    for name,(proc,log) in processes.items():
        if proc.poll() is None:
            (evidence/(name+'.stop')).write_text('stop')
            try:proc.wait(timeout=3)
            except subprocess.TimeoutExpired:proc.kill();proc.wait()
        log.close()
    write(evidence/'checks.json',checks);write(evidence/'gate.json',gate)
    print('W6_1_EVIDENCE='+str(evidence),flush=True)
    print('W6_1_PASS' if gate['passed'] else 'W6_1_INCOMPLETE',flush=True)
raise SystemExit(0 if gate['passed'] else 1)
