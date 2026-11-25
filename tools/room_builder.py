"""Build new dungeon room objects in bin/Objects.dat from existing ones.

A room is defined by a RECIPE: a source object plus a list of geometric operations.
The result is written to Objects.dat (replacing a previous build of the same name,
otherwise appended with the next free id), and the bounding box / exits needed by
scripts/generator.gd and tools/generate_dungeonNewObjects.py are printed.

Supported operations (applied in order, coordinates are object-local):
  ('mirror_half', axis, plane)  Clip away everything on the low side of `plane` and
                                replace it with a mirror image of the high side, e.g.
                                a doorway on the +x wall gets a twin on the -x wall.
  ('remove_slab', axis, a, b)   Delete the slab a..b along `axis` and pull everything
                                beyond b back by (b - a). Geometry crossing the slab must
                                be a constant cross-section (no vertex may lie inside), so
                                run it before mirror_half, whose clipping adds vertices.
  ('translate', dx, dz)         Move the geometry on the floor plane.
  ('center',)                   Translate (by whole units) so the xz bounding box is
                                centred on the origin.

Exits declared in the recipe (local pos + outward direction of the source object) are
carried through the same transformations so the printed exits match the new geometry.

Usage:
  python tools/room_builder.py                # build every recipe
  python tools/room_builder.py ROOM07         # build one recipe
  python tools/room_builder.py --dry-run      # report only, don't touch Objects.dat
"""
import argparse
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OBJECTS_DAT = os.path.join(ROOT, 'bin', 'Objects.dat')

AXIS = {'x': 0, 'y': 1, 'z': 2}
EPS = 1e-4

# To add another room, add a recipe here, run this script, then copy the printed
# exits / bounding box into OBJECTS and BOUNDING_BOXES_FULL of both generators
# (plus FLOOR_SLOTS and TORCH_POSITIONS).
RECIPES = {
    # ROOM05, a bit smaller, with its entrance arch mirrored onto the opposite wall.
    'ROOM07': {
        'source': 'ROOM05',
        'exits': [{'pos': (455, -450), 'out': (1, 0)}],
        'ops': [
            # ROOM05 has no vertices for 586 > z > -182 (plain walls/floor/ceiling); cut
            # 400 units. Done before mirroring, whose clipping adds seam vertices.
            ('remove_slab', 'z', -100.0, 300.0),
            # No vertices for 367 > x > -325 either; mirroring at x=100 copies the arch
            # to the west wall and makes the room ~140 units narrower.
            ('mirror_half', 'x', 100.0),
            ('center',),
        ],
    },
}


# ---------------------------------------------------------------- Objects.dat I/O

def read_lines(path):
    with open(path, 'r', encoding='latin-1', newline='') as f:
        text = f.read()
    newline = '\r\n' if '\r\n' in text else '\n'
    return text.split(newline), newline


def find_object(lines, name):
    """Returns (start, end, id) line span of the object called `name` (case-insensitive)."""
    start = obj_id = None
    for i, line in enumerate(lines):
        parts = line.split()
        is_header = len(parts) >= 1 and parts[0] in ('OBJECT', 'Q2M_OBJECT')
        is_end = len(parts) >= 1 and parts[0] == 'END_FILE'
        if start is not None and (is_header or is_end):
            return start, i, obj_id
        if is_header and len(parts) >= 3 and parts[2].lower() == name.lower():
            start, obj_id = i, int(parts[1])
    if start is not None:
        return start, len(lines), obj_id
    return None


def parse_triangles(lines):
    """Triangles as (texture, [(x, y, z, u, v)] * 3) from TRITEX / QUADTEX records."""
    tokens = ' '.join(lines).split()
    tris = []
    texture = 'wall1'
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok == 'TEXTURE':
            texture = tokens[i + 1]
            i += 2
        elif tok in ('TRITEX', 'QUADTEX'):
            n = 3 if tok == 'TRITEX' else 4
            verts = [tuple(float(t) for t in tokens[i + 1 + k * 5:i + 6 + k * 5]) for k in range(n)]
            i += 1 + n * 5
            if n == 3:
                tris.append((texture, verts))
            else:  # same split as scripts/parsers.gd QUAD_ORDER
                tris.append((texture, [verts[0], verts[1], verts[3]]))
                tris.append((texture, [verts[2], verts[3], verts[1]]))
        elif tok in ('TRI', 'QUAD'):
            raise ValueError('Untextured %s records are not supported' % tok)
        else:
            i += 1
    return tris


