"""Real-device button audit. Uses SDK uitest, preserves existing records/settings.

Creates one uniquely named event and temporary classifications, verifies actual
feedback and persistence, removes test records and restores appearance settings.
"""
import importlib.util
import json
import sys
import time

spec = importlib.util.spec_from_file_location('ui', __file__.replace('test-buttons-ui.py', 'test-relations-ui.py'))
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
STAMP = str(int(time.time()))
EVENT = 'LG_BUTTONS_' + STAMP
PASSED = []
ORIGINAL_APPEARANCE = None
TEMP_TAGS = {}


def by_id(control_id, tree=None):
    return ui.find(tree or ui.layout(), node_id=control_id)


def tap_id(control_id):
    ui.click(by_id(control_id))


def selected(control_id, expected=True, tree=None):
    node = by_id(control_id, tree)
    assert (node.get('selected') == 'true') == expected, (control_id, node)
    assert node.get('text', '').startswith('✓ ') == expected or control_id.startswith('event-color-'), node


def checkpoint(name):
    tree = ui.layout()
    (ui.ROOT / 'evidence' / ('buttons-' + name + '.json')).write_text(json.dumps(tree, ensure_ascii=False), encoding='utf-8')
    PASSED.append(name)
    print('PASS ' + name, flush=True)


def text_exists(text):
    return any(n.get('text') == text for n in ui.nodes(ui.layout()))


def input_text(node, value):
    left, top, right, bottom = ui.bounds(node)
    ui.click(node)
    # SDK coordinate input inserts at the caret; explicitly replace existing text.
    ui.hdc('shell', 'uitest', 'uiInput', 'keyEvent', 2072, 2017)
    ui.hdc('shell', 'uitest', 'uiInput', 'keyEvent', 2055)
    quoted = "'" + value.replace("'", "'\"'\"'") + "'"
    ui.hdc('shell', 'uitest', 'uiInput', 'text', quoted)
    time.sleep(0.15)
    hide = [n for n in ui.nodes(ui.layout()) if n.get('id') == 'KeyHideKbd']
    if hide: ui.click(hide[0])


def back():
    tap_id('nav-back')


def scroll_down(amount=550):
    tree = ui.layout(); scroll = next(n for n in ui.nodes(tree) if n.get('type') == 'Scroll')
    left, top, right, bottom = ui.bounds(scroll)
    ui.hdc('shell', 'uitest', 'uiInput', 'swipe', right - 15, top + 120, right - 15, min(bottom - 60, top + 120 + amount), 1200)
    time.sleep(0.15)


def group(prefix):
    return [n for n in ui.nodes(ui.layout()) if n.get('type') == 'Button' and n.get('id', '').startswith(prefix)]


def title(expected):
    assert by_id('page-title')['text'] == expected


def profile_menu(label):
    for attempt in range(4):
        found = [n for n in ui.nodes(ui.layout()) if n.get('type') == 'Text' and n.get('text') == label and
                 ui.bounds(n)[3] - ui.bounds(n)[1] > 35]
        if len(found) == 1: ui.click(found[0]); return
        if attempt == 0: ui.scroll_bottom()
        else: scroll_down(950)
    raise AssertionError('Profile menu is not reachable: ' + label)


def tag_delete(label):
    tree = ui.layout()
    rows = []
    def visit(node):
        attrs = node.get('attributes', {})
        descendants = ui.nodes(node)
        if attrs.get('type') == 'Row' and any(n.get('text') == label for n in descendants):
            candidates = [n for n in descendants if n.get('type') == 'Button' and n.get('text') == '删除']
            if len(candidates) == 1: rows.append(candidates[0])
        for child in node.get('children', []): visit(child)
    visit(tree); assert rows, ('No delete control', label)
    ui.click(rows[-1])


