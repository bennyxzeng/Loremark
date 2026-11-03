"""Make EPUB variants from the downloaded books, for the cases real books
rarely show: no table of contents, a broken one, one huge file, a damaged zip.

mutate.py <raw dir> <variants dir>
Each variant is <variants dir>/<id>-<kind>/book.epub, with a note in
variants.json. Inputs are untrusted: they are only read as zip data here.
"""
import json
import os
import posixpath
import re
import sys
import zipfile

RAW, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)


def read_zip(path):
    with zipfile.ZipFile(path) as z:
        return [(i.filename, z.read(i.filename)) for i in z.infolist()]


def write_zip(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        names = [n for n, _ in entries]
        if 'mimetype' in names:
            z.writestr(zipfile.ZipInfo('mimetype'), dict(entries)['mimetype'],
                       compress_type=zipfile.ZIP_STORED)
        for name, data in entries:
            if name != 'mimetype':
                z.writestr(name, data)


def opf_path(entries):
    container = dict(entries)['META-INF/container.xml'].decode('utf-8', 'replace')
    return re.search(r'full-path="([^"]+)"', container).group(1)


def toc_files(opf_text, opf_dir):
    """Paths of the nav document and NCX, from the manifest."""
    out = []
    for item in re.findall(r'<item\b[^>]*/?>', opf_text):
        href = re.search(r'href="([^"]*)"', item)
        if not href:
            continue
        if 'properties="nav"' in item or 'application/x-dtbncx+xml' in item \
                or re.search(r'properties="[^"]*\bnav\b', item):
            out.append((posixpath.normpath(posixpath.join(opf_dir, href.group(1))), item))
    return out


def no_toc(entries):
    opf = opf_path(entries)
    opf_dir = posixpath.dirname(opf)
    text = dict(entries)[opf].decode('utf-8')
    gone = toc_files(text, opf_dir)
    for _, item in gone:
        text = text.replace(item, '')
        idref = re.search(r'id="([^"]+)"', item)
        if idref:
            text = re.sub(r'<itemref\b[^>]*idref="%s"[^>]*/>' % re.escape(idref.group(1)), '', text)
    text = re.sub(r'(<spine\b[^>]*?)\s+toc="[^"]*"', r'\1', text)
    names = {p for p, _ in gone}
    out = [(n, (text.encode('utf-8') if n == opf else d)) for n, d in entries if n not in names]
    return out, len(gone)


def rewrite_toc(entries, fn):
    opf = opf_path(entries)
    opf_dir = posixpath.dirname(opf)
    text = dict(entries)[opf].decode('utf-8')
    targets = {p for p, _ in toc_files(text, opf_dir)}
    out = []
    for n, d in entries:
        if n in targets:
            body = d.decode('utf-8', 'replace')
            body = fn(n, body)
            d = body.encode('utf-8')
        out.append((n, d))
    return out


def ghost_links(name, body):
    count = [0]

    def sub(m):
        count[0] += 1
        return '%s="ghost/missing-%d.xhtml#nowhere"' % (m.group(1), count[0])
    return re.sub(r'\b(href|src)="[^"#][^"]*"', sub, body) if name.endswith('.ncx') is False \
        else re.sub(r'(src)="[^"]*"', sub, body)


def one_link(name, body):
    seen = [0]

    def sub(m):
        seen[0] += 1
        if seen[0] == 1:
            return m.group(0)
        return '%s="ghost/missing-%d.xhtml"' % (m.group(1), seen[0])
    pattern = r'(src)="[^"]*"' if name.endswith('.ncx') else r'\b(href)="[^"]*"'
    return re.sub(pattern, sub, body)


def one_file(entries):
    opf = opf_path(entries)
    opf_dir = posixpath.dirname(opf)
    d = dict(entries)
    text = d[opf].decode('utf-8')
    manifest = {}
    for item in re.findall(r'<item\b[^>]*/?>', text):
        i = re.search(r'\bid="([^"]+)"', item)
        h = re.search(r'\bhref="([^"]+)"', item)
        if i and h:
            manifest[i.group(1)] = (posixpath.normpath(posixpath.join(opf_dir, h.group(1))), item)
    refs = re.findall(r'<itemref\b[^>]*idref="([^"]+)"[^>]*/>', text)
    docs = [manifest[r][0] for r in refs if r in manifest and manifest[r][0] in d]
    if len(docs) < 3:
        return None
    head = d[docs[0]].decode('utf-8', 'replace')
    parts, mapping = [], {}
    for n, doc in enumerate(docs):
        html = d[doc].decode('utf-8', 'replace')
        m = re.search(r'<body\b[^>]*>(.*)</body>', html, re.S | re.I)
        if not m:
            continue
        mapping[doc] = 'loremark-file-%d' % n
        parts.append('<div id="loremark-file-%d">%s</div>' % (n, m.group(1)))
    merged_name = posixpath.join(opf_dir, 'merged.xhtml')
    merged = re.sub(r'(<body\b[^>]*>).*(</body>)', lambda m: m.group(1) + ''.join(parts) + m.group(2),
                    head, count=1, flags=re.S | re.I)
    keep_ref = refs[[manifest.get(r, ('',))[0] for r in refs].index(docs[0])]
    for r in refs:
        if r in manifest and manifest[r][0] in mapping and r != keep_ref:
            text = re.sub(r'<itemref\b[^>]*idref="%s"[^>]*/>' % re.escape(r), '', text)
            text = text.replace(manifest[r][1], '')
    first_item = manifest[keep_ref][1]
    first_href = re.search(r'\bhref="([^"]+)"', first_item).group(1)
    text = text.replace(first_item, first_item.replace(first_href, 'merged.xhtml'))
    out = []
    removed = set(mapping) - {docs[0]}
    for n, data in entries:
        if n in removed:
            continue
        if n == opf:
            data = text.encode('utf-8')
        elif n == docs[0]:
            n, data = merged_name, merged.encode('utf-8')
        out.append((n, data))

    def relink(name, body):
        base = posixpath.dirname(name)

        def sub(m):
            attr, href = m.group(1), m.group(2)
            path, _, frag = href.partition('#')
            target = posixpath.normpath(posixpath.join(base, path))
            if target in mapping:
                return '%s="merged.xhtml#%s"' % (attr, frag or mapping[target])
            return m.group(0)
        return re.sub(r'\b(href|src)="([^"]*)"', sub, body)
    return rewrite_toc(out, relink), len(docs)


def truncate(entries_path):
    data = open(entries_path, 'rb').read()
    return data[: int(len(data) * 0.6)]


manifest = json.load(open(os.path.join(RAW, 'manifest.json'), encoding='utf-8'))
by_id = {b['id']: b for b in manifest}
notes = []


def emit(bid, kind, entries, note):
    path = os.path.join(OUT, '%s-%s' % (bid, kind), 'book.epub')
    write_zip(path, entries)
    notes.append({'id': '%s-%s' % (bid, kind), 'from': bid, 'kind': kind,
                  'languages': by_id[bid]['languages'], 'note': note})
    print('made', bid, kind)


# No table of contents: various languages and lengths, including right-to-left.
for bid in [11, 1661, 2701, 62215, 78125, 25716, 35018, 16527, 5139, 43007, 2600, 227]:
    path = os.path.join(RAW, str(bid), 'book.epub')
    if os.path.exists(path):
        entries, removed = no_toc(read_zip(path))
        emit(bid, 'notoc', entries, 'nav and NCX removed (%d files)' % removed)

# A table of contents whose links all point nowhere, and one with a single link.
for bid in [84, 61851, 1982]:
    path = os.path.join(RAW, str(bid), 'book.epub')
    if os.path.exists(path):
        emit(bid, 'ghosttoc', rewrite_toc(read_zip(path), ghost_links), 'every TOC link points to a missing file')
for bid in [345, 78041]:
    path = os.path.join(RAW, str(bid), 'book.epub')
    if os.path.exists(path):
        emit(bid, 'onelink', rewrite_toc(read_zip(path), one_link), 'only the first TOC link is usable')

# All text in one spine file, with a table of contents of anchors into it.
for bid in [84, 1661, 345, 46]:
    path = os.path.join(RAW, str(bid), 'book.epub')
    if os.path.exists(path):
        result = one_file(read_zip(path))
        if result:
            emit(bid, 'onefile', result[0], 'all %d spine files merged into one' % result[1])

# Damaged files: the app must fail with a message, not crash.
for bid in [84, 1342]:
    path = os.path.join(RAW, str(bid), 'book.epub')
    if os.path.exists(path):
        out = os.path.join(OUT, '%s-truncated' % bid, 'book.epub')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out, 'wb').write(truncate(path))
        notes.append({'id': '%s-truncated' % bid, 'from': bid, 'kind': 'truncated',
                      'languages': by_id[bid]['languages'], 'note': 'first 60 percent of the zip'})
not_epub = os.path.join(OUT, 'notepub-text', 'book.epub')
os.makedirs(os.path.dirname(not_epub), exist_ok=True)
open(not_epub, 'wb').write(b'this is not a zip file at all\n' * 50)
notes.append({'id': 'notepub-text', 'from': None, 'kind': 'notepub', 'languages': [], 'note': 'plain text named .epub'})

json.dump(notes, open(os.path.join(OUT, 'variants.json'), 'w', encoding='utf-8'), indent=1)
print(len(notes), 'variants')
