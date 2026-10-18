"""W6.3 disposable data, rendered input/runtime proof, then complete W6.2 chain.

Production content and owner profiles are never test targets. Failed runs stay.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--runner', required=True, type=Path)
parser.add_argument('--focused-only', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
runner = args.runner
graphical = runner.with_name('godot.windows.editor.x86_64.exe')
evidence = repo / '.verification/wave6/w6_3' / ('run-' + time.strftime('%Y%m%dT%H%M%S', time.gmtime()) + '-' + str(time.time_ns() % 1000000000))
evidence.mkdir(parents=True)
work = Path(tempfile.mkdtemp(prefix='lf63-', dir='D:/'))
project = work / 'project'
checks, processes = [], {}
gate = dict(passed=False, certified=False, focused_only=args.focused_only,
            starting_commit=subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
            manual_acceptance='OWNER VOXEL EDITOR ACCEPTANCE REQUIRED', temp_project=str(project))


def write(path, value):
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def check(value, label):
    checks.append(dict(passed=bool(value), label=label))
    if not value:
        raise RuntimeError(label)


def git(*values):
    return subprocess.check_output(['git', '-C', str(repo), *values])


def inventory():
    tracked = set(git('ls-files').decode().splitlines())
    return [p for p in git('ls-files', '--cached', '--others', '--exclude-standard', '--',
                          'project.godot', 'src', 'content', 'scenes', 'tests', 'tools', 'addons', 'docs', 'AGENTS.md').decode().splitlines()
            if (not p.endswith('.gd.uid') or p in tracked) and '/__pycache__/' not in p and not p.endswith('.pyc')]


def start(name, arguments, rendered=False, profile='test'):
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA']:
        env[key] = str(work / (profile + '-' + key))
        Path(env[key]).mkdir(exist_ok=True)
    env['TEMP'] = env['TMP'] = str(work)
    env.pop('LEYFORGE_FORGE_ROOT', None)
    log = (evidence / (name + '.log')).open('w', encoding='utf-8')
    process = subprocess.Popen([str(graphical if rendered else runner), '--log-file', str(evidence / (name + '-engine.log')),
                                *map(str, arguments)], cwd=project, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes[name] = process, log
    return process


def log_text(name):
    return '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in [evidence / (name + '.log'), evidence / (name + '-engine.log')] if p.exists())


def finish(name, timeout=300):
    process, log = processes[name]
    code = process.wait(timeout=timeout)
    log.flush()
    text = log_text(name)
    check(code == 0 and not re.search(r'(?m)^\s*(SCRIPT ERROR|ERROR:)', text), name + ' clean exit: ' + text[-3500:] if code or 'ERROR:' in text else name + ' clean exit')


def read(name='creator'):
    try:
        return json.loads((evidence / (name + '.json')).read_text(encoding='utf-8-sig'))
    except (ValueError, OSError):
        return {}


def wait(condition, timeout=100):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = read()
        if result and condition(result):
            return result
        if processes['creator'][0].poll() is not None or 'SCRIPT ERROR:' in log_text('creator'):
            raise RuntimeError('creator failed: ' + log_text('creator')[-4000:])
        time.sleep(.1)
    raise RuntimeError('creator report timeout: ' + str(read())[-1000:])


def command(op, **values):
    before = read().get('processed', 0)
    pending = evidence / 'creator.command.pending'
    write(pending, dict(op=op, **values))
    pending.replace(evidence / 'creator.command.json')
    result = wait(lambda r: r.get('processed', 0) > before)
    with (evidence / 'input-events.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps(dict(input=dict(op=op, **values), revision=result['revision'], undo=result['undo'], cells=len(result['data'].get('cells', [])))) + '\n')
    return result


def widget(text=None, kind=None, contains=None):
    values = [w for w in read()['widgets'] if (text is None or w['text'] == text) and
              (kind is None or w['class'] == kind) and (contains is None or contains in w['path'])]
    check(len(values) == 1, 'one visible input target ' + str((text, kind, contains)))
    return values[0]


def click_widget(value):
    if 'ScrollContainer' in value['path']:
        for _ in range(40):
            value = next(w for w in read()['widgets'] if w['path']==value['path'])
            bx, by, bw, bh = read()['sidebar']
            _, y, _, h = value['rect']
            if y>=by and y+h<=by+bh:
                break
            command('click',x=bx+bw/2,y=by+bh/2,button=5 if y+h>by+bh else 4)
    x, y, width, height = value['rect']
    screen = read()['window_size']
    check(0 <= x and 0 <= y and x + width <= screen[0] + 1 and y + height <= screen[1] + 1, 'reachable ' + value['text'])
    return command('click', x=x + width/2, y=y + height/2)


def click(text):
    return click_widget(widget(text=text))


def text_field(value, text):
    click_widget(value)
    command('key', code=65, ctrl=True)
    command('text', text=text)


def page(index):
    x, y, width, height = read()['tabs'][index]
    return command('click', x=x+width/2, y=y+height/2)


def colour(value):
    click_widget(widget(kind='ColorPickerButton'))
    fields = [w for w in read()['widgets'] if w['class']=='LineEdit' and 'PopupPanel' in w['path']]
    check(len(fields)==1, 'native colour hex field')
    text_field(fields[0], value)
    command('key',code=4194309)
    command('key',code=4194305)
    check(not read()['ghost_visible'] and not read()['pending'], 'Escape removes temporary hover/gesture presentation')


def cell(x, y, z):
    px, py = read()['projections']['%d,%d,%d' % (x,y,z)]
    return command('click', x=px, y=py)


def stop():
    (evidence / 'creator.stop').write_text('stop')
    finish('creator')


def runtime_proof(name, root, relative, bundle):
    start(name, ['--path', project, '--script', 'res://tests/forge/w6_3_runtime.gd', '--', root, relative, bundle, evidence/name], True, name)
    finish(name)
    check(read(name).get('passed'), name + ' native mesh/collision proof')


try:
    check(digest(runner) == '06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A', 'approved console runner')
    check(digest(graphical) == '87D0A6077ABE38B905F973B23D9F27FD4F3B7A8DB2309DFD6807FAD7DFF582C8', 'approved graphical runner')
    write(evidence/'runner_manifest.json', dict(console=digest(runner), graphical=digest(graphical)))
    paths = inventory()
    raw, manifest = {}, {}
    for relative in paths:
        source = repo / relative
        data = source.read_bytes()
        raw[relative] = digest(source)
        if relative in ['project.godot', 'scenes/main/wave_1_playground.tscn']:
            data = git('show', 'HEAD:' + relative)
        if source.suffix in ('.gd', '.ps1', '.py', '.md', '.json', '.tscn', '.godot', '.tres', '.txt', '.cfg', '.gdextension', '.svg'):
            data = data.replace(b'\r\n', b'\n')
        target = project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest[relative] = digest(target)
    write(evidence/'source_manifest.json', manifest)
    write(evidence/'working_source_manifest.json', raw)
    reviewed = {'README.md':digest(repo/'README.md')}
    write(evidence/'additional_working_source_manifest.json',reviewed)
    write(evidence/'additional_source_manifest.json',{'README.md':hashlib.sha256((repo/'README.md').read_bytes().replace(b'\r\n',b'\n')).hexdigest().upper()})
    protected = {p: digest(repo/p) for p in git('ls-files', '--modified', '--others', '--exclude-standard').decode().splitlines() if (repo/p).is_file()}
    write(evidence/'protected_inventory.json', protected)
    start('import', ['--headless', '--editor', '--path', project, '--quit'])
    finish('import')
    start('focused', ['--headless', '--path', project, '--script', 'res://tests/forge/w6_3_focused.gd', '--', evidence/'focused.json'])
    finish('focused')
    focused = read('focused')
    check(focused.get('passed'), 'strict source, history, draft/recovery, publish, bake and DDA tests')
    runtime_proof('runtime-focused', focused['runtime_root'], focused['runtime_source'], focused['runtime_bundle'])
    start('creator', ['--path', project, '--script', 'res://tests/forge/w6_3_process.gd', '--', evidence/'creator'], True, 'creator')
    wait(lambda r: r.get('ready'))
    page(4)
    fields = [w for w in read()['widgets'] if w['class']=='LineEdit']
    text_field(fields[0], 'fixture:detail_block')
    text_field(fields[1], 'Detailed block study')
    click('New')
    check(read()['data']['cells']==[], 'new empty voxel volume through text and pointer input')
    click('Top')
    cell(5,0,5)
    check(len(read()['data']['cells'])==1 and read()['undo']==1, 'empty plane individual placement')
    click('Voxel Undo')
    check(not read()['data']['cells'], 'pointer undo restores empty model')
    point=read()['projections']['2,0,2']
    command('move',x=point[0],y=point[1])
    check(read()['hover'].get('valid') and read()['hover']['cell']==[2,0,2], 'empty plane hover identifies exact ghost cell')
    command('hold',x=point[0],y=point[1])
    check(read()['stroke'] and read()['pending']==1 and not read()['data']['cells'], 'pending gesture remains temporary editor presentation')
    command('key',code=4194305)
    command('release',x=point[0],y=point[1])
    check(not read()['stroke'] and read()['undo']==0 and not read()['data']['cells'], 'Escape cancels unfinished gesture with no history')
    command('hold',x=point[0],y=point[1])
    click_widget(widget(text='Detailed block study',kind='LineEdit'))
    check(not read()['stroke'] and not read()['data']['cells'], 'leaving viewport for text input cancels capture')
    a = read()['projections']['4,0,4']; b = read()['projections']['11,0,4']
    command('drag', x=a[0], y=a[1], dx=b[0]-a[0], dy=b[1]-a[1])
    check(len(read()['data']['cells'])>=8 and read()['undo']==1, 'fast spatial drag fills cells in one command')
    click('Voxel Undo')
    click('Box anchors'); cell(4,0,4)
    text_field(widget(kind='SpinBox'),'7')
    command('key',code=4194309)
    cell(11,7,11)
    check(read()['box_count']==512, 'visible two-anchor 8 cubed box region')
    click('Apply box')
    check(len(read()['data']['cells'])==512 and read()['undo']==1, 'atomic block-shaped box placement')
    click('Box anchors');click('Remove');cell(4,7,4)
    check(len(read()['data']['cells'])==511, 'detailed block notch through pointer removal')
    # Add a second literal swatch using the inspector's stable key field.
    text_field(widget(text='base', kind='LineEdit'), 'trim')
    colour('d08030ff')
    click('Apply swatch')
    check(len(read()['data']['palette'])==2, 'palette command via controls')
    click('Paint');cell(5,7,5)
    check(any(c[3]=='trim' for c in read()['data']['cells']), 'paint individual occupied cell')
    click('Voxel Undo');click('Voxel Redo')
    text_field(widget(text='trim',kind='LineEdit'),'stone')
    click('Use block colour reference');click('Apply swatch');click('Paint');cell(6,7,6)
    check(any(p.get('block_ref')=='leyforge:stone' for p in read()['data']['palette']) and any(c[3]=='stone' for c in read()['data']['cells']), 'existing solid-block colour reference through graphical swatch controls')
    click('Select');cell(5,7,5)
    check(read()['selection']==1, 'cell selection independent of content history')
    before = read()
    surface = widget(kind='SubViewportContainer')
    sx, sy, sw, sh = surface['rect']
    command('drag', x=sx+sw/2, y=sy+sh/2, dx=45, dy=15, button=2)
    check(read()['yaw']!=before['yaw'] and read()['undo']==before['undo'], 'RMB camera orbit independent of history')
    command('drag', x=sx+sw/2, y=sy+sh/2, dx=30, dy=15, button=3)
    check(read()['focus']!=before['focus'], 'MMB camera pan')
    command('click', x=sx+sw/2, y=sy+sh/2, button=4)
    command('key', code=70)
    check(read()['distance']!=before['distance'], 'selection frame / zoom')
    click_widget(widget(text='Detailed block study', kind='LineEdit'))
    yaw = read()['yaw']; command('key', code=70)
    check(read()['yaw']==yaw, 'text F does not move camera')
    text_field(widget(text='Detailed block study', kind='LineEdit'), 'Detailed block study')
    click('Frame model')
    for width, height in [(1920,1080),(1280,720),(960,540)]:
        command('resize', width=width, height=height)
        command('capture', path=str(evidence/('voxel-%dx%d.png' % (width,height))))
        x,y,w,h = widget(kind='SubViewportContainer')['rect']
        check(x>=0 and y>=0 and x+w<=width+1 and y+h<=height+1 and w>=400 and h>=160, 'usable voxel viewport %dx%d' % (width,height))
    click('Voxel Undo')
    click('Save voxel draft')
    snapshot = read()
    stop()
    (evidence/'creator.stop').unlink()
    start('creator-restart', ['--path', project, '--script', 'res://tests/forge/w6_3_process.gd', '--', evidence/'creator'], True, 'creator')
    processes['creator'] = processes['creator-restart']
    wait(lambda r: r.get('pid')==processes['creator'][0].pid and r.get('ready'))
    page(4)
    text_field([w for w in read()['widgets'] if w['class']=='LineEdit'][0], 'fixture:detail_block')
    click('Reopen draft')
    check(read()['data']==snapshot['data'] and read()['undo']==snapshot['undo'] and read()['redo']==snapshot['redo'], 'separate process restores full voxel draft/history')
    click('Voxel Redo');click('Validate');click('Review / Publish…')
    command('capture', path=str(evidence/'voxel-publication-review.png'))
    click('Publish voxel source')
    check(read()['last_result']['success'] and not read()['dirty'], 'explicit graphical voxel source publication')
    click('Bake')
    check(read()['last_result']['success'] and read()['bake_path'], 'graphical deterministic published bake')
    runtime_proof('runtime-block', read()['source_root'], read()['relative_path'], read()['bake_path'])
    # Second non-block silhouette uses the same authoring infrastructure.
    text_field(widget(text='fixture:detail_block', kind='LineEdit'), 'fixture:small_prop')
    text_field(widget(text='Detailed block study', kind='LineEdit'), 'Small prop study')
    click('New');click('Top');click('Place')
    a=read()['projections']['4,0,8'];b=read()['projections']['10,0,8']
    command('drag',x=a[0],y=a[1],dx=b[0]-a[0],dy=b[1]-a[1])
    cell(9,0,7);cell(9,0,9);cell(10,0,7);cell(10,0,9)
    text_field(widget(text='base',kind='LineEdit'),'metal');colour('8899aaff');click('Apply swatch');click('Paint');cell(9,0,8)
    command('capture',path=str(evidence/'small-non-block-prop.png'))
    check(len(read()['data']['cells'])>=10, 'small non-block asset via spatial tools')
    click('Validate');click('Review / Publish…');click('Publish voxel source');click('Bake')
    check(read()['last_result']['success'], 'second asset publish/bake')
    runtime_proof('runtime-prop',read()['source_root'],read()['relative_path'],read()['bake_path'])
    stop()
    gate['focused_graphical']=True
    check(paths==inventory() and all(digest(repo/p)==h for p,h in raw.items()),'source stable before complete nested regressions')
    if not args.focused_only:
        prior=set((repo/'.verification/wave6/w6_2').glob('run-*'))
        with (evidence/'w6_2-full.log').open('w',encoding='utf-8') as log:
            result=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(repo/'tools/development/verify_wave_6_part_2.ps1'),'-GodotExecutable',str(runner)],cwd=repo,stdout=log,stderr=subprocess.STDOUT)
        created=set((repo/'.verification/wave6/w6_2').glob('run-*'))-prior
        check(len(created)==1,'one fresh complete W6.2 receipt')
        nested=created.pop();gate['w6_2_evidence']=str(nested)
        receipt=json.loads((nested/'gate.json').read_text())
        check(result.returncode==0 and all(receipt.get(k) for k in ['passed','certified','snapshot_matches_source','full_regressions']),'complete W6.2/W6.1/W5.9 chain and unchanged full soak')
        check(json.loads((nested/'source_manifest.json').read_text())==manifest,'nested source manifest equality')
        gate['full_regressions']=True
    check(paths==inventory() and all(digest(repo/p)==h for p,h in raw.items()),'final source matches gate input')
    check(all(digest(repo/p)==h for p,h in reviewed.items()),'additional reviewed source unchanged')
    check(all(digest(repo/p)==h for p,h in protected.items()),'protected files unchanged')
    gate.update(passed=True,certified=not args.focused_only,snapshot_matches_source=True)
except Exception as error:
    gate['failure']=str(error)
    print('W6_3_FAILURE: '+str(error),flush=True)
finally:
    for process,log in processes.values():
        if process.poll() is None:
            process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        log.close()
    fixture_sources = {'canonical-voxel-assets':project/'content/voxel_assets'}
    for profile in ['test','creator']:
        fixture_sources[profile+'-voxel-drafts-bakes']=work/(profile+'-APPDATA')/'Godot/app_userdata/Leyforge/forge/voxel_assets'
    for name,source in fixture_sources.items():
        if source.exists():
            shutil.copytree(source,evidence/'fixtures'/name,dirs_exist_ok=True)
    write(evidence/'checks.json',checks)
    write(evidence/'gate.json',gate)
    print('W6_3_EVIDENCE='+str(evidence),flush=True)
    print('W6_3_PASS' if gate['passed'] else 'W6_3_INCOMPLETE',flush=True)
raise SystemExit(0 if gate['passed'] else 1)
