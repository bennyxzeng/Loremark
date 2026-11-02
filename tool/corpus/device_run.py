"""Drive real books through the app on the emulator and check what the user
would see: page ends reported, Contents list and jumps, and search.

device_run.py <corpus dir> <out.jsonl> <book id> [<book id> ...]
A book id is a folder under raw/ or variants/. Needs `adb` and a debug build of
the app installed on one running emulator. Untrusted EPUBs are only read as zip
data here and pushed to the emulator.
"""
import html
import json
import os
import posixpath
import re
import subprocess
import sys
import time
import zipfile
import xml.etree.ElementTree as ET

ADB = os.environ.get('ADB', 'adb')
APP = 'com.example.loremark'
FILES = f'/data/user/0/{APP}/files'
CORPUS, OUT = sys.argv[1], sys.argv[2]
IDS = sys.argv[3:]
PAGES = 24
NEXT = ('1018', '2095')


def adb(*args, input_bytes=None, timeout=60):
    try:
        return subprocess.run([ADB, *args], capture_output=True, timeout=timeout,
                              input=input_bytes).stdout.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired:
        return ''


def shell(command, timeout=60):
    return adb('shell', command, timeout=timeout)


def ui():
    for _ in range(3):
        shell('uiautomator dump /sdcard/ui.xml')
        xml = adb('exec-out', 'cat', '/sdcard/ui.xml')
        start = xml.find('<?xml')
        if start >= 0:
            try:
                return ET.fromstring(xml[start:].strip())
            except ET.ParseError:
                pass
        time.sleep(1)
    return None