def format_object(obj_id, name, tris):
    out = ['OBJECT %d %s' % (obj_id, name), '', '']
    texture = None
    for tex, verts in tris:
        if tex != texture:
            texture = tex
            out.append('')
            out.append('TEXTURE %s' % tex)
        for k, v in enumerate(verts):
            prefix = 'TRITEX ' if k == 0 else '       '
            out.append(prefix + ' '.join(_num(c) for c in v))
        out.append('       ')
    out.pop()
    return out


def _num(v):
    s = '%.8f' % v
    return '0.00000000' if s == '-0.00000000' else s


def write_object(path, name, tris):
    lines, newline = read_lines(path)
    existing = find_object(lines, name)
    if existing:
        start, end, obj_id = existing
        while end > start + 1 and lines[end - 1].strip() == '':
            end -= 1
        lines[start:end] = format_object(obj_id, name, tris)
        action = 'Replaced'
    else:
        ids = [int(m.group(1)) for m in (re.match(r'\s*(?:Q2M_)?OBJECT\s+(\d+)', l) for l in lines) if m]
        obj_id = max(ids) + 1
        end_idx = next(i for i, l in enumerate(lines) if l.strip() == 'END_FILE')
        while end_idx > 0 and lines[end_idx - 1].strip() == '':
            end_idx -= 1
        lines[end_idx:end_idx] = ['', ''] + format_object(obj_id, name, tris)
        action = 'Added'
    with open(path, 'w', encoding='latin-1', newline='') as f:
        f.write(newline.join(lines))
    return action, obj_id


# ---------------------------------------------------------------- geometry ops

def _lerp(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(5))


def clip_polygon(verts, axis, plane):
    """Sutherland-Hodgman clip keeping coord >= plane; UVs are interpolated."""
    out = []
    n = len(verts)
    for k in range(n):
        cur, nxt = verts[k], verts[(k + 1) % n]
        cur_in = cur[axis] >= plane - EPS
        nxt_in = nxt[axis] >= plane - EPS
        if cur_in:
            out.append(cur)
        if cur_in != nxt_in:
            t = (plane - cur[axis]) / (nxt[axis] - cur[axis])
            out.append(_lerp(cur, nxt, t))
    return out


def _area2(tri):
    ax, ay, az = (tri[1][k] - tri[0][k] for k in range(3))
    bx, by, bz = (tri[2][k] - tri[0][k] for k in range(3))
    cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    return (cx * cx + cy * cy + cz * cz) ** 0.5


def mirror_half(tris, exits, axis_name, plane):
    axis = AXIS[axis_name]
    kept = []
    for tex, verts in tris:
        poly = clip_polygon(verts, axis, plane)
        for k in range(1, len(poly) - 1):
            tri = [poly[0], poly[k], poly[k + 1]]
            if _area2(tri) > EPS:
                kept.append((tex, tri))

    def reflect(v):
        v = list(v)
        v[axis] = 2 * plane - v[axis]
        return tuple(v)

    # Reversed vertex order keeps the face winding (normals) consistent after a reflection.
    mirrored = [(tex, [reflect(v) for v in reversed(verts)]) for tex, verts in kept]

    exit_axis = 0 if axis_name == 'x' else 1
    new_exits = []
    for ex in exits:
        if ex['pos'][exit_axis] < plane:
            continue
        new_exits.append(ex)
        pos, out = list(ex['pos']), list(ex['out'])
        pos[exit_axis] = 2 * plane - pos[exit_axis]
        out[exit_axis] = -out[exit_axis]
        new_exits.append({'pos': tuple(pos), 'out': tuple(out)})
    return kept + mirrored, new_exits