def run_core():
    ui.restart(); title('Life Graph')
    filters = group('graph-relation-')
    if filters:
        key = filters[0]['id']; tap_id(key); selected(key); selected('choice-全部关系', False)
        tap_id(key); selected(key, False); selected('choice-全部关系')
        tap_id(key); tap_id('choice-全部关系'); selected(key, False)
    checkpoint('home-relation-filters')

    # Both zoom controls must change actual SVG label size, not just accept clicks.
    time.sleep(1)
    labels = [n for n in ui.nodes(ui.layout()) if n.get('type') == 'genericContainer' and n.get('text') == '我']
    if labels:
        width = ui.bounds(labels[0])[2] - ui.bounds(labels[0])[0]
        tap_id('graph-zoom-in'); time.sleep(.3)
        enlarged = ui.find(ui.layout(), text='我', kind='genericContainer')
        big = ui.bounds(enlarged)[2] - ui.bounds(enlarged)[0]
        assert big > width, (width, big)
        tap_id('graph-zoom-out'); time.sleep(.3)
        normal = ui.find(ui.layout(), text='我', kind='genericContainer')
        assert ui.bounds(normal)[2] - ui.bounds(normal)[0] < big
        checkpoint('graph-zoom-actions')

    tap_id('nav-search'); title('搜索生活')
    selected('choice-人物'); tap_id('choice-事件'); selected('choice-事件'); selected('choice-人物', False)
    tap_id('choice-人物'); selected('choice-人物'); back(); title('Life Graph')
    checkpoint('search-tabs-and-back')

    ui.click_text('＋ 记录'); title('记下一件事')
    input_text(by_id('event-title'), EVENT)
    ui.scroll_bottom(); scroll_down()
    participants = group('event-person-'); assert len(participants) >= 2
    default = next(n for n in participants if n.get('selected') == 'true')
    other = next(n for n in participants if n.get('selected') != 'true')
    person_key = other['id']; person_name = other['text']
    tap_id(person_key); selected(person_key); tap_id(person_key); selected(person_key, False)
    tap_id(person_key); tap_id(default['id']); selected(default['id'], False); selected(person_key)
    checkpoint('participant-toggle-feedback')
    branch = group('event-branch-')[0]; branch_key = branch['id']; branch_name = branch['text']
    tap_id(branch_key); selected(branch_key); tap_id(branch_key); selected(branch_key, False); tap_id(branch_key)
    checkpoint('branch-toggle-feedback')
    emotion = group('event-emotion-')[0]; emotion_key = emotion['id']; emotion_name = emotion['text']
    tap_id(emotion_key); selected(emotion_key); tap_id(emotion_key); selected(emotion_key, False); tap_id(emotion_key)
    checkpoint('emotion-toggle-feedback')
    ui.scroll_bottom()
    colors = group('event-color-'); color_key = colors[1]['id']
    tap_id(color_key); selected(color_key)
    assert sum(n.get('selected') == 'true' for n in group('event-color-')) == 1
    checkpoint('event-color-selection')
    ui.click_text('保存事件'); time.sleep(.3)
    ui.click_text('事件'); ui.click(ui.find(ui.layout(), text=EVENT, kind='Text')); title('生活记录')
    assert text_exists(person_name)
    assert any(branch_name in n.get('text', '') and emotion_name in n.get('text', '') for n in ui.nodes(ui.layout()))
    checkpoint('event-saved-selected-values')
    ui.click_text('编辑事件'); ui.scroll_bottom(); scroll_down()
    selected(person_key); selected(default['id'], False); selected(branch_key); selected(emotion_key)
    ui.scroll_bottom(); selected(color_key)
    checkpoint('event-editor-restores-selection')
    # Native picker cancellation should return control to a usable form.
    for control_id in ['event-pick-image', 'event-pick-audio']:
        tap_id(control_id); time.sleep(.5)
        tree = ui.layout()
        foreign = [n.get('bundleName') for n in ui.nodes(tree) if n.get('bundleName') and n.get('bundleName') != ui.BUNDLE]
        assert len(foreign) > 1 or any(n.get('type') in ['Dialog', 'UIExtensionComponent'] for n in ui.nodes(tree)), (control_id, foreign)
        ui.hdc('shell', 'uitest', 'uiInput', 'keyEvent', 'Back'); time.sleep(.3)
        title('记下一件事'); assert by_id(control_id).get('enabled') == 'true'
        checkpoint(control_id + '-cancel')
    ui.click_text('取消'); title('生活记录')
    ui.restart(); ui.click_text('事件'); ui.click(ui.find(ui.layout(), text=EVENT, kind='Text'))
    assert text_exists(person_name)
    ui.click_text('编辑事件'); ui.scroll_bottom(); scroll_down()
    selected(person_key); selected(branch_key); selected(emotion_key)
    ui.scroll_bottom(); selected(color_key); ui.click_text('取消')
    checkpoint('event-selection-survives-restart')
    ui.click_text('删除事件'); ui.click_text('取消', kind='Text'); title('生活记录')
    ui.click_text('删除事件'); ui.click_text('删除', kind='Text'); assert not text_exists(EVENT)
    checkpoint('event-delete-cancel-and-confirm')
    ui.restart(); ui.click_text('我的'); title('我的')
    assert not any(n.get('id') == 'nav-search' for n in ui.nodes(ui.layout()))
    checkpoint('bottom-tabs-title-and-controls')


def run_classifications():
    ui.restart(); ui.click_text('我的'); title('我的')
    for index, label in enumerate(['关系类型', '生活分支', '情绪标签']):
        profile_menu(label)
        name = 'LG_BTN_TAG_' + STAMP + '_' + str(index); renamed = name + '_R'
        TEMP_TAGS[label] = name
        input_text(ui.find(ui.layout(), kind='TextInput'), name); ui.click_text('添加')
        assert text_exists(name); ui.click(ui.find(ui.layout(), text=name, kind='Text'))
        ui.click_text('取消重命名')
        ui.click(ui.find(ui.layout(), text=name, kind='Text'))
        input_text(ui.find(ui.layout(), kind='TextInput'), renamed); ui.click_text('保存'); TEMP_TAGS[label] = renamed
        assert text_exists(renamed) and not text_exists(name)
        tag_delete(renamed); ui.click_text('取消', kind='Text'); assert text_exists(renamed)
        tag_delete(renamed); ui.click_text('删除', kind='Text'); assert not text_exists(renamed)
        TEMP_TAGS.pop(label); checkpoint('classification-' + str(index) + '-actions'); back()

