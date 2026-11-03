"""v1.2 lift + shaft remodel and the winch room centrepiece, modelled and baked in Blender
(headless, reproducible), in the same style as build_props.py (it reuses its helpers:
bevelled parts, dents, one lightmap UV + a baked AO x edge-wear x grime multiply map).

    blender -b -P tools/gfx_blender/build_lift_v12.py [-- --only=lift_cage,winch --samples=48 --res=512]

Writes assets/props_v12/<name>.glb + <name>_bake.png for:
  lift_cage        the lift car: angle-steel posts, bolted top frame, crosshead + sheave,
                   kick plates, round bars, mid rails, roof grate (origin: platform top centre)
  lift_rail        a 16 m T-section guide rail with bracket clips every 2 m (origin: base centre)
  lift_cables      six hoist ropes, three-strand twist, 16 m (origin: the old cable bundle centre)
  lift_counterweight  frame + stacked plates + rope shackle (origin: centre)
  shaft_bunton     an 8 m I-beam with end plates and rivets (shaft ring beams)
  shaft_column     a 16 m H-column for the shaft corners
  lift_callbox     the call box: bevelled body, recessed plate, bezels, key switch, conduit
  winch            the hoist winch: grooved drum with wound rope, side frames, finned motor,
                   gearbox, brake band, base skid (origin: base centre; 2.4 x 1.3 x 1.4 m)
Godot axes: Blender (x, y, z) -> Godot (x, z, -y) on export (export_yup).
"""
import bpy, math, os, sys, random
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "build_props.py")).read()
src = src.split("# ------------------------------------------------------------------ door panel")[0]
_argv = sys.argv
sys.argv = [a for a in sys.argv if not a.startswith("--only")]
exec(compile(src, "build_props_helpers", "exec"))
sys.argv = _argv
OUT = os.path.join(ROOT, "assets", "props_v12")
os.makedirs(OUT, exist_ok=True)
ONLY = None
for _a in _argv:
    if _a.startswith("--only="):
        ONLY = _a.split("=", 1)[1].split(",")
random.seed(12)
_finish_props = finish


def finish(o, occluders=(), res=None):
    set_mat(o, o.name + "_m")
    _finish_props(o, occluders, res)


def want(n):
    return ONLY is None or n in ONLY


def ibeam(name, length, h, w, tf, tw, axis="x", loc=(0, 0, 0)):
    """an I-section beam along `axis` (flanges top/bottom)"""
    parts = []
    if axis == "x":
        parts.append(box(name + "_t", (length, w, tf), (loc[0], loc[1], loc[2] + h / 2 - tf / 2), bevel=0.003, segs=1))
        parts.append(box(name + "_b", (length, w, tf), (loc[0], loc[1], loc[2] - h / 2 + tf / 2), bevel=0.003, segs=1))
        parts.append(box(name + "_w", (length, tw, h - 2 * tf), loc, bevel=0.0))
    elif axis == "y":
        parts.append(box(name + "_t", (w, length, tf), (loc[0], loc[1], loc[2] + h / 2 - tf / 2), bevel=0.003, segs=1))
        parts.append(box(name + "_b", (w, length, tf), (loc[0], loc[1], loc[2] - h / 2 + tf / 2), bevel=0.003, segs=1))
        parts.append(box(name + "_w", (tw, length, h - 2 * tf), loc, bevel=0.0))
    else:  # vertical H column: flanges facing +-x
        parts.append(box(name + "_f1", (tf, w, length), (loc[0] + h / 2 - tf / 2, loc[1], loc[2]), bevel=0.003, segs=1))
        parts.append(box(name + "_f2", (tf, w, length), (loc[0] - h / 2 + tf / 2, loc[1], loc[2]), bevel=0.003, segs=1))
        parts.append(box(name + "_w", (h - 2 * tf, tw, length), loc, bevel=0.0))
    return parts


def angle(name, length, s, t, loc, rot_z=0.0):
    """L-angle steel post (vertical)"""
    a = box(name + "a", (s, t, length), (loc[0], loc[1] - s / 2 + t / 2, loc[2]), bevel=0.002, segs=1)
    b2 = box(name + "b", (t, s, length), (loc[0] - s / 2 + t / 2, loc[1], loc[2]), bevel=0.002, segs=1)
    for o in (a, b2):
        o.rotation_euler.z = rot_z
    return [a, b2]


def rivets(parts, pts, r=0.012):
    for p in pts:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=6, ring_count=3, radius=r, location=p)
        o = bpy.context.active_object
        o.scale = (1, 1, 0.6) if False else (1, 1, 1)
        parts.append(o)


