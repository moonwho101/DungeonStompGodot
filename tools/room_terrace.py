"""Designs ROOM11, "the Titans' Terrace": an open-air dungeon terrace floating in the void.

A lens-shaped terrace open to the sky, with the void on both long sides:
  * the doorways (east / west) are guarded by OBJECT 200 ENTRANCE, scaled up into stone titans:
    the corridor opens into a tight passage between each titan's legs, set in a gabled wall
    whose pediments carry the entrance04 triangle carving,
  * both open sides are curved bastions with a balustrade (rail too high to jump, gaps too
    narrow to squeeze through) and pyramid-capped piers,
  * four carved pylons mark the corners: spiral-relief shafts (entrance01 / 08), flared double-
    spiral capitals (entrance05), a temple crown (entrance06) and a pyramid,
  * the floor is paved flagstones with a compass inlay pointing at both titans and both bastions,
    and underneath the terrace tapers to a single stone spike,
  * out in the void: a broken causeway of BLOCK01 / BLOCK02 stones falling away from the front
    bastion, two floating islets carrying block ruins, tumbling blocks and drifting shards. The
    bounding box reaches out past them so the rest of the dungeon is seen floating beyond.

Usage:
  python tools/room_terrace.py            # add/replace ROOM11 in bin/Objects.dat
  python tools/room_terrace.py --dry-run  # only print the generator data
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import room_builder as rb  # noqa: E402
from room_rotunda import FY, Kit, WallFrame, annulus, box_ring, drop_hidden, regular  # noqa: E402

NAME = 'ROOM11'

E, EXIT = 517.0, 520.0          # end wall planes / exits (3 apart so corridor end caps can't z-fight)
Z0, SAG = -370.0, 300.0         # end walls run z = Z0..-Z0; each bastion bows SAG beyond them
T = 40.0                        # end wall thickness
EAVE, APEX = 470.0, 620.0       # gabled end walls
CORRIDOR_HALF, CORRIDOR_TOP = 305.0, 455.0   # the corridor behind each end wall hides its outer face
DECAL_Y = FY + 1.0

GATE_SOURCE, GATE_SCALE = 'ENTRANCE', 1.4
GATE_BACK_X, GATE_GAP_Z, GATE_LINTEL = 57.1875, -7.5, 119.0   # native back face, gap centre, gap top
HOLE_HALF = 60.0                 # passage cut in the end walls behind each titan's legs

ARC_SEGS, PARAPET_T, FASCIA = 12, 26.0, 70.0
# Balustrade: a jump lifts the player's feet ~85, eyes are at 100, the player is 56 wide and
# monsters 48, so the rail sits between the two and the balusters leave 38-unit gaps.
BASE_TOP, RAIL_Y0, RAIL_Y1, BALUSTERS, BAL_HALF = FY + 15.0, FY + 80.0, FY + 92.0, (0.25, 0.75), 7.0
PIERS, PIER_HALF, PIER_TOP, PIER_CAP = (2, 4, 6, 8, 10), 24.0, FY + 160.0, FY + 200.0
SPIKE_Y = FY - 560.0

PYLON_X = E + 20.0               # corner pylons sit over the ends of the end walls
PYLON = [  # (y0, y1, half at y0, half at y1, texture, vertical repeats)
    (FY, FY + 40.0, 55.0, 55.0, 'entrance_uni2', 0.5),
    (FY + 40.0, 440.0, 38.0, 38.0, 'spiral', 5.0),
    (440.0, 490.0, 38.0, 52.0, 'entrance05', 1.0),
    (490.0, 570.0, 52.0, 52.0, 'entrance06', 1.0),
]
PYLON_PEAK = 640.0

R = (E * E + SAG * SAG) / (2 * SAG)
ZC = Z0 - SAG + R                # centre of the front bastion arc
A0 = math.atan2(Z0 - ZC, -E) % (2 * math.pi)  # west end of the arc (angles grow through the front)
A1 = 2 * math.pi + math.atan2(Z0 - ZC, E)

# Out in the void. Shards: (x, y, z, radius, half height, turn degrees, texture)
SHARDS = [
    (-420, 330, -760, 42, 75, 20, 'entrance03'), (380, 420, -820, 34, 60, 65, 'entrance_uni2'),
    (-200, -140, -860, 55, 95, 40, 'entrance03'), (470, -60, -720, 30, 55, 10, 'entrance_uni1'),
    (20, 470, -960, 28, 50, 30, 'entrance03'), (300, -260, -950, 60, 100, 55, 'entrance03'),
    (-380, 400, 780, 36, 62, 50, 'entrance_uni2'), (120, 450, 900, 30, 55, 15, 'entrance03'),
    (-120, -200, 860, 58, 98, 70, 'entrance03'), (460, 300, 760, 40, 70, 35, 'entrance_uni1'),
]
# Blocks: (source, x, y, z, scale, yaw, tilt) -- a broken causeway falling away from the front,
# ruins on two islets, and loose tumbling stones.
BLOCKS = [
    ('BLOCK01', 0, FY - 35, -770, 1.6, 8, 4), ('BLOCK02', 25, FY - 95, -855, 1.5, 28, -14),
    ('BLOCK01', -20, FY - 190, -940, 1.4, -18, 30),
    ('BLOCK01', -390, 175, -880, 1.3, 15, 0), ('BLOCK02', -385, 253, -880, 1.3, 40, 0),
    ('BLOCK01', 330, 115, 900, 1.3, -10, 0), ('BLOCK02', 340, 200, 895, 1.3, 25, 18),
    ('BLOCK02', 430, 330, -740, 1.0, 20, 35), ('BLOCK01', -470, 360, 800, 1.1, 60, 50),
]
ISLETS = [(-390, 135, -880, 95.0), (330, 75, 900, 95.0)]   # (x, top y, z, radius)


# ---------------------------------------------------------------- helpers

def arc_pt(r, a, y):
    return (r * math.cos(a), y, ZC + r * math.sin(a))


def arc_angle(k):
    return A0 + (A1 - A0) * k / ARC_SEGS


def mirrored(tris):
    """Front-to-back copy (z -> -z); the vertex order is reversed to keep the winding."""
    return [(tex, [(x, y, -z, u, v) for x, y, z, u, v in reversed(verts)]) for tex, verts in tris]


def floor_outline():
    """East wall, back bastion (east to west), west wall, front bastion (west to east)."""
    front = [arc_pt(R, arc_angle(k), 0.0) for k in range(1, ARC_SEGS)]
    pts = [(E, Z0), (E, -Z0)]
    pts += [(x, -z) for x, _, z in reversed(front)]
    pts += [(-E, -Z0), (-E, Z0)]
    pts += [(x, z) for x, _, z in front]
    return pts


def load_object(name):
    lines, _ = rb.read_lines(rb.OBJECTS_DAT)
    span = rb.find_object(lines, name)
    if not span:
        raise SystemExit('%s not found in %s' % (name, rb.OBJECTS_DAT))
    return rb.parse_triangles(lines[span[0] + 1:span[1]])


def place(kit, tris, fn):
    for tex, verts in tris:
        kit.tris.append((tex, [fn(x, y, z) + (u, v) for x, y, z, u, v in verts]))


def gate_x():
    return E - 1.0 - GATE_BACK_X * GATE_SCALE   # back of the titan 1 unit in front of the end wall


# ---------------------------------------------------------------- terrace

def floor(kit):
    outline = floor_outline()
    kit.fan('entrance_uni2', [(x, FY, z, x / 110.0, z / 110.0) for x, z in outline])
    # compass inlay: ring, strips to both titans and both bastions, a spiral emblem in the middle
    annulus(kit, 'entrance_uni1', regular(16, 170.0), regular(16, 150.0), DECAL_Y, lambda x, z: (x / 80.0, z / 80.0))
    reach = -(Z0 - SAG) - PARAPET_T - 60.0
    strips = [((168, -18), (gate_x() - 70, 18)), ((-gate_x() + 70, -18), (-168, 18)),
              ((-18, -reach), (18, -168)), ((-18, 168), (18, reach))]
    for (xa, za), (xb, zb) in strips:
        kit.quad('entrance_uni1', (xa, DECAL_Y, za, 0, 0), (xb, DECAL_Y, za, (xb - xa) / 80, 0),
                 (xb, DECAL_Y, zb, (xb - xa) / 80, 1), (xa, DECAL_Y, zb, 0, 1))
    d = 85.0
    kit.quad('entrance01', (0.0, DECAL_Y, -d, 0, 1), (d, DECAL_Y, 0.0, 1, 1), (0.0, DECAL_Y, d, 1, 0), (-d, DECAL_Y, 0.0, 0, 0))

    # underside: a fascia under each edge (up to the balustrade base on the bastions), tapering
    # to one stone spike
    apex = (0.0, SPIKE_Y, 0.0)
    u = 0.0
    for i in range(len(outline)):
        (x0, z0), (x1, z1) = outline[i], outline[(i + 1) % len(outline)]
        du = math.hypot(x1 - x0, z1 - z0) / 150.0
        top = FY if abs(x0) == E and abs(x1) == E else BASE_TOP
        kit.quad('entrance_uni1', (x0, FY - FASCIA, z0, u, 0.8), (x1, FY - FASCIA, z1, u + du, 0.8),
                 (x1, top, z1, u + du, 0.0), (x0, top, z0, u, 0.0))
        kit.tri('entrance03', (x0, FY - FASCIA, z0, u, 0.0), (x1, FY - FASCIA, z1, u + du, 0.0), apex + (u + du / 2, 3.5))
        u += du


def bastion(kit):
    """The front bastion's balustrade; the back one is its mirror image. Faces only seen from far
    out in the void (rail outer face) are left out; the base's outer face is part of the fascia."""
    r_in, r_mid = R - PARAPET_T, R - PARAPET_T / 2
    for k in range(ARC_SEGS):
        a0, a1 = arc_angle(k), arc_angle(k + 1)
        for y0, y1, v in ((FY, BASE_TOP, 0.2), (RAIL_Y0, RAIL_Y1, 0.15)):
            kit.quad('entrance_uni2', arc_pt(r_in, a0, y0) + (0, v), arc_pt(r_in, a1, y0) + (1, v),
                     arc_pt(r_in, a1, y1) + (1, 0), arc_pt(r_in, a0, y1) + (0, 0))
            kit.quad('entrance_uni1', arc_pt(r_in, a0, y1) + (0, 0), arc_pt(r_in, a1, y1) + (1, 0),
                     arc_pt(R, a1, y1) + (1, 0.25), arc_pt(R, a0, y1) + (0, 0.25))
        for f in BALUSTERS:   # three-sided balusters, one edge pointing into the terrace
            a = a0 + (a1 - a0) * f
            cx, _, cz = arc_pt(r_mid, a, 0.0)
            pts = [(cx + BAL_HALF * 1.4 * math.cos(a + math.pi + q * 2 * math.pi / 3),
                    cz + BAL_HALF * 1.4 * math.sin(a + math.pi + q * 2 * math.pi / 3)) for q in range(3)]
            for i in range(3):
                (x0, z0), (x1, z1) = pts[i], pts[(i + 1) % 3]
                kit.quad('entrance_uni1', (x0, BASE_TOP, z0, 0.0, 0.6), (x1, BASE_TOP, z1, 0.15, 0.6),
                         (x1, RAIL_Y0, z1, 0.15, 0.0), (x0, RAIL_Y0, z0, 0.0, 0.0))
    for k in PIERS:
        a = arc_angle(k)
        cx, _, cz = arc_pt(r_mid, a, 0.0)
        top = box_ring(kit, 'entrance_uni2', cx, cz, a, PIER_HALF, FY, PIER_TOP, 0.0, 1.0, 0.0, 2.0)
        for i in range(4):
            (x0, z0), (x1, z1) = top[i], top[(i + 1) % 4]
            kit.tri('entrance_uni1', (x0, PIER_TOP, z0, 0, 1), (x1, PIER_TOP, z1, 1, 1), (cx, PIER_CAP, cz, 0.5, 0))


