"""Designs ROOM11, "the Titans' Terrace": an open-air dungeon terrace hanging over the void.

A paved terrace walled in by sheer cliff faces on three sides and open to the void on the fourth:
  * the doorways (east / west) are guarded by OBJECT 200 ENTRANCE, scaled up into stone titans:
    the corridor opens into a tight passage between each titan's legs,
  * the back wall is a carved facade: pilasters with double-spiral capitals (entrance05), a
    temple relief (entrance06) under a spiral crown, stacked spiral panels (entrance01 / 08),
    cracked masonry (entrance03) and a cornice on triangular corbels (entrance04),
  * stone pergola beams project from the pilasters over the terrace,
  * the front is a curved bastion with a parapet (too high to jump) and pyramid-capped piers,
    carried on a cracked stone spike that hangs into the void,
  * out in the ether a toppled titan and stone shards drift; the room's bounding box reaches
    out past them so the rest of the dungeon is seen floating beyond.

The walkable floor is flat. Textures are the entrance set (entrance01/03/04/05/06/08,
entrance_uni1/2) plus corridor01 on the threshold.

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
B, Z0, SAG = 380.0, -370.0, 300.0  # back wall, front of the end walls, depth of the bastion bow
T = 40.0                         # wall thickness (caps)
END_TOP, BACK_TOP = 720.0, 780.0
DECAL_Y = FY + 1.0

GATE_SOURCE, GATE_SCALE = 'ENTRANCE', 1.4
GATE_BACK_X, GATE_GAP_Z, GATE_LINTEL = 57.1875, -7.5, 119.0   # native back face, gap centre, gap top
HOLE_HALF = 60.0                 # passage cut in the end walls behind each titan's legs

PLINTH, R1_TOP, CORNICE_Y, CORNICE_TOP, CORNICE_OUT = FY + 70, FY + 370, 640.0, 690.0, 55.0
PILASTERS, PIL_HALF, PIL_OUT, CAP_Y, CAP_HALF, CAP_OUT = (-355.0, -175.0, 175.0, 355.0), 25.0, 30.0, 560.0, 45.0, 50.0
BEAM_HALF, BEAM_Y0, BEAM_REACH, CROSS_Y1 = 18.0, 600.0, 330.0, 675.0

ARC_SEGS, PARAPET_T, FASCIA = 12, 26.0, 70.0
# Balustrade: a jump lifts the player's feet ~85, eyes are at 100, the player is 56 wide and
# monsters 48, so the rail sits between the two and the balusters leave 38-unit gaps.
BASE_TOP, RAIL_Y0, RAIL_Y1, BALUSTERS, BAL_HALF = FY + 15.0, FY + 80.0, FY + 92.0, (0.25, 0.75), 7.0
PIERS, PIER_HALF, PIER_TOP, PIER_CAP = (2, 4, 6, 8, 10), 24.0, FY + 160.0, FY + 200.0
SPIKE_Y = FY - 520.0

R = (E * E + SAG * SAG) / (2 * SAG)
ZC = Z0 - SAG + R                # centre of the bastion arc
A0 = math.atan2(Z0 - ZC, -E) % (2 * math.pi)  # west end of the arc (angles grow through the front)
A1 = 2 * math.pi + math.atan2(Z0 - ZC, E)

# Out in the ether: (x, y, z, radius, half height, turn degrees, texture)
SHARDS = [
    (-420, 330, -760, 42, 75, 20, 'entrance03'), (380, 420, -820, 34, 60, 65, 'entrance_uni2'),
    (-200, -140, -860, 55, 95, 40, 'entrance03'), (470, -60, -720, 30, 55, 10, 'entrance_uni1'),
    (-480, 60, -980, 48, 80, 75, 'entrance_uni2'), (20, 470, -1010, 28, 50, 30, 'entrance03'),
    (300, -260, -1000, 60, 100, 55, 'entrance03'), (-60, 220, -1180, 36, 60, 5, 'entrance_uni1'),
]
FALLEN_TITAN = {'pos': (210.0, 60.0, -1060.0), 'scale': 0.9, 'yaw': 35.0, 'tilt': -62.0}


# ---------------------------------------------------------------- helpers

def rect(kit, wall, tex, s0, s1, y0, y1, depth=0.0, tile=None):
    """Wall-plane rectangle; the texture reads left-to-right from inside the room.
    tile=None stretches the texture once, otherwise it repeats every `tile` units."""
    def uv(s, y):
        if tile is None:
            return ((s1 - s) / (s1 - s0), (y1 - y) / (y1 - y0))
        return ((s1 - s) / tile, (y1 - y) / tile)
    kit.quad(tex, *[wall.at(s, y, depth) + uv(s, y) for s, y in ((s0, y0), (s1, y0), (s1, y1), (s0, y1))])


def tiles(kit, wall, tex, s0, s1, y0, y1, size):
    """Whole texture repeats sized ~size, fitted exactly to the rectangle."""
    nx, ny = max(1, round((s1 - s0) / size)), max(1, round((y1 - y0) / size))
    for i in range(nx):
        for j in range(ny):
            rect(kit, wall, tex, s0 + (s1 - s0) * i / nx, s0 + (s1 - s0) * (i + 1) / nx,
                 y0 + (y1 - y0) * j / ny, y0 + (y1 - y0) * (j + 1) / ny)


def box(kit, tex, x0, x1, y0, y1, z0, z1, skip=(), scale=100.0):
    """Axis-aligned box; skip any of 'x0 x1 y0 y1 z0 z1' (faces against something else)."""
    faces = {
        'x0': [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],
        'x1': [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)],
        'z0': [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)],
        'z1': [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
        'y0': [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
        'y1': [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],
    }
    for name, pts in faces.items():
        if name in skip:
            continue
        if name[0] == 'x':
            uv = [(p[2] / scale, -p[1] / scale) for p in pts]
        elif name[0] == 'z':
            uv = [(p[0] / scale, -p[1] / scale) for p in pts]
        else:
            uv = [(p[0] / scale, p[2] / scale) for p in pts]
        kit.quad(tex, *[p + q for p, q in zip(pts, uv)])


def arc_pt(r, a, y):
    return (r * math.cos(a), y, ZC + r * math.sin(a))


def arc_angle(k):
    return A0 + (A1 - A0) * k / ARC_SEGS


def floor_outline():
    """Counter-clockwise: east wall, back wall, west wall, then the bastion bow."""
    pts = [(E, Z0), (E, B), (-E, B), (-E, Z0)]
    for k in range(1, ARC_SEGS):
        x, _, z = arc_pt(R, arc_angle(k), 0.0)
        pts.append((x, z))
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


# ---------------------------------------------------------------- titans

def gate_x():
    return E - 1.0 - GATE_BACK_X * GATE_SCALE   # back of the titan 1 unit in front of the end wall


def gates(kit, gate):
    s, gx = GATE_SCALE, gate_x()
    # east titan as modelled (carved face towards -x, into the room); west titan turned around
    place(kit, gate, lambda x, y, z: (gx + x * s, FY + y * s, (z - GATE_GAP_Z) * s))
    place(kit, gate, lambda x, y, z: (-gx - x * s, FY + y * s, -(z - GATE_GAP_Z) * s))


def fallen_titan(kit, gate):
    px, py, pz = FALLEN_TITAN['pos']
    s = FALLEN_TITAN['scale']
    yaw, tilt = math.radians(FALLEN_TITAN['yaw']), math.radians(FALLEN_TITAN['tilt'])

    def fn(x, y, z):
        x, y, z = x * s, (y - 193.0) * s, z * s
        x, y = x * math.cos(tilt) - y * math.sin(tilt), x * math.sin(tilt) + y * math.cos(tilt)
        x, z = x * math.cos(yaw) - z * math.sin(yaw), x * math.sin(yaw) + z * math.cos(yaw)
        return (px + x, py + y, pz + z)
    place(kit, gate, fn)


# ---------------------------------------------------------------- walls

def end_walls(kit):
    lintel = FY + GATE_LINTEL * GATE_SCALE - 2.0
    for wall, door_s in ((WallFrame((E, Z0), (E, B)), -Z0), (WallFrame((-E, B), (-E, Z0)), B)):
        L = wall.len
        s0, s1 = door_s - HOLE_HALF, door_s + HOLE_HALF
        outline = [(0.0, FY), (s0, FY), (s0, lintel), (s1, lintel), (s1, FY), (L, FY), (L, END_TOP), (0.0, END_TOP)]
        wall.surface(kit, 'entrance03', outline, lambda s, y: (-s / 130.0, (END_TOP - y) / 130.0))
        # threshold to the corridor floor
        kit.quad('corridor01', *[wall.at(s, FY, d) + (s / 256.0, d / 256.0)
                                 for s, d in ((s0, 0.0), (s1, 0.0), (s1, EXIT - E), (s0, EXIT - E))])
        # outer face (only clear of the corridor, which runs z -305..305 behind the doorway), top cap
        z_lo, z_hi = sorted((wall.at(0.0, 0, 0)[2], wall.at(L, 0, 0)[2]))
        for za, zb in ((z_lo, -305.0), (305.0, z_hi)):
            sa, sb = sorted((wall.s_of(wall.p0[0], za), wall.s_of(wall.p0[0], zb)))
            rect(kit, wall, 'entrance03', sa, sb, FY, END_TOP, T, 130.0)
        kit.quad('entrance_uni1', *[wall.at(s, END_TOP, d) + (s / 100.0, d / 100.0)
                                    for s, d in ((0.0, 0.0), (L, 0.0), (L, T), (0.0, T))])
    for sx in (1, -1):
        x0, x1 = sorted((sx * E, sx * (E + T)))
        box(kit, 'entrance_uni1', x0, x1, FY, END_TOP, Z0 - 0.01, Z0, skip=('x0', 'x1', 'y0', 'y1', 'z1'))


def back_wall(kit):
    wall = WallFrame((E, B), (-E, B))           # s = E - x, room on the -z side

    def s_of(x):
        return E - x

    def span(x0, x1):
        return s_of(x1), s_of(x0)

    tiles(kit, wall, 'entrance_uni2', 0.0, 2 * E, FY, PLINTH, 90.0)
    # outer fields behind the titans, and the attic above the cornice
    for xa, xb in ((380.0, E), (-E, -380.0)):
        tiles(kit, wall, 'entrance03', *span(xa, xb), PLINTH, CORNICE_Y, 120.0)
    rect(kit, wall, 'entrance_uni1', -T, 2 * E + T, CORNICE_TOP, BACK_TOP, 0.0, 120.0)

    # centre bay: temple relief under a double-spiral crown
    rect(kit, wall, 'entrance06', *span(-150.0, 150.0), PLINTH, R1_TOP)
    rect(kit, wall, 'entrance05', *span(-150.0, 150.0), R1_TOP, R1_TOP + 120.0)
    tiles(kit, wall, 'entrance03', *span(-150.0, 150.0), R1_TOP + 120.0, CORNICE_Y, 150.0)
    # side bays: stacked spiral panels, mirrored left / right, cracked masonry above
    for xa, xb, pair in ((200.0, 330.0, ('entrance08', 'entrance01')), (-330.0, -200.0, ('entrance01', 'entrance08'))):
        size = xb - xa
        y = PLINTH
        for tex in pair:
            rect(kit, wall, tex, *span(xa, xb), y, y + size)
            y += size
        rect(kit, wall, 'entrance_uni1', *span(xa, xb), y, R1_TOP, 0.0, 100.0)
        tiles(kit, wall, 'entrance03', *span(xa, xb), R1_TOP, CORNICE_Y, 120.0)

    # pilasters: base, shaft, flared double-spiral capital
    for c in PILASTERS:
        box(kit, 'entrance_uni2', c - 35, c + 35, FY, PLINTH + 10, B - 40, B, skip=('y0', 'z1'))
        box(kit, 'entrance_uni1', c - PIL_HALF, c + PIL_HALF, PLINTH + 10, CAP_Y, B - PIL_OUT, B, skip=('y0', 'y1', 'z1'),
            scale=120.0)
        bl, br = (c - PIL_HALF, CAP_Y, B - PIL_OUT), (c + PIL_HALF, CAP_Y, B - PIL_OUT)
        tl, tr = (c - CAP_HALF, CORNICE_Y, B - CAP_OUT), (c + CAP_HALF, CORNICE_Y, B - CAP_OUT)
        kit.quad('entrance05', bl + (0.2, 0.95), br + (0.8, 0.95), tr + (0.98, 0.05), tl + (0.02, 0.05))
        for (b0, t0, side) in ((bl, tl, -1), (br, tr, 1)):
            kit.quad('entrance_uni1', b0 + (0.0, 1.0), (b0[0], CAP_Y, B) + (0.3, 1.0), (t0[0], CORNICE_Y, B) + (0.5, 0.0),
                     t0 + (0.0, 0.0))

    # cornice on triangular corbels
    box(kit, 'entrance_uni2', -E, E, CORNICE_Y, CORNICE_TOP, B - CORNICE_OUT, B, skip=('x0', 'x1', 'z1'), scale=90.0)
    corbels = [-470, -420, -112.5, -37.5, 37.5, 112.5, 232.5, 297.5, 420, 470]
    corbels += [-c for c in (232.5, 297.5)]
    for c in corbels:
        top, out, drop = CORNICE_Y, CORNICE_OUT - 5, 100.0
        for x in (c - 8, c + 8):
            kit.tri('entrance04', (x, top, B) + (0.92, 0.02), (x, top - drop, B) + (0.02, 0.19),
                    (x, top, B - out) + (0.96, 0.92))
        kit.quad('entrance_uni1', (c - 8, top - drop, B, 0.0, 1.0), (c + 8, top - drop, B, 0.16, 1.0),
                 (c + 8, top, B - out, 0.16, 0.0), (c - 8, top, B - out, 0.0, 0.0))

    # pergola: beams from the capitals and a cross beam on their ends
    zf = B - BEAM_REACH
    for c in PILASTERS:
        box(kit, 'entrance_uni2', c - BEAM_HALF, c + BEAM_HALF, BEAM_Y0, CORNICE_Y, zf, B - CAP_OUT, skip=('z1', 'y1'),
            scale=110.0)
        kit.quad('entrance_uni1', (c - BEAM_HALF, CORNICE_Y, zf + 40, 0.0, 0.0), (c + BEAM_HALF, CORNICE_Y, zf + 40, 0.3, 0.0),
                 (c + BEAM_HALF, CORNICE_Y, B - CORNICE_OUT, 0.3, 2.0), (c - BEAM_HALF, CORNICE_Y, B - CORNICE_OUT, 0.0, 2.0))
    box(kit, 'entrance_uni2', -400.0, 400.0, CORNICE_Y, CROSS_Y1, zf, zf + 40, scale=110.0)

    # caps where the back wall rises above the end walls
    kit.quad('entrance_uni1', (-E - T, BACK_TOP, B, 0, 0), (E + T, BACK_TOP, B, 10, 0),
             (E + T, BACK_TOP, B + T, 10, 0.4), (-E - T, BACK_TOP, B + T, 0, 0.4))
    for sx in (1, -1):
        x = sx * (E + T)
        kit.quad('entrance_uni1', (x, END_TOP, B, 0, 0.6), (x, END_TOP, B + T, 0.4, 0.6),
                 (x, BACK_TOP, B + T, 0.4, 0), (x, BACK_TOP, B, 0, 0))


# ---------------------------------------------------------------- terrace

def floor(kit):
    kit.fan('entrance_uni2', [(x, FY, z, x / 110.0, z / 110.0) for x, z in floor_outline()])
    # inlay: ring with strips to both titans and the bastion, a spiral emblem in the middle
    annulus(kit, 'entrance_uni1', regular(16, 170.0), regular(16, 150.0), DECAL_Y, lambda x, z: (x / 80.0, z / 80.0))
    for (xa, za), (xb, zb) in (((168, -18), (gate_x() - 70, 18)), ((-gate_x() + 70, -18), (-168, 18)),
                               ((-18, Z0 - SAG + 90), (18, -168))):
        kit.quad('entrance_uni1', (xa, DECAL_Y, za, 0, 0), (xb, DECAL_Y, za, (xb - xa) / 80, 0),
                 (xb, DECAL_Y, zb, (xb - xa) / 80, 1), (xa, DECAL_Y, zb, 0, 1))
    d = 85.0
    kit.quad('entrance01', (0.0, DECAL_Y, -d, 0, 1), (d, DECAL_Y, 0.0, 1, 1), (0.0, DECAL_Y, d, 1, 0), (-d, DECAL_Y, 0.0, 0, 0))


def bastion(kit):
    r_in, r_mid = R - PARAPET_T, R - PARAPET_T / 2
    length = 0.0
    for k in range(ARC_SEGS):
        a0, a1 = arc_angle(k), arc_angle(k + 1)
        # balustrade: base, rail (inner faces and tops) and the balusters between them
        for y0, y1, v in ((FY, BASE_TOP, 0.2), (RAIL_Y0, RAIL_Y1, 0.15)):
            kit.quad('entrance_uni2', arc_pt(r_in, a0, y0) + (0, v), arc_pt(r_in, a1, y0) + (1, v),
                     arc_pt(r_in, a1, y1) + (1, 0), arc_pt(r_in, a0, y1) + (0, 0))
            kit.quad('entrance_uni1', arc_pt(r_in, a0, y1) + (0, 0), arc_pt(r_in, a1, y1) + (1, 0),
                     arc_pt(R, a1, y1) + (1, 0.25), arc_pt(R, a0, y1) + (0, 0.25))
        for f in BALUSTERS:
            a = a0 + (a1 - a0) * f
            cx, _, cz = arc_pt(r_mid, a, 0.0)
            box_ring(kit, 'entrance_uni1', cx, cz, a, BAL_HALF, BASE_TOP, RAIL_Y0, 0.0, 0.15, 0.0, 0.6)
        # outer faces seen from the void: the fascia under the floor up to the base, and the rail
        kit.quad('entrance_uni1', arc_pt(R, a0, FY - FASCIA) + (0, 0.7), arc_pt(R, a1, FY - FASCIA) + (1, 0.7),
                 arc_pt(R, a1, BASE_TOP) + (1, 0), arc_pt(R, a0, BASE_TOP) + (0, 0))
        kit.quad('entrance_uni1', arc_pt(R, a0, RAIL_Y0) + (0, 0.15), arc_pt(R, a1, RAIL_Y0) + (1, 0.15),
                 arc_pt(R, a1, RAIL_Y1) + (1, 0), arc_pt(R, a0, RAIL_Y1) + (0, 0))
        # the spike under the bastion
        seg = math.hypot(*(arc_pt(R, a1, 0)[i] - arc_pt(R, a0, 0)[i] for i in (0, 2))) / 150.0
        kit.tri('entrance03', arc_pt(R, a0, FY - FASCIA) + (length, 0.0), arc_pt(R, a1, FY - FASCIA) + (length + seg, 0.0),
                (0.0, SPIKE_Y, Z0 - SAG / 2, length + seg / 2, 3.5))
        length += seg
    for a in (A0, A1):
        for y0, y1 in ((FY, BASE_TOP), (RAIL_Y0, RAIL_Y1)):
            kit.quad('entrance_uni1', arc_pt(r_in, a, y0) + (0, 1), arc_pt(R, a, y0) + (0.25, 1),
                     arc_pt(R, a, y1) + (0.25, 0), arc_pt(r_in, a, y1) + (0, 0))
    kit.tri('entrance03', (-E, FY - FASCIA, Z0, 0, 0), (E, FY - FASCIA, Z0, 7, 0), (0.0, SPIKE_Y, Z0 - SAG / 2, 3.5, 3.5))

    for k in PIERS:
        a = arc_angle(k)
        cx, _, cz = arc_pt(R - PARAPET_T / 2, a, 0.0)
        top = box_ring(kit, 'entrance_uni2', cx, cz, a, PIER_HALF, FY, PIER_TOP, 0.0, 1.0, 0.0, 2.0)
        for i in range(4):
            (x0, z0), (x1, z1) = top[i], top[(i + 1) % 4]
            kit.tri('entrance_uni1', (x0, PIER_TOP, z0, 0, 1), (x1, PIER_TOP, z1, 1, 1), (cx, PIER_CAP, cz, 0.5, 0))


def ether(kit):
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
    native = load_object(GATE_SOURCE)
    floor(kit)
    end_walls(kit)
    back_wall(kit)
    bastion(kit)
    gates(kit, drop_hidden(native, 0.0))
    fallen_titan(kit, drop_hidden(native, -math.inf))
    ether(kit)
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
            (0.0, 260.0), (0.0, -300.0), (230.0, -420.0), (-230.0, -420.0), (0.0, -540.0)]


def torch_positions():
    """(x, z, rot): on the front of each pilaster, and on the inner face of each parapet pier."""
    out = [(int(c), int(B - PIL_OUT - 20), 90) for c in PILASTERS]
    for k in PIERS:
        a = arc_angle(k)
        x, _, z = arc_pt(R - PARAPET_T / 2 - PIER_HALF - 20, a, 0.0)
        out.append((int(round(x)), int(round(z)), int(round(math.degrees(a))) % 360))
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
