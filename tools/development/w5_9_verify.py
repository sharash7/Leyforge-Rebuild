"""Final local/LAN foundation gate. All gameplay runs use disposable profiles.

Fixture credentials remain memory/environment only. A diagnostic skip or short
soak can pass its executed checks but cannot produce certified=true.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--runner', required=True, type=Path)
parser.add_argument('--skip-regression', action='store_true')
parser.add_argument('--soak-seconds', type=int, default=660)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
runner = args.runner
powershell_modules = str(Path(subprocess.check_output(['powershell.exe','-NoProfile','-Command','$PSHOME'],text=True).strip()) / 'Modules')
stamp = time.strftime('%Y%m%dT%H%M%S', time.gmtime()) + f'{time.time_ns()%1000000000//1000000:03}'
evidence = repo / '.verification/wave5/w5_9' / ('run-'+stamp)
evidence.mkdir(parents=True)
work = Path(tempfile.mkdtemp(prefix='lf59-'))
project = work / 'project'
project.mkdir()
game_project = work / 'game'
processes = {}
credentials = []
raw_hashes = {}
manifest = {}
checks = []
command_latencies = []

class ProcessMemory(ctypes.Structure):
    _fields_=[('cb',ctypes.c_ulong),('PageFaultCount',ctypes.c_ulong)]+[(field,ctypes.c_size_t) for field in ['PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage']]

def working_set(name):
    counters=ProcessMemory();counters.cb=ctypes.sizeof(counters)
    api=ctypes.WinDLL('psapi').GetProcessMemoryInfo
    api.argtypes=[ctypes.c_void_p,ctypes.POINTER(ProcessMemory),ctypes.c_ulong]
    if not api(int(processes[name][0]._handle),ctypes.byref(counters),counters.cb):
        raise OSError('Cannot measure launched process working set')
    return dict(working_set_bytes=counters.WorkingSetSize,peak_working_set_bytes=counters.PeakWorkingSetSize)
gate = dict(passed=False, certified=False, timestamp_utc=stamp,
            application='0.6.1-wave5-w5.9', protocol=7, save=4, content=1, worldgen=2,
            stored_worldgen_v1_supported=True, manual_acceptance='LAN HUMAN ACCEPTANCE REQUIRED',
            real_LAN_certified=False, real_WAN_certified=False, direct_WAN='DEFERRED_TO_WAVE_17',
            temp_project=str(project), regressions=False,
            runner_sha256=hashlib.sha256(runner.read_bytes()).hexdigest(),
            starting_commit=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip())

def check(condition, label):
    checks.append(dict(label=label, passed=bool(condition)))
    if not condition:
        raise RuntimeError(label)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')

def git(*arguments):
    return subprocess.check_output(['git','-C',str(repo),*arguments])

def new_secret():
    value = secrets.token_hex(16)
    credentials.extend([value,value.upper(),'-'.join(value[i:i+4] for i in range(0,32,4)).upper()])
    return value

def start(name, arguments, profile=None, executable=runner, cwd=project, key='', bridge=False):
    profile = profile or name
    env = os.environ.copy()
    if Path(executable).name.lower() == 'powershell.exe':
        env['PSMODULEPATH'] = powershell_modules
    for var, suffix in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
        env[var] = str(work/(profile+'-'+suffix)); Path(env[var]).mkdir(exist_ok=True)
    for var in ['LEYFORGE_INVITE','LEYFORGE_TEST_INVITE','LEYFORGE_TEST_NEXT_INVITE','LEYFORGE_TEST_ONE_WAY_MSEC']:
        env.pop(var,None)
    env['LEYFORGE_TEST_ONE_WAY_MSEC'] = '0'
    env['LEYFORGE_GODOT_ROOT'] = str(runner.parent)
    if key:
        env['LEYFORGE_INVITE'] = key
        if bridge: env['LEYFORGE_TEST_INVITE'] = key
    log = (evidence/(name+'.log')).open('w',encoding='utf-8')
    proc = subprocess.Popen([str(executable),*map(str,arguments)],cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
    processes[name]=(proc,log)
    return proc

def finish(name, seconds=60):
    proc,log=processes[name]
    try: code=proc.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        proc.kill();proc.wait();raise RuntimeError(name+' timed out')
    log.flush()
    content=(evidence/(name+'.log')).read_text(encoding='utf-8',errors='replace')
    check(code==0,name+' exit '+str(code)+': '+content[-2000:] if code else name+' process exit')
    errors=re.findall(r'(?m)^\s*(?:SCRIPT ERROR|ERROR:).*$',content)
    expected='ERROR: WAVE_2_SAVE_FAIL Could not open temporary world save.'
    if name=='host' and gate.get('write_failure'):
        check([s.strip() for s in errors]==[expected],'exactly one expected injected save-write error; no other engine error')
        gate['expected_failure_diagnostics']=[dict(process=name,message=expected,classification='EXPECTED_INJECTED_WRITE_FAILURE')]
    else:
        check(not errors,name+' no engine errors: '+content[-2000:])
    print(name+' PASS',flush=True)

def read(name):
    for attempt in range(8):
        try: return json.loads((evidence/(name+'.json')).read_text(encoding='utf-8-sig'))
        except (OSError,ValueError): time.sleep(.025)
    return {}

def wait(name, predicate, seconds=60):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        value=read(name)
        if value and predicate(value):
            check(value.get('passed',False),name+' fixture assertions '+str(value.get('failures',[])))
            return value
        if processes[name][0].poll() is not None:
            finish(name);raise RuntimeError(name+' exited before expected state')
        time.sleep(.1)
    raise RuntimeError(name+' state timeout: '+str(read(name))[:2000])

def submit(name, **value):
    count=len(read(name).get('commands',[]))
    path=evidence/(name+'.command.json')
    pending=path.with_suffix('.pending')
    write_json(pending,value);pending.replace(path)
    return count

def command(name, **value):
    begun=time.monotonic()
    count=submit(name,**value)
    result=wait(name,lambda r:len(r.get('commands',[]))>count,30)
    command_latencies.append(dict(process=name,operation=value.get('op'),gameplay_operation=value.get('operation'),observed_result_msec=(time.monotonic()-begun)*1000))
    return result

def stop(name):
    (evidence/(name+'.stop')).write_text('stop')
    finish(name)

def ready(name):
    return wait(name,lambda r:r.get('ready') and r.get('resource_ready') and r.get('survival_ready'),90)

def probe(name, mode, key, profile=None, world='wave5-w59-fixture'):
    return start(name,['--path',game_project,'--script','res://tests/networking/w5_9_process.gd','--',
       '--session='+mode,'--proof-dir='+str(evidence),'--proof-name='+name,'--port=25661',
       '--world-id='+world,'--seed=184552221'],profile=profile,executable=runner.with_name('godot.windows.editor.x86_64.exe'),cwd=game_project,key=key,bridge=True)

def converge(name):
    return wait(name,lambda r:r.get('ready') and r.get('final_error',99)<.12,30)

def move_actor(host, name, position, settle=False):
    command(host,op='actor_position',player_id=read(name)['player_id'],position=position)
    # Water aim needs a settled camera; other fixture teleports retain their
    # original arrival predicate (some deliberately overlap placed material).
    # Opt-in settling keeps the existing bounded relocation deadline.
    def settled(r):
        arrived=(r.get('ready') and r.get('final_error',99)<.12 and
                 abs(r.get('position',[1e9,0,1e9])[0]-position[0])<.12 and
                 abs(r.get('position',[1e9,0,1e9])[2]-position[2])<.12)
        if not settle or not arrived:return arrived
        body=read(host).get('bodies',{}).get(r.get('player_id'),{}).get('state',{})
        return (r.get('grounded') and abs(r.get('velocity',[0,99,0])[1])<.02 and
                r.get('settled_physics_frames',0)>=6 and body.get('grounded') and
                abs(body.get('velocity',[0,99,0])[1])<.02 and
                abs(body.get('position',[0,1e9,0])[1]-r['position'][1])<.12)
    return wait(name,settled,30)

def quantity(personal, content):
    return sum(int(s.get('quantity',1)) for s in personal.get('inventory',[])+personal.get('equipment',[]) if s and s.get('content')==content)

def race(left, right, label):
    counts={name:submit(name,op='resource_release') for name in [left,right]}
    results=[wait(name,lambda r,n=name:len(r['commands'])>counts[n],30)['commands'][-1]['result'] for name in [left,right]]
    check(sum(bool(r.get('success')) for r in results)==1,label+' exactly one winner')
    check(read('host')['instances_unique'],label+' global instance uniqueness')
    return dict(label=label,results=results,totals=read('host')['totals'])

def copy_evidence(source, target):
    def extended(path):
        return Path('\\\\?\\'+str(path.resolve())) if os.name=='nt' else path
    source,target=extended(source),extended(target)
    shutil.copytree(source,target)
    def inventory(root):
        return {f.relative_to(root).as_posix():digest(f) for f in root.rglob('*') if f.is_file()}
    before,after=inventory(source),inventory(target)
    check(before==after,'complete regression evidence copy hashes')
    return dict(files=len(before),hashes_verified=True)

try:
    check(gate['runner_sha256']=='06e7be7ed0298e81be421076a4a3166a7ae0e6b72c8a948d6faefd5823b3ee1a','approved console runner')
    graphical=runner.with_name('godot.windows.editor.x86_64.exe')
    check(digest(graphical)=='87D0A6077ABE38B905F973B23D9F27FD4F3B7A8DB2309DFD6807FAD7DFF582C8','approved graphical runner')
    gate['graphical_runner_sha256']=digest(graphical)
    # Pin publishable LF bytes; exclude pre-existing editor scene/project hunks
    # and untracked UID sidecars. Retain their raw hashes independently.
    paths=git('ls-files','--cached','--others','--exclude-standard','--','project.godot','src','content','scenes','tests','tools','addons','docs','AGENTS.md').decode().splitlines()
    tracked=set(git('ls-files').decode().splitlines())
    paths=[p for p in paths if (not p.endswith('.gd.uid') or p in tracked) and '/__pycache__/' not in p and not p.endswith('.pyc')]
    for relative in paths:
        source=repo/relative;raw=source.read_bytes();raw_hashes[relative]=digest(source)
        if relative=='project.godot': data=re.sub(rb'config/version="[^"]+"',b'config/version="0.6.1-wave5-w5.9"',git('show','HEAD:'+relative))
        elif relative=='scenes/main/wave_1_playground.tscn': data=git('show','HEAD:'+relative)
        else: data=raw.replace(b'\r\n',b'\n') if source.suffix in ('.gd','.ps1','.py','.md','.json','.tscn','.godot','.tres','.txt','.cfg','.gdextension','.svg') else raw
        target=project/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);manifest[relative]=digest(target)
    write_json(project/'.verification_snapshot_inventory.json',paths)
    write_json(evidence/'source_manifest.json',manifest)
    write_json(evidence/'working_source_manifest.json',raw_hashes)
    write_json(evidence/'runner_manifest.json',dict(console={'path':str(runner),'sha256':digest(runner)},graphical={'path':str(graphical),'sha256':digest(graphical)},plugins={p:pin for p,pin in manifest.items() if p.startswith('addons/') and p.endswith('.dll')}))
    gate['hardware']=dict(platform=platform.platform(),processor=platform.processor(),logical_cpus=os.cpu_count(),python=platform.python_version())
    gate['powershell_child_modules']=powershell_modules
    gate['hardware']['cim']=subprocess.check_output(['powershell.exe','-NoProfile','-Command',"@{cpu=@(Get-CimInstance Win32_Processor | Select-Object Name);gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion);memory_bytes=(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory} | ConvertTo-Json -Depth 4"],text=True).strip()
    start('import',['--headless','--editor','--path',project,'--quit']);finish('import',180)
    start('focused',['--headless','--path',project,'--script','res://tests/networking/w5_9_focused.gd','--','--output='+str(evidence/'focused.json')]);finish('focused')
    check(read('focused').get('passed'),'focused validation');gate['focused']=read('focused')
    shutil.copytree(project,game_project)
    main=game_project/'src/game/app/wave_1_playground.gd'
    main.write_text(main.read_text().replace('LfeNetworkSession.new()','load("res://tests/networking/w5_9_measured_session.gd").new()'),encoding='utf-8')
    with (game_project/'project.godot').open('a',encoding='utf-8') as file:file.write('\n[autoload]\nW58FixtureInvite="*res://tests/networking/w5_8_regression_bridge.gd"\n')
    gate['test_only_instrumentation']=dict(session_constructor=digest(main),project=digest(game_project/'project.godot'),credential_bridge=digest(game_project/'tests/networking/w5_8_regression_bridge.gd'),normal_runtime_unchanged=True)
    start('game-import',['--headless','--editor','--path',game_project,'--quit'],cwd=game_project);finish('game-import',180)
    key=new_secret()
    probe('host','HOST',key);h=ready('host')
    arena=command('host',op='arena');y=arena['commands'][-1]['y']
    for name in ['client','third']:
        probe(name,'JOIN',key);ready(name)
    ids=[read(n)['player_id'] for n in ['host','client','third']]
    pids=[read(n)['pid'] for n in ['host','client','third']]
    check(len(set(ids))==3 and len(set(pids))==3,'three distinct durable identities and OS processes')
    h=wait('host',lambda r:len(r.get('bodies',{}))==2 and len(r.get('roster',[]))==3)
    check(not h['upnp_enabled'],'local/LAN certification does not enable UPnP')
    check(len(h['bindings'])==3 and h['graph_valid'],'one authority graph with three character records')
    for name in ['client','third']:
        c=read(name);check(c['no_authority'] and c['no_world_save'],'JOIN has no authority/save '+name)
        command('host',op='survival_items',player_id=c['player_id'])
        command('host',op='survival_set',player_id=c['player_id'],values={'thirst':37 if name=='client' else 63,'fatigue':11 if name=='client' else 23})
        wait(name,lambda r,n=name:r['survival']['thirst']<40 if n=='client' else r['survival']['thirst']>60)
    check(read('client')['personal_hash']!=read('third')['personal_hash'] or read('client')['survival']!=read('third')['survival'],'independent owner views')
    gate['multi_client']=dict(identities=ids,pids=pids,roster=3,remote_bodies=2,maximum_design=8)
    for name in ['host','client','third']:command(name,op='w59_capture',file='three-player-ready')

    # A malformed authenticated peer cannot mutate other players or authority.
    command('host',op='w59_freeze',active=True)
    before=read('host');malformed=command('client',op='w59_malformed')['commands'][-1];time.sleep(1)
    after=read('host')
    check(malformed['sent']==40 and malformed['rejected_before_send']==10,'bounded malformed packets sent; oversized packets rejected at transport seam')
    check(before['totals']==after['totals'] and before['overrides']==after['overrides'] and before['characters']==after['characters'],'all gameplay families malformed injection leaves frozen authoritative graph unchanged')
    check(read('third')['state']=='CONNECTED' and after['graph_valid'],'healthy third player survives malformed peer')
    command('host',op='w59_freeze',active=False)
    gate['malformed_real_transport']=dict(attempted=malformed['attempted'],sent=malformed['sent'],rejected_before_send=malformed['rejected_before_send'],channels=[1,3,4,5,6,7,8,9,10,11])

    # Actual storage failure cancels graceful shutdown while both clients stay.
    check(command('host',op='w57_save_measure')['commands'][-1]['saved'],'initial checkpoint creates isolated world directory')
    check(command('host',op='w59_io_block',active=True)['commands'][-1]['error']==0,'create isolated pending-path write failure')
    blocked=command('host',op='w57_shutdown_blocked')
    check(not blocked['commands'][-1]['accepted'] and blocked['state']=='HOSTING' and not blocked['shutdown_fence'],'write failure cancels HOST shutdown')
    check(ready('client')['state']=='CONNECTED' and ready('third')['state']=='CONNECTED','write failure retains clients')
    check(command('host',op='w59_io_block',active=False)['commands'][-1]['error']==0,'remove only isolated failure directory')
    check(command('host',op='w57_save_measure')['commands'][-1]['saved'],'save recovers after write failure')
    gate['write_failure']=True

    # Concurrent block mining: normal held input, one finite block/drop.
    command('host',op='resource_pause_pickup',active=True)
    for name,x in [('client',-.5),('third',1.5)]:
        move_actor('host',name,[x,y+.05,3.5]);command(name,op='look',cell=[0,y,0])
    baseline=read('host')['totals']['leyforge:dirt']
    command('host',op='watch',cells=[[0,y,0]])
    for name in ['client','third']:command(name,op='harvest_input',active=True)
    wait('host',lambda r:r.get('cells') and r['cells'][0]['canonical']=='leyforge:air',15)
    for name in ['client','third']:command(name,op='harvest_input',active=False)
    time.sleep(.5)
    mined=read('host')
    check(mined['totals']['leyforge:dirt']==baseline and sum(d['stack']['quantity'] for d in mined['drops'] if d['stack']['content']=='leyforge:dirt')==1,'same block contention one finite drop output and conserved placed material')
    gate['voxel_contention']=True

    # Same-cell inventory-backed placement with conserved world material.
    for name,x in [('client',-1.5),('third',2.5)]:
        move_actor('host',name,[x,y+.05,3.5]);command(name,op='w59_aim',point=[.5,y-.01,2.5])
        wait(name,lambda r:r.get('target')==[0,y-1,2])
        command(name,op='resource_queue',operation='place',content='leyforge:oak_planks',args={'cell':[0,y,2],'expected_block':'leyforge:air'})
    total=read('host')['totals']['leyforge:oak_planks']
    gate['contention']=[race('client','third','same target placement')]
    check(read('host')['totals']['leyforge:oak_planks']==total,'placement total includes exactly one recoverable block')
    for name in ['client','third']:command(name,op='retry')
    time.sleep(.7);check(read('host')['totals']['leyforge:oak_planks']==total,'placement exact/conflicting retry conserves')

    # Boundary edits are real commits; every receiver must observe exact final
    # cells and collision, then the same sparse graph must survive HOST restart.
    boundary=[15,y,0]
    for name in ['host','client','third']:command(name,op='watch',cells=[boundary,[16,y,0]])
    command('host',op='traffic',cell=boundary)
    command('host',op='traffic',cell=[16,y,0])
    for name in ['client','third']:
        wait(name,lambda r:len(r.get('cells',[]))==2 and all(v['canonical']=='leyforge:grass' and v['collision'] for v in r['cells']),30)
    gate['boundary_ordering_collision']=dict(commits=80,final='leyforge:grass',cells=[boundary,[16,y,0]])

    # In addition to direct commit ordering, exercise actual inventory-backed
    # placement and normal held mining on both sides of the 16-cell boundary.
    command('host',op='w59_boundary_arena',y=y)
    check(command('host',op='w59_seed_personal',player_id=ids[1],content='leyforge:oak_planks',quantity=8)['commands'][-1]['added']==8,'explicit isolated boundary input fixture')
    wait('client',lambda r:quantity(r['personal'],'leyforge:oak_planks')>=8)
    move_actor('host','client',[15.5,y+.05,2.5])
    original_host_position=read('host')['position']
    distant=command('host',op='host_distance',player_id=ids[1],distance=180)['commands'][-1]['position']
    ready('host')
    wait('client',lambda r:ids[0] not in r.get('avatars',[]))
    check(abs(distant[0]-read('client')['position'][0])>128,'HOST camera beyond remote relevance')
    plank_total=read('host')['totals']['leyforge:oak_planks']
    boundary_cycles=[]
    for x in [15,16,15,16,15,16]:
        cell=[x,y,0]
        move_actor('host','client',[x+.5,y+.05,2.5])
        command('client',op='watch',cells=[cell])
        command('client',op='w59_aim',point=[x+.5,y-.01,.5])
        wait('client',lambda r:r.get('target')==[x,y-1,0])
        placed=command('client',op='source_place',content='leyforge:oak_planks',cell=cell)
        check(placed['commands'][-1]['result']['success'],'real boundary inventory placement')
        wait('client',lambda r:r.get('cells') and r['cells'][0]['canonical']=='leyforge:oak_planks' and r['cells'][0]['collision'])
        check(command('client',op='gather_one',cell=cell)['commands'][-1]['removed'],'real boundary held mining')
        wait('client',lambda r:r.get('cells') and r['cells'][0]['canonical']=='leyforge:air' and not r['cells'][0]['collision'])
        h=wait('host',lambda r:r['totals']['leyforge:oak_planks']==plank_total)
        check(h['instances_unique'] and h['graph_valid'],'boundary inventory/drop/placed conservation graph')
        boundary_cycles.append(dict(cell=cell,conserved_planks=plank_total))
    gate['boundary_gameplay_cycles']=boundary_cycles
    # The HOST camera stays far away while a real renewable held intent reaches
    # a finite canonical cache at the remote body's own streamed position.
    water=next(s for s in read('host')['sources'] if s['source']=='trail_water' and s['remaining']>0)
    for name in ['host','client']:
        command(name,op='w59_harvest_probe',source=water['instance'],actor=ids[1])
    wx,wy,wz=water['position']
    arrival=move_actor('host','client',[wx,int(wy)+.05,wz+2],settle=True)
    wait('client',lambda r:water['instance'] in r.get('source_nodes',[]))
    before_water=quantity(read('client')['personal'],'leyforge:drinking_water')
    before_hunger=read('client')['survival']['hunger']
    before_total=read('host')['totals']['leyforge:drinking_water']
    command('client',op='source_look',id=water['instance'])
    aimed=wait('client',lambda r:r.get('harvest_probe',{}).get('target_source')==water['instance'] and r.get('settled_physics_frames',0)>=6,15)
    host_aimed=wait('host',lambda r:r.get('harvest_probe',{}).get('host_source_reason')=='ok',15)
    command('client',op='harvest_input',active=True)
    wait('host',lambda r:next(s for s in r['sources'] if s['instance']==water['instance'])['remaining']==0,15)
    command('client',op='harvest_input',active=False)
    wait('client',lambda r:quantity(r['personal'],'leyforge:drinking_water')==before_water+4)
    check(read('client')['survival']['hunger']<before_hunger and read('third')['state']=='CONNECTED','distant survival and independent third continue')
    check(read('host')['totals']['leyforge:drinking_water']==before_total+4 and read('host')['graph_valid'] and read('host')['instances_unique'],'finite water output conserved across authoritative resource graph')
    check(abs(read('host')['position'][0]-read('client')['position'][0])>128,'HOST camera remains outside water harvesting relevance')
    write_json(evidence/'water-readiness.json',dict(arrival=arrival['harvest_probe'],aimed=aimed['harvest_probe'],host_aimed=host_aimed['harvest_probe'],before_water=before_water,after_water=quantity(read('client')['personal'],'leyforge:drinking_water'),before_total=before_total,after_total=read('host')['totals']['leyforge:drinking_water'],remaining=next(s for s in read('host')['sources'] if s['instance']==water['instance'])['remaining']))
    for name in ['host','client']:command(name,op='w59_harvest_probe')
    gate['distant_resource_simulation']=dict(host_camera_x=distant[0],finite_output=4,source=water['instance'],normal_held_input=True)
    command('host',op='actor_position',player_id=ids[0],position=original_host_position)
    ready('host')

    # Shared Workbench still has separate actor staging and canonical output.
    bench=command('host',op='w59_fixture',cell=[-2,y,0],content='leyforge:workbench')['commands'][-1]['id']
    for name,x in [('client',-2.5),('third',-.5)]:
        move_actor('host',name,[x,y+.05,2.5])
        check(command(name,op='resource',operation='open_context',args={'target':bench})['commands'][-1]['result']['success'],'shared Workbench opens '+name)
    for name in ['client','third']:
        check(command(name,op='resource_move',content='leyforge:oak_planks',quantity=1,destination='grid',destination_slot=0)['commands'][-1]['result']['success'],'independent Workbench staging '+name)
    h=wait('host',lambda r:all(r.get('grids',{}).get(actor,[None])[0] for actor in ids[1:]))
    check(h['grids'][ids[1]] is not h['grids'][ids[2]],'distinct staged actor records')
    counts={name:submit(name,op='resource',operation='craft',args={'recipe':'leyforge:split_oak_sticks'}) for name in ['client','third']}
    for name in ['client','third']:
        r=wait(name,lambda r,n=name:len(r['commands'])>counts[n])
        check(r['commands'][-1]['result']['success'],'simultaneous independent Workbench craft '+name)
        check(command(name,op='resource',operation='close_grid',args={})['commands'][-1]['result']['success'],'Workbench staging release '+name)
    gate['shared_workbench']=True

    storage=command('host',op='w59_fixture',cell=[-2,y,1],content='leyforge:storage_box')['commands'][-1]['id']
    endpoint='storage/'+storage
    for name in ['client','third']:
        check(command(name,op='resource',operation='open_context',args={'target':storage})['commands'][-1]['result']['success'],'shared storage opens '+name)
        command(name,op='resource_queue',operation='transfer',content='leyforge:oak_stick',args={'source':'inventory','destination':endpoint,'destination_slot':0,'quantity':1})
    gate['contention'].append(race('client','third','simultaneous storage deposits same expected state'))
    # The loser has no committed debit and may retry using fresh domain facts.
    for name in ['client','third']:
        command(name,op='resource_queue',operation='transfer',content='leyforge:oak_stick',args={'source':endpoint,'destination':'inventory','destination_slot':-1,'quantity':1})
    gate['contention'].append(race('client','third','final shared storage stack withdrawal'))
    command('host',op='w59_seed_endpoint',family='storage',id=storage,full=True)
    for name in ['client','third']:
        r=command(name,op='resource_move',content='leyforge:oak_stick',quantity=1,destination=endpoint,destination_slot=-1)
        check(not r['commands'][-1]['result']['success'],'full storage deposit rejected '+name)
        command(name,op='resource',operation='close_grid',args={})

    kiln=command('host',op='w59_fixture',cell=[1,y,0],content='leyforge:kiln')['commands'][-1]['id']
    for name,x in [('client',.5),('third',2.5)]:
        move_actor('host',name,[x,y+.05,2.5])
        check(command(name,op='resource',operation='open_context',args={'target':kiln})['commands'][-1]['result']['success'],'shared Kiln opens '+name)
    for family,amount in [('input',2),('fuel',1)]:
        command('host',op='w59_seed_endpoint',family=family,id=kiln,content='leyforge:oak_heartwood',quantity=amount)
        endpoint='station/'+kiln+'/'+family
        for name in ['client','third']:
            wait(name,lambda r:r.get('resource_streams',{}).get('object/'+kiln,{}).get('station',{}).get(family,[None])[0] is not None)
            command(name,op='resource_queue',operation='transfer',content='leyforge:oak_heartwood',args={'source':endpoint,'destination':'inventory','destination_slot':-1,'quantity':amount})
        gate['contention'].append(race('client','third','same Kiln '+family+' withdrawal'))
        # Return exactly the withdrawn quantity from its actual winning owner.
        owner=next(n for n in ['client','third'] if quantity(read(n)['personal'],'leyforge:oak_heartwood')>=amount)
        check(command(owner,op='resource_move',content='leyforge:oak_heartwood',quantity=amount,destination=endpoint,destination_slot=0)['commands'][-1]['result']['success'],'return contested Kiln '+family)
    check(command('client',op='resource',operation='start_process',args={'target':kiln,'recipe':'leyforge:charcoal_burn'})['commands'][-1]['result']['success'],'shared Kiln starts once')
    wait('host',lambda r:any(o['instance']==kiln and o.get('station',{}).get('output',[None])[0] is not None for o in r.get('objects',[])),20)
    for name in ['client','third']:
        wait(name,lambda r:r.get('resource_streams',{}).get('object/'+kiln,{}).get('station',{}).get('output',[None])[0] is not None)
        command(name,op='resource_queue',operation='transfer',content='leyforge:charcoal',args={'source':'station/'+kiln+'/output','destination':'inventory','destination_slot':-1,'quantity':2})
    gate['contention'].append(race('client','third','final shared Kiln output withdrawal'))
    for name in ['client','third']:command(name,op='resource',operation='close_grid',args={})

    # Ten context-specific leaves, same running HOST and stable third player.
    # Physical Workbench/Storage/Kiln/rest interaction itself is additionally
    # exercised by the complete Repair-1 normal-input regression.
    contexts=[]
    for label in ['idle','movement','held_harvest','voxel','inventory','workbench','storage','kiln','manual','rest','pending_transaction']:
        if label in ['movement']:command('client',op='w59_motion',direction='move_right',sprint=True)
        elif label in ['held_harvest','voxel']:
            move_actor('host','client',[2.5,y+.05,3.5]);command('client',op='look',cell=[2,y,0]);command('client',op='harvest_input',active=True)
        elif label in ['inventory','manual']:command('client',op='w57_ui',manual=label=='manual')
        elif label=='pending_transaction':command('client',op='w57_pending')
        elif label in ['workbench','storage','kiln','rest']:
            # An isolated functional fixture uses the production object/voxel
            # seam; it supplies no player-owned resources or forged client state.
            block={'workbench':'workbench','storage':'storage_box','kiln':'kiln','rest':'rest_mat'}[label]
            cell=[3,y,2]
            if label=='rest':
                move_actor('host','client',[2.5,y+.05,4.5])
                fixture=command('host',op='survival_shelter',player_id=ids[1])['commands'][-1]
                wait('client',lambda r:'object/'+fixture['target'] in r.get('resource_streams',{}))
                command('client',op='survival_rest',target=fixture['target'])
                wait('host',lambda r:ids[1] in r.get('rests',{}))
            else:
                # Remove a previous fixture only after clients have left its UI.
                obj=command('host',op='w59_fixture',cell=cell,content='leyforge:'+block)['commands'][-1]
                move_actor('host','client',[2.5,y+.05,4.5])
                opened=command('client',op='w57_context',id=obj['id'])['commands'][-1]
                check(opened['accepted'] and opened['opened'],label+' context open before disconnect')
        if label=='manual':check(read('client')['manual_visible'],'Manual visible before disconnect')
        if label=='inventory':check(read('client')['ui_open'],'Inventory visible before disconnect')
        prior=read('client');before=read('host')
        command('client',op='w57_leave')
        ended=wait('client',lambda r:r['state']=='DISCONNECTED' and not r['terrain_exists'] and not r['player_exists'],15)
        check(ended['world_node_count']==0,label+' no ghost world nodes')
        h=wait('host',lambda r:len(r.get('bodies',{}))==1 and len(r.get('bindings',{}))==2)
        check(h['totals']==before['totals'],label+' disconnect conserves all resources')
        check(ids[1] not in h.get('held_actions',{}) and ids[1] not in h.get('rests',{}),label+' clears actions/rest')
        check(ready('third')['state']=='CONNECTED' and h['instances_unique'] and h['graph_valid'],label+' third continues and graph valid')
        command('client',op='w57_reconnect');again=ready('client')
        command('client',op='w59_motion',direction='stop')
        check(again['pid']==prior['pid'] and again['player_id']==ids[1] and again['generation']>prior['generation'],label+' same durable identity fresh session')
        check(again['no_authority'] and again['no_world_save'],label+' JOIN save negative')
        contexts.append(dict(context=label,generation=again['generation'],nodes_ended=ended['world_node_count'],roster=len(read('host')['roster']),totals=read('host')['totals']))
    gate['disconnect_matrix']=contexts

    # Bounded stress beyond two remotes, then return to the three-player soak.
    for name in ['fourth','fifth']:probe(name,'JOIN',key);ready(name)
    h=wait('host',lambda r:len(r.get('bodies',{}))==4)
    check(len(h['bindings'])==5 and len(h['roster'])==5 and h['graph_valid'],'five actual players / four remote bodies')
    command('host',op='w59_capture',file='five-player-smoke')
    for name in ['fourth','fifth']:
        check(read(name)['no_authority'] and read(name)['no_world_save'],'extra JOIN save negative '+name)
        command(name,op='w59_motion',direction='move_right')
    time.sleep(3)
    gate['multi_client']['stress']=dict(total_players=5,remote_bodies=4,measured_seconds=3,not_eight_player_certification=True)
    for name in ['fourth','fifth']:stop(name)
    wait('host',lambda r:len(r.get('bodies',{}))==2)

    # Continuous actual-process soak, idle and active. Each active cycle has
    # opposite/direction-changing motion, a real item transaction and edits.
    soak_start=time.monotonic();samples=[];cycle=0
    print('W5.9 continuous soak started ('+str(args.soak_seconds)+' seconds)',flush=True)
    while time.monotonic()-soak_start<args.soak_seconds:
        for name in ['host','client','third']:
            r=ready(name);check(r['state'] in ['HOSTING','CONNECTED'],name+' live during soak')
        active=cycle%2==0
        directions=['move_left','move_right'] if (cycle//2)%2==0 else ['move_right','move_left']
        for name,direction in zip(['client','third'],directions):
            command(name,op='w59_motion',direction=direction if active else 'stop',sprint=active,jump=active)
        command('host',op='edit',cell=[16,y,0],block='leyforge:air' if active else 'leyforge:grass')
        c=command('client',op='resource',operation='select',args={'slot':cycle%9})
        check(c['commands'][-1]['result'].get('success'),'soak authoritative selection transaction')
        h=read('host');check(h['graph_valid'] and h['instances_unique'],'soak graph/instance validation')
        samples.append(dict(elapsed=time.monotonic()-soak_start,active=active,host=h['measurements'][-1] if h.get('measurements') else {},client=read('client').get('measurements',[])[-1:],third=read('third').get('measurements',[])[-1:],process_memory={n:working_set(n) for n in ['host','client','third']}))
        cycle+=1
        time.sleep(min(12,max(0,args.soak_seconds-(time.monotonic()-soak_start))))
        if cycle%4==0:print('W5.9 soak elapsed '+str(round(time.monotonic()-soak_start))+'s',flush=True)
    duration=time.monotonic()-soak_start
    for name in ['client','third']:command(name,op='w59_motion',direction='stop');converge(name)
    gate['soak']=dict(duration_seconds=duration,requested_seconds=args.soak_seconds,cycles=cycle,continuous=True,processes=pids,samples=samples)
    write_json(evidence/'soak_metrics.json',gate['soak'])
    summaries={}
    for name in ['host','client','third']:
        r=read(name);write_json(evidence/(name+'-metrics.json'),r['measurements'])
        m=r['measurements'];check(len(m)>=2,name+' measured performance samples')
        tail=m[-max(2,len(m)//3):]
        check(max(s['reliable_queue'] for s in m)<4096,name+' bounded send queue')
        # Static engine allocation and Windows RSS are distinct. A measured
        # tail bound catches runaway fixture/runtime allocation without claiming
        # a production memory guarantee from this machine.
        check(tail[-1]['static_memory_bytes']-tail[0]['static_memory_bytes']<64*1024*1024,name+' tail static memory growth below 64 MiB')
        def measured(sample):
            return sample[name] if name=='host' else sample[name][0]
        first,last=measured(samples[0]),measured(samples[-1])
        elapsed=max(.001,(last['msec']-first['msec'])/1000)
        frame_delta=last['frames']-first['frames']
        sent_bytes=lambda s:s['gameplay_transport']['sent_bytes']+s['transport']['sent_bytes']
        sent_packets=lambda s:s['gameplay_transport']['sent_packets']+s['transport']['sent_packets']
        summaries[name]=dict(measured_seconds=elapsed,frame_interval_mean_msec=elapsed*1000/max(1,frame_delta),physics_msec_last=last['physics_msec'],process_msec_last=last['process_msec'],sent_payload_bytes_per_second=(sent_bytes(last)-sent_bytes(first))/elapsed,sent_packets_per_second=(sent_packets(last)-sent_packets(first))/elapsed,received_payload_bytes_per_second=(last['gameplay_transport']['received_bytes_including_control']-first['gameplay_transport']['received_bytes_including_control'])/elapsed,static_memory_start=first['static_memory_bytes'],static_memory_end=last['static_memory_bytes'],working_set_start=samples[0]['process_memory'][name]['working_set_bytes'],working_set_end=samples[-1]['process_memory'][name]['working_set_bytes'],nodes_start=first['nodes'],nodes_end=last['nodes'],max_observed_send_queue=max(s['reliable_queue'] for s in m))
        summaries[name]['resource_commits_or_results_per_second']=(last.get('resource_commands',0)-first.get('resource_commands',0))/elapsed
    gate['performance']=dict(context='single development PC; concurrent rendered fixture/report overhead; application payload counters exclude ENet/UDP overhead',metrics=['host-metrics.json','client-metrics.json','third-metrics.json'],summary=summaries,eight_player_performance_certified=False)
    write_json(evidence/'performance_summary.json',gate['performance'])

    # Exact completed save graph/file survive fresh HOST process; current JOIN
    # snapshots are discarded on shutdown and rebuilt from saved HOST truth.
    for name in ['client','third']:stop(name)
    wait('host',lambda r:len(r.get('bodies',{}))==0)
    check(command('host',op='w57_save_measure')['commands'][-1]['saved'],'final complete graph save')
    command('host',op='w57_f10');finish('host',30);saved=read('host')
    probe('restart','HOST',key,profile='host');restored=ready('restart')
    check(restored['loaded_graph_hash']==saved['saved_graph_hash'] and restored['loaded_file_hash']==saved['saved_file_hash'],'fresh HOST exact authoritative graph/file equality')
    probe('rejoin','JOIN',key,profile='client');c=ready('rejoin')
    check(c['player_id']==ids[1] and c['no_world_save'] and c['no_authority'],'restarted identity/rejoin cannot save')
    gate['persistence']=dict(saved_graph_hash=saved['saved_graph_hash'],loaded_graph_hash=restored['loaded_graph_hash'],saved_file_hash=saved['saved_file_hash'],loaded_file_hash=restored['loaded_file_hash'])
    stop('rejoin');stop('restart')

    # Exact new owner HOST/LOCAL JOIN launchers, normal main scene, missing
    # class cache and existing physical input observer (no production rewrite).
    start('owner-prepare',['-NoProfile','-ExecutionPolicy','Bypass','-File',project/'tests/networking/w5_9_prepare_owner.ps1','-SnapshotPath',project,'-TempRoot',work,'-EvidencePath',evidence],executable='powershell.exe');finish('owner-prepare',60)
    prepared=read('owner-preparation');check(prepared['clean_cache'],'normal W5.9 owner launch starts with missing cache')
    owner_project=Path(prepared['project'])
    for name,mode in [('owner-host','HOST'),('owner-client','JOIN')]:
        start(name,['-NoProfile','-ExecutionPolicy','Bypass','-File',project/'tests/networking/w5_9_launch.ps1','-ProjectPath',owner_project,'-ProofDir',evidence,'-ProofName',name,'-Mode',mode,'-Port','25662','-GodotRoot',runner.parent],executable='powershell.exe',cwd=owner_project,key=key,bridge=True)
        ready(name)
    check(read('owner-host')['world']['world_id']=='wave5-w59-owner-test','W5.9 HOST default world forwarded')
    check(read('owner-client')['no_authority'] and read('owner-client')['no_world_save'],'normal local JOIN save prohibition')
    command('owner-client',op='w57_ui',manual=True)
    check(read('owner-client')['manual_visible'],'normal W5.9 JOIN Manual physical button')
    submit('owner-host',op='w57_f10');finish('owner-host',30)
    wait('owner-client',lambda r:r['state']=='DISCONNECTED' and not r['terrain_exists'] and r['ended_visible'],15)
    stop('owner-client')
    gate['exact_owner_launchers']=dict(clean_cache=True,normal_main_scene=True,host_defaults=True,local_join=True,manual_physical_input=True,host_f10_teardown=True,instrumentation='owner-preparation.json')

    # A full W5.8 run on these exact source bytes includes all earlier gates,
    # rendered normal UI, malformed/auth negatives and 50/100/200-ms conditions.
    if not args.skip_regression:
        regression=work/'regression';shutil.copytree(project,regression)
        start('regression',[regression/'tools/development/w5_8_verify.py','--runner',runner,'--git-source-repository',repo],executable='python',cwd=regression)
        finish('regression',7200)
        prior=sorted((regression/'.verification/wave5/w5_8').glob('run-*'))[-1]
        receipt=json.loads((prior/'gate.json').read_text(encoding='utf-8-sig'))
        check(receipt['passed'] and receipt['certified'] and receipt['snapshot_matches_source'],'complete W5.8 and all prior regressions certified')
        pins=json.loads((prior/'source_manifest.json').read_text(encoding='utf-8-sig'))
        check(pins==manifest and receipt['runner_sha256'].upper()==gate['runner_sha256'].upper(),'regression exact source inventory and runner identity')
        gate['regression_evidence']=copy_evidence(prior,evidence/'regression_w58')
        gate['regressions']=receipt['regressions']+'; W5.8 PASS'
        gate['network_quality']=receipt['network_quality']
    # A W5.9 compatible portable kit gets its own clean import and normal JOIN.
    kit=work/'portable-lan'
    start('kit-build',['-NoProfile','-ExecutionPolicy','Bypass','-File',project/'tools/development/build_wave_5_part_9_lan_join_kit.ps1','-OutputPath',kit,'-VerificationSnapshotPath',project],executable='powershell.exe');finish('kit-build',180)
    kit_manifest=json.loads((kit/'kit_manifest.json').read_text(encoding='utf-8-sig'))
    check(kit_manifest['application']==gate['application'] and kit_manifest['protocol']==7,'W5.9 compatible LAN kit')
    for relative,pin in kit_manifest['files'].items():check(digest(kit/relative)==pin,'kit hash '+relative)
    forbidden={'.git','.godot','identity','worlds','saves','logs','.verification','userdata'}
    check(not any(p in forbidden for f in kit.rglob('*') for p in f.relative_to(kit).parts),'kit private-data exclusions')
    start('kit-import',['--headless','--editor','--path',kit,'--quit'],executable=kit/'runtime/godot.windows.editor.x86_64.console.exe',cwd=kit);finish('kit-import',180)
    probe('kit-host','HOST',key);ready('kit-host')
    start('kit-launch',['-NoProfile','-ExecutionPolicy','Bypass','-File',project/'tests/networking/w5_9_kit_launch.ps1','-KitPath',kit,'-EvidencePath',evidence,'-Port','25661'],executable='powershell.exe',cwd=kit,key=key);finish('kit-launch',120)
    check(read('kit-launch')['passed'] and read('kit-launch')['unique_local_identity'] not in ids,'normal portable LAN launcher own identity')
    stop('kit-host');gate['lan_kit']=dict(files=len(kit_manifest['files']),hashes_verified=True,clean_import=True,normal_join=True,precommit_verification_only=True)
    for relative,pin in raw_hashes.items():check(digest(repo/relative)==pin,'source remained unchanged '+relative)
    final_paths=git('ls-files','--cached','--others','--exclude-standard','--','project.godot','src','content','scenes','tests','tools','addons','docs','AGENTS.md').decode().splitlines()
    final_paths=[p for p in final_paths if (not p.endswith('.gd.uid') or p in tracked) and '/__pycache__/' not in p and not p.endswith('.pyc')]
    check(set(final_paths)==set(paths),'complete source inventory unchanged during gate')
    for f in Path('\\\\?\\'+str(evidence)).rglob('*'):
        if f.is_file() and f.suffix in ('.log','.json','.txt'):
            text=f.read_text(encoding='utf-8',errors='replace')
            check(not any(secret in text for secret in credentials),'invite redaction '+f.name)
    gate['secret_redaction']=True;gate['snapshot_matches_source']=True
    gate['passed']=True;gate['certified']=bool(gate['regressions']) and duration>=600
    gate['classification']='AUTOMATED_CERTIFIED' if gate['certified'] else 'DIAGNOSTIC_UNCERTIFIED'
    print('WAVE_5_PART_9_VALIDATION_PASS',flush=True)
except Exception as error:
    gate['failure']=str(error)[:6000];gate['classification']='FAIL'
    print('W5_9_FAILURE: '+str(error)[:6000],flush=True)
finally:
    for name,(proc,log) in processes.items():
        if proc.poll() is None:(evidence/(name+'.stop')).write_text('stop')
    for proc,log in processes.values():
        if proc.poll() is None:
            try:proc.wait(timeout=3)
            except subprocess.TimeoutExpired:proc.kill();proc.wait()
        log.close()
    write_json(evidence/'checks.json',checks)
    write_json(evidence/'command_latencies.json',command_latencies)
    write_json(evidence/'gate.json',gate)
    print('WAVE_5_PART_9_EVIDENCE='+str(evidence),flush=True)
raise SystemExit(0 if gate['passed'] else 1)
