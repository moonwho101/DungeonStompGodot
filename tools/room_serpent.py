"""Designs ROOM09, "the Serpent's Coil": a crescent gallery from the dungeon's own building blocks.

A quarter-ring hall that curves 90 degrees between two entrance arches (west and south), so it
works as a curved corner piece:
  * one cross-section (walls + elliptical vault) is swept around the curve,
  * five teal ribs arch over the hall like the ribcage of a giant serpent,
  * spiral reliefs sit in the outer wall between the ribs,
  * a teal stripe winds along the floor between the two arches: the serpent's spine.

The walkable floor is flat, every texture is one the existing pieces use, and the arches are
copied from ROOM05 like in tools/room_rotunda.py.

Usage:
  python tools/room_serpent.py            # add/replace ROOM09 in bin/Objects.dat
  python tools/room_serpent.py --dry-run  # only print the generator data
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import room_builder as rb  # noqa: E402
from room_rotunda import DOOR_OPENING, FY, Kit, arch_triangles, ear_clip, rot_xz  # noqa: E402

NAME = 'ROOM09'

CX = CZ = -372.0          # centre of the ring; puts the room's bounding box around the origin
R_IN, R_OUT = 250.0, 810.0
R_MID = (R_IN + R_OUT) / 2  # corridors join on the middle of the hall
SEGMENTS = 12             # 7.5 degrees each
WALL_TOP, VAULT_RISE, VAULT_STEPS = 300.0, 170.0, 6
INNER_PLINTH, OUTER_PLINTH = 100.0, 120.0
EXIT_GAP = 3.0            # end walls sit 3 units inside the exits so they can't z-fight corridor end caps
BAY = 2                   # segments between ribs
RIB_DEPTH, RIB_HALF = 10.0, 10.0
SPINE_HALF, SPINE_WAVE, SPINE_WAVES, SPINE_STEPS = 18.0, 90.0, 2, 32
DECAL_Y = FY + 1.0
SPIRALS = ('corridor06', 'corridor07')


def pt(r, y, th):
    return (CX + r * math.cos(th), y, CZ + r * math.sin(th))


def seg_angle(i):
    return math.pi / 2 * i / SEGMENTS


def vault():
    """Elliptical vault from the inner wall top to the outer wall top: [(r, y, inward normal)]."""
    w = (R_OUT - R_IN) / 2
    out = []
    for k in range(VAULT_STEPS + 1):
        a = math.pi * k / VAULT_STEPS
        r, y = R_MID - w * math.cos(a), WALL_TOP + VAULT_RISE * math.sin(a)
        nr, ny = -(r - R_MID) / w ** 2, -(y - WALL_TOP) / VAULT_RISE ** 2
        n = math.hypot(nr, ny)
        out.append((r, y, (nr / n, ny / n)))
    return out


def profile():
    """Whole cross-section, inner floor edge -> vault -> outer floor edge, with inward normals."""
    return [(R_IN, FY, (1.0, 0.0))] + vault() + [(R_OUT, FY, (-1.0, 0.0))]


def wall_band(kit, r, y0, y1, tex_uv):
    for i in range(SEGMENTS):
        tex, (u0, u1), (v0, v1) = tex_uv(i)
        a0, a1 = seg_angle(i), seg_angle(i + 1)
        kit.quad(tex, pt(r, y0, a0) + (u0, v1), pt(r, y0, a1) + (u1, v1),
                 pt(r, y1, a1) + (u1, v0), pt(r, y1, a0) + (u0, v0))


def outer_wall(kit):
    """Each bay is four columns: totem relief, spiral relief over the middle two, totem relief.

    Columns are laid along the straight segment chords, so the wall stays flush with the vault."""
    col = R_OUT * math.pi / 2 / SEGMENTS / 2
    for i in range(SEGMENTS):
        p0, p1 = pt(R_OUT, 0.0, seg_angle(i)), pt(R_OUT, 0.0, seg_angle(i + 1))
        for c in range(2):
            q = (i % BAY) * 2 + c                     # column within the bay, 0..3
            j = i * 2 + c                             # column along the whole wall
            if q in (1, 2):
                tex, u0, u1 = SPIRALS[(i // BAY) % 2], (q - 1) / 2.0, q / 2.0
            else:
                tex, u0, u1 = 'corridor03', j * col / 360.0, (j + 1) * col / 360.0
            a = [p0[k] + (p1[k] - p0[k]) * c / 2.0 for k in (0, 2)]
            b = [p0[k] + (p1[k] - p0[k]) * (c + 1) / 2.0 for k in (0, 2)]
            kit.quad(tex, (a[0], OUTER_PLINTH, a[1], u0, 1.0), (b[0], OUTER_PLINTH, b[1], u1, 1.0),
                     (b[0], WALL_TOP, b[1], u1, 0.0), (a[0], WALL_TOP, a[1], u0, 0.0))


def build_walls(kit):
    seg_in, seg_out = R_IN * math.pi / 2 / SEGMENTS, R_OUT * math.pi / 2 / SEGMENTS
    wall_band(kit, R_IN, FY, INNER_PLINTH, lambda i: ('entrance_uni2', (i * seg_in / 90, (i + 1) * seg_in / 90), (0, 1)))
    wall_band(kit, R_IN, INNER_PLINTH, WALL_TOP,
              lambda i: ('corridor09', (i * seg_in / 120, (i + 1) * seg_in / 120), (0, (WALL_TOP - INNER_PLINTH) / 120)))
    wall_band(kit, R_OUT, FY, OUTER_PLINTH, lambda i: ('entrance_uni2', (i * seg_out / 90, (i + 1) * seg_out / 90), (0, 1)))
    outer_wall(kit)

    v = vault()
    length = [0.0]
    for (r0, y0, _), (r1, y1, _) in zip(v, v[1:]):
        length.append(length[-1] + math.hypot(r1 - r0, y1 - y0))
    for i in range(SEGMENTS):
        a0, a1 = seg_angle(i), seg_angle(i + 1)
        for j in range(len(v) - 1):
            (r0, y0, _), (r1, y1, _) = v[j], v[j + 1]
            l0, l1 = length[j] / 220.0, length[j + 1] / 220.0
            kit.quad('corridor08', pt(r0, y0, a0) + (a0 * r0 / 220, l0), pt(r0, y0, a1) + (a1 * r0 / 220, l0),
                     pt(r1, y1, a1) + (a1 * r1 / 220, l1), pt(r1, y1, a0) + (a0 * r1 / 220, l1))


def build_ribs(kit):
    prof = profile()
    for i in range(BAY, SEGMENTS, BAY):
        th = seg_angle(i)
        inner = [(r + n[0] * RIB_DEPTH, y + n[1] * RIB_DEPTH, r) for r, y, n in prof]
        outer = [(r, y, r) for r, y, _ in prof]
        for j in range(len(prof) - 1):
            v0, v1 = j / 4.0, (j + 1) / 4.0
            (ri0, yi0, rr0), (ri1, yi1, rr1) = inner[j], inner[j + 1]
            d0, d1 = RIB_HALF / rr0, RIB_HALF / rr1
            kit.quad('entrance_uni1', pt(ri0, yi0, th - d0) + (0.0, v0), pt(ri0, yi0, th + d0) + (1.0, v0),
                     pt(ri1, yi1, th + d1) + (1.0, v1), pt(ri1, yi1, th - d1) + (0.0, v1))
            (ro0, yo0, _), (ro1, yo1, _) = outer[j], outer[j + 1]
            for s, (dd0, dd1) in ((-1, (d0, d1)), (1, (d0, d1))):
                kit.quad('entrance_uni2', pt(ro0, yo0, th + s * dd0) + (0.0, v0), pt(ri0, yi0, th + s * dd0) + (0.15, v0),
                         pt(ri1, yi1, th + s * dd1) + (0.15, v1), pt(ro1, yo1, th + s * dd1) + (0.0, v1))


def build_floor(kit):
    for i in range(SEGMENTS):
        a0, a1 = seg_angle(i), seg_angle(i + 1)
        quad = [pt(R_IN, FY, a0), pt(R_OUT, FY, a0), pt(R_OUT, FY, a1), pt(R_IN, FY, a1)]
        kit.quad('corridor01', *[p + (p[0] / 256.0, p[2] / 256.0) for p in quad])

    steps = SPINE_STEPS
    prev = None
    for k in range(steps + 1):
        th = math.pi / 2 * k / steps
        rc = R_MID + SPINE_WAVE * math.sin(4 * SPINE_WAVES * th)
        cur = (pt(rc - SPINE_HALF, DECAL_Y, th), pt(rc + SPINE_HALF, DECAL_Y, th), th * R_MID / 80.0)
        if prev:
            kit.quad('entrance_uni1', prev[0] + (prev[2], 0.0), prev[1] + (prev[2], 1.0),
                     cur[1] + (cur[2], 1.0), cur[0] + (cur[2], 0.0))
        prev = cur


def end_wall(kit, end):
    """Flat end of the crescent with the doorway; end 0 faces south (theta 0), end 1 west (theta 90)."""
    if end == 0:
        to3d = lambda r, y: (CX + r, y, CZ)  # noqa: E731
        door = [(R_MID + lat, y) for lat, y in reversed(DOOR_OPENING)]
    else:
        to3d = lambda r, y: (CX, y, CZ + r)  # noqa: E731
        door = [(R_MID - lat, y) for lat, y in DOOR_OPENING]
    outline = [(r, y) for r, y, _ in profile()] + door
    for a, b, c in ear_clip(outline):
        kit.tri('corridor03', *[to3d(*outline[k]) + (outline[k][0] / 360.0, (WALL_TOP - outline[k][1]) / 180.0)
                                for k in (a, b, c)])


def exits():
    """[(pos, quarter turns from +x, generator direction)] for the two doorways."""
    return [((CX + R_MID, CZ - EXIT_GAP), 3, 'DIR_S'), ((CX - EXIT_GAP, CZ + R_MID), 2, 'DIR_W')]


def build_doorways(kit):
    arch = arch_triangles()
    lat0, lat1 = DOOR_OPENING[0][0], DOOR_OPENING[-1][0]
    for (ex, ez), k, _ in exits():
        for tex, verts in arch:
            out = []
            for x, y, z, u, v in verts:
                x, z = rot_xz(x, z, k)
                out.append((x + ex, y, z + ez, u, v))
            kit.tris.append((tex, out))
        # threshold between the end wall and the exit
        corners = [rot_xz(dx, lat, k) for dx, lat in ((-EXIT_GAP, lat0), (0.0, lat0), (0.0, lat1), (-EXIT_GAP, lat1))]
        kit.quad('corridor01', *[(ex + x, FY, ez + z, (ex + x) / 256.0, (ez + z) / 256.0) for x, z in corners])


def build_room():
    kit = Kit()
    build_floor(kit)
    build_walls(kit)
    build_ribs(kit)
    end_wall(kit, 0)
    end_wall(kit, 1)
    build_doorways(kit)
    order = {}
    for tex, _ in kit.tris:
        order.setdefault(tex, len(order))
    kit.tris.sort(key=lambda t: order[t[0]])
    return kit.tris


# ---------------------------------------------------------------- generator data

def local(r, deg):
    x, _, z = pt(r, 0.0, math.radians(deg))
    return round(x) + 0.0, round(z) + 0.0


def floor_slots():
    slots = [(0.0, 0.0)]  # the centre of the bounding box is mid-hall, where the generator puts lights / portal
    slots += [local(R_MID, d) for d in (15, 30, 60, 75)]
    slots += [local(r, d) for d in (22.5, 67.5) for r in (R_IN + 130, R_OUT - 130)]
    return slots


def torch_positions():
    """(x, z, rot): on the outer wall beside each rib, on the inner wall in the middle of each bay."""
    out = []
    for i in range(BAY, SEGMENTS, BAY):
        deg = 90.0 * i / SEGMENTS
        x, z = local(R_OUT - 45, deg)
        out.append((int(x), int(z), int(round(deg)) % 360))
    for i in range(BAY // 2, SEGMENTS, BAY):
        deg = 90.0 * i / SEGMENTS
        x, z = local(R_IN + 45, deg)
        out.append((int(x), int(z), int(round(deg + 180)) % 360))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--objects', default=rb.OBJECTS_DAT, help='path to Objects.dat')
    ap.add_argument('--dry-run', action='store_true', help="report only, don't write Objects.dat")
    args = ap.parse_args()

    tris = build_room()
    min_x, min_y, min_z, max_x, max_y, max_z = rb.bounds(tris)
    print('%s: %d triangles, y %.1f..%.1f' % (NAME, len(tris), min_y, max_y))
    print('  BOUNDING_BOXES_FULL: [%d, %d, %d, %d]' % (math.floor(min_x), math.floor(min_z), math.ceil(max_x), math.ceil(max_z)))
    for (x, z), _, d in exits():
        print('  exit: {"pos": [%g, %g], "out": %s}' % (x, z, d))
    print('  FLOOR_SLOTS: %s' % ', '.join('[%.1f, %.1f]' % s for s in floor_slots()))
    print('  TORCH_POSITIONS: %s' % ', '.join('[%d, %d, %d]' % t for t in torch_positions()))
    if not args.dry_run:
        action, obj_id = rb.write_object(args.objects, NAME, tris)
        print('  %s OBJECT %d %s in %s' % (action, obj_id, NAME, args.objects))


if __name__ == '__main__':
    main()
