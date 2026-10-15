"""W5.8 isolated qualification. Secrets exist only in parent/child process memory."""
import argparse, hashlib, json, os, re, secrets, shutil, subprocess, tempfile, time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--runner', required=True)
parser.add_argument('--skip-regression', action='store_true')
parser.add_argument('--git-source-repository', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
git_repo = args.git_source_repository or repo
runner = Path(args.runner)
powershell_modules = str(Path(subprocess.check_output(['powershell.exe','-NoProfile','-Command','$PSHOME'],text=True).strip()) / 'Modules')
stamp = time.strftime('%Y%m%dT%H%M%S', time.gmtime()) + f'{time.time_ns()%1000000000//1000000:03}'
evidence = repo / '.verification/wave5/w5_8' / ('run-'+stamp)
evidence.mkdir(parents=True)
work = Path(tempfile.mkdtemp(prefix='lf58-'))
project = work / 'project'
project.mkdir()
processes = {}
raw_hashes = {}
manifest = {}
credentials = []
gate = dict(passed=False, certified=False, REAL_WAN_OWNER_TEST_REQUIRED=True,
            real_LAN_certified=False, real_WAN_certified=False, manual_acceptance='PENDING_EXTERNAL_HUMAN',
            timestamp_utc=stamp, runner_sha256=hashlib.sha256(runner.read_bytes()).hexdigest(),
            starting_commit=subprocess.check_output(['git','-C',str(git_repo),'rev-parse','HEAD'],text=True).strip(),
            temp_project=str(project), regressions=False)

def check(condition, message):
    if not condition:
        raise RuntimeError(message)

def io_path(path):
    # Windows Python 3.9 needs extended paths for nested retained receipts.
    value = os.path.abspath(os.fspath(path))
    if os.name == 'nt' and not value.startswith('\\\\?\\'):
        value = ('\\\\?\\UNC\\'+value[2:]) if value.startswith('\\\\') else ('\\\\?\\'+value)
    return Path(value)

def copy_evidence(source, target):
    source, target = io_path(source), io_path(target)
    shutil.copytree(source, target)
    def inventory(root):
        return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                for p in root.rglob('*') if p.is_file()}
    before, after = inventory(source), inventory(target)
    check(before == after, 'complete regression evidence inventory/hash mismatch')
    return dict(files=len(before), hashes_verified=True, long_path_safe=True)

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2),encoding='utf-8')

def git(*arguments):
    return subprocess.check_output(['git','-C',str(git_repo),*arguments])

def new_secret():
    value = secrets.token_hex(16)
    credentials.extend([value,value.upper(),'-'.join(value[i:i+4] for i in range(0,32,4)).upper()])
    return value

