"""Turn the corpus results into Markdown tables.

report.py <corpus dir>   (reads results.jsonl, device.jsonl, raw/manifest.json)
"""
import json
import os
import statistics
import sys

ROOT = sys.argv[1]


def load(name):
    path = os.path.join(ROOT, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as handle:
        return [json.loads(line) for line in handle if line.strip()]


host = {r['id']: r for r in load('results.jsonl')}
device = {r['id']: r for r in load('device.jsonl')}
manifest = {str(b['id']): b for b in json.load(open(os.path.join(ROOT, 'raw', 'manifest.json'), encoding='utf-8'))}
variants = {v['id']: v for v in json.load(open(os.path.join(ROOT, 'variants', 'variants.json'), encoding='utf-8'))}


def title(bid):
    if bid in manifest:
        return ascii(manifest[bid]['title'])[1:-1][:34], ','.join(manifest[bid]['languages'])
    v = variants.get(bid)
    if v:
        base = manifest.get(str(v['from']))
        name = ascii(base['title'])[1:-1][:24] if base else v['kind']
        return f"{name} ({v['kind']})", ','.join(v['languages'])
    return bid, ''


def kb(n):
    return f'{n / 1024:.0f} KB' if n < 1024 * 1024 else f'{n / 1048576:.1f} MB'


def ms(n):
    return '' if n is None else (f'{n} ms' if n < 10000 else f'{n / 1000:.1f} s')


out = []
w = out.append
rows = sorted(host.values(), key=lambda r: r.get('words') or 0)
real = [r for r in rows if r['id'] in manifest]
opened = [r for r in rows if r.get('words')]

w('## Host results: every file through the app\'s own code\n')
w(f"{len(rows)} files ({len(real)} downloaded books, {len(rows) - len(real)} made from them). "
  f"{sum(1 for r in rows if not r['problems'])} passed every check, "
  f"{sum(1 for r in rows if r['problems'])} reported a problem.\n")
w('| File | Lang | Size | Words | Sections | Parse | Text | Index | Index file | Pieces | Query p50 | Auto sections | Search | Page ends |')
w('| :-- | :-: | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: | :-: | :-: |')
for r in rows:
    name, lang = title(r['id'])
    if not r.get('words'):
        status = r.get('openError', 'no text')
        w(f"| {name} | {lang} | {kb(r['bytes'])} | | | | | | | | | | refused: {status} | |")
        continue
    search = f"{r.get('searchFound', '-')}/{r.get('searchTrials', '-')}, {r.get('searchHiddenClean', '-')} hidden" \
        if 'searchTrials' in r else 'skipped'
    pe = f"{r.get('pageEndChecks', 0) - r.get('pageEndMismatches', 0)}/{r.get('pageEndChecks', 0)}"
    w(f"| {name} | {lang} | {kb(r['bytes'])} | {r['words']:,} | {r['sections']} | {ms(r.get('spineMs'))} | "
      f"{ms(r.get('textMs'))} | {ms(r.get('indexMs'))} | {kb(r.get('indexBytes', 0))} | "
      f"{r.get('paragraphs', 0):,} | {r.get('queryP50Us', 0) / 1000:.2f} ms | {r.get('syntheticSections', 0)} | {search} | {pe} |")
w('')

big = [r for r in opened if r['words'] >= 100000]
if opened:
    w('### Benchmark summary\n')
    w('Times are from a debug (JIT) test run on a Windows laptop, so a phone running the app compiled ahead of time will differ. They are for comparing books with each other.\n')
    w(f"- Books of 100,000 words or more: {len(big)}. Slowest text extraction: "
      f"{max(r.get('textMs', 0) for r in opened) / 1000:.1f} s; slowest index build: "
      f"{max(r.get('indexMs', 0) for r in opened) / 1000:.1f} s.")
    qs = [r['queryP50Us'] for r in opened if r.get('queryP50Us')]
    if qs:
        w(f"- Search query median across books: {statistics.median(qs) / 1000:.2f} ms; the slowest book's median is {max(qs) / 1000:.2f} ms.")
    sb = [r['sectionBuildMs'] for r in opened if r.get('sectionBuildMs') is not None]
    if sb:
        w(f"- Building the automatic sections: median {statistics.median(sb)} ms, slowest {max(sb)} ms.")
    pcs = [r for r in opened if r.get('paragraphs')]
    if pcs:
        w(f"- Search passages per book: median {statistics.median(r['paragraphs'] for r in pcs):,.0f}, most {max(r['paragraphs'] for r in pcs):,}.")
        w(f"- Longest passage anywhere: {max(r.get('longestParagraph', 0) for r in pcs):,} characters; "
          f"books with any passage over 600 characters: {sum(1 for r in pcs if r.get('paragraphsOver600'))}.")
    w('')

# Search totals.
trials = sum(r.get('searchTrials', 0) for r in rows)
found = sum(r.get('searchFound', 0) for r in rows)
clean = sum(r.get('searchHiddenClean', 0) for r in rows)
bounds = sum(r.get('searchBoundaryChecks', 0) for r in rows)
pe = sum(r.get('pageEndChecks', 0) for r in rows)
pm = sum(r.get('pageEndMismatches', 0) for r in rows)
w('### Search and page-end totals\n')
w(f'- Words before the cutoff found: {found} of {trials}.')
w(f'- Words after the cutoff correctly not found: {clean} of {trials}.')
w(f'- Cutoffs one character short of a passage end that correctly hid it, and exact ones that showed it: {bounds} pairs.')
w(f'- Page-end positions checked against an independent calculation: {pe}, mismatches: {pm}.\n')

bad = [r for r in rows if r['problems']]
if bad:
    w('### Host problems\n')
    for r in bad:
        w(f"- **{r['id']}** ({title(r['id'])[0]}):")
        for p in r['problems'][:5]:
            w(f"  - {p.splitlines()[0][:200]}")
    w('')

if device:
    w('## Device results: real Readium on the emulator\n')
    drows = list(device.values())
    w(f"{len(drows)} books opened in the app. {sum(1 for r in drows if not r['problems'])} had no problems.\n")
    w('| Book | Lang | Page ends | Rejected | Contents | Jump | Search at start (mid) | Search after jump (mid / late) |')
    w('| :-- | :-: | --: | --: | :-- | :-- | :-: | :-: |')

    def mark(r, key, want_found):
        x = r.get(key)
        if not x:
            return '-'
        return 'ok' if x['found'] == want_found else 'WRONG'
    for r in drows:
        name, lang = title(r['id'])
        contents = f"{r.get('contentsEntries', '-')}" + (' (made)' if r.get('contentsNote') else '')
        jump = ''
        if r.get('jumpTarget'):
            jump = f"{r['jumpTarget'][:14]} → {r.get('percentAfterJump')}% bar '{(r.get('barAfterJump') or '')[:14]}'"
        w(f"| {name} | {lang} | {r.get('pageEndLogs', '-')} | {r.get('pageEndRejected', '-')} | {contents} | {jump} | "
          f"{mark(r, 'searchMidAtStart', False)} | {mark(r, 'searchMidAfterJump', True)} / {mark(r, 'searchLateAfterJump', False)} |")
    w('')
    dbad = [r for r in drows if r['problems']]
    if dbad:
        w('### Device problems\n')
        for r in dbad:
            w(f"- **{r['id']}** ({title(r['id'])[0]}): " + '; '.join(p[:160] for p in r['problems'][:4]))
        w('')
    tot = sum(r.get('pageEndLogs', 0) for r in drows)
    rej = sum(r.get('pageEndRejected', 0) for r in drows)
    w(f'Page ends reported by the web view across all books: {tot}; rejected by the tail check: {rej}.\n')

print('\n'.join(out))
