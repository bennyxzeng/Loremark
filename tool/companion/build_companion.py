"""Build the Ask companion's sprite layers from the artist's files.

Reads assets/ai_chat_illust/loremark-motion/ (motion.json and its PNGs):
a 2048 x 3072 body with holes where the eyes, mouth and hand go, three
pictures for each of those, and idle.png, the body with its default ones.

Writes assets/companion/: every layer cropped to the figure and halved, and
companion.json with where each goes. The app pastes the current eyes, mouth
and hand onto the body at whole pixels, then scales the result as one picture,
so the holes' edges can't show as seams.

Halving uses a box filter on premultiplied colour. Every layer's position and
size is even, so each 2 x 2 block lies wholly inside a hole or outside it, and
halving the layers then pasting them gives exactly the halved idle.png. The
script checks that before writing anything.

Uses only the standard library. Run from the repository root:
    python3 tool/companion/build_companion.py
"""
import json
import os
import struct
import sys
import zlib

SOURCE = 'assets/ai_chat_illust/loremark-motion'
OUT = 'assets/companion'

# Pixels fainter than this are left out when finding the figure's edges: the
# glow around her fades out to alpha 1 or 2 across the whole canvas.
EDGE_ALPHA = 4

# The head and shoulders, with the raised hand and all the hair beside them,
# in the artist's 2048 x 3072 pixels. Shown under the newest answer.
BUST = (240, 40, 1720, 900)