def start(name, arguments, profile=None, executable=runner, cwd=project, secret='', delay=0, bridge=False, next_key=''):
    profile = profile or name
    env = os.environ.copy()
    if Path(executable).name.lower() == 'powershell.exe':
        # Codex may inherit PowerShell 7 modules into a Windows PowerShell 5
        # child. Use that child's built-ins; this is process-local only.
        env['PSMODULEPATH'] = powershell_modules
    env['APPDATA'] = str(work / (profile+'-appdata'))
    env['LOCALAPPDATA'] = str(work / (profile+'-localappdata'))
    Path(env['APPDATA']).mkdir(exist_ok=True)
    Path(env['LOCALAPPDATA']).mkdir(exist_ok=True)
    env.pop('LEYFORGE_INVITE',None)
    env.pop('LEYFORGE_TEST_INVITE',None)
    if secret:
        env['LEYFORGE_INVITE'] = secret
        if bridge: env['LEYFORGE_TEST_INVITE'] = secret
    env['LEYFORGE_TEST_ONE_WAY_MSEC'] = str(delay)
    if next_key: env['LEYFORGE_TEST_NEXT_INVITE'] = next_key
    log = (evidence / (name+'.log')).open('w',encoding='utf-8')
    proc = subprocess.Popen([str(executable),*map(str,arguments)],cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
    processes[name] = (proc,log)
    return proc

def finish(name, seconds=60):
    proc, log = processes[name]
    try: result=proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        proc.kill();proc.wait();raise RuntimeError(name+' timed out')
    log.flush()
    text=(evidence/(name+'.log')).read_text(encoding='utf-8',errors='replace')
    check(result==0, f'{name} exit {result}: '+text[-3000:])
    check('SCRIPT ERROR' not in text and '\nERROR:' not in text, name+' engine errors: '+text[-3000:])
    print(name+' PASS',flush=True)

def read(name):
    path=evidence/(name+'.json')
    for attempt in range(8):
        try: return json.loads(path.read_text(encoding='utf-8-sig'))
        except (OSError,ValueError): time.sleep(.025)
    return {}

def wait(name, predicate, seconds=50):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        value=read(name)
        if value and predicate(value):
            check(value.get('passed',False),name+' fixture assertions '+str(value.get('failures')))
            return value
        if processes[name][0].poll() is not None:
            finish(name);raise RuntimeError(name+' exited before expected state')
        time.sleep(.1)
    raise RuntimeError(name+' state timeout: '+str(read(name))[:1200])

def stop(name):
    (evidence/(name+'.stop')).write_text('stop')
    finish(name)

def command(name, **value):
    before=read(name);count=len(before.get('commands',[]))
    target=evidence/(name+'.command.json')
    pending=target.with_suffix('.pending')
    write_json(pending,value);pending.replace(target)
    return wait(name,lambda r:len(r.get('commands',[]))>count,20)

def auth_probe(name, mode='JOIN', fault='', key='', port=25659, address='127.0.0.1', hold=.5):
    return start(name,['--headless','--path',project,'--script','res://tests/networking/w5_8_auth_process.gd','--',
       '--session='+mode,'--proof-dir='+str(evidence),'--proof-name='+name,'--fault='+fault,'--port='+str(port),
       '--address='+address,'--hold='+str(hold)],secret=key)

def game_probe(name, mode, key, delay, profile=None, port=25660, next_key=''):
    return start(name,['--path',game_project,'--script','res://tests/networking/w5_8_game_process.gd','--',
       '--session='+mode,'--proof-dir='+str(evidence),'--proof-name='+name,'--port='+str(port),
       '--world-id=wave5-w58-fixture','--seed=184552221'],profile=profile,secret=key,delay=delay,bridge=True,next_key=next_key,cwd=game_project,
       executable=runner.with_name('godot.windows.editor.x86_64.exe'))

try:
    # Candidate projection deliberately excludes unrelated scene/editor and UID changes.
    snapshot_inventory = repo / '.verification_snapshot_inventory.json'
    using_snapshot = snapshot_inventory.is_file()
    paths = json.loads(snapshot_inventory.read_text(encoding='utf-8-sig')) if using_snapshot else git('ls-files','--cached','--others','--exclude-standard','--','project.godot','src','content','scenes','tests','tools','addons','docs','AGENTS.md').decode().splitlines()
    tracked=set(git('ls-files').decode().splitlines())
    paths=[p for p in paths if (not p.endswith('.gd.uid') or p in tracked) and '/__pycache__/' not in p and not p.endswith('.pyc')]
    for relative in paths:
        source=repo/relative;target=project/relative;target.parent.mkdir(parents=True,exist_ok=True)
        raw=source.read_bytes();raw_hashes[relative]=hashlib.sha256(raw).hexdigest().upper()
        if using_snapshot: data=raw
        elif relative=='project.godot': data=git('show','HEAD:'+relative).replace(b'0.5.9-wave5-w5.7',b'0.6.0-wave5-w5.8')
        elif relative=='scenes/main/wave_1_playground.tscn': data=git('show','HEAD:'+relative)
        else: data=raw.replace(b'\r\n',b'\n') if source.suffix in ('.gd','.ps1','.py','.md','.json','.tscn','.godot','.tres','.txt','.cfg','.gdextension','.svg') else raw
        target.write_bytes(data);manifest[relative]=hashlib.sha256(data).hexdigest().upper()
    write_json(project/'.verification_snapshot_inventory.json',paths)
    write_json(evidence/'source_manifest.json',manifest)
    write_json(evidence/'working_source_manifest.json',raw_hashes)
    start('import',['--headless','--editor','--path',project,'--quit']);finish('import',180)
    for name in ('focused','upnp'):
        start(name,['--headless','--path',project,'--script','res://tests/networking/w5_8_'+name+'.gd','--','--output='+str(evidence/(name+'.json'))]);finish(name)
        check(read(name)['passed'],name+' assertions');gate[name]=read(name)
    key=new_secret()
    auth_probe('auth-host','HOST',key=key);wait('auth-host',lambda r:r['state']=='HOSTING')
    auth_probe('valid',key=key);finish('valid');check(read('valid')['state']=='CONNECTED' and read('valid')['world_seen'] and not read('valid')['world_before_proof'],'actual ENet challenge/proof/result success')
    security=[]
    for fault in ('wrong','missing','malformed_invite','nonce','auth_type','byte','shape','proof_type','session','replay','stale','timeout'):
        before_admission=len(read('auth-host')['admitted'])
        name='negative-'+fault;auth_probe(name,fault=fault,key=key);finish(name,20)
        result=read(name)
        expected='auth_timeout' if fault in ('stale','timeout') else 'private_session_denied'
        check(result['reason']==expected and not result['world_seen'],name+' denied before world manifest')
        check(len(read('auth-host')['admitted'])==before_admission+(1 if fault=='replay' else 0),'no character admission from rejected attempt '+fault)
        security.append(dict(case=fault,reason=result['reason'],world_seen=False))
    gate['security_negatives']=security
    # Concurrent unauthenticated attempts remain bounded; existing traffic stays alive.
    auth_probe('healthy',key=key,hold=12);wait('healthy',lambda r:r['state']=='CONNECTED')
    for i in range(8):auth_probe('flood-'+str(i),fault='wrong',key=key)
    for i in range(8):finish('flood-'+str(i),20)
    check(read('auth-host')['pending']<=8,'pending auth bounded')
    check(read('healthy')['state']=='CONNECTED','existing peer survived auth flood')
    finish('healthy',20);gate['auth_flood_bound']=True
    stop('auth-host')
    # A real accepted protocol-6 client is executed from its immutable committed source.
    legacy=work/'legacy';legacy.mkdir()
    archive=work/'legacy.tar'
    subprocess.run(['git','-C',str(git_repo),'archive','--format=tar','--output='+str(archive),'54eb181423e02e584f45c76a79bd08edd6cdfe35'],check=True)
    subprocess.run(['tar.exe','-xf',str(archive),'-C',str(legacy)],check=True)
    start('legacy-import',['--headless','--editor','--path',legacy,'--quit'],cwd=legacy);finish('legacy-import',180)
    auth_probe('legacy-host','HOST',key=key);wait('legacy-host',lambda r:r['state']=='HOSTING')
    start('legacy-client',['--headless','--path',legacy,'--script','res://tests/networking/w5_2_process.gd','--','--session=JOIN','--address=127.0.0.1','--port=25659','--proof-dir='+str(evidence),'--proof-name=legacy-client'],cwd=legacy)
    finish('legacy-client',30);check(read('legacy-client')['reason']=='protocol_mismatch','real protocol 6 clean rejection');stop('legacy-host');gate['real_protocol6_rejected']=True
    auth_probe('no-host',key=key);finish('no-host',18);check(read('no-host')['state']=='CONNECTION_FAILED','bounded no-host connect')
    # Wildcard binding reachable on a real non-loopback local interface, not LAN certification.
    address_text=subprocess.check_output(['powershell.exe','-NoProfile','-Command',"Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notmatch '^(127\\.|169\\.254\\.)' } | Select-Object -First 1 -ExpandProperty IPAddress"],text=True).strip()
    check(bool(address_text),'non-loopback interface required for direct socket gate')
    auth_probe('interface-host','HOST',key=key);wait('interface-host',lambda r:r['state']=='HOSTING')
    auth_probe('interface-client',key=key,address=address_text);finish('interface-client');check(read('interface-client')['state']=='CONNECTED','wildcard listens on actual local interface');stop('interface-host');gate['non_loopback_interface']=True
    game_project=work/'game';shutil.copytree(project,game_project)
    game_source=game_project/'src/game/app/wave_1_playground.gd'
    game_source.write_text(game_source.read_text().replace('LfeNetworkSession.new()','load("res://tests/networking/w5_8_delayed_session.gd").new()'),encoding='utf-8')
    with (game_project/'project.godot').open('a',encoding='utf-8') as file:file.write('\n[autoload]\nW58FixtureInvite="*res://tests/networking/w5_8_regression_bridge.gd"\n')
    gate['game_instrumentation']={'session_constructor':'test-only delayed subclass','fixture_key':'memory/environment only','game_source_sha256':hashlib.sha256(game_source.read_bytes()).hexdigest()}
    start('game-import',['--headless','--editor','--path',game_project,'--quit'],cwd=game_project);finish('game-import',180)
    quality=[]
    next_key=new_secret()
    for rtt in (50,100,200):
        host='game-host-'+str(rtt);client='game-client-'+str(rtt);delay=rtt//2
        game_probe(host,'HOST',key,delay);h=wait(host,lambda r:r.get('ready'),60)
        game_probe(client,'JOIN',key,delay,next_key=next_key);c=wait(client,lambda r:r.get('ready') and r.get('resource_ready') and r.get('survival_ready'),60)
        check(c['no_authority'] and c['no_world_save'],'JOIN cannot own/save world')
        actor=c['player_id'];pid=c['pid']
        command(client,op='move')
        if rtt == 100:
            for i in range(4):auth_probe('game-flood-'+str(i),fault='wrong',key=key,port=25660)
            for i in range(4):finish('game-flood-'+str(i),20)
            check(read(client)['state']=='CONNECTED' and read(client)['ready'],'live gameplay survives wrong-auth peers')
            gate['gameplay_during_wrong_auth']=True
        time.sleep(2);command(client,op='move',direction='stop');time.sleep(1)
        c=read(client);moving_max_error=c.get('maximum_error');moving_final_error=c.get('final_error');check(c['state']=='CONNECTED' and c.get('final_error',99)<1,'movement converges under delay/jitter/loss')
        a=command(host,op='arena');y=a['commands'][-1]['y'];time.sleep(.7)
        begun=time.monotonic();command(host,op='edit',cell=[4,y,0],block='leyforge:oak_planks')
        c=wait(client,lambda r:any(v['block']=='leyforge:oak_planks' and v['position']==[4,y,0] for v in r.get('overrides',[])))
        voxel_ms=(time.monotonic()-begun)*1000
        command(host,op='survival_items',player_id=actor)
        c=wait(client,lambda r:any(v and v.get('content')=='leyforge:oak_planks' for v in r.get('personal',{}).get('inventory',[])))
        before=read(host)['totals']
        command(host,op='resource_pause_pickup',active=True)
        begun=time.monotonic();c=command(client,op='resource_drop',content='leyforge:oak_planks');resource_ms=(time.monotonic()-begun)*1000
        check(c['commands'][-1]['result'].get('success'), 'authoritative item drop under delay')
        time.sleep(.5)
        after=read(host)
        check(after['totals']==before and after['instances_unique'],'delayed item transaction conserves global quantities/identities')
        commits=after['resource_commits']
        command(client,op='retry');time.sleep(.5)
        check(read(host)['resource_commits']==commits and read(host)['totals']==before,'delayed exact retry cannot duplicate item')
        begun=time.monotonic()
        opened=command(client,op='resource',operation='open_context',args={'target':''})
        check(opened['commands'][-1]['result'].get('success'),'personal context accepted under delay')
        wait(client,lambda r:r.get('ui_open',False))
        context_ms=(time.monotonic()-begun)*1000
        command(client,op='resource',operation='close_grid',args={})
        begun=time.monotonic()
        command(host,op='survival_set',player_id=actor,values={'thirst':37.0})
        wait(client,lambda r:36.0<r.get('survival',{}).get('thirst',100)<38.0)
        survival_ms=(time.monotonic()-begun)*1000
        command(client,op='w57_leave');wait(client,lambda r:r['state']=='DISCONNECTED' and not r['terrain_exists'],15)
        # Headless/CLI fixture direct reconnect still uses the same production application seam.
        target=evidence/(client+'.command.json');write_json(target,{'op':'w57_reconnect'})
        c=wait(client,lambda r:r.get('ready') and r['state']=='CONNECTED',60)
        check(c['player_id']==actor and c['pid']==pid,'authenticated same-process reconnect retains character')
        time.sleep(2);c=read(client)
        check(c.get('lost_unreliable',0)>0,'unreliable loss actually applied')
        quality.append(dict(simulated_rtt_msec=rtt,jitter_one_way_msec=6,unreliable_loss='every 20th eligible send',metrics=c['lifecycle_metrics'],maximum_error=moving_max_error,final_error=moving_final_error,voxel_propagation_msec=voxel_ms,resource_transaction_msec=resource_ms,context_open_msec=context_ms,survival_convergence_msec=survival_ms,reconnect=True))
        if rtt != 200: stop(client);stop(host)
    gate['network_quality']=quality
    saved=command(host,op='save')
    write_json(evidence/(host+'.command.json'),{'op':'w57_f10'})
    finish(host,25)
    saved=read(host)
    ended=wait(client,lambda r:r['state']=='DISCONNECTED' and not r['terrain_exists'],15)
    check(ended['reason']=='host_shutdown','delayed graceful HOST closing removes JOIN world')
    game_probe('restarted-host','HOST',next_key,100,profile=host)
    restarted=wait('restarted-host',lambda r:r.get('ready'),60)
    check(restarted['loaded_graph_hash']==saved['saved_graph_hash'] and restarted['loaded_file_hash']==saved['saved_file_hash'],'HOST restart restores completed authoritative save')
    command(client,op='w57_reconnect')
    denied=wait(client,lambda r:r['state']=='REJECTED',20)
    check(denied['reason']=='private_session_denied' and not denied['terrain_exists'] and not denied['world'],'old HOST-process invite fails before bootstrap')
    command(client,op='w58_next_invite')
    c=wait(client,lambda r:r.get('ready') and r['state']=='CONNECTED',60)
    check(c['player_id']==actor and c['pid']==pid,'new invite returns same world-local character')
    gate['host_restart_new_invite']=True
    begun=time.monotonic();command('restarted-host',op='w58_silence')
    ended=wait(client,lambda r:r['state']=='DISCONNECTED' and not r['terrain_exists'],15)
    check(ended['reason']=='server_timeout','true silence ends gameplay under WAN timeout')
    gate['silence_detection_msec']=(time.monotonic()-begun)*1000
    stop(client);stop('restarted-host')
    # Validate kit generation/import in a disposable path with bundled approved runtime.
    kit=work/'portable-friend'
    start('kit-build',['-NoProfile','-ExecutionPolicy','Bypass','-File',project/'tools/development/build_wave_5_part_8_remote_join_kit.ps1','-OutputPath',kit,'-VerificationSnapshotPath',project],executable='powershell.exe')
    finish('kit-build',180)
    kit_manifest=json.loads((kit/'kit_manifest.json').read_text(encoding='utf-8-sig'))
    check(kit_manifest['application']==re.search(r'config/version="([^"]+)"',(project/'project.godot').read_text())[1],'portable regression kit records actual candidate application')
    for relative,digest in kit_manifest['files'].items():check(hashlib.sha256((kit/relative).read_bytes()).hexdigest().upper()==digest,'kit hash '+relative)
    forbidden=['.git','.godot','identity','worlds','saves','logs','.verification','userdata']
    check(not any(p in forbidden for f in kit.rglob('*') for p in f.relative_to(kit).parts),'kit excludes private owner data/cache')
    start('kit-import',['--headless','--editor','--path',kit,'--quit'],executable=kit/'runtime/godot.windows.editor.x86_64.console.exe',cwd=kit);finish('kit-import',180)
    game_probe('kit-host','HOST',key,0)
    wait('kit-host',lambda r:r.get('ready'),60)
    start('kit-launch',['-NoProfile','-ExecutionPolicy','Bypass','-File',project/'tests/networking/w5_8_kit_launch.ps1','-KitPath',kit,'-EvidencePath',evidence],executable='powershell.exe',cwd=kit,secret=key)
    finish('kit-launch',100)
    kit_result=read('kit-launch')
    check(kit_result['passed'] and kit_result['unique_local_identity']!=actor,'portable JOIN creates distinct local tester identity and full gameplay')
    stop('kit-host')
    gate['remote_kit']={'files':len(kit_manifest['files']),'hashes_verified':True,'clean_import':True,'precommit_verification_only':True}
    gate['remote_kit']['normal_join_launcher']=True
    gate['remote_kit']['own_identity_no_save']=True
    if not args.skip_regression:
        regression=work/'regression';shutil.copytree(project,regression)
        with (regression/'project.godot').open('a',encoding='utf-8') as file:file.write('\n[autoload]\nW58FixtureInvite="*res://tests/networking/w5_8_regression_bridge.gd"\n')
        start('regression',['-NoProfile','-ExecutionPolicy','Bypass','-File',regression/'tools/development/verify_wave_5_part_7.ps1','-GitSourceRepository',git_repo],executable='powershell.exe',cwd=regression,secret=key,bridge=True)
        finish('regression',3600)
        prior_runs=sorted((regression/'.verification/wave5/w5_7').glob('run-*'))
        receipt=json.loads((prior_runs[-1]/'gate.json').read_text(encoding='utf-8-sig'))
        check(receipt['passed'] and receipt['certified'],'full Wave 0-4 and W5.1-W5.7 chain certified')
        gate['regression_evidence']=copy_evidence(regression/'.verification/wave5/w5_7',evidence/'regression_w57')
        gate['regressions']=receipt.get('regressions','')+'; W5.7 PASS'
    for relative,digest in raw_hashes.items():check(hashlib.sha256((repo/relative).read_bytes()).hexdigest().upper()==digest,'source changed during gate: '+relative)
    for log in io_path(evidence).rglob('*'):
        if log.is_file() and log.suffix in ('.log','.json','.txt'):
            text=log.read_text(encoding='utf-8',errors='replace')
            check(not any(secret in text for secret in credentials),'raw invite leaked into '+log.name)
    gate['secret_redaction']=True
    gate['snapshot_matches_source']=True
    gate['passed']=True;gate['certified']=not args.skip_regression
    print('WAVE_5_PART_8_VALIDATION_PASS',flush=True)
except Exception as error:
    gate['failure']=str(error)[:6000]
    print('W5_8_FAILURE: '+str(error)[:6000],flush=True)
finally:
    for name,(proc,log) in processes.items():
        if proc.poll() is None:
            (evidence/(name+'.stop')).write_text('stop')
    for proc,log in processes.values():
        if proc.poll() is None:
            try:proc.wait(timeout=2)
            except subprocess.TimeoutExpired:proc.kill();proc.wait()
        log.close()
    write_json(evidence/'gate.json',gate)
    print('WAVE_5_PART_8_EVIDENCE='+str(evidence),flush=True)
    # Retain the external candidate for failure diagnosis; no owner/save cleanup.
raise SystemExit(0 if gate['passed'] else 1)
