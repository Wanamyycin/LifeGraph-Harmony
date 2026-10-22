"""Regression on the real Harmony app through the SDK's uitest CLI.

Creates a uniquely named person, exercises real Select/Slider widgets, checks
saved detail pages across a process restart, and removes only that test person.
Requires an already installed debug app and running DevEco emulator.
"""
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
HDC = pathlib.Path('F:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe')
TARGET = '127.0.0.1:5555'
BUNDLE = 'com.lifegraph.harmony.spike'
WORK = ROOT / '.test' / 'relation-ui'
WORK.mkdir(parents=True, exist_ok=True)
NAME = 'LG_REL_FIX_' + str(int(time.time()))
REPORT = []


def hdc(*args):
    result = subprocess.run([str(HDC), '-t', TARGET, *map(str, args)], capture_output=True, timeout=25)
    output = result.stdout.decode('utf-8', errors='replace') + result.stderr.decode('utf-8', errors='replace')
    if result.returncode or '[Fail]' in output or 'ErrorCode:' in output:
        raise RuntimeError(output)
    return output


def nodes(tree):
    result = [tree.get('attributes', {})]
    for child in tree.get('children', []):
        result.extend(nodes(child))
    return result


def layout():
    hdc('shell', 'uitest', 'dumpLayout', '-p', '/data/local/tmp/lifegraph-relations-check.json')
    hdc('file', 'recv', '/data/local/tmp/lifegraph-relations-check.json', str(WORK / 'layout.json'))
    return json.loads((WORK / 'layout.json').read_text(encoding='utf-8'))


def bounds(node):
    return list(map(int, re.findall(r'-?\d+', node['bounds'])))


def find(tree, *, text=None, node_id=None, kind=None):
    found = [n for n in nodes(tree) if
             (text is None or n.get('text') == text) and
             (node_id is None or n.get('id') == node_id) and
             (kind is None or n.get('type') == kind)]
    assert len(found) == 1, f'Expected one widget: {text=}, {node_id=}, {kind=}; found {len(found)}'
    return found[0]