# ------------------------------------------------------------------ lift car
def lift_cage():
    reset()
    X, Y, top = 1.6, 1.18, 2.72    # half width, half depth, roof height above the platform
    P = []
    # corner posts (angle steel, the corner turned outwards)
    for (sx, sy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]:
        P += angle("post", top, 0.1, 0.012, (sx * (X - 0.05), sy * (Y - 0.05), top / 2), rot_z=math.atan2(-sy, -sx) + math.pi * 0.75)
    # top frame: channels all round, bolted gussets in the corners
    for sy in (1, -1):
        P.append(box("beamx", (2 * X, 0.08, 0.12), (0, sy * (Y - 0.04), top), bevel=0.006))
    for sx in (1, -1):
        P.append(box("beamy", (0.08, 2 * Y, 0.12), (sx * (X - 0.04), 0, top), bevel=0.006))
    for (sx, sy) in [(1, 1), (-1, 1), (1, -1), (-1, -1)]:
        g = box("gusset", (0.22, 0.22, 0.012), (sx * (X - 0.15), sy * (Y - 0.15), top + 0.065), bevel=0.003, segs=1)
        g.rotation_euler.z = math.pi / 4
        P.append(g)
    # crosshead (I-beam across the car) + the sheave the ropes hang from
    P += ibeam("cross", 2 * X, 0.22, 0.12, 0.018, 0.012, "x", (0, -0.85, top + 0.17))
    P.append(cyl("sheave", 0.2, 0.06, (0, -0.85, top + 0.42), rot=(0, math.pi / 2, 0), verts=20, bevel=0.006))
    P.append(torus("sheave_rim", 0.2, 0.022, (0, -0.85, top + 0.42), rot=(0, math.pi / 2, 0), maj=20, mn=6))
    for sx in (1, -1):
        P.append(box("cheek", (0.02, 0.28, 0.36), (sx * 0.06, -0.85, top + 0.36), bevel=0.004))
    P.append(cyl("axle", 0.025, 0.2, (0, -0.85, top + 0.42), rot=(0, math.pi / 2, 0), verts=10))
    # roof grate: a frame of flat bars
    for k in range(9):
        P.append(box("roofbar", (2 * X - 0.12, 0.025, 0.012), (0, -Y + 0.14 + k * (2 * Y - 0.28) / 8, top + 0.055), bevel=0.0))
    # sides (+x / -x) and back (-y): a solid lower panel (pressed steel with ribs and a
    # dented skin) up to KP, a mid rail, and round bars above it
    KP = 0.95
    for sx in (1, -1):
        kick = box("kick", (0.014, 2 * Y - 0.12, KP), (sx * (X - 0.03), 0, KP / 2), bevel=0.003, segs=1)
        dents(kick, 0.005, 0.25, subdiv=2)
        P.append(kick)
        for z in (0.22, 0.5, 0.78):
            P.append(box("rib", (0.02, 2 * Y - 0.2, 0.04), (sx * (X - 0.045), 0, z), bevel=0.008))
        for z in (KP, 1.9):
            P.append(box("rail", (0.03, 2 * Y - 0.1, 0.05), (sx * (X - 0.04), 0, z), bevel=0.006))
        n = 10
        for k in range(n):
            y = -Y + 0.17 + k * (2 * Y - 0.34) / (n - 1)
            P.append(cyl("bar", 0.011, top - KP, (sx * (X - 0.04), y, KP + (top - KP) / 2), verts=8))
    kick = box("kickb", (2 * X - 0.12, 0.014, KP), (0, -(Y - 0.03), KP / 2), bevel=0.003, segs=1)
    dents(kick, 0.005, 0.25, subdiv=2)
    P.append(kick)
    for z in (0.22, 0.5, 0.78):
        P.append(box("ribb", (2 * X - 0.2, 0.02, 0.04), (0, -(Y - 0.045), z), bevel=0.008))
    for z in (KP, 1.9):
        P.append(box("railb", (2 * X - 0.1, 0.03, 0.05), (0, -(Y - 0.04), z), bevel=0.006))
    for k in range(14):
        x = -X + 0.13 + k * (2 * X - 0.26) / 13
        P.append(cyl("barb", 0.011, top - KP, (x, -(Y - 0.04), KP + (top - KP) / 2), verts=8))
    # an inspection plate + hand-painted capacity stencil plate on the back panel
    P.append(box("plate", (0.5, 0.008, 0.3), (0.9, -(Y - 0.05), 0.62), bevel=0.003))
    # front: the low gate rail + gate posts (the hazard-striped top rail stays a game mesh)
    P.append(box("gatelow", (2 * X - 0.1, 0.04, 0.05), (0, Y - 0.03, 0.3), bevel=0.006))
    for sx in (1, -1):
        P.append(box("gatepost", (0.05, 0.05, 1.0), (sx * (X - 0.2), Y - 0.03, 0.5), bevel=0.006))
    # floor edge angle + toe plate rivets
    for sy in (1, -1):
        P.append(box("edge", (2 * X, 0.05, 0.05), (0, sy * (Y - 0.02), 0.025), bevel=0.006))
    pts = []
    for k in range(12):
        x = -X + 0.12 + k * (2 * X - 0.24) / 11
        pts.append((x, Y + 0.002, 0.025))
    rivets(P, pts, 0.01)
    join(P, "lift_cage")
    o = bpy.context.active_object
    # floor + shaft wall stand-ins so the AO has contact shadows
    occ = [box("occ_floor", (3.4, 2.6, 0.05), (0, 0, -0.025), bevel=0.0)]
    finish(o, occluders=occ)