def end_walls(kit):
    """Gabled walls holding the titan gates, with entrance04 triangle carvings in the pediments."""
    lintel = FY + GATE_LINTEL * GATE_SCALE - 2.0
    for wall in (WallFrame((E, Z0), (E, -Z0)), WallFrame((-E, -Z0), (-E, Z0))):
        L, h = wall.len, wall.len / 2
        s0, s1 = h - HOLE_HALF, h + HOLE_HALF
        wall.surface(kit, 'entrance03', [(0.0, FY), (s0, FY), (s0, lintel), (s1, lintel), (s1, FY), (L, FY), (L, EAVE),
                                         (0.0, EAVE)], lambda s, y: (-s / 130.0, (EAVE - y) / 130.0))
        # pediment: two right triangles, each carrying the carved triangle frame (right angle at the
        # texture's top right, long leg along its top edge)
        for a in (0.0, L):
            kit.tri('entrance04', wall.at(a, EAVE) + (0.03, 0.18), wall.at(h, EAVE) + (0.93, 0.03),
                    wall.at(h, APEX) + (0.96, 0.92))
        # threshold to the corridor floor
        kit.quad('corridor01', *[wall.at(s, FY, d) + (s / 256.0, d / 256.0)
                                 for s, d in ((s0, 0.0), (s1, 0.0), (s1, EXIT - E), (s0, EXIT - E))])
        # outer face (the corridor hides the middle), sloped copings
        c0, c1 = h - CORRIDOR_HALF, h + CORRIDOR_HALF
        wall.surface(kit, 'entrance03', [(0.0, FY), (c0, FY), (c0, CORRIDOR_TOP), (c1, CORRIDOR_TOP), (c1, FY), (L, FY),
                                         (L, EAVE), (h, APEX), (0.0, EAVE)],
                     lambda s, y: (s / 130.0, (EAVE - y) / 130.0), T)
        for a in (0.0, L):
            kit.quad('entrance_uni1', wall.at(a, EAVE) + (0, 0), wall.at(h, APEX) + (2, 0),
                     wall.at(h, APEX, T) + (2, 0.3), wall.at(a, EAVE, T) + (0, 0.3))