def click(node):
    left, top, right, bottom = bounds(node)
    hdc('shell', 'uitest', 'uiInput', 'click', (left + right) // 2, (top + bottom) // 2)
    time.sleep(0.18)


def click_text(text, kind='Button'):
    click(find(layout(), text=text, kind=kind))


def scroll_bottom():
    tree = layout()
    scrolls = [n for n in nodes(tree) if n.get('type') == 'Scroll' and n.get('bundleName', BUNDLE) == BUNDLE]
    assert scrolls, 'Expected person editor Scroll'
    left, top, right, bottom = bounds(scrolls[0])
    hdc('shell', 'uitest', 'uiInput', 'swipe', right - 20, bottom - 80, right - 20, top + 150, 1400)
    time.sleep(0.18)


def row_ids(tree):
    return list(dict.fromkeys(n['id'][:-7] for n in nodes(tree) if n.get('id', '').endswith('-target') and n.get('type') == 'Select'))


def select(row, suffix, value=None, excluded=()):
    click(find(layout(), node_id=row + suffix, kind='Select'))
    menu = layout()
    options = [n for n in nodes(menu) if n.get('type') == 'Option' and n.get('text') not in excluded]
    option = next((n for n in options if value is None or n.get('text') == value), None)
    assert option is not None, f'No option {value=}; {[n.get("text") for n in options]}'
    chosen = option['text']; click(option); return chosen


def strength(row, value):
    tree = layout(); slider = find(tree, node_id=row + '-strength', kind='Slider')
    left, top, right, bottom = bounds(slider)
    # ArkUI slider reserves space for the thumb at each end.
    current = float(slider['text'])
    start = left + 35 + (right - left - 70) * (current - 1) / 4
    end = left + 35 + (right - left - 70) * (value - 1) / 4
    hdc('shell', 'uitest', 'uiInput', 'swipe', round(start), (top + bottom) // 2, round(end), (top + bottom) // 2, 800)
    time.sleep(0.18)
    tree = layout()
    assert find(tree, node_id=row + '-value')['text'] == '关系强度 ' + str(value)
    assert round(float(find(tree, node_id=row + '-strength')['text'])) == value
    return tree


def verify_row(tree, row, person, kind, value):
    assert find(tree, node_id=row + '-target')['text'] == person
    assert find(tree, node_id=row + '-kind')['text'] == kind
    assert find(tree, node_id=row + '-value')['text'] == '关系强度 ' + str(value)


def checkpoint(label, tree=None):
    tree = tree or layout()
    (ROOT / 'evidence' / ('relations-' + label + '.json')).write_text(json.dumps(tree, ensure_ascii=False), encoding='utf-8')
    REPORT.append(label)
    print('PASS ' + label, flush=True)


def restart():
    hdc('shell', 'aa', 'force-stop', BUNDLE)
    hdc('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', BUNDLE)
    time.sleep(0.6)


def open_test_detail():
    click_text('人物')
    click(find(layout(), text=NAME, kind='Text'))


def verify_detail(expected):
    texts = [n.get('text') for n in nodes(layout())]
    for person, kind, value in expected:
        assert f'{person} · {kind} · 强度 {value}' in texts, (expected, texts)
    assert not any(text and text.startswith('我 · ') for text in texts), texts


def delete_test_person():
    click_text('删除人物')
    click_text('彻底删除', kind='Text')
    assert NAME not in [n.get('text') for n in nodes(layout())]


def run():
    restart(); click_text('人物'); click_text('＋')
    field = find(layout(), kind='TextInput'); left, top, right, bottom = bounds(field)
    hdc('shell', 'uitest', 'uiInput', 'inputText', (left + right) // 2, (top + bottom) // 2, NAME)
    time.sleep(0.3)
    tree = layout(); hide = [n for n in nodes(tree) if n.get('id') == 'KeyHideKbd']
    if hide: click(hide[0])
    click_text('＋ 添加关系'); scroll_bottom()
    first = row_ids(layout())[0]
    person_b = select(first, '-target', excluded=('我', 'LG_REL_BEFORE'))
    kind_b = select(first, '-kind', excluded=('朋友',))
    verify_row(strength(first, 5), first, person_b, kind_b, 5)
    verify_row(strength(first, 1), first, person_b, kind_b, 1)
    verify_row(strength(first, 5), first, person_b, kind_b, 5)
    checkpoint('live-strength-and-selection')

    click_text('＋ 添加关系'); scroll_bottom()
    second = next(row for row in row_ids(layout()) if row != first)
    person_c = select(second, '-target', excluded=('我', 'LG_REL_BEFORE', person_b))
    kind_c = select(second, '-kind', excluded=('朋友', kind_b))
    verify_row(strength(second, 2), second, person_c, kind_c, 2)
    verify_row(layout(), first, person_b, kind_b, 5)
    checkpoint('two-independent-rows')
    click_text('保存人物')
    click(find(layout(), text=NAME, kind='Text'))
    verify_detail([(person_b, kind_b, 5), (person_c, kind_c, 2)])
    checkpoint('new-person-saved-other-people')

    restart(); open_test_detail()
    verify_detail([(person_b, kind_b, 5), (person_c, kind_c, 2)])
    checkpoint('relations-survive-process-restart')
    click_text('编辑人物与关系'); scroll_bottom()
    first, second = row_ids(layout())
    click(find(layout(), node_id=first + '-remove'))
    tree = layout(); assert row_ids(tree) == [second]
    kind_c = select(second, '-kind', excluded=(kind_c,))
    verify_row(strength(second, 4), second, person_c, kind_c, 4)
    checkpoint('remove-first-preserves-second')

    click_text('＋ 添加关系'); scroll_bottom()
    added = next(row for row in row_ids(layout()) if row != second)
    assert added not in (first, second)
    select(added, '-target', person_b); strength(added, 1)
    verify_row(layout(), second, person_c, kind_c, 4)
    click(find(layout(), node_id=added + '-remove'))
    click_text('保存人物')
    verify_detail([(person_c, kind_c, 4)])
    texts = [n.get('text', '') for n in nodes(layout())]
    assert not any(text.startswith(person_b + ' · ') for text in texts)
    checkpoint('removed-rows-not-saved')
    click_text('编辑人物与关系'); scroll_bottom()
    only = row_ids(layout()); assert len(only) == 1
    verify_row(layout(), only[0], person_c, kind_c, 4)
    click_text('取消')
    checkpoint('reopened-editor-restores-values')
    delete_test_person()
    checkpoint('temporary-record-cleaned')


if __name__ == '__main__':
    try:
        run()
    finally:
        if len(REPORT) != 8:
            try:
                restart(); click_text('人物')
                existing = [n for n in nodes(layout()) if n.get('type') == 'Text' and n.get('text') == NAME]
                if len(existing) == 1:
                    click(existing[0]); delete_test_person()
                print('Failure cleanup completed for ' + NAME, flush=True)
            except Exception as cleanup_error:
                print('Cleanup pending for ' + NAME + ': ' + str(cleanup_error), flush=True)
        (ROOT / 'evidence' / 'relations-ui-summary.json').write_text(json.dumps({
            'testPerson': NAME, 'passed': REPORT, 'completed': len(REPORT) == 8,
            'scope': 'Real app UI through HarmonyOS SDK uitest; no mock database'
        }, ensure_ascii=False, indent=2), encoding='utf-8')