def nodes(root):
    if root is None:
        return
    for n in root.iter('node'):
        b = re.findall(r'\d+', n.get('bounds', ''))
        if len(b) != 4:
            continue
        x1, y1, x2, y2 = map(int, b)
        yield {'text': n.get('text', ''), 'desc': n.get('content-desc', ''),
               'cls': n.get('class', ''), 'c': ((x1 + x2) // 2, (y1 + y2) // 2)}


def tap(x, y):
    shell(f'input tap {x} {y}')


def tap_label(label, exact=False):
    for n in nodes(ui()):
        for field in (n['text'], n['desc']):
            if (field == label) if exact else (label.lower() in field.lower()):
                tap(*n['c'])
                return True
    return False


def wait_for(label, seconds=40):
    end = time.time() + seconds
    while time.time() < end:
        if any(n['desc'] == label or n['text'] == label for n in nodes(ui())):
            return True
        time.sleep(1.5)
    return False


def texts():
    return [n for n in nodes(ui()) if n['text'] or n['desc']]


def chapter_bar():
    for n in texts():
        if n['c'][1] in range(340, 400) and n['c'][0] < 800 and n['cls'].endswith('View'):
            return n['text'] or n['desc']
    return None


def percent():
    for n in texts():
        m = re.fullmatch(r'(\d+)\s?%', n['text'] or n['desc'])
        if m:
            return int(m.group(1))
    return None


# --- library helpers -------------------------------------------------------

def read_library():
    raw = adb('exec-out', 'run-as', APP, 'cat', 'files/library/library.json')
    return json.loads(raw)


def write_library(data):
    body = json.dumps(data, separators=(',', ':')).encode('utf-8')
    adb('shell', f"run-as {APP} sh -c 'cat > files/library/library.json'", input_bytes=body)


def add_book(bid, path, title):
    key = 'corpus' + re.sub(r'[^0-9a-z]', '', bid.lower())
    adb('push', path, '/data/local/tmp/lm.epub', timeout=300)
    shell(f"run-as {APP} sh -c 'cp /data/local/tmp/lm.epub files/library/books/{key}.epub'")
    library = read_library()
    library['books'] = [b for b in library['books'] if b['id'] != key]
    library['books'].append({
        'id': key, 'title': title, 'author': None,
        'epub_path': f'{FILES}/library/books/{key}.epub', 'cover_path': None,
        'imported_at': '2026-11-01T00:00:00Z',
    })
    library['last_opened_id'] = key
    write_library(library)
    shell(f"run-as {APP} rm -f files/library/reading_state/{key}.json")
    return key


# --- ground truth from the book itself (crude, for choosing words) ---------

def crude_words(path):
    z = zipfile.ZipFile(path)
    container = z.read('META-INF/container.xml').decode('utf-8', 'replace')
    opf = re.search(r'full-path="([^"]+)"', container).group(1)
    base = posixpath.dirname(opf)
    text = z.read(opf).decode('utf-8', 'replace')
    manifest = dict(re.findall(r'<item\b[^>]*?\bid="([^"]+)"[^>]*?\bhref="([^"]+)"', text))
    manifest.update({k: v for v, k in re.findall(r'<item\b[^>]*?\bhref="([^"]+)"[^>]*?\bid="([^"]+)"', text)})
    refs = re.findall(r'<itemref\b[^>]*idref="([^"]+)"', text)
    out = []
    for r in refs:
        href = manifest.get(r)
        if not href:
            continue
        name = posixpath.normpath(posixpath.join(base, href.split('#')[0]))
        try:
            data = z.read(name).decode('utf-8', 'replace')
        except KeyError:
            continue
        body = re.sub(r'<(script|style)\b.*?</\1>', ' ', data, flags=re.S | re.I)
        out.append(html.unescape(re.sub(r'<[^>]+>', ' ', body)))
    return ' '.join(out)


def pick_words(path):
    text = crude_words(path)
    words = re.findall(r"[a-z]{7,}", text.lower())
    counts = {}
    # Search stems words and treats the last word as a prefix, so a word only
    # counts as rare if no other word starts the same way.
    for w in words:
        counts[w[:5]] = counts.get(w[:5], 0) + 1
    n = len(words)
    if n < 2000:
        return None

    def region(lo, hi):
        for i in range(int(n * lo), int(n * hi)):
            if counts[words[i][:5]] == 1:
                return words[i]
        return None
    return {'mid': region(0.20, 0.30), 'late': region(0.88, 0.95)}



SHEET_SKIP = {'Dismiss', 'Scrim', 'CONTENTS'}


def sheet_rows():
    """Entry labels showing in the Contents sheet, top to bottom, and whether
    the sheet says the book has no table of contents."""
    rows, note = [], False
    for n in sorted(texts(), key=lambda n: n['c'][1]):
        label = n['text'] or n['desc']
        if n['c'][1] < 1000 or label in SHEET_SKIP:
            continue
        if label.startswith('This book has no table of contents'):
            note = True
            continue
        rows.append(label)
    return rows, note


def collect_entries(limit=60):
    seen, note = [], False
    for _ in range(limit):
        rows, has_note = sheet_rows()
        note = note or has_note
        fresh = [r for r in rows if r not in seen]
        if not fresh and seen:
            break
        seen.extend(fresh)
        shell('input swipe 540 2100 540 1300 300')
        time.sleep(0.6)
    return seen, note


def tap_entry(label, limit=60):
    for _ in range(limit):
        if tap_label(label, exact=True):
            return True
        shell('input swipe 540 1300 540 2100 300')
        time.sleep(0.6)
    return False

# --- one book ------------------------------------------------------------

def find_path(bid):
    for group in ('raw', 'variants'):
        p = f'{CORPUS}/{group}/{bid}/book.epub'
        try:
            open(p, 'rb').close()
            return p
        except OSError:
            continue
    raise SystemExit(f'no such book {bid}')


def page_ends():
    log = adb('logcat', '-d', timeout=120)
    rows = []
    for line in log.splitlines():
        m = re.search(r'LOREMARK_PAGE_TEXT (\{.*\})', line)
        if m:
            try:
                rows.append(json.loads(m.group(1)))
            except json.JSONDecodeError:
                pass
    return rows


def search(word):
    if not tap_label('Search', exact=True):
        return None
    time.sleep(3)
    shell(f'input text {word}')
    # The first search of a book builds its index, which takes many seconds
    # for a long one, so wait for an answer instead of a fixed time.
    whole = re.compile(r'(?<![a-z])' + re.escape(word) + r'(?![a-z])')
    found = empty = False
    waited = 0
    while waited < 120:
        time.sleep(4)
        waited += 4
        seen = [n for n in texts() if not n['cls'].endswith('EditText')]
        # The box also matches longer words that start with the query, so
        # only a whole word counts.
        found = any(whole.search((n['text'] or n['desc']).lower()) for n in seen)
        empty = any("No matches" in (n['text'] or n['desc']) for n in seen)
        if found or empty:
            break
    shell('input keyevent 4')
    time.sleep(1)
    shell('input keyevent 4')
    time.sleep(1)
    return {'found': found, 'empty': empty, 'waited': waited}


def no_answer(r, word, problems):
    if r and not (r['found'] or r['empty']):
        problems.append(f"search for '{word}' gave no answer in {r['waited']}s")


def run_book(bid):
    path = find_path(bid)
    result = {'id': bid, 'problems': []}
    problems = result['problems']
    words = pick_words(path)
    result['words'] = words
    key = add_book(bid, path, f'corpus {bid}')
    shell(f'am force-stop {APP}')
    adb('logcat', '-c')
    shell(f'monkey -p {APP} -c android.intent.category.LAUNCHER 1')
    time.sleep(6)
    opened = wait_for('Contents', 45)
    result['opened'] = opened
    if not opened:
        # No Contents button: a short book, or one that failed to open.
        result['screen'] = [n['text'] or n['desc'] for n in texts()][:12]
    start_percent = percent()
    result['startPercent'] = start_percent

    if words and words['mid']:
        r = search(words['mid'])
        result['searchMidAtStart'] = r
        no_answer(r, words['mid'], problems)
        if r and r['found']:
            problems.append(f"'{words['mid']}' (20-30% in) found at the start of the book")

    for _ in range(PAGES):
        tap(*NEXT)
        time.sleep(0.8)
    time.sleep(2)
    result['percentAfterPaging'] = percent()
    ends = page_ends()
    result['pageEndLogs'] = len(ends)
    result['pageEndRejected'] = sum(1 for e in ends if e.get('textProgression') is None)
    last = {}
    inversions = 0
    for e in ends:
        p = e.get('textProgression')
        if p is None:
            continue
        s = e['section']
        if s in last and p < last[s] - 1e-9:
            inversions += 1
        last[s] = p
    result['pageEndInversions'] = inversions
    if inversions:
        problems.append(f'{inversions} page ends moved backwards while paging forward')
    if ends and result['pageEndRejected']:
        problems.append(f"{result['pageEndRejected']} page ends were rejected (tail or position)")

    # Contents.
    if opened and tap_label('Contents', exact=False):
        time.sleep(2)
        rows, note = collect_entries()
        result['contentsEntries'] = len(rows)
        result['contentsNote'] = note
        result['contentsFirst'] = rows[:3]
        if rows:
            index = len(rows) // 2
            target = rows[index]
            if tap_entry(target):
                time.sleep(5)
                result['jumpTarget'] = target
                result['barAfterJump'] = chapter_bar()
                result['percentAfterJump'] = percent()
                bar = result['barAfterJump']
                if bar and not (bar == target or target.startswith(bar) or bar.startswith(target[:12])):
                    problems.append(f"jumped to '{target}' but the bar says '{bar}'")
                p = result['percentAfterJump']
                if p is not None and note:
                    want = 100 * index / len(rows)
                    if abs(p - want) > 12:
                        problems.append(f'section {index + 1} of {len(rows)} landed at {p}%, expected about {want:.0f}%')
            else:
                problems.append(f"could not tap the Contents entry '{target}'")
        else:
            problems.append('Contents opened with no entries')
            shell('input keyevent 4')
        time.sleep(1)
    elif opened:
        result['contentsEntries'] = 0

    # Search after the jump: what was passed is searchable, what is ahead is not.
    ahead = result.get('percentAfterJump')
    if words and words['mid'] and ahead is not None and ahead >= 40:
        r = search(words['mid'])
        result['searchMidAfterJump'] = r
        no_answer(r, words['mid'], problems)
        if r and not r['found']:
            problems.append(f"'{words['mid']}' (20-30% in) not found after jumping to {ahead}%")
    if words and words['late'] and ahead is not None and ahead < 80:
        r = search(words['late'])
        result['searchLateAfterJump'] = r
        no_answer(r, words['late'], problems)
        if r and r['found']:
            problems.append(f"'{words['late']}' (88-95% in) found at {ahead}%")
    return result


with open(OUT, 'a', encoding='utf-8') as out:
    for bid in IDS:
        try:
            r = run_book(bid)
        except Exception as error:  # noqa: BLE001
            r = {'id': bid, 'problems': [f'driver error: {error!r}']}
        out.write(json.dumps(r, ensure_ascii=False) + '\n')
        out.flush()
        print(bid, 'OK' if not r['problems'] else r['problems'], flush=True)