def read_png(path):
    """Width, height and rows of 8-bit RGBA bytes."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        sys.exit(f'{path}: not a PNG')
    pos = 8
    idat = []
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            width, height, depth, colour, _, _, interlace = struct.unpack(
                '>IIBBBBB', body)
            if depth != 8 or colour != 6 or interlace != 0:
                sys.exit(f'{path}: expected 8-bit RGBA, not interlaced')
        elif kind == b'IDAT':
            idat.append(body)
    raw = zlib.decompress(b''.join(idat))
    stride = width * 4
    rows = []
    prev = bytearray(stride)
    at = 0
    for _ in range(height):
        kind = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        if kind == 1:
            for x in range(4, stride):
                line[x] = (line[x] + line[x - 4]) & 255
        elif kind == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif kind == 3:
            for x in range(stride):
                left = line[x - 4] if x >= 4 else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif kind == 4:
            for x in range(stride):
                a = line[x - 4] if x >= 4 else 0
                b = prev[x]
                c = prev[x - 4] if x >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
                line[x] = (line[x] + pred) & 255
        rows.append(line)
        prev = line
    return width, height, rows


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def write_png(path, rows):
    """Writes rows of RGBA bytes, picking each row's filter by the usual
    smallest-sum heuristic."""
    height = len(rows)
    stride = len(rows[0])
    prev = bytes(stride)
    out = bytearray()
    for line in rows:
        sub = bytearray(stride)
        up = bytearray(stride)
        avg = bytearray(stride)
        pae = bytearray(stride)
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            v = line[x]
            sub[x] = (v - a) & 255
            up[x] = (v - b) & 255
            avg[x] = (v - ((a + b) >> 1)) & 255
            pae[x] = (v - _paeth(a, b, c)) & 255
        candidates = [bytes(line), sub, up, avg, pae]

        def cost(row):
            return sum(v if v < 128 else 256 - v for v in row)

        kind = min(range(5), key=lambda k: cost(candidates[k]))
        out.append(kind)
        out += candidates[kind]
        prev = line

    def chunk(kind, body):
        return (struct.pack('>I', len(body)) + kind + body +
                struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff))

    header = struct.pack('>IIBBBBB', stride // 4, height, 8, 6, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', header))
        f.write(chunk(b'IDAT', zlib.compress(bytes(out), 9)))
        f.write(chunk(b'IEND', b''))


def alpha_box(rows, threshold):
    """The smallest (left, top, right, bottom) holding every pixel at least
    [threshold] opaque."""
    width = len(rows[0]) // 4
    left, top, right, bottom = width, len(rows), 0, 0
    for y, line in enumerate(rows):
        alphas = line[3::4]
        xs = [x for x in range(width) if alphas[x] >= threshold]
        if xs:
            top = min(top, y)
            bottom = y + 1
            left = min(left, xs[0])
            right = max(right, xs[-1] + 1)
    return left, top, right, bottom


def crop(rows, left, top, right, bottom):
    return [bytearray(line[left * 4:right * 4]) for line in rows[top:bottom]]


def halve(rows):
    """Each 2 x 2 block averaged on premultiplied colour."""
    width = len(rows[0]) // 4
    out = []
    for y in range(0, len(rows) - 1, 2):
        upper, lower = rows[y], rows[y + 1]
        line = bytearray(width // 2 * 4)
        for x in range(width // 2):
            i = x * 8
            pixels = (upper[i:i + 4], upper[i + 4:i + 8],
                      lower[i:i + 4], lower[i + 4:i + 8])
            alpha = sum(p[3] for p in pixels)
            o = x * 4
            if alpha:
                for k in range(3):
                    weighted = sum(p[k] * p[3] for p in pixels)
                    line[o + k] = (weighted + alpha // 2) // alpha
                line[o + 3] = (alpha + 2) // 4
        out.append(line)
    return out


def paste(rows, layer, left, top):
    """Copies [layer] onto [rows] at whole pixels. Only right over a hole:
    the check below makes sure every layer lands on one."""
    for dy, line in enumerate(layer):
        rows[top + dy][left * 4:left * 4 + len(line)] = line


def main():
    with open(os.path.join(SOURCE, 'motion.json')) as f:
        motion = json.load(f)
    if (motion['canvas']['width'], motion['canvas']['height']) != (2048, 3072):
        sys.exit('motion.json: expected a 2048 x 3072 canvas')

    def load(name):
        width, height, rows = read_png(os.path.join(SOURCE, name))
        return rows

    print('Reading the body…')
    body = load(motion['base'])
    print('Reading the idle picture…')
    idle = load(motion['idle'])

    # Where the figure is, with even edges so halving keeps holes whole.
    left, top, right, bottom = alpha_box(body, EDGE_ALPHA)
    left, top = left - left % 2, top - top % 2
    right, bottom = right + right % 2, bottom + bottom % 2
    print(f'Figure: x {left}–{right}, y {top}–{bottom}')

    layers = {}
    for name, spec in motion['layers'].items():
        x, y, w, h = spec['x'], spec['y'], spec['width'], spec['height']
        if any(v % 2 for v in (x, y, w, h)):
            sys.exit(f'{name}: position and size must be even to halve exactly')
        if x < left or y < top or x + w > right or y + h > bottom:
            sys.exit(f'{name}: lies outside the figure')
        # The body must be clear under the layer, or pasting would differ
        # from drawing it on top.
        covered = sum(
            1 for line in body[y:y + h] for a in line[x * 4 + 3:(x + w) * 4:4]
            if a)
        if covered:
            sys.exit(f'{name}: the body has {covered} pixels showing under it')
        pictures = {}
        for state, file in spec['files'].items():
            rows = load(file)
            if len(rows) != h or len(rows[0]) != w * 4:
                sys.exit(f'{file}: expected {w} x {h}')
            pictures[state] = (file, halve(rows))
        layers[name] = ((x - left) // 2, (y - top) // 2, pictures)

    print('Halving…')
    small_body = halve(crop(body, left, top, right, bottom))
    small_idle = halve(crop(idle, left, top, right, bottom))

    # Pasting the halved layers must give exactly the halved idle picture.
    check = [bytearray(line) for line in small_body]
    for name, (x, y, pictures) in layers.items():
        paste(check, pictures[motion['initial'][name]][1], x, y)
    worst = max(
        abs(a - b) for line_a, line_b in zip(check, small_idle)
        for a, b in zip(line_a, line_b))
    if worst:
        sys.exit(f'The pasted layers differ from idle.png by up to {worst}')
    print('Check passed: the pasted layers match idle.png exactly.')

    os.makedirs(OUT, exist_ok=True)
    print('Writing…')
    write_png(os.path.join(OUT, 'body.png'), small_body)
    for name, (x, y, pictures) in layers.items():
        for state, (file, rows) in pictures.items():
            write_png(os.path.join(OUT, file), rows)

    width = (right - left) // 2
    height = (bottom - top) // 2
    bust_left = max(BUST[0], left)
    bust_top = max(BUST[1], top)
    bust_right = min(BUST[2], right)
    bust_bottom = min(BUST[3], bottom)
    frames = {
        'full': [0, 0, width, height],
        'bust': [
            (bust_left - left) // 2,
            (bust_top - top) // 2,
            (bust_right - bust_left) // 2,
            (bust_bottom - bust_top) // 2,
        ],
    }
    manifest = {
        'width': width,
        'height': height,
        'base': 'body.png',
        'layers': {
            name: {
                'x': x,
                'y': y,
                'files': {state: file for state, (file, _) in pictures.items()},
            }
            for name, (x, y, pictures) in layers.items()
        },
        'initial': motion['initial'],
        'frames': frames,
    }
    with open(os.path.join(OUT, 'companion.json'), 'w') as f:
        json.dump(manifest, f, indent=2)
        f.write('\n')
    for name in sorted(os.listdir(OUT)):
        size = os.path.getsize(os.path.join(OUT, name))
        print(f'  {name}: {size / 1024:.0f} KB')
    print(f'Body {width} x {height}; frames {frames}')


if __name__ == '__main__':
    main()
