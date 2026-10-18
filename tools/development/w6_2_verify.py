"""W6.2 isolated creator workflow, Windows failure tests and full W6.1 regression.

The source projection matches W6.1. Never import the live checkout. The launcher
also imports a disposable project, but selects the real canonical root explicitly.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
parser = argparse.ArgumentParser()
parser.add_argument('--runner', required=True, type=Path)
parser.add_argument('--focused-only', action='store_true')
parser.add_argument('--launch', action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
runner = args.runner
graphical = runner.with_name('godot.windows.editor.x86_64.exe')
evidence = repo / '.verification/wave6/w6_2' / ('run-' + time.strftime('%Y%m%dT%H%M%S', time.gmtime()) + '-' + str(time.time_ns() % 1000000000))
evidence.mkdir(parents=True)
work = Path(tempfile.mkdtemp(prefix='lf62-'))
project = work / 'project'
checks = []
processes = {}
gate = dict(passed=False, certified=False, focused_only=args.focused_only,
            starting_commit=subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
            manual_acceptance='OWNER FORGE ACCEPTANCE REQUIRED', temp_project=str(project))


def write(path, value):
    path.write_text(json.dumps(value, indent=2), encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def check(value, label):
    checks.append(dict(label=label, passed=bool(value)))
    if not value:
        raise RuntimeError(label)


def git(*arguments):
    return subprocess.check_output(['git', '-C', str(repo), *arguments])


def inventory():
    tracked = set(git('ls-files').decode().splitlines())
    paths = git('ls-files', '--cached', '--others', '--exclude-standard', '--', 'project.godot', 'src', 'content', 'scenes', 'tests', 'tools', 'addons', 'docs', 'AGENTS.md').decode().splitlines()
    return [p for p in paths if (not p.endswith('.gd.uid') or p in tracked) and '/__pycache__/' not in p and not p.endswith('.pyc')]


def start(name, arguments, rendered=False, profile='test'):
    env = os.environ.copy()
    for key in ['APPDATA', 'LOCALAPPDATA']:
        env[key] = str(work / (profile + '-' + key))
        Path(env[key]).mkdir(exist_ok=True)
    env['TEMP'] = env['TMP'] = str(work)
    env.pop('LEYFORGE_FORGE_ROOT', None)
    if args.launch:
        env['LEYFORGE_FORGE_ROOT'] = str(repo)
        for key in ['APPDATA', 'LOCALAPPDATA']:
            env[key] = str(Path(os.environ[key]) / 'LeyforgeForge')
            Path(env[key]).mkdir(exist_ok=True)
    log = (evidence / (name + '.log')).open('w', encoding='utf-8')
    command = [str(graphical if rendered else runner), '--log-file', str(evidence / (name + '-engine.log')), *map(str, arguments)]
    proc = subprocess.Popen(command, env=env, cwd=project, stdout=log, stderr=subprocess.STDOUT)
    processes[name] = proc, log
    return proc


def log_text(name):
    return '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in [evidence / (name + '.log'), evidence / (name + '-engine.log')] if p.exists())


def finish(name, timeout=240):
    proc, log = processes[name]
    code = proc.wait(timeout=timeout)
    log.flush()
    text = log_text(name)
    check(code == 0 and not re.search(r'(?m)^\s*(SCRIPT ERROR|ERROR:)', text), name + ' clean exit: ' + text[-2400:] if code or 'SCRIPT ERROR' in text else name + ' clean exit')


def read(name='creator'):
    try:
        return json.loads((evidence / (name + '.json')).read_text(encoding='utf-8-sig'))
    except (ValueError, OSError):
        return {}


def wait(condition, name='creator', timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        report = read(name)
        if report and condition(report):
            return report
        proc = processes[name][0]
        if proc.poll() is not None or 'SCRIPT ERROR:' in log_text(name):
            raise RuntimeError(name + ' failed before report: ' + log_text(name)[-4000:])
        time.sleep(.1)
    raise RuntimeError(name + ' report timeout: ' + str(read(name))[-1500:])


def command(op, **values):
    before = read().get('processed', 0)
    pending = evidence / 'creator.command.pending'
    write(pending, dict(op=op, **values))
    pending.replace(evidence / 'creator.command.json')
    report = wait(lambda r: r.get('processed', 0) > before)
    with (evidence / 'input-events.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps(dict(input=dict(op=op, **values), report={k: v for k, v in report.items() if k not in ['widgets', 'tabs', 'validation']})) + '\n')
    return report


def widget(text=None, kind=None, suffix=None):
    matches = [w for w in read()['widgets'] if (text is None or w['text'] == text) and (kind is None or w['class'] == kind) and (suffix is None or w['path'].endswith(suffix))]
    check(len(matches) == 1, 'unique visible input target ' + str((text, kind, suffix)))
    return matches[0]


def click_widget(w, fx=.5, fy=.5):
    x, y, width, height = w['rect']
    size = read().get('window_size', [1920, 1080])
    check(0 <= x and 0 <= y and x + width <= size[0] + 1 and y + height <= size[1] + 1, 'pointer target within creator window: ' + str(w['text']))
    return command('click', x=x + width * fx, y=y + height * fy)


def click_text(text):
    return click_widget(widget(text=text, kind='Button'))


def page(index):
    # TabBar rectangles are read from the real UI. Labels have stable measured widths.
    widths = read().get('tabs', [])
    if widths:
        rect = widths[index]
        return command('click', x=rect[0] + rect[2] / 2, y=rect[1] + rect[3] / 2)
    raise RuntimeError('tab geometry unavailable')


def name_edit(value):
    click_widget(widget(kind='LineEdit', text=read()['stone']['display_name']))
    command('key', code=65, ctrl=True)
    command('text', text=value)
    return click_text('Apply name')


def colour_edit(value):
    click_widget(widget(kind='ColorPickerButton'))
    fields = [w for w in read()['widgets'] if w['class'] == 'LineEdit' and 'PopupPanel' in w['path']]
    check(len(fields) == 1, 'native compact colour picker hex field')
    click_widget(fields[0])
    command('key', code=65, ctrl=True)
    command('text', text=value)
    command('key', code=4194309)
    return command('key', code=4194305)


def select_content(identity):
    search = [w for w in read()['widgets'] if w.get('role') == 'search']
    check(len(search) == 1, 'browser search target')
    click_widget(search[0])
    command('key', code=65, ctrl=True)
    command('text', text=identity)
    browser = widget(kind='ItemList')
    x, y, width, height = browser['rect']
    command('click', x=x + 60, y=y + 14)
    check(read()['selected'] == identity, 'canonical selection ' + identity)


def stop(name='creator'):
    (evidence / (name + '.stop')).write_text('stop')
    finish(name)


try:
    check(digest(runner) == '06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A', 'approved console runner')
    check(digest(graphical) == '87D0A6077ABE38B905F973B23D9F27FD4F3B7A8DB2309DFD6807FAD7DFF582C8', 'approved graphical runner')
    write(evidence / 'runner_manifest.json', dict(console=digest(runner), graphical=digest(graphical)))
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
    write(evidence / 'source_manifest.json', manifest)
    write(evidence / 'working_source_manifest.json', raw)
    write(evidence / 'protected_inventory.json', {p: digest(repo / p) for p in git('ls-files', '--modified', '--others', '--exclude-standard').decode().splitlines() if (repo / p).is_file()})
    start('import', ['--headless', '--editor', '--path', project, '--quit'])
    finish('import')
    if args.launch:
        print('FORGE_EVIDENCE=' + str(evidence), flush=True)
        start('forge', ['--path', project, 'res://tools/forge/forge.tscn'], True)
        finish('forge', timeout=None)
        gate['launcher_success'] = True
    else:
        start('focused', ['--headless', '--path', project, '--script', 'res://tests/forge/w6_2_focused.gd', '--', evidence / 'focused.json'])
        finish('focused')
        focused = read('focused')
        check(focused.get('passed') and focused.get('original_sha256') == focused.get('final_sha256'), 'focused data/failure tests conserve isolated content')
        start('creator', ['--path', project, '--script', 'res://tests/forge/w6_2_process.gd', '--', evidence / 'creator'], True, 'creator')
        wait(lambda r: r.get('ready') and r.get('mesh'))
        page(1)
        name_edit('Forge UI stone')
        check(read()['stone']['display_name'] == 'Forge UI stone' and read()['dirty'], 'normal pointer/keyboard draft editing')
        click_text('Undo')
        check(read()['stone']['display_name'] == focused['stone']['display_name'], 'UI undo')
        click_text('Redo')
        check(read()['stone']['display_name'] == 'Forge UI stone', 'UI redo')
        before_commands = read()['undo']
        colour_edit('2277bbff')
        check(read()['stone']['color'] == '#2277BBFF' and read()['undo'] == before_commands + 1, 'native colour gesture is one undo command')
        colour_edit('aa6633ff')
        check(read()['stone']['color'] == '#AA6633FF', 'second native colour edit')
        click_text('Undo')
        check(read()['stone']['color'] == '#2277BBFF', 'colour UI undo')
        click_text('Redo')
        check(read()['stone']['color'] == '#AA6633FF', 'colour UI redo')
        click_text('Undo'); name_edit('Forge UI stone final')
        check(read()['redo'] == 0, 'UI edit after undo clears redo')
        for identity in ['leyforge:grass', 'leyforge:air', 'leyforge:stone'] * 3:
            select_content(identity)
            check(read()['preview_identity'] == identity and read()['preview_nodes'] <= 5, 'selection refresh releases previous preview resource')
        check(read()['mesh_color'] == '2277bbff', 'runtime factory mesh uses validated draft colour')
        page(3)
        surface = widget(kind='SubViewportContainer')
        x, y, width, height = surface['rect']
        x += width / 2; y += height / 2
        before = read()
        command('drag', x=x, y=y, dx=90, dy=35)
        check(read()['yaw'] != before['yaw'] and read()['undo'] == before['undo'], 'viewport orbit independent of history')
        command('drag', x=x, y=y, dx=30, dy=20, shift=True)
        check(read()['focus'] != before['focus'], 'viewport pan')
        command('click', x=x, y=y, button=4)
        check(read()['distance'] < before['distance'], 'bounded viewport wheel zoom')
        command('key', code=70)
        check(read()['focus'] == [.5, .5, .5] and abs(read()['distance'] - 3.4) < .001, 'focused Frame Selection')
        for width, height in [(1920, 1080), (1280, 720), (960, 540)]:
            command('resize', width=width, height=height)
            command('capture', path=str(evidence / ('preview-%dx%d.png' % (width, height))))
            for w in read()['widgets']:
                rx, ry, rw, rh = w['rect']
                check(rx >= 0 and ry >= 0 and rx + rw <= width + 1 and ry + rh <= height + 1, 'reachable layout %dx%d %s' % (width, height, w['class']))
            page(1)
            command('capture', path=str(evidence / ('editor-%dx%d.png' % (width, height))))
            page(3)
        page(1)
        before = read()['yaw']
        click_widget(widget(kind='LineEdit', text='Forge UI stone final'))
        command('key', code=70)
        check(read()['yaw'] == before, 'text focus does not move camera')
        command('key', code=65, ctrl=True)
        command('text', text='Forge UI stone final')
        click_text('Save draft')
        snapshot = read()['stone']
        stop()
        (evidence / 'creator.stop').unlink()
        start('creator-restart', ['--path', project, '--script', 'res://tests/forge/w6_2_process.gd', '--', evidence / 'creator'], True, 'creator')
        # Commands continue targeting the same proof endpoint, with a new OS process.
        processes['creator'] = processes['creator-restart']
        wait(lambda r: r.get('pid') == processes['creator'][0].pid and r.get('ready'))
        check(read()['stone'] == snapshot and read()['dirty'], 'graphical close/reopen retains draft')
        page(2)
        click_text('Validate draft')
        click_text('Review Publish…')
        command('capture', path=str(evidence / 'publish-confirmation.png'))
        click_text('Publish')
        check(read()['last_result']['success'] and not read()['dirty'], 'explicit UI publication in disposable content')
        canonical = project / 'content/blocks/wave_1_blocks.json'
        shutil.copy2(canonical, evidence / 'published-blocks.json')
        check(json.loads(canonical.read_text(encoding='utf-8'))['blocks'][3]['display_name'] == 'Forge UI stone final', 'published candidate is runtime canonical input')
        page(1)
        name_edit('Conflict candidate')
        external = canonical.read_bytes() + b'\n'
        canonical.write_bytes(external)
        page(2); click_text('Validate draft'); click_text('Review Publish…'); click_text('Publish')
        check(not read()['last_result']['success'] and canonical.read_bytes() == external and read()['dirty'], 'UI conflict preserves external canonical and draft')
        command('capture', path=str(evidence / 'conflict.png'))
        stop()
        gate['focused_graphical'] = True
        if not args.focused_only:
            prior = set((repo / '.verification/wave6/w6_1').glob('run-*'))
            with (evidence / 'w6_1-full.log').open('w', encoding='utf-8') as log:
                result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(repo / 'tools/development/verify_wave_6_part_1.ps1'), '-GodotExecutable', str(runner)], cwd=repo, stdout=log, stderr=subprocess.STDOUT)
            created = set((repo / '.verification/wave6/w6_1').glob('run-*')) - prior
            check(len(created) == 1, 'one fresh W6.1 full receipt')
            nested = created.pop(); gate['w6_1_evidence'] = str(nested)
            receipt = json.loads((nested / 'gate.json').read_text())
            check(result.returncode == 0 and all(receipt.get(k) for k in ['passed', 'certified', 'snapshot_matches_source', 'full_regressions']), 'complete W6.1 and unchanged W5.9 660-second/full Waves 0-5 chain')
            check(json.loads((nested / 'source_manifest.json').read_text()) == manifest, 'W6.2 and full W6.1 source inventories match')
            gate['full_regressions'] = True
        check(inventory() == paths and all(digest(repo / p) == h for p, h in raw.items()), 'final candidate source unchanged throughout gate')
        gate.update(passed=True, certified=not args.focused_only, snapshot_matches_source=True)
except Exception as error:
    gate['failure'] = str(error)
    print('W6_2_FAILURE: ' + str(error), flush=True)
finally:
    for name, (proc, log) in processes.items():
        if proc.poll() is None:
            try:
                proc.terminate(); proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
        log.close()
    for profile in ['test-APPDATA', 'creator-APPDATA']:
        authoring = work / profile / 'Godot/app_userdata/Leyforge/forge'
        if authoring.exists():
            destination = evidence / 'fixtures' / profile
            destination.mkdir(parents=True, exist_ok=True)
            for artifact in ['session.json', 'session.json.tmp', 'recovery', 'exports']:
                source = authoring / artifact
                if source.is_dir():
                    shutil.copytree(source, destination / artifact, dirs_exist_ok=True)
                elif source.is_file():
                    shutil.copy2(source, destination / artifact)
    write(evidence / 'checks.json', checks)
    write(evidence / 'gate.json', gate)
    print('W6_2_EVIDENCE=' + str(evidence), flush=True)
    print('W6_2_PASS' if gate['passed'] else 'W6_2_INCOMPLETE', flush=True)
raise SystemExit(0 if gate['passed'] or gate.get('launcher_success') else 1)
