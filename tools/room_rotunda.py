"""Designs ROOM08, "the Sanctum of the Coiled Eye", from the dungeon's own building blocks.

An octagonal rotunda with an entrance arch on each of its four sides, so it works as a hub:
  * eight square totem pillars stand on a ring and carry a glowing teal ring beam,
  * above the beam a clerestory drum of alternating totem / spiral panels rises into a stepped
    dome capped by the corridor10 rosette as an oculus,
  * a rosette medallion, a teal inlaid ring and four teal spokes on the floor point to the arches,
  * each diagonal wall holds a pointed shrine niche with a spiral relief and an offering ledge,
    flanked by torch spots.

The walkable floor is completely flat (the player capsule has no step logic), every texture is
one the corridor/room pieces already use, and the entrance arches are copied verbatim from
ROOM05, so corridors join this room exactly as they join ROOM05.

Usage:
  python tools/room_rotunda.py            # add/replace ROOM08 in bin/Objects.dat
  python tools/room_rotunda.py --dry-run  # only print the generator data
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import room_builder as rb  # noqa: E402

NAME = 'ROOM08'

FY = 37.34178            # floor top, same as the corridor floors
H = 517.0                # cardinal wall plane: 3 units inside the exit so it can't z-fight corridor end caps
EXIT = 520.0             # exit plane (where the corridor starts)
C = 800.0                # diagonal walls lie on |x| + |z| = C
WALL_TOP = 360.0         # walls end here, a cove carries on up to the ceiling
CEIL_Y = 400.0
COVE_IN = 40.0
PLINTH_Y, PLINTH_IN = 82.0, 16.0
DECAL_Y = FY + 1.0       # floor inlays sit just above the floor

PILLAR_R, PILLAR_HALF = 330.0, 26.0
BEAM_IN, BEAM_OUT, BEAM_Y = 292.0, 368.0, 370.0
DRUM_SIDES, DRUM_TOP = 16, 530.0
DOME = [(BEAM_IN, DRUM_TOP), (220.0, 590.0), (220.0, 606.0), (150.0, 646.0)]

RING_IN, RING_OUT = 236.0, 256.0
MEDALLION_R = 140.0
SPOKE_HALF = 20.0

NICHE_HALF, NICHE_SILL, NICHE_SHOULDER, NICHE_PEAK, NICHE_DEPTH = 60.0, 150.0, 280.0, 325.0, 36.0

# Doorway cut into the cardinal walls as (lateral, y): the corridor01 inner profile (baseboards,
# sloped walls, pointed vault) inset ~6 units so the wall overlaps the corridor's end.
DOOR_OPENING = [(-154, FY), (-166, 81), (-141, 214), (-8, 346), (14, 346), (147, 214), (173, 81), (160, FY)]
PLINTH_GAP = (-190.0, 200.0)  # plinth stops inside the arch pedestals

ARCH_SOURCE = 'ROOM05'
ARCH_EXIT = (455.0, -450.0)   # ROOM05's +x exit, the arch is copied relative to it
ARCH_TEXTURES = ('entrance_uni1', 'entrance_uni2', 'corridor05', 'corridor07')

# corridor03 totem relief, corridor05 trapezoid keystone, corridor06/07 spirals, corridor08 plain dark,
# corridor09 dark with a totem, corridor10 rosette, entrance_uni1/2 teal stone.
NICHE_TEXTURES = ('corridor06', 'corridor07')
DRUM_TEXTURES = ('corridor09', 'corridor06', 'corridor09', 'corridor07')


# ---------------------------------------------------------------- small geometry kit

def rot_xz(x, z, k):
    """Quarter turns in the generator's convention: rotate(x, z, 90) == (-z, x)."""
    for _ in range(k % 4):
        x, z = -z, x
    return x, z


def octagon(h, c):
    k = c - h
    return [(h, -k), (h, k), (k, h), (-k, h), (-h, k), (-h, -k), (-k, -h), (k, -h)]