def lift_rail():
    reset()
    L = 16.0
    P = [box("blade", (0.02, 0.09, L), (0, -0.045, L / 2), bevel=0.003, segs=1),
         box("foot", (0.14, 0.02, L), (0, 0.0, L / 2), bevel=0.003, segs=1)]
    for k in range(8):
        z = 1.0 + k * 2.0
        P.append(box("clip", (0.2, 0.03, 0.12), (0, 0.025, z), bevel=0.005))
        P.append(box("bracket", (0.06, 0.12, 0.16), (0, 0.09, z), bevel=0.005))
        for sx in (1, -1):
            P.append(cyl("bolt", 0.012, 0.03, (sx * 0.075, 0.035, z), rot=(math.pi / 2, 0, 0), verts=6))
    join(P, "lift_rail")
    finish(bpy.context.active_object, res=256)


def lift_cables():
    reset()
    L = 16.0
    P = []
    for i in range(6):
        x = -0.6 + i * 0.24
        for s in range(2):
            # two strands twisted around the rope axis (cheap; the bake adds the lay)
            bpy.ops.curve.primitive_bezier_curve_add()
            cu = bpy.context.active_object
            sp = cu.data.splines[0]
            cu.data.splines.remove(sp)
            sp = cu.data.splines.new("POLY")
            n = 40
            sp.points.add(n - 1)
            for k in range(n):
                z = L * k / (n - 1)
                a = s * 2.094 + z * 9.0 + i
                sp.points[k].co = (x + math.cos(a) * 0.009, math.sin(a) * 0.009, z, 1)
            cu.data.bevel_depth = 0.013
            cu.data.bevel_resolution = 0
            cu.data.fill_mode = "FULL"
            bpy.ops.object.convert(target="MESH")
            P.append(bpy.context.active_object)
    join(P, "lift_cables")
    o = bpy.context.active_object
    o.location = (0, 0, -L / 2)
    bpy.ops.object.transform_apply(location=True)
    finish(o, res=256)


def lift_counterweight():
    reset()
    W, H, D = 1.2, 1.4, 0.3
    P = []
    for sx in (1, -1):
        P.append(box("side", (0.08, D, H), (sx * (W / 2 - 0.04), 0, 0), bevel=0.006))
    for sz in (1, -1):
        P.append(box("cap", (W, D + 0.02, 0.1), (0, 0, sz * (H / 2 - 0.05)), bevel=0.008))
    for k in range(9):
        pl = box("plate", (W - 0.18, D - 0.05, 0.11), (0, 0, -H / 2 + 0.16 + k * 0.122), bevel=0.01)
        pl.location.x += random.uniform(-0.008, 0.008)
        P.append(pl)
    P.append(box("tie", (0.05, 0.05, H), (0, D / 2 - 0.01, 0), bevel=0.004))
    P.append(torus("shackle", 0.07, 0.02, (0, 0, H / 2 + 0.1), rot=(math.pi / 2, 0, 0), maj=14, mn=6))
    join(P, "lift_counterweight")
    finish(bpy.context.active_object, res=256)