def pylons(kit):
    for sx in (1, -1):
        for sz in (1, -1):
            cx, cz = sx * PYLON_X, sz * -Z0
            for y0, y1, h0, h1, tex, rep in PYLON:
                lo = [(cx - h0, cz - h0), (cx + h0, cz - h0), (cx + h0, cz + h0), (cx - h0, cz + h0)]
                hi = [(cx - h1, cz - h1), (cx + h1, cz - h1), (cx + h1, cz + h1), (cx - h1, cz + h1)]
                for i in range(4):
                    j = (i + 1) % 4
                    t = tex
                    if tex == 'spiral':   # alternate the two spiral reliefs around the shaft
                        t = 'entrance01' if i % 2 == 0 else 'entrance08'
                    kit.quad(t, (lo[i][0], y0, lo[i][1], 0.0, rep), (lo[j][0], y0, lo[j][1], 1.0, rep),
                             (hi[j][0], y1, hi[j][1], 1.0, 0.0), (hi[i][0], y1, hi[i][1], 0.0, 0.0))
                if (y0, tex) == (PYLON[0][0], PYLON[0][4]):   # ledge on top of the base
                    kit.fan('entrance_uni1', [(x, y1, z, x / 80.0, z / 80.0) for x, z in hi])
            h, y = PYLON[-1][3], PYLON[-1][1]
            top = [(cx - h, cz - h), (cx + h, cz - h), (cx + h, cz + h), (cx - h, cz + h)]
            for i in range(4):
                (x0, z0), (x1, z1) = top[i], top[(i + 1) % 4]
                kit.tri('entrance_uni1', (x0, y, z0, 0, 1), (x1, y, z1, 1, 1), (cx, PYLON_PEAK, cz, 0.5, 0))