def regular(n, r, phase=0.0):
    return [(r * math.cos(phase + 2 * math.pi * i / n), r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def ray_hit(theta, poly):
    """Distance from the origin along angle theta to a convex polygon around the origin."""
    dx, dz = math.cos(theta), math.sin(theta)
    best = math.inf
    for i in range(len(poly)):
        (px, pz), (qx, qz) = poly[i], poly[(i + 1) % len(poly)]
        ex, ez = qx - px, qz - pz
        den = dx * ez - dz * ex
        if abs(den) < 1e-12:
            continue
        t = (px * ez - pz * ex) / den
        s = (px * dz - pz * dx) / den
        if t > 0 and -1e-9 <= s <= 1 + 1e-9:
            best = min(best, t)
    return best


def angles_of(*polys):
    angs = {round(math.atan2(z, x) % (2 * math.pi), 9) for poly in polys for x, z in poly}
    return sorted(angs)


def ear_clip(poly):
    """Triangulates a simple 2D polygon; returns index triples."""
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
               for i in range(len(poly)))
    idx = list(range(len(poly))) if area > 0 else list(reversed(range(len(poly))))
    out = []
    while len(idx) > 3:
        for i in range(len(idx)):
            a, b, c = idx[i - 1], idx[i], idx[(i + 1) % len(idx)]
            pa, pb, pc = poly[a], poly[b], poly[c]
            if cross(pa, pb, pc) <= 1e-9:
                continue
            if any(cross(pa, pb, poly[j]) >= 0 and cross(pb, pc, poly[j]) >= 0 and cross(pc, pa, poly[j]) >= 0
                   for j in idx if j not in (a, b, c) and poly[j] not in (pa, pb, pc)):
                continue
            out.append((a, b, c))
            idx.pop(i)
            break
        else:
            raise ValueError('ear clipping failed')
    out.append(tuple(idx))
    return out


class Kit:
    def __init__(self):
        self.tris = []

    def tri(self, tex, a, b, c):
        if rb._area2([a, b, c]) > 1e-6:
            self.tris.append((tex, [tuple(a), tuple(b), tuple(c)]))

    def fan(self, tex, verts):
        for i in range(1, len(verts) - 1):
            self.tri(tex, verts[0], verts[i], verts[i + 1])

    def quad(self, tex, a, b, c, d):
        self.fan(tex, [a, b, c, d])

    def extend(self, other, k=0):
        for tex, verts in other.tris:
            out = []
            for x, y, z, u, v in verts:
                x, z = rot_xz(x, z, k)
                out.append((x, y, z, u, v))
            self.tris.append((tex, out))


class WallFrame:
    """Maps (s along the wall, y, depth outward) to 3D for the wall p0 -> p1 (room on the left)."""

    def __init__(self, p0, p1):
        self.p0 = p0
        self.len = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        self.d = ((p1[0] - p0[0]) / self.len, (p1[1] - p0[1]) / self.len)
        self.n = (self.d[1], -self.d[0])

    def at(self, s, y, depth=0.0):
        return (self.p0[0] + self.d[0] * s + self.n[0] * depth, y, self.p0[1] + self.d[1] * s + self.n[1] * depth)

    def s_of(self, x, z):
        return (x - self.p0[0]) * self.d[0] + (z - self.p0[1]) * self.d[1]

    def surface(self, kit, tex, outline, uv, depth=0.0):
        """Flat polygon in the wall plane; uv(s, y) gives the texture coordinates."""
        for a, b, c in ear_clip(outline):
            kit.tri(tex, *[self.at(*outline[i], depth) + uv(*outline[i]) for i in (a, b, c)])


def planar(x, y, z, scale):
    return (x, y, z, x / scale, z / scale)


# ---------------------------------------------------------------- room parts

def load_arch():
    lines, _ = rb.read_lines(rb.OBJECTS_DAT)
    start, end, _ = rb.find_object(lines, ARCH_SOURCE)
    arch = Kit()
    for tex, verts in rb.parse_triangles(lines[start + 1:end]):
        if tex in ARCH_TEXTURES:
            arch.tris.append((tex, [(x - ARCH_EXIT[0] + EXIT, y, z - ARCH_EXIT[1], u, v) for x, y, z, u, v in verts]))
    if not arch.tris:
        raise SystemExit('No arch geometry found in %s' % ARCH_SOURCE)
    return arch


def wall_uv(s, y):
    # corridor03 is a 2:1 totem relief: one repeat per 520 units, full height between plinth and cove
    return (s / 520.0, (WALL_TOP - y) / (WALL_TOP - PLINTH_Y))


def east_wall(kit):
    """Cardinal wall with the doorway, plinth, cove, threshold and floor spoke (east side)."""
    k = C - H
    wall = WallFrame((H, -k), (H, k))
    outline = [(0.0, FY)] + [(lat + k, y) for lat, y in DOOR_OPENING] + [(2 * k, FY), (2 * k, WALL_TOP), (0.0, WALL_TOP)]
    wall.surface(kit, 'corridor03', outline, wall_uv)

    hp, kp = H - PLINTH_IN, (C - PLINTH_IN * math.sqrt(2)) - (H - PLINTH_IN)
    for z0, z1, zi0, zi1 in ((-k, PLINTH_GAP[0], -kp, PLINTH_GAP[0]), (PLINTH_GAP[1], k, PLINTH_GAP[1], kp)):
        kit.quad('entrance_uni2', (hp, FY, zi0, zi0 / 90.0, 1.0), (hp, FY, zi1, zi1 / 90.0, 1.0),
                 (hp, PLINTH_Y, zi1, zi1 / 90.0, 0.0), (hp, PLINTH_Y, zi0, zi0 / 90.0, 0.0))
        kit.quad('entrance_uni1', planar(H, PLINTH_Y, z0, 120.0), planar(H, PLINTH_Y, z1, 120.0),
                 planar(hp, PLINTH_Y, zi1, 120.0), planar(hp, PLINTH_Y, zi0, 120.0))

    hc, kc = H - COVE_IN, (C - COVE_IN * math.sqrt(2)) - (H - COVE_IN)
    kit.quad('corridor09', (H, WALL_TOP, -k, -k / 130.0, 1.0), (H, WALL_TOP, k, k / 130.0, 1.0),
             (hc, CEIL_Y, kc, kc / 130.0, 0.0), (hc, CEIL_Y, -kc, -kc / 130.0, 0.0))

    z0, z1 = DOOR_OPENING[0][0], DOOR_OPENING[-1][0]
    kit.quad('corridor01', planar(H, FY, z0, 256.0), planar(EXIT, FY, z0, 256.0),
             planar(EXIT, FY, z1, 256.0), planar(H, FY, z1, 256.0))
    x0 = RING_OUT
    kit.quad('entrance_uni1', (x0, DECAL_Y, -SPOKE_HALF, 0.0, 0.0), (EXIT, DECAL_Y, -SPOKE_HALF, (EXIT - x0) / 80.0, 0.0),
             (EXIT, DECAL_Y, SPOKE_HALF, (EXIT - x0) / 80.0, 1.0), (x0, DECAL_Y, SPOKE_HALF, 0.0, 1.0))


def diagonal_wall(kit, niche_tex):
    """North-east wall with a pointed shrine niche, its ledge, plinth and cove."""
    k = C - H
    wall = WallFrame((H, k), (k, H))
    L, sc = wall.len, wall.len / 2
    a, b = sc - NICHE_HALF, sc + NICHE_HALF
    wall.surface(kit, 'corridor03', [(0, FY), (L, FY), (L, NICHE_SILL), (0, NICHE_SILL)], wall_uv)
    wall.surface(kit, 'corridor03', [(0, NICHE_SILL), (a, NICHE_SILL), (a, WALL_TOP), (0, WALL_TOP)], wall_uv)
    wall.surface(kit, 'corridor03', [(b, NICHE_SILL), (L, NICHE_SILL), (L, WALL_TOP), (b, WALL_TOP)], wall_uv)
    wall.surface(kit, 'corridor03', [(a, NICHE_SHOULDER), (sc, NICHE_PEAK), (b, NICHE_SHOULDER),
                                     (b, WALL_TOP), (a, WALL_TOP)], wall_uv)

    hole = [(a, NICHE_SILL), (b, NICHE_SILL), (b, NICHE_SHOULDER), (sc, NICHE_PEAK), (a, NICHE_SHOULDER)]
    wall.surface(kit, niche_tex, hole,
                 lambda s, y: ((s - a) / (b - a), (NICHE_PEAK - y) / (NICHE_PEAK - NICHE_SILL)), NICHE_DEPTH)
    for i in range(len(hole)):
        (s0, y0), (s1, y1) = hole[i], hole[(i + 1) % len(hole)]
        span = math.hypot(s1 - s0, y1 - y0) / 120.0
        kit.quad('entrance_uni1', wall.at(s0, y0) + (0.0, 0.0), wall.at(s1, y1) + (span, 0.0),
                 wall.at(s1, y1, NICHE_DEPTH) + (span, 0.3), wall.at(s0, y0, NICHE_DEPTH) + (0.0, 0.3))

    # offering ledge in front of the niche
    l0, l1, top, bot, out = a - 12, b + 12, NICHE_SILL, NICHE_SILL - 12, -14.0
    ledge = 'entrance_uni2'
    kit.quad(ledge, wall.at(l0, top) + (0.0, 0.0), wall.at(l1, top) + (1.0, 0.0),
             wall.at(l1, top, out) + (1.0, 0.15), wall.at(l0, top, out) + (0.0, 0.15))
    kit.quad(ledge, wall.at(l0, bot, out) + (0.0, 1.0), wall.at(l1, bot, out) + (1.0, 1.0),
             wall.at(l1, top, out) + (1.0, 0.8), wall.at(l0, top, out) + (0.0, 0.8))
    kit.quad(ledge, wall.at(l0, bot) + (0.0, 0.0), wall.at(l1, bot) + (1.0, 0.0),
             wall.at(l1, bot, out) + (1.0, 0.15), wall.at(l0, bot, out) + (0.0, 0.15))
    for s in (l0, l1):
        kit.quad(ledge, wall.at(s, bot) + (0.0, 1.0), wall.at(s, bot, out) + (0.15, 1.0),
                 wall.at(s, top, out) + (0.15, 0.8), wall.at(s, top) + (0.0, 0.8))

    # plinth (mitred into the cardinal plinths) and cove
    hp, kp = H - PLINTH_IN, (C - PLINTH_IN * math.sqrt(2)) - (H - PLINTH_IN)
    p0, p1 = (hp, kp), (kp, hp)
    s0, s1 = wall.s_of(*p0), wall.s_of(*p1)
    kit.quad('entrance_uni2', (p0[0], FY, p0[1], s0 / 90.0, 1.0), (p1[0], FY, p1[1], s1 / 90.0, 1.0),
             (p1[0], PLINTH_Y, p1[1], s1 / 90.0, 0.0), (p0[0], PLINTH_Y, p0[1], s0 / 90.0, 0.0))
    kit.quad('entrance_uni1', planar(H, PLINTH_Y, k, 120.0), planar(k, PLINTH_Y, H, 120.0),
             planar(p1[0], PLINTH_Y, p1[1], 120.0), planar(p0[0], PLINTH_Y, p0[1], 120.0))
    hc, kc = H - COVE_IN, (C - COVE_IN * math.sqrt(2)) - (H - COVE_IN)
    c0, c1 = (hc, kc), (kc, hc)
    kit.quad('corridor09', (H, WALL_TOP, k, 0.0, 1.0), (k, WALL_TOP, H, L / 130.0, 1.0),
             (c1[0], CEIL_Y, c1[1], wall.s_of(*c1) / 130.0, 0.0), (c0[0], CEIL_Y, c0[1], wall.s_of(*c0) / 130.0, 0.0))


def box_ring(kit, tex, cx, cz, phi, half, y0, y1, u0=0.0, u1=1.0, v0=0.0, v1=1.0):
    """Four sides of a square prism around (cx, cz) whose faces point radially (angle phi)."""
    ax, az = math.cos(phi), math.sin(phi)
    bx, bz = -az, ax
    corners = [(cx + (ax * i + bx * j) * half, cz + (az * i + bz * j) * half) for i, j in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    for i in range(4):
        (x0, z0), (x1, z1) = corners[i], corners[(i + 1) % 4]
        kit.quad(tex, (x0, y0, z0, u0, v1), (x1, y0, z1, u1, v1), (x1, y1, z1, u1, v0), (x0, y1, z0, u0, v0))
    return corners


def pillar(kit, phi):
    cx, cz = PILLAR_R * math.cos(phi), PILLAR_R * math.sin(phi)
    for tex, half, y0, y1 in (('entrance_uni2', 44.0, FY, FY + 20), ('entrance_uni1', 34.0, FY + 20, FY + 34)):
        top = box_ring(kit, tex, cx, cz, phi, half, y0, y1)
        kit.fan('entrance_uni1', [planar(x, y1, z, 80.0) for x, z in top])
    # corridor03's totem figure stacked twice up the shaft: a totem pole
    box_ring(kit, 'corridor03', cx, cz, phi, PILLAR_HALF, FY + 34, 320.0, 0.12, 0.38, 0.0, 2.0)
    # flared capital: corridor05 is a trapezoid keystone, mapped onto each trapezoid face
    ax, az = math.cos(phi), math.sin(phi)
    bx, bz = -az, ax
    sq = ((1, 1), (-1, 1), (-1, -1), (1, -1))
    lo = [(cx + (ax * i + bx * j) * PILLAR_HALF, cz + (az * i + bz * j) * PILLAR_HALF) for i, j in sq]
    hi = [(cx + (ax * i + bx * j) * 44.0, cz + (az * i + bz * j) * 44.0) for i, j in sq]
    for i in range(4):
        n = (i + 1) % 4
        kit.quad('corridor05', (lo[i][0], 320.0, lo[i][1], 0.2, 0.97), (lo[n][0], 320.0, lo[n][1], 0.8, 0.97),
                 (hi[n][0], BEAM_Y, hi[n][1], 0.97, 0.03), (hi[i][0], BEAM_Y, hi[i][1], 0.03, 0.03))


def band(kit, tex, poly_a, ya, poly_b, yb, segments_tex=None):
    """Side surface between two matching polylines (closed), one texture repeat per segment."""
    n = len(poly_a)
    for i in range(n):
        j = (i + 1) % n
        t = segments_tex[i % len(segments_tex)] if segments_tex else tex
        kit.quad(t, (poly_a[i][0], ya, poly_a[i][1], 0.0, 1.0), (poly_a[j][0], ya, poly_a[j][1], 1.0, 1.0),
                 (poly_b[j][0], yb, poly_b[j][1], 1.0, 0.0), (poly_b[i][0], yb, poly_b[i][1], 0.0, 0.0))


def disc(kit, tex, poly, y, radius):
    """Polygon with a texture stretched once across its circumscribed circle (rosettes)."""
    verts = [(x, y, z, 0.5 + x / (2 * radius), 0.5 + z / (2 * radius)) for x, z in poly]
    for i in range(len(verts)):
        kit.tri(tex, (0.0, y, 0.0, 0.5, 0.5), verts[i], verts[(i + 1) % len(verts)])


def annulus(kit, tex, outer, inner, y, uv):
    """Flat ring between two convex polygons around the origin, sampled on both sets of vertex angles."""
    angs = angles_of(outer, inner)
    pts = [(ray_hit(a, outer), ray_hit(a, inner), a) for a in angs]
    for i in range(len(pts)):
        ro0, ri0, a0 = pts[i]
        ro1, ri1, a1 = pts[(i + 1) % len(pts)]
        quad = [(ro0 * math.cos(a0), ro0 * math.sin(a0)), (ro1 * math.cos(a1), ro1 * math.sin(a1)),
                (ri1 * math.cos(a1), ri1 * math.sin(a1)), (ri0 * math.cos(a0), ri0 * math.sin(a0))]
        kit.quad(tex, *[(x, y, z) + uv(x, z) for x, z in quad])


def build_room():
    room = Kit()
    arch = load_arch()
    for k in range(4):
        quarter = Kit()
        east_wall(quarter)
        quarter.extend(arch)
        diagonal_wall(quarter, NICHE_TEXTURES[k % 2])
        room.extend(quarter, k)

    # floor, medallion, inlaid ring
    floor = octagon(H, C)
    room.fan('corridor01', [planar(x, FY, z, 256.0) for x, z in floor])
    disc(room, 'corridor10', regular(32, MEDALLION_R), DECAL_Y, MEDALLION_R)
    annulus(room, 'entrance_uni1', regular(48, RING_OUT), regular(48, RING_IN), DECAL_Y, lambda x, z: (x / 80.0, z / 80.0))

    # totem pillars carrying the ring beam
    for i in range(8):
        pillar(room, math.radians(22.5 + 45 * i))
    beam_in, beam_out = regular(32, BEAM_IN), regular(32, BEAM_OUT)
    annulus(room, 'entrance_uni2', beam_out, beam_in, BEAM_Y, lambda x, z: (x / 100.0, z / 100.0))
    band(room, 'entrance_uni1', beam_out, BEAM_Y, beam_out, CEIL_Y)
    band(room, 'entrance_uni1', beam_in, BEAM_Y, beam_in, CEIL_Y)

    # flat ceiling between the coves and the beam
    cove_edge = octagon(H - COVE_IN, C - COVE_IN * math.sqrt(2))
    annulus(room, 'corridor08', cove_edge, beam_out, CEIL_Y, lambda x, z: (x / 200.0, z / 200.0))

    # clerestory drum, stepped dome and rosette oculus
    drum = regular(DRUM_SIDES, BEAM_IN)
    band(room, None, drum, CEIL_Y, drum, DRUM_TOP, DRUM_TEXTURES)
    dome_tex = ('corridor08', 'entrance_uni1', 'corridor08')
    for (r0, y0), (r1, y1), tex in zip(DOME, DOME[1:], dome_tex):
        band(room, tex, regular(DRUM_SIDES, r0), y0, regular(DRUM_SIDES, r1), y1)
    r_top, y_top = DOME[-1]
    disc(room, 'corridor10', regular(DRUM_SIDES, r_top), y_top, r_top)

    # keep each texture's triangles together so Objects.dat stays compact
    order = {}
    for tex, _ in room.tris:
        order.setdefault(tex, len(order))
    room.tris.sort(key=lambda t: order[t[0]])
    return room.tris


# ---------------------------------------------------------------- generator data

EXITS = [((EXIT, 0.0), 'DIR_E'), ((0.0, EXIT), 'DIR_N'), ((-EXIT, 0.0), 'DIR_W'), ((0.0, -EXIT), 'DIR_S')]


def floor_slots():
    slots = [(0.0, 0.0)]
    for k in range(4):
        slots.append(rot_xz(127.0, 127.0, k))
        slots.append(rot_xz(200.0, 0.0, k))
        slots.append(rot_xz(300.0, 300.0, k))
    return [(x + 0.0, z + 0.0) for x, z in slots]  # + 0.0 turns -0.0 into 0.0


def torch_positions():
    """(x, z, rot): two beside each shrine niche, one on the inner face of each pillar."""
    out = []
    k = C - H
    wall = WallFrame((H, k), (k, H))
    for q in range(4):
        for ds in (-105.0, 105.0):
            x, _, z = wall.at(wall.len / 2 + ds, 0.0, -40.0)
            x, z = rot_xz(x, z, q)
            out.append((round(x), round(z), (45 + 90 * q) % 360))
    for i in range(8):
        a = math.radians(22.5 + 45 * i)
        r = PILLAR_R - PILLAR_HALF - 45.0
        out.append((round(r * math.cos(a)), round(r * math.sin(a)), int(round(22.5 + 45 * i)) % 360))
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
    for (x, z), d in EXITS:
        print('  exit: {"pos": [%g, %g], "out": %s}' % (x, z, d))
    print('  FLOOR_SLOTS: %s' % ', '.join('[%.1f, %.1f]' % s for s in floor_slots()))
    print('  TORCH_POSITIONS: %s' % ', '.join('[%d, %d, %d]' % t for t in torch_positions()))
    if not args.dry_run:
        action, obj_id = rb.write_object(args.objects, NAME, tris)
        print('  %s OBJECT %d %s in %s' % (action, obj_id, NAME, args.objects))


if __name__ == '__main__':
    main()
