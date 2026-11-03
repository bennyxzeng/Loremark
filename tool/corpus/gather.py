"""Download a varied corpus of public-domain EPUBs from Project Gutenberg.

Each book goes into its own new directory under the corpus root, as
<root>/<gutenberg id>/book.epub, with a manifest.json beside the directories.
"""
import json
import os
import sys
import time
import urllib.request

ROOT = sys.argv[1]
TARGET = 50
UA = {'User-Agent': 'loremark-corpus-test/1.0 (class project; polite, 1 req/s)'}

# Explicit English picks for length variety: very short to over a million words.
ENGLISH = [
    1952,   # The Yellow Wallpaper (about 6k words)
    5200,   # Metamorphosis (22k)
    46,     # A Christmas Carol (28k)
    11,     # Alice in Wonderland (27k)
    64317,  # The Great Gatsby (50k, many chapters per file)
    84,     # Frankenstein (75k)
    1661,   # Sherlock Holmes (105k)
    1342,   # Pride and Prejudice (122k)
    345,    # Dracula (160k)
    2701,   # Moby Dick (210k)
    996,    # Don Quixote (390k)
    1184,   # Count of Monte Cristo (460k)
    135,    # Les Miserables, English (570k)
    2600,   # War and Peace (580k)
    2009,   # Origin of Species
    100,    # Complete Works of Shakespeare (about 1M words)
    10,     # King James Bible (about 800k words, thousands of verses)
]

# (language, how many) taken from Gutendex's most-downloaded list.
OTHERS = [
    ('fr', 4), ('de', 4), ('es', 3), ('it', 2), ('pt', 2), ('nl', 2),
    ('fi', 2), ('la', 1), ('el', 1), ('eo', 1), ('hu', 1), ('pl', 1),
    ('zh', 3), ('ja', 2), ('ru', 1), ('he', 1), ('ar', 1), ('sv', 1),
]


def get(url, timeout=60):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def epub_url(book):
    formats = book.get('formats', {})
    for key in ('application/epub+zip',):
        if key in formats:
            return formats[key]
    return None


def download(book, manifest, note=''):
    bid = book['id']
    url = epub_url(book)
    if not url:
        print('no epub for', bid)
        return False
    folder = os.path.join(ROOT, str(bid))
    if os.path.exists(folder):
        # Already downloaded by an earlier run: count it, do not fetch again.
        size = os.path.getsize(os.path.join(folder, 'book.epub'))
        manifest.append({
            'id': bid,
            'title': book.get('title'),
            'languages': book.get('languages'),
            'authors': [a.get('name') for a in book.get('authors', [])],
            'bytes': size,
            'url': url,
            'note': note,
        })
        return True
    try:
        data = get(url, timeout=180)
    except Exception as error:  # noqa: BLE001
        print('failed', bid, error)
        return False
    if not data.startswith(b'PK'):
        print('not a zip', bid)
        return False
    os.makedirs(folder)
    with open(os.path.join(folder, 'book.epub'), 'wb') as handle:
        handle.write(data)
    manifest.append({
        'id': bid,
        'title': book.get('title'),
        'languages': book.get('languages'),
        'authors': [a.get('name') for a in book.get('authors', [])],
        'bytes': len(data),
        'url': url,
        'note': note,
    })
    print('ok', bid, book.get('languages'), len(data), ascii(book.get('title') or '')[:60])
    time.sleep(1.0)
    return True


def main():
    os.makedirs(ROOT, exist_ok=True)
    manifest = []
    for bid in ENGLISH:
        if len(manifest) >= TARGET:
            break
        try:
            book = json.loads(get(f'https://gutendex.com/books/{bid}'))
        except Exception as error:  # noqa: BLE001
            print('lookup failed', bid, error)
            continue
        download(book, manifest, 'english pick')
    for lang, want in OTHERS:
        got = 0
        url = f'https://gutendex.com/books/?languages={lang}&sort=popular'
        while url and got < want and len(manifest) < TARGET:
            try:
                page = json.loads(get(url))
            except Exception as error:  # noqa: BLE001
                print('page failed', lang, error)
                break
            for book in page['results']:
                if got >= want or len(manifest) >= TARGET:
                    break
                if lang not in book.get('languages', []):
                    continue
                if download(book, manifest, f'popular {lang}'):
                    got += 1
            url = page.get('next')
    with open(os.path.join(ROOT, 'manifest.json'), 'w', encoding='utf-8') as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=1)
    print('total', len(manifest))


main()
