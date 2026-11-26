"""Designs ROOM10, "the Ether Gallery": an observatory hanging in the void, from the dungeon's own blocks.

An elongated octagon with an entrance arch at each end (east / west). Its long sides and the four
angled corners are pierced by ten tall lancet windows that look out into the ether:
  * each window is an open pointed arch with a deep teal reveal and two stone bars, spaced so
    the player (and monsters) can see through but never squeeze or jump out,
  * outside, stone shards drift around the room and a rosette "eye" in a teal ring hangs in
    front of each middle window,
  * the room's bounding box reaches out past the windows, so the generator always keeps that
    space empty and the rest of the dungeon is seen floating in the fog beyond,
  * underneath, the floor tapers to a stone spike like a floating island,
  * inside: a rosette medallion and teal ring on the floor with strips to both arches, a coved
    ceiling with a rosette, and a teal dado under the windows.

Usage:
  python tools/room_observatory.py            # add/replace ROOM10 in bin/Objects.dat
  python tools/room_observatory.py --dry-run  # only print the generator data
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import room_builder as rb  # noqa: E402
from room_rotunda import (DOOR_OPENING, FY, Kit, WallFrame, annulus, arch_triangles, disc,  # noqa: E402
                          regular, rot_xz)

NAME = 'ROOM10'

E, EXIT = 517.0, 520.0    # end wall plane, exit plane (3 units apart so the corridor end caps can't z-fight)
K = 230.0                 # half width of the end walls
S, W = 300.0, 450.0       # side walls run x = -S..S at z = +-W
FLOOR = [(E, -K), (E, K), (S, W), (-S, W), (-E, K), (-E, -K), (-S, -W), (S, -W)]  # counter-clockwise

SILL, WALL_TOP, CEIL_Y, COVE_IN = FY + 60.0, 360.0, 400.0, 40.0
DECAL_Y = FY + 1.0

# Lancet windows. Two bars leave 40-unit gaps; the player capsule is 56 wide and jumps ~85 high.
WIN_HALF, WIN_SHOULDER, WIN_PEAK, REVEAL = 70.0, 280.0, 330.0, 30.0
BAR_OFFSETS, BAR_HALF = (-25.0, 25.0), 5.0
SIDE_WINDOWS = (100.0, 300.0, 500.0)    # along the 600-long side walls

MEDALLION_R, RING_IN, RING_OUT, STRIP_HALF = 140.0, 200.0, 220.0, 20.0
ROSETTE_R, SPIKE_DEPTH = 130.0, 420.0

EYE_Y, EYE_Z, EYE_RING, EYE_DISC = 210.0, 640.0, (82.0, 100.0), 66.0

# Drifting shards outside the windows: (x, y, z, radius, half height, turn degrees, texture)
SHARDS = [
    (-380, 360, 560, 40, 70, 20, 'entrance_uni2'), (260, 80, 600, 55, 90, 50, 'corridor09'),
    (-150, -60, 540, 35, 60, 10, 'entrance_uni1'), (420, 300, 520, 30, 55, 70, 'entrance_uni2'),
    (-20, 420, 660, 28, 45, 35, 'corridor09'),
    (380, 330, -560, 45, 75, 40, 'entrance_uni2'), (-260, 120, -610, 50, 85, 15, 'corridor09'),
    (150, -40, -540, 38, 62, 60, 'entrance_uni1'), (-430, 280, -520, 30, 50, 80, 'entrance_uni2'),
    (40, 440, -650, 26, 44, 5, 'corridor09'),
    (560, 200, 520, 40, 70, 25, 'corridor09'), (-560, 180, -520, 42, 68, 55, 'corridor09'),
    (-540, 360, 540, 30, 50, 0, 'entrance_uni1'), (540, 60, -540, 34, 58, 45, 'entrance_uni1'),
]


def walls():
    """(p0, p1) for every wall, counter-clockwise, so WallFrame depth > 0 points outside."""
    return [(FLOOR[i], FLOOR[(i + 1) % len(FLOOR)]) for i in range(len(FLOOR))]


def is_end_wall(p0, p1):
    return abs(p0[0]) == E and abs(p1[0]) == E


def window_centres(wall):
    return SIDE_WINDOWS if abs(wall.len - 2 * S) < 1e-6 else (wall.len / 2,)


def wall_uv(s, y):
    # corridor03 is a 2:1 totem relief: one repeat over the window band height
    return (s / (2 * (WALL_TOP - SILL)), (WALL_TOP - y) / (WALL_TOP - SILL))


def offset_polygon(poly, d):
    """Counter-clockwise convex polygon moved inwards by d."""
    lines = []
    for i in range(len(poly)):
        (x0, z0), (x1, z1) = poly[i], poly[(i + 1) % len(poly)]
        ln = math.hypot(x1 - x0, z1 - z0)
        nx, nz = (z1 - z0) / ln, -(x1 - x0) / ln
        lines.append(((x0 - nx * d, z0 - nz * d), ((x1 - x0) / ln, (z1 - z0) / ln)))
    out = []
    for i in range(len(lines)):
        (px, pz), (dx, dz) = lines[i - 1]
        (qx, qz), (ex, ez) = lines[i]
        t = ((qx - px) * ez - (qz - pz) * ex) / (dx * ez - dz * ex)
        out.append((px + dx * t, pz + dz * t))
    return out


# ---------------------------------------------------------------- room parts

def end_wall(kit, p0, p1):
    wall = WallFrame(p0, p1)
    outline = [(0.0, FY)] + [(lat + K, y) for lat, y in DOOR_OPENING] + [(2 * K, FY), (2 * K, WALL_TOP), (0.0, WALL_TOP)]
    wall.surface(kit, 'corridor03', outline, wall_uv)


def window(kit, wall, c):
    a, b = c - WIN_HALF, c + WIN_HALF
    wall.surface(kit, 'corridor03', [(a, WIN_SHOULDER), (c, WIN_PEAK), (b, WIN_SHOULDER), (b, WALL_TOP), (a, WALL_TOP)],
                 wall_uv)
    hole = [(a, SILL), (b, SILL), (b, WIN_SHOULDER), (c, WIN_PEAK), (a, WIN_SHOULDER)]
    for i in range(len(hole)):
        (s0, y0), (s1, y1) = hole[i], hole[(i + 1) % len(hole)]
        span = math.hypot(s1 - s0, y1 - y0) / 120.0
        kit.quad('entrance_uni1', wall.at(s0, y0) + (0.0, 0.0), wall.at(s1, y1) + (span, 0.0),
                 wall.at(s1, y1, REVEAL) + (span, 0.3), wall.at(s0, y0, REVEAL) + (0.0, 0.3))

    for off in BAR_OFFSETS:
        top = WIN_SHOULDER + (WIN_PEAK - WIN_SHOULDER) * (1 - (abs(off) - BAR_HALF) / WIN_HALF)
        s0, s1 = c + off - BAR_HALF, c + off + BAR_HALF
        d0, d1 = REVEAL / 2 - BAR_HALF, REVEAL / 2 + BAR_HALF
        ring = [(s0, d0), (s1, d0), (s1, d1), (s0, d1)]
        v = (top - SILL) / 100.0
        for i in range(4):
            (sa, da), (sb, db) = ring[i], ring[(i + 1) % 4]
            kit.quad('entrance_uni2', wall.at(sa, SILL, da) + (0.0, v), wall.at(sb, SILL, db) + (0.1, v),
                     wall.at(sb, top, db) + (0.1, 0.0), wall.at(sa, top, da) + (0.0, 0.0))


def window_wall(kit, p0, p1):
    wall = WallFrame(p0, p1)
    wall.surface(kit, 'entrance_uni2', [(0, FY), (wall.len, FY), (wall.len, SILL), (0, SILL)],
                 lambda s, y: (s / 90.0, (SILL - y) / (SILL - FY)))
    prev = 0.0
    for c in window_centres(wall):
        wall.surface(kit, 'corridor03', [(prev, SILL), (c - WIN_HALF, SILL), (c - WIN_HALF, WALL_TOP), (prev, WALL_TOP)],
                     wall_uv)
        window(kit, wall, c)
        prev = c + WIN_HALF
    wall.surface(kit, 'corridor03', [(prev, SILL), (wall.len, SILL), (wall.len, WALL_TOP), (prev, WALL_TOP)], wall_uv)


def ceiling(kit):
    inner = offset_polygon(FLOOR, COVE_IN)
    for i in range(len(FLOOR)):
        j = (i + 1) % len(FLOOR)
        span = math.hypot(FLOOR[j][0] - FLOOR[i][0], FLOOR[j][1] - FLOOR[i][1]) / 130.0
        kit.quad('corridor09', (FLOOR[i][0], WALL_TOP, FLOOR[i][1], 0.0, 1.0), (FLOOR[j][0], WALL_TOP, FLOOR[j][1], span, 1.0),
                 (inner[j][0], CEIL_Y, inner[j][1], span, 0.0), (inner[i][0], CEIL_Y, inner[i][1], 0.0, 0.0))
    kit.fan('corridor08', [(x, CEIL_Y, z, x / 200.0, z / 200.0) for x, z in inner])
    disc(kit, 'corridor10', regular(16, ROSETTE_R), CEIL_Y - 2.0, ROSETTE_R)


def floor(kit):
    kit.fan('corridor01', [(x, FY, z, x / 256.0, z / 256.0) for x, z in FLOOR])
    disc(kit, 'corridor10', regular(16, MEDALLION_R), DECAL_Y, MEDALLION_R)
    annulus(kit, 'entrance_uni1', regular(24, RING_OUT), regular(24, RING_IN), DECAL_Y, lambda x, z: (x / 80.0, z / 80.0))
    for sx in (1, -1):
        x0, x1 = sx * RING_OUT, sx * EXIT
        kit.quad('entrance_uni1', (x0, DECAL_Y, -STRIP_HALF, 0.0, 0.0), (x1, DECAL_Y, -STRIP_HALF, (x1 - x0) / 80.0, 0.0),
                 (x1, DECAL_Y, STRIP_HALF, (x1 - x0) / 80.0, 1.0), (x0, DECAL_Y, STRIP_HALF, 0.0, 1.0))
    # the floating island's underside
    apex = (0.0, FY - SPIKE_DEPTH, 0.0, 0.0, 3.0)
    u = 0.0
    for i in range(len(FLOOR)):
        (x0, z0), (x1, z1) = FLOOR[i], FLOOR[(i + 1) % len(FLOOR)]
        du = math.hypot(x1 - x0, z1 - z0) / 200.0
        kit.tri('corridor09', (x0, FY, z0, u, 0.0), (x1, FY, z1, u + du, 0.0), apex)
        u += du


def doorways(kit):
    arch = arch_triangles()
    lat0, lat1 = DOOR_OPENING[0][0], DOOR_OPENING[-1][0]
    for (ex, ez), k, _ in exits():
        for tex, verts in arch:
            out = []
            for x, y, z, u, v in verts:
                x, z = rot_xz(x, z, k)
                out.append((x + ex, y, z + ez, u, v))
            kit.tris.append((tex, out))
        corners = [rot_xz(dx, lat, k) for dx, lat in ((-(EXIT - E), lat0), (0.0, lat0), (0.0, lat1), (-(EXIT - E), lat1))]
        kit.quad('corridor01', *[(ex + x, FY, ez + z, (ex + x) / 256.0, (ez + z) / 256.0) for x, z in corners])


def ether(kit):
    for side in (1, -1):
        cz = side * EYE_Z
        r_in, r_out = EYE_RING
        for i in range(16):
            t0, t1 = 2 * math.pi * i / 16, 2 * math.pi * (i + 1) / 16
            pts = [(r_out, t0), (r_out, t1), (r_in, t1), (r_in, t0)]
            kit.quad('entrance_uni1', *[(r * math.cos(t), EYE_Y + r * math.sin(t), cz, r * math.cos(t) / 80.0,
                                         r * math.sin(t) / 80.0) for r, t in pts])
        rim = [(EYE_DISC * math.cos(2 * math.pi * i / 16), EYE_DISC * math.sin(2 * math.pi * i / 16)) for i in range(16)]
        for i in range(16):
            (x0, y0), (x1, y1) = rim[i], rim[(i + 1) % 16]
            kit.tri('corridor10', (0.0, EYE_Y, cz, 0.5, 0.5),
                    (x0, EYE_Y + y0, cz, 0.5 + x0 / (2 * EYE_DISC), 0.5 - y0 / (2 * EYE_DISC)),
                    (x1, EYE_Y + y1, cz, 0.5 + x1 / (2 * EYE_DISC), 0.5 - y1 / (2 * EYE_DISC)))

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
    for p0, p1 in walls():
        (end_wall if is_end_wall(p0, p1) else window_wall)(kit, p0, p1)
    ceiling(kit)
    doorways(kit)
    ether(kit)
    order = {}
    for tex, _ in kit.tris:
        order.setdefault(tex, len(order))
    kit.tris.sort(key=lambda t: order[t[0]])
    return kit.tris


# ---------------------------------------------------------------- generator data

def exits():
    return [((EXIT, 0.0), 0, 'DIR_E'), ((-EXIT, 0.0), 2, 'DIR_W')]


def floor_slots():
    return [(0.0, 0.0), (250.0, 0.0), (-250.0, 0.0), (150.0, 250.0), (-150.0, 250.0),
            (150.0, -250.0), (-150.0, -250.0), (380.0, -120.0), (-380.0, 120.0)]


def torch_positions():
    """(x, z, rot): on the wall piers between the side windows, and on the angled walls next to the
    side walls (the other end of the angled walls is taken by the arch pedestals)."""
    out = []
    for p0, p1 in walls():
        if is_end_wall(p0, p1):
            continue
        wall = WallFrame(p0, p1)
        rot = int(round(math.degrees(math.atan2(wall.n[1], wall.n[0])))) % 360
        if len(window_centres(wall)) > 1:
            spots = [(a + b) / 2 for a, b in zip(window_centres(wall), window_centres(wall)[1:])]
        else:
            spots = [wall.len - 50.0 if abs(p1[1]) == W else 50.0]
        for s in spots:
            x, _, z = wall.at(s, 0.0, -40.0)
            out.append((int(round(x)), int(round(z)), rot))
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