def gates(kit, gate):
    s, gx = GATE_SCALE, gate_x()
    # east titan as modelled (carved face towards -x, into the terrace); west titan turned around
    place(kit, gate, lambda x, y, z: (gx + x * s, FY + y * s, (z - GATE_GAP_Z) * s))
    place(kit, gate, lambda x, y, z: (-gx - x * s, FY + y * s, -(z - GATE_GAP_Z) * s))


# ---------------------------------------------------------------- the void

def blocks(kit):
    src = {name: load_object(name) for name in {b[0] for b in BLOCKS}}
    for name, px, py, pz, s, yaw, tilt in BLOCKS:
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))

        def fn(x, y, z, px=px, py=py, pz=pz, s=s, cy=cy, sy=sy, ct=ct, st=st):
            x, y, z = (x - 2.3) * s, (y - 30.1) * s, (z - 1.9) * s     # about the block's centre
            y, z = y * ct - z * st, y * st + z * ct
            x, z = x * cy - z * sy, x * sy + z * cy
            return (px + x, py + y, pz + z)
        place(kit, src[name], fn)


def islets(kit):
    for x, y, z, r in ISLETS:
        ring = regular(6, r, math.radians(15))
        kit.fan('entrance_uni2', [(x + dx, y, z + dz, dx / 80.0, dz / 80.0) for dx, dz in ring])
        for i in range(6):
            (ax, az), (bx, bz) = ring[i], ring[(i + 1) % 6]
            kit.quad('entrance_uni1', (x + ax, y - 22, z + az, 0, 0.3), (x + bx, y - 22, z + bz, 1, 0.3),
                     (x + bx, y, z + bz, 1, 0), (x + ax, y, z + az, 0, 0))
            kit.tri('entrance03', (x + ax, y - 22, z + az, 0, 0), (x + bx, y - 22, z + bz, 1, 0), (x, y - 200, z, 0.5, 1.6))