def run_appearance():
    global ORIGINAL_APPEARANCE
    ui.restart(); ui.click_text('我的'); title('我的')
    profile_menu('生活分支图谱')
    graph_branches = group('graph-branch-')
    if graph_branches:
        key = graph_branches[0]['id']; tap_id(key); selected(key); selected('choice-全部分支', False)
        tap_id('choice-全部分支'); selected(key, False); selected('choice-全部分支')
    checkpoint('branch-graph-filters'); back()

    profile_menu('外观与主题')
    themes = ['森林', '海洋', '日落', '极简']; modes = ['跟随系统', '浅色', '深色']
    tree = ui.layout()
    original_theme = next(label for label in themes if by_id('choice-' + label, tree).get('selected') == 'true')
    original_mode = next(label for label in modes if by_id('choice-' + label, tree).get('selected') == 'true')
    ORIGINAL_APPEARANCE = (original_theme, original_mode)
    for label in themes:
        tap_id('choice-' + label); tree = ui.layout(); selected('choice-' + label, tree=tree)
        assert sum(by_id('choice-' + item, tree).get('selected') == 'true' for item in themes) == 1
    checkpoint('all-theme-buttons')
    for label in modes:
        tap_id('choice-' + label); tree = ui.layout(); selected('choice-' + label, tree=tree)
        assert sum(by_id('choice-' + item, tree).get('selected') == 'true' for item in modes) == 1
    checkpoint('all-appearance-buttons')
    color = '#' + format(int(STAMP) % 0xffffff, '06X')
    existing = [n.get('text', '') for n in ui.nodes(ui.layout())]
    assert color + ' ×' not in existing
    input_text(ui.find(ui.layout(), kind='TextInput'), color); ui.click_text('添加')
    assert text_exists(color + ' ×'); ui.click_text(color + ' ×'); assert not text_exists(color + ' ×')
    checkpoint('custom-event-color-add-and-remove')
    ui.restart(); ui.click_text('我的'); profile_menu('外观与主题')
    selected('choice-极简'); selected('choice-深色')
    tap_id('choice-' + original_theme); tap_id('choice-' + original_mode)
    selected('choice-' + original_theme); selected('choice-' + original_mode)
    ORIGINAL_APPEARANCE = None
    checkpoint('appearance-persisted-and-original-restored'); back()
def run_services():
    ui.restart(); ui.click_text('我的'); title('我的')
    profile_menu('AI 生活助手'); assert by_id('ai-send').get('enabled') == 'false'
    input_text(by_id('ai-question'), 'button check'); assert by_id('ai-send').get('enabled') == 'true'
    checkpoint('ai-send-empty-and-ready-states'); back()
    profile_menu('本地备份与恢复')
    ui.click_text('选择备份并恢复'); time.sleep(.5)
    ui.hdc('shell', 'uitest', 'uiInput', 'keyEvent', 'Back'); time.sleep(.3)
    title('本地备份与恢复'); ui.click_text('导出备份'); time.sleep(.5)
    ui.hdc('shell', 'uitest', 'uiInput', 'keyEvent', 'Back'); time.sleep(.3)
    title('本地备份与恢复'); assert text_exists('已取消导出')
    checkpoint('backup-picker-cancellation'); back()


def run_settings():
    run_classifications(); run_appearance(); run_services()


if __name__ == '__main__':
    phase = sys.argv[1] if len(sys.argv) > 1 else 'all'
    assert phase in ['all', 'core', 'settings', 'classifications', 'appearance', 'services']
    success = False
    try:
        if phase in ['all', 'core']: run_core()
        if phase in ['all', 'settings']: run_settings()
        if phase == 'classifications': run_classifications()
        if phase == 'appearance': run_appearance()
        if phase == 'services': run_services()
        success = True
    finally:
        if not success:
            try:
                tree = ui.layout()
                (ui.ROOT/'evidence/buttons-failure.json').write_text(json.dumps(tree,ensure_ascii=False),encoding='utf-8')
            except Exception: pass
            if ORIGINAL_APPEARANCE is not None:
                try:
                    ui.restart(); ui.click_text('我的'); profile_menu('外观与主题')
                    for label in ORIGINAL_APPEARANCE: tap_id('choice-' + label)
                    ORIGINAL_APPEARANCE = None
                except Exception as restore_error:
                    print('Original appearance restore pending: '+str(restore_error),flush=True)
        filename = 'buttons-ui-summary.json' if phase == 'all' else 'buttons-' + phase + '-ui-summary.json'
        (ui.ROOT/'evidence'/filename).write_text(json.dumps({
            'phase':phase, 'completed': success, 'passed': PASSED, 'testEvent': EVENT,
            'temporaryClassificationsRemaining': TEMP_TAGS, 'appearanceNeedsRestore': ORIGINAL_APPEARANCE,
            'scope': 'Real app UI and persistent data, SDK uitest; no mock provider requests'
        },ensure_ascii=False,indent=2),encoding='utf-8')
