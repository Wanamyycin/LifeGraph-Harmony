"""Additional real UI checks: date, recording response, filters, detail links."""
import importlib.util
import json
import time

spec = importlib.util.spec_from_file_location('buttons', __file__.replace('test-button-extras-ui.py', 'test-buttons-ui.py'))
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
ui = b.ui
NAME = 'LG_BTN_EXTRA_' + str(int(time.time()))
PASSED = []


def checkpoint(label):
    tree = ui.layout()
    (ui.ROOT/'evidence'/('buttons-extra-'+label+'.json')).write_text(json.dumps(tree,ensure_ascii=False),encoding='utf-8')
    PASSED.append(label); print('PASS '+label,flush=True)


def run():
    ui.restart(); ui.click_text('＋ 记录')
    b.input_text(b.by_id('event-title'), NAME)
    b.tap_id('event-date'); tree = ui.layout()
    assert any('DatePicker' in n.get('type','') for n in ui.nodes(tree)), 'Native date picker did not open'
    # System dialog exposes its cancel label separately from the page button.
    labels = [n for n in ui.nodes(tree) if n.get('text') == '取消']
    inner = [n for n in labels if n.get('type') == 'Text']
    if inner: ui.click(inner[-1])
    else:
        dialogs = [n for n in labels if n.get('type') == 'Button']
        assert dialogs; ui.click(dialogs[-1])
    b.title('记下一件事'); checkpoint('date-picker-open-cancel')
    ui.scroll_bottom(); b.scroll_down()
    choices = b.group('event-person-')
    other = next(n for n in choices if n.get('selected') != 'true')
    person = other['text']; b.tap_id(other['id']); b.selected(other['id'])
    branch = b.group('event-branch-')[0]; branch_id = branch['id'].replace('event-branch-', '')
    b.tap_id(branch['id']); ui.scroll_bottom()
    ui.click_text('录音'); time.sleep(.4)
    tree = ui.layout()
    for _ in range(5):
        texts = [n.get('text', '') for n in ui.nodes(tree)]
        if any(text.startswith('停止 ') or text in ['不允许', '拒绝'] or '麦克风权限' in text or '不支持录音' in text or '无法开始录音' in text for text in texts): break
        time.sleep(.2); tree = ui.layout()
    stop = [n for n in ui.nodes(tree) if n.get('type') == 'Button' and n.get('text','').startswith('停止 ')]
    if stop:
        ui.click(stop[0]); time.sleep(.4); ui.scroll_bottom()
        assert b.text_exists('播放'), 'Stopped recording did not update attachment list'
        checkpoint('record-stop-updates-attachment-list')
        ui.click_text('移除附件')
        assert not b.text_exists('播放') and not b.text_exists('移除附件')
        checkpoint('attachment-remove-refreshes-list')
    else:
        deny = [n for n in ui.nodes(tree) if n.get('text') in ['不允许', '拒绝']]
        if deny: ui.click(deny[-1]); tree = ui.layout()
        messages = [n.get('text','') for n in ui.nodes(tree)]
        assert any('麦克风权限' in text or '不支持录音' in text or '无法开始录音' in text for text in messages), messages
        assert ui.find(tree,text='录音',kind='Button').get('enabled') == 'true'
        checkpoint('record-permission-or-capability-feedback')
    ui.click_text('保存事件'); ui.click_text('事件')
    key = 'event-filter-' + branch_id
    b.tap_id(key); b.selected(key); assert b.text_exists(NAME)
    others = [n for n in b.group('event-filter-') if n['id'] != key]
    assert others; b.tap_id(others[0]['id']); b.selected(others[0]['id']); assert not b.text_exists(NAME)
    b.tap_id('choice-全部'); b.selected('choice-全部'); assert b.text_exists(NAME)
    checkpoint('event-list-filters-and-reset')
    ui.click(ui.find(ui.layout(),text=NAME,kind='Text'))
    b.tap_id('choice-'+person); b.title('人物详情'); b.back(); b.title('生活记录')
    checkpoint('event-participant-detail-navigation')
    ui.click_text('删除事件'); ui.click_text('删除',kind='Text'); assert not b.text_exists(NAME)
    checkpoint('extra-event-cleaned')


if __name__ == '__main__':
    success = False
    try:
        run(); success = True
    finally:
        tree = ui.layout()
        (ui.ROOT/'evidence/buttons-extra-final.json').write_text(json.dumps(tree,ensure_ascii=False),encoding='utf-8')
        (ui.ROOT/'evidence/buttons-extra-summary.json').write_text(json.dumps({
            'completed':success,'passed':PASSED,'testEvent':NAME,
            'scope':'Real native UI; recording permission is never granted by the script'
        },ensure_ascii=False,indent=2),encoding='utf-8')