def shaft_bunton():
    reset()
    L = 8.0
    P = ibeam("b", L, 0.24, 0.14, 0.02, 0.012, "x", (0, 0, 0))
    for sx in (1, -1):
        P.append(box("endplate", (0.016, 0.26, 0.34), (sx * (L / 2 - 0.008), 0, 0), bevel=0.003))
    pts = []
    for k in range(int(L / 0.5)):
        x = -L / 2 + 0.25 + k * 0.5
        for sy in (1, -1):
            pts.append((x, sy * 0.045, 0.121))
    rivets(P, pts, 0.011)
    join(P, "shaft_bunton")
    o = bpy.context.active_object
    dents(o, 0.002, 0.6)
    finish(o, res=256)


def shaft_column():
    reset()
    L = 16.0
    P = ibeam("c", L, 0.22, 0.2, 0.02, 0.014, "z", (0, 0, L / 2))
    for k in range(6):
        P.append(box("stiff", (0.2, 0.2, 0.014), (0, 0, 1.5 + k * 2.8), bevel=0.002, segs=1))
    join(P, "shaft_column")
    finish(bpy.context.active_object, res=256)


def lift_callbox():
    reset()
    W, H, D = 0.3, 0.45, 0.12      # the LiftPanel collider is 0.34 x 0.5 x 0.3 (unchanged)
    body = box("body", (W, D, H), (0, 0, 0), bevel=0.014, segs=3)
    apply_all(body)
    c = box("cut", (W - 0.06, 0.02, H - 0.1), (0, -D / 2, -0.01), bevel=0.0)
    apply_all(c)
    boolean(body, c)
    P = [body, box("plate", (W - 0.07, 0.006, H - 0.11), (0, -D / 2 + 0.008, -0.01), bevel=0.002, segs=1)]
    # bezel around the game's red button (at local +0.05 up), a dead second button, a key switch
    P.append(torus("bezel", 0.058, 0.009, (0, -D / 2 + 0.004, 0.05), rot=(math.pi / 2, 0, 0), maj=20, mn=6))
    P.append(torus("bezel2", 0.04, 0.008, (0, -D / 2 + 0.004, -0.09), rot=(math.pi / 2, 0, 0), maj=16, mn=6))
    P.append(cyl("deadbtn", 0.032, 0.02, (0, -D / 2 + 0.002, -0.09), rot=(math.pi / 2, 0, 0), verts=14, bevel=0.003))
    P.append(cyl("key", 0.016, 0.025, (0.09, -D / 2 + 0.0, -0.16), rot=(math.pi / 2, 0, 0), verts=10))
    P.append(box("hood", (W + 0.02, 0.07, 0.025), (0, -D / 2 - 0.02, H / 2 + 0.005), bevel=0.004))
    for sx in (1, -1):
        for sz in (1, -1):
            P.append(cyl("screw", 0.008, 0.01, (sx * (W / 2 - 0.022), -D / 2 + 0.001, sz * (H / 2 - 0.022)), rot=(math.pi / 2, 0, 0), verts=6))
    # conduit down into the floor (the post below is the old v1.0 stand)
    P.append(cyl("conduit", 0.018, 0.75, (0.1, 0.02, -H / 2 - 0.375), verts=8))
    P.append(box("gland", (0.05, 0.05, 0.04), (0.1, 0.02, -H / 2 - 0.01), bevel=0.004))
    join(P, "lift_callbox")
    finish(bpy.context.active_object, res=256)