def shards(kit):
    for x, y, z, r, h, turn, tex in SHARDS:
        a = math.radians(turn)
        ring = [(x + rr * math.cos(a + q * math.pi / 2), y, z + rr * math.sin(a + q * math.pi / 2))
                for q, rr in enumerate((r, r * 0.6, r, r * 0.6))]
        top, bottom = (x, y + h, z), (x, y - h * 1.3, z)
        for i in range(4):
            p, q = ring[i], ring[(i + 1) % 4]
            kit.tri(tex, top + (0.5, 0.0), p + (0.0, 1.0), q + (1.0, 1.0))
            kit.tri(tex, bottom + (0.5, 0.0), q + (1.0, 1.0), p + (0.0, 1.0))


def build_room():
    kit = Kit()
    floor(kit)
    front = Kit()
    bastion(front)
    kit.tris += front.tris + mirrored(front.tris)
    end_walls(kit)
    pylons(kit)
    gates(kit, drop_hidden(load_object(GATE_SOURCE), 0.0))
    blocks(kit)
    islets(kit)
    shards(kit)
    order = {}
    for tex, _ in kit.tris:
        order.setdefault(tex, len(order))
    kit.tris.sort(key=lambda t: order[t[0]])
    return kit.tris


# ---------------------------------------------------------------- generator data

def exits():
    return [((EXIT, 0.0), 'DIR_E'), ((-EXIT, 0.0), 'DIR_W')]


def floor_slots():
    return [(0.0, 0.0), (220.0, 150.0), (-220.0, 150.0), (220.0, -150.0), (-220.0, -150.0),
            (0.0, 330.0), (0.0, -330.0), (230.0, -430.0), (-230.0, 430.0), (0.0, 560.0), (0.0, -560.0)]


def torch_positions():
    """(x, z, rot): the room-facing side of each corner pylon, then the inner face of each balustrade
    pier on both bastions."""
    inner = PYLON_X - PYLON[1][2] - 20.0
    out = [(int(sx * inner), int(sz * -Z0), 0 if sx > 0 else 180) for sx in (1, -1) for sz in (-1, 1)]
    for sz in (1, -1):
        for k in PIERS:
            a = arc_angle(k)
            x, _, z = arc_pt(R - PARAPET_T / 2 - PIER_HALF - 20, a, 0.0)
            deg = math.degrees(a)
            out.append((int(round(x)), int(round(z * sz)), int(round(deg if sz > 0 else -deg)) % 360))
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
    for (x, z), d in exits():
        print('  exit: {"pos": [%g, %g], "out": %s}' % (x, z, d))
    print('  FLOOR_SLOTS: %s' % ', '.join('[%.1f, %.1f]' % s for s in floor_slots()))
    print('  TORCH_POSITIONS: %s' % ', '.join('[%d, %d, %d]' % t for t in torch_positions()))
    if not args.dry_run:
        action, obj_id = rb.write_object(args.objects, NAME, tris)
        print('  %s OBJECT %d %s in %s' % (action, obj_id, NAME, args.objects))


if __name__ == '__main__':
    main()