def remove_slab(tris, exits, axis_name, a, b):
    axis = AXIS[axis_name]
    width = b - a
    for tex, verts in tris:
        for v in verts:
            if a + EPS < v[axis] < b - EPS:
                raise ValueError('Vertex %s (%s) lies inside the %s slab %g..%g' % (v[:3], tex, axis_name, a, b))

    def shift(v):
        if v[axis] >= b - EPS:
            v = list(v)
            v[axis] -= width
            return tuple(v)
        return v

    exit_axis = 0 if axis_name == 'x' else 1
    new_exits = []
    for ex in exits:
        p = ex['pos'][exit_axis]
        if a < p < b:
            raise ValueError('Exit %s lies inside the removed slab' % (ex['pos'],))
        pos = list(ex['pos'])
        if p >= b:
            pos[exit_axis] -= width
        new_exits.append({'pos': tuple(pos), 'out': ex['out']})
    return [(tex, [shift(v) for v in verts]) for tex, verts in tris], new_exits


def translate(tris, exits, dx, dz):
    moved = [(tex, [(v[0] + dx, v[1], v[2] + dz, v[3], v[4]) for v in verts]) for tex, verts in tris]
    return moved, [{'pos': (e['pos'][0] + dx, e['pos'][1] + dz), 'out': e['out']} for e in exits]


def bounds(tris):
    xs = [v[0] for _, verts in tris for v in verts]
    ys = [v[1] for _, verts in tris for v in verts]
    zs = [v[2] for _, verts in tris for v in verts]
    return min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)


def apply_ops(tris, exits, ops):
    for op in ops:
        kind = op[0]
        if kind == 'mirror_half':
            tris, exits = mirror_half(tris, exits, op[1], op[2])
        elif kind == 'remove_slab':
            tris, exits = remove_slab(tris, exits, op[1], op[2], op[3])
        elif kind == 'translate':
            tris, exits = translate(tris, exits, op[1], op[2])
        elif kind == 'center':
            min_x, _, min_z, max_x, _, max_z = bounds(tris)
            tris, exits = translate(tris, exits, -round((min_x + max_x) / 2), -round((min_z + max_z) / 2))
        else:
            raise ValueError('Unknown op %r' % (kind,))
    return tris, exits


# ---------------------------------------------------------------- driver

DIR_NAMES = {(0, 1): 'DIR_N', (0, -1): 'DIR_S', (-1, 0): 'DIR_W', (1, 0): 'DIR_E'}


def build(name, recipe, path, dry_run=False):
    lines, _ = read_lines(path)
    span = find_object(lines, recipe['source'])
    if not span:
        raise SystemExit('Source object %s not found in %s' % (recipe['source'], path))
    tris = parse_triangles(lines[span[0] + 1:span[1]])
    exits = [dict(e) for e in recipe['exits']]
    tris, exits = apply_ops(tris, exits, recipe['ops'])

    min_x, min_y, min_z, max_x, max_y, max_z = bounds(tris)
    print('%s (from %s): %d triangles' % (name, recipe['source'], len(tris)))
    print('  BOUNDING_BOXES_FULL: [%d, %d, %d, %d]  (y %.1f..%.1f)' % (
        round(min_x), round(min_z), round(max_x), round(max_z), min_y, max_y))
    for e in exits:
        print('  exit: {"pos": [%g, %g], "out": %s}' % (round(e['pos'][0]), round(e['pos'][1]), DIR_NAMES[tuple(e['out'])]))
    if not dry_run:
        action, obj_id = write_object(path, name, tris)
        print('  %s OBJECT %d %s in %s' % (action, obj_id, name, path))
    return tris, exits


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('rooms', nargs='*', help='recipe names (default: all)')
    ap.add_argument('--objects', default=OBJECTS_DAT, help='path to Objects.dat')
    ap.add_argument('--dry-run', action='store_true', help="report only, don't write Objects.dat")
    args = ap.parse_args()
    for name in args.rooms or list(RECIPES):
        if name not in RECIPES:
            raise SystemExit('Unknown recipe %s (known: %s)' % (name, ', '.join(RECIPES)))
        build(name, RECIPES[name], args.objects, args.dry_run)


if __name__ == '__main__':
    main()