def winch():
    reset()
    P = []
    # base skid
    for sy in (1, -1):
        P += ibeam("skid", 2.4, 0.16, 0.12, 0.016, 0.01, "x", (0, sy * 0.5, 0.08))
    for k in range(4):
        P.append(box("cross", (0.08, 1.12, 0.06), (-1.05 + k * 0.7, 0, 0.13), bevel=0.004))
    # side frames carrying the drum
    for sx in (-0.75, 0.55):
        fr = box("frame", (0.05, 0.9, 1.05), (sx, 0, 0.66), bevel=0.01)
        P.append(fr)
        P.append(cyl("bearing", 0.12, 0.12, (sx, 0, 0.8), rot=(0, math.pi / 2, 0), verts=16, bevel=0.01))
    # the drum: a barrel with flanges and rope wound in grooves
    P.append(cyl("drum", 0.36, 1.2, (-0.1, 0, 0.8), rot=(0, math.pi / 2, 0), verts=28, bevel=0.0))
    for x in (-0.68, 0.48):
        P.append(cyl("flange", 0.52, 0.035, (x, 0, 0.8), rot=(0, math.pi / 2, 0), verts=28, bevel=0.006))
    for k in range(22):
        x = -0.64 + k * 0.053
        P.append(torus("wrap", 0.382, 0.022, (x, 0, 0.8), rot=(0, math.pi / 2, 0), maj=16, mn=4))
    # rope off the top of the drum, up to the shaft wall
    P.append(cyl("rope", 0.02, 1.6, (0.3, -0.25, 1.45), rot=(math.radians(-55), 0, 0), verts=6))
    # gear + gearbox + motor with cooling fins
    P.append(cyl("gear", 0.46, 0.08, (0.66, 0, 0.8), rot=(0, math.pi / 2, 0), verts=36, bevel=0.004))
    # the gear runs inside a bolted sheet guard
    P.append(cyl("guard", 0.53, 0.14, (0.66, 0, 0.8), rot=(0, math.pi / 2, 0), verts=28, bevel=0.01))
    for k in range(10):
        a = k * math.tau / 10
        P.append(cyl("gbolt", 0.015, 0.03, (0.74, math.cos(a) * 0.48, 0.8 + math.sin(a) * 0.48), rot=(0, math.pi / 2, 0), verts=6))
    P.append(box("gearbox", (0.36, 0.5, 0.5), (0.92, 0.0, 0.48), bevel=0.02))
    P.append(cyl("motor", 0.24, 0.6, (0.95, 0.35, 0.95), rot=(0, math.pi / 2, 0), verts=20, bevel=0.01))
    for k in range(8):
        P.append(cyl("fin", 0.27, 0.012, (0.72 + k * 0.065, 0.35, 0.95), rot=(0, math.pi / 2, 0), verts=20))
    P.append(box("tbox", (0.14, 0.12, 0.1), (0.95, 0.35, 1.22), bevel=0.01))
    # brake band round the left flange
    P.append(torus("brake", 0.54, 0.02, (-0.73, 0, 0.8), rot=(0, math.pi / 2, 0), maj=28, mn=5))
    P.append(box("brakearm", (0.05, 0.05, 0.7), (-0.82, 0.45, 0.45), bevel=0.006))
    P[-1].rotation_euler.x = math.radians(20)
    join(P, "winch")
    o = bpy.context.active_object
    occ = [box("occ_floor", (4, 3, 0.05), (0, 0, -0.025), bevel=0.0)]
    finish(o, occluders=occ)


def records_fill():
    """binders and archive boxes for one 2.2 m shelf unit (4 boards at 0.17/0.77/1.37/1.97 m),
    one mesh so a whole shelf is one draw call. Origin: the shelf's floor centre, facing -y."""
    reset()
    P = []
    rnd = random.Random(5)
    for lvl_i in range(4):
        z = 0.17 + lvl_i * 0.6 + 0.02
        x = -1.0
        while x < 0.95:
            if rnd.random() < 0.3:
                w = rnd.uniform(0.32, 0.4)
                if x + w > 1.0:
                    break
                bx = box("abox", (w, 0.36, 0.26), (x + w / 2, 0.0, z + 0.13), bevel=0.008)
                bx.rotation_euler.z = rnd.uniform(-0.05, 0.05)
                P.append(bx)
                P.append(box("lid", (w + 0.01, 0.37, 0.03), (x + w / 2, 0.0, z + 0.27), bevel=0.004))
                x += w + 0.03
            else:
                n = rnd.randint(3, 7)
                for j in range(n):
                    tw = rnd.uniform(0.045, 0.07)
                    h = rnd.uniform(0.28, 0.33)
                    lean = 0.0 if j < n - 1 or rnd.random() < 0.5 else rnd.uniform(0.12, 0.3)
                    b2 = box("binder", (tw, 0.3, h), (x + tw / 2, -0.02, z + h / 2), bevel=0.004)
                    b2.rotation_euler.y = lean
                    P.append(b2)
                    x += tw + 0.004
                x += rnd.uniform(0.05, 0.15)
    join(P, "records_fill")
    o = bpy.context.active_object
    occ = []
    for lvl_i in range(4):
        occ.append(box("occ_board", (2.2, 0.45, 0.04), (0, 0, 0.15 + lvl_i * 0.6), bevel=0.0))
    occ.append(box("occ_back", (2.2, 0.02, 1.9), (0, 0.22, 1.0), bevel=0.0))
    finish(o, occluders=occ, res=512)


for name, fn in [("records_fill", records_fill), ("lift_cage", lift_cage), ("lift_rail", lift_rail), ("lift_cables", lift_cables),
                 ("lift_counterweight", lift_counterweight), ("shaft_bunton", shaft_bunton),
                 ("shaft_column", shaft_column), ("lift_callbox", lift_callbox), ("winch", winch)]:
    if want(name):
        fn()
print("DONE")
