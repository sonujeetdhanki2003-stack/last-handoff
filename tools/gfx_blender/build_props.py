"""v1.1 hero props, modelled and baked in Blender (headless, reproducible).

    blender -b -P tools/gfx_blender/build_props.py [-- --only=door,locker --samples=48 --res=512]

Writes assets/props_v11/<name>.glb plus <name>_bake.png (R = baked ambient occlusion,
G = edge wear, B = grime/drip mask) for: door_panel, door_jamb, door_header, locker_body,
locker_door, lamp_fixture, vent_grate, pipe_flange, pipe_hanger.
Each mesh is authored at the exact size the game builds it (door 1.6 x 2.4 x 0.12, locker
0.62 x 1.95 x 0.55 ...), origin where the game's node sits, so collision, interaction and
gameplay sizes are untouched (the game scales a door mesh by width/1.6, height/2.4).
UV layer 0 = box projection (unused by the triplanar materials), UV layer 1 = a non-overlapping
lightmap unwrap the bake map lives on (Godot: UV2).
"""
import bpy, bmesh, math, os, sys, random
import numpy as np
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "props_v11")
os.makedirs(OUT, exist_ok=True)
ARGS = {}
if "--" in sys.argv:
    for a in sys.argv[sys.argv.index("--") + 1:]:
        if a.startswith("--") and "=" in a:
            k, v = a[2:].split("=", 1)
            ARGS[k] = v
ONLY = ARGS.get("only", "").split(",") if ARGS.get("only") else None
SAMPLES = int(ARGS.get("samples", "48"))
RES = int(ARGS.get("res", "512"))
random.seed(11)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False
    w = bpy.data.worlds.new("W")
    w.color = (1, 1, 1)
    sc.world = w


def box(name, size, loc, bevel=0.004, segs=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        m = o.modifiers.new("bev", "BEVEL")
        m.width = bevel
        m.segments = segs
        m.limit_method = "ANGLE"
        m.harden_normals = False
    return o


def cyl(name, r, depth, loc, rot=(0, 0, 0), verts=16, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if bevel > 0:
        m = o.modifiers.new("bev", "BEVEL")
        m.width = bevel
        m.segments = 1
        m.limit_method = "ANGLE"
    return o


def torus(name, R, r, loc, rot=(0, 0, 0), maj=24, mn=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=maj, minor_segments=mn, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def boolean(target, cutter, op="DIFFERENCE"):
    m = target.modifiers.new("b_" + cutter.name, "BOOLEAN")
    m.object = cutter
    m.operation = op
    m.solver = "EXACT"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def dents(o, strength=0.004, scale=0.35, subdiv=0):
    """hammered, dented sheet metal: a low-frequency noise displacement"""
    if subdiv:
        s = o.modifiers.new("sub", "SUBSURF")
        s.levels = subdiv
        s.subdivision_type = "SIMPLE"
    t = bpy.data.textures.new(o.name + "_dent", "CLOUDS")
    t.noise_scale = scale
    t.noise_depth = 1
    d = o.modifiers.new("dent", "DISPLACE")
    d.texture = t
    d.strength = strength
    d.mid_level = 0.5
    d.texture_coords = "GLOBAL"


def apply_all(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(objs, name):
    for o in objs:
        apply_all(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def set_mat(o, name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    o.data.materials.clear()
    o.data.materials.append(m)


def finish(o, occluders=(), res=None):
    """UVs, bake AO + edge wear + grime into one RGB map, export glb."""
    res = res or RES
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0002)
    bpy.ops.object.mode_set(mode="OBJECT")
    me = o.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    me.uv_layers.active = me.uv_layers["UVMap"]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.cube_project(cube_size=1.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    me.uv_layers.new(name="Bake")
    me.uv_layers.active = me.uv_layers["Bake"]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.uv.pack_islands(margin=0.012)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in me.polygons:
        p.use_smooth = True
    try:
        me.set_sharp_from_angle(angle=math.radians(40))
    except Exception:
        pass
    # 1) Cycles ambient-occlusion bake  2) an emission bake of a drip/grime noise in object space
    #    -> combined here into ONE sRGB multiplier map: AO darkening x grime tint (game: detail albedo, MUL, UV2)
    sc = bpy.context.scene
    sc.render.bake.margin = 6
    sc.world.light_settings.distance = 0.35
    imgs = {}
    for kind in ("AO", "EMIT"):
        img = bpy.data.images.new(o.name + "_" + kind, res, res, alpha=False, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        mat = bpy.data.materials.new(o.name + "_bake_" + kind)
        mat.use_nodes = True
        nt = mat.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        outn = nt.nodes.new("ShaderNodeOutputMaterial")
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(em.outputs[0], outn.inputs["Surface"])
        if kind == "EMIT":
            tc = nt.nodes.new("ShaderNodeTexCoord")
            mp = nt.nodes.new("ShaderNodeMapping")
            mp.inputs["Scale"].default_value = (7.0, 7.0, 0.45)      # long vertical streaks
            nz = nt.nodes.new("ShaderNodeTexNoise")
            nz.inputs["Scale"].default_value = 5.0
            nz.inputs["Detail"].default_value = 6.0
            nz.inputs["Roughness"].default_value = 0.6
            nz2 = nt.nodes.new("ShaderNodeTexNoise")                  # blotches
            nz2.inputs["Scale"].default_value = 3.0
            nz2.inputs["Detail"].default_value = 3.0
            cmb = nt.nodes.new("ShaderNodeCombineXYZ")
            nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
            nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
            nt.links.new(tc.outputs["Object"], nz2.inputs["Vector"])
            nt.links.new(nz.outputs["Fac"], cmb.inputs[0])
            nt.links.new(nz2.outputs["Fac"], cmb.inputs[1])
            nt.links.new(tc.outputs["Object"], cmb.inputs[2]) if False else None
            nt.links.new(cmb.outputs[0], em.inputs["Color"])
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nt.nodes.active = tex
        keep = [sl.material for sl in o.material_slots]
        for i in range(len(o.material_slots)):
            o.material_slots[i].material = mat
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.bake(type=kind)
        for i, m in enumerate(keep):
            o.material_slots[i].material = m
        imgs[kind] = np.array(img.pixels[:], dtype=np.float32).reshape(res, res, 4)
    ao = np.clip(imgs["AO"][..., 0], 0, 1)
    streak = np.clip((imgs["EMIT"][..., 0] - 0.48) / 0.22, 0, 1)
    blot = np.clip((imgs["EMIT"][..., 1] - 0.45) / 0.25, 0, 1)
    grime = np.clip((1.0 - ao) * 0.8 + streak * 0.35 + blot * 0.18, 0, 1)
    mulv = (0.2 + 0.8 * ao ** 1.6)
    tint = np.array([0.62, 0.55, 0.45])          # brown-black oily dirt
    rgb = mulv[..., None] * (1.0 - grime[..., None] * (1.0 - tint))
    rgb = np.clip(rgb, 0, 1) ** (1 / 2.2)        # store sRGB
    out = bpy.data.images.new(o.name + "_bake", res, res, alpha=False)
    px = np.ones((res, res, 4), dtype=np.float32)
    px[..., :3] = rgb
    out.pixels[:] = px.ravel()
    out.filepath_raw = os.path.join(OUT, o.name + "_bake.png")
    out.file_format = "PNG"
    out.save()
    for oc in occluders:
        bpy.data.objects.remove(oc, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    me.uv_layers.active = me.uv_layers["UVMap"]
    path = os.path.join(OUT, o.name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_texcoords=True, export_normals=True, export_materials="PLACEHOLDER",
                              export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    print("PROP", o.name, "tris", tris, "->", path)


def want(n):
    return ONLY is None or n in ONLY


# ------------------------------------------------------------------ door panel 1.6 x 2.4 x 0.12
def door_panel():
    reset()
    W, H, D = 1.6, 2.4, 0.12
    slab = box("door_panel", (W, D, H), (0, 0, H / 2), bevel=0.012, segs=2)   # blender Y = depth
    apply_all(slab)
    # recessed panels on both faces (pressed steel), the window opening stays solid (glass is a game mesh)
    for sy in (1, -1):
        for (cx, cz, w, h) in [(0, 0.62, 1.22, 0.8), (0, 1.75, 0.82, 0.55)]:
            c = box("cut", (w, 0.03, h), (cx, sy * (D / 2), cz), bevel=0.0)
            apply_all(c)
            boolean(slab, c)
    parts = [slab]
    # pressed ribs in the lower recess
    for sy in (1, -1):
        for k in range(4):
            parts.append(box("rib", (1.1, 0.012, 0.035), (0, sy * (D / 2 - 0.01), 0.36 + k * 0.17), bevel=0.005))
        # window frame (raised steel surround for the glass)
        fw, fh = 0.64 + 0.09, 0.35 + 0.09
        for (sx, sz, x, z) in [(fw, 0.045, 0, 1.75 + fh / 2), (fw, 0.045, 0, 1.75 - fh / 2), (0.045, fh, fw / 2, 1.75), (0.045, fh, -fw / 2, 1.75)]:
            parts.append(box("wf", (sx, 0.03, sz), (x, sy * (D / 2 + 0.005), z), bevel=0.006))
        # kick plate + its screws
        parts.append(box("kick", (1.5, 0.008, 0.24), (0, sy * (D / 2 + 0.002), 0.14), bevel=0.003))
        for x in (-0.7, 0.0, 0.7):
            parts.append(cyl("screw", 0.011, 0.012, (x, sy * (D / 2 + 0.008), 0.235), rot=(math.pi / 2, 0, 0), verts=6))
        # rivets around the edge
        for i in range(9):
            z = 0.12 + i * (H - 0.24) / 8
            for x in (-W / 2 + 0.045, W / 2 - 0.045):
                parts.append(cyl("rivet", 0.012, 0.012, (x, sy * (D / 2 + 0.004), z), rot=(math.pi / 2, 0, 0), verts=6))
        # pull handle (a bent bar on stand-offs)
        parts.append(cyl("bar", 0.016, 0.42, (W / 2 - 0.16, sy * (D / 2 + 0.06), 1.05), verts=10, bevel=0.0))
        for z in (0.86, 1.24):
            parts.append(cyl("stand", 0.014, 0.06, (W / 2 - 0.16, sy * (D / 2 + 0.03), z), rot=(math.pi / 2, 0, 0), verts=10))
    o = join(parts, "door_panel")
    dents(o, 0.0035, 0.4)
    apply_all(o)
    set_mat(o, "panel")
    finish(o)


def door_jamb():
    # vertical frame post: 0.12 wide, unit height (scaled to height + t in game), 0.34 deep, origin bottom centre
    reset()
    parts = [box("post", (0.12, 0.34, 1.0), (0, 0, 0.5), bevel=0.01, segs=2)]
    # chamfered inner rebate + a rubber gasket strip + bolts
    parts.append(box("rebate", (0.03, 0.06, 1.0), (0.06, 0, 0.5), bevel=0.004))
    for sy in (1, -1):
        parts.append(box("flange", (0.16, 0.02, 1.0), (0, sy * 0.175, 0.5), bevel=0.004))
        for i in range(6):
            parts.append(cyl("bolt", 0.014, 0.02, (-0.035, sy * 0.188, 0.08 + i * 0.168), rot=(math.pi / 2, 0, 0), verts=6, bevel=0.003))
    o = join(parts, "door_jamb")
    set_mat(o, "frame")
    finish(o, res=256)


def door_header():
    # horizontal header: unit width (scaled to width + 2t), 0.12 tall, 0.34 deep, origin centre
    reset()
    parts = [box("beam", (1.0, 0.34, 0.12), (0, 0, 0), bevel=0.01, segs=2)]
    for sy in (1, -1):
        parts.append(box("flange", (1.0, 0.02, 0.16), (0, sy * 0.175, 0), bevel=0.004))
        for i in range(5):
            parts.append(cyl("bolt", 0.014, 0.02, (-0.4 + i * 0.2, sy * 0.188, 0.035), rot=(math.pi / 2, 0, 0), verts=6, bevel=0.003))
    o = join(parts, "door_header")
    set_mat(o, "frame")
    finish(o, res=256)


# ------------------------------------------------------------------ locker 0.62 x 1.95 x 0.55
def locker():
    reset()
    w, d, h = 0.62, 0.55, 1.95
    # carcass (open front), origin bottom centre, front face at +d/2 (Godot +Z = Blender -Y)
    parts = []
    t = 0.025
    parts.append(box("back", (w, t, h), (0, d / 2 - t / 2, h / 2), bevel=0.004))
    for sx in (1, -1):
        parts.append(box("side", (t, d, h), (sx * (w / 2 - t / 2), 0, h / 2), bevel=0.006))
        # pressed stiffening ribs on the sides
        for k in range(3):
            parts.append(box("srib", (0.006, d * 0.7, 0.03), (sx * (w / 2 + 0.002), 0, 0.5 + k * 0.5), bevel=0.003))
    parts.append(box("top", (w + 0.02, d + 0.02, 0.04), (0, 0, h - 0.02), bevel=0.008, segs=2))
    parts.append(box("plinth", (w - 0.02, d - 0.04, 0.08), (0, 0.01, 0.04), bevel=0.004))
    parts.append(box("shelf", (w - 2 * t, d - t, 0.02), (0, 0, 1.62), bevel=0.003))
    parts.append(box("hook_rail", (w - 2 * t, 0.02, 0.02), (0, d / 2 - 0.05, 1.5), bevel=0.003))
    # front frame lip
    parts.append(box("lip_t", (w, 0.02, 0.04), (0, -d / 2 + 0.01, h - 0.06), bevel=0.004))
    parts.append(box("lip_b", (w, 0.02, 0.06), (0, -d / 2 + 0.01, 0.1), bevel=0.004))
    body = join(parts, "locker_body")
    dents(body, 0.004, 0.25)
    apply_all(body)
    set_mat(body, "steel")
    finish(body)

    reset()
    # door: hinge edge at x = 0, spans +x to w, outer face at -y (Godot +z)
    dw, dh, dt = w, h - 0.04, 0.025
    slab = box("door", (dw, dt, dh), (dw / 2, 0, dh / 2 + 0.02), bevel=0.006, segs=2)
    apply_all(slab)
    # louvres: real angled slats over shallow slots (still opaque, as the game's door is)
    for k in range(5):
        z = 1.42 + k * 0.045
        c = box("slot", (dw * 0.6, 0.03, 0.026), (dw / 2, -dt / 2, z), bevel=0.0)
        apply_all(c)
        boolean(slab, c)
    parts = [slab]
    # a dark backing plate behind the slots, inside the door (you still can't see through)
    parts.append(box("backing", (dw * 0.64, 0.004, 0.26), (dw / 2, dt / 2 - 0.002, 1.51), bevel=0.0))
    for k in range(5):
        z = 1.42 + k * 0.045
        s = box("slat", (dw * 0.6, 0.004, 0.03), (dw / 2, -dt / 2 - 0.006, z + 0.006), bevel=0.0015)
        s.rotation_euler = (math.radians(-35), 0, 0)
        parts.append(s)
    for k in range(3):   # lower vents
        z = 0.18 + k * 0.045
        c = box("slot", (dw * 0.6, 0.012, 0.024), (dw / 2, -dt / 2, z), bevel=0.0)
        apply_all(c)
        boolean(slab, c)
    # handle housing + lift latch, name-card frame, three hinges, a vertical pressed rib
    parts.append(box("latch_plate", (0.05, 0.012, 0.2), (dw - 0.07, -dt / 2 - 0.006, 1.05), bevel=0.004))
    parts.append(box("latch", (0.03, 0.03, 0.12), (dw - 0.07, -dt / 2 - 0.02, 1.05), bevel=0.006))
    parts.append(cyl("lock", 0.012, 0.02, (dw - 0.07, -dt / 2 - 0.02, 1.2), rot=(math.pi / 2, 0, 0), verts=12, bevel=0.003))
    parts.append(box("card", (0.14, 0.006, 0.07), (dw / 2, -dt / 2 - 0.003, 1.72), bevel=0.002))
    parts.append(box("card_in", (0.12, 0.004, 0.05), (dw / 2, -dt / 2 - 0.006, 1.72), bevel=0.0))
    for z in (0.25, 0.95, 1.7):
        parts.append(cyl("hinge", 0.011, 0.1, (0.0, -dt / 2, z), verts=10, bevel=0.002))
    for x in (0.12, dw - 0.18):
        parts.append(box("vrib", (0.03, 0.006, 1.0), (x, -dt / 2 - 0.002, 0.8), bevel=0.003))
    door = join(parts, "locker_door")
    dents(door, 0.003, 0.2)
    apply_all(door)
    set_mat(door, "steel")
    finish(door)


# ------------------------------------------------------------------ fluorescent batten fixture
def lamp_fixture():
    reset()
    L = 1.25
    parts = [box("housing", (L, 0.24, 0.05), (0, 0, 0.055), bevel=0.008, segs=2)]
    # reflector channel (inverted V) under the housing
    for sy in (1, -1):
        r = box("refl", (L - 0.06, 0.13, 0.006), (0, sy * 0.06, 0.02), bevel=0.0)
        r.rotation_euler = (sy * math.radians(18), 0, 0)
        parts.append(r)
    for sx in (1, -1):
        parts.append(box("endcap", (0.04, 0.25, 0.09), (sx * (L / 2 - 0.02), 0, 0.02), bevel=0.008, segs=2))
        # tube sockets
        for sy in (1, -1):
            parts.append(box("socket", (0.03, 0.04, 0.04), (sx * (L / 2 - 0.055), sy * 0.055, -0.02), bevel=0.004))
    # wire guard cage over the tubes
    for i in range(9):
        x = -L / 2 + 0.1 + i * (L - 0.2) / 8
        tor = torus("cage", 0.115, 0.004, (x, 0, 0.0), rot=(0, math.pi / 2, 0), maj=12, mn=3)
        bm = bmesh.new()
        bm.from_mesh(tor.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > 0.035 and False], context="VERTS")
        bm.to_mesh(tor.data)
        bm.free()
        tor.scale = (1, 1, 0.7)
        parts.append(tor)
    for sy in (-0.09, 0.0, 0.09):
        parts.append(cyl("cage_rail", 0.004, L - 0.18, (0, sy, -0.075 if sy == 0.0 else -0.05), rot=(0, math.pi / 2, 0), verts=6))
    # hanger rods with ceiling cups and a junction box
    for sx in (-0.45, 0.45):
        parts.append(cyl("rod", 0.006, 0.3, (sx, 0, 0.22), verts=8))
        parts.append(cyl("cup", 0.03, 0.02, (sx, 0, 0.37), verts=12, bevel=0.004))
        parts.append(cyl("nut", 0.012, 0.015, (sx, 0, 0.088), verts=6))
    parts.append(box("jbox", (0.12, 0.08, 0.05), (0, 0, 0.105), bevel=0.006))
    o = join(parts, "lamp_fixture")
    set_mat(o, "metal")
    finish(o, res=256)


# ------------------------------------------------------------------ ceiling vent grate (0.9 x 0.9)
def vent_grate():
    reset()
    S = 0.9
    parts = []
    # frame flange flush to the ceiling (top at z = 0), a duct collar above it
    for (sx, sy, x, y) in [(S, 0.08, 0, S / 2 - 0.04), (S, 0.08, 0, -S / 2 + 0.04), (0.08, S, S / 2 - 0.04, 0), (0.08, S, -S / 2 + 0.04, 0)]:
        parts.append(box("frame", (sx, sy, 0.03), (x, y, -0.015), bevel=0.006, segs=2))
    for (sx, sy, x, y) in [(S - 0.16, 0.02, 0, S / 2 - 0.09), (S - 0.16, 0.02, 0, -S / 2 + 0.09), (0.02, S - 0.16, S / 2 - 0.09, 0), (0.02, S - 0.16, -S / 2 + 0.09, 0)]:
        parts.append(box("collar", (sx, sy, 0.25), (x, y, 0.11), bevel=0.003))
    # louvred blades, angled, one of them bent where something forced its way out
    n = 9
    for i in range(n):
        y = -S / 2 + 0.12 + i * (S - 0.24) / (n - 1)
        b = box("blade", (S - 0.18, 0.004, 0.06), (0, y, -0.02), bevel=0.0015)
        ang = math.radians(40)
        if i in (5, 6):
            ang = math.radians(75 + i * 4)
        b.rotation_euler = (ang, 0, 0)
        parts.append(b)
    for sx in (1, -1):
        for sy in (1, -1):
            parts.append(cyl("screw", 0.01, 0.012, (sx * (S / 2 - 0.04), sy * (S / 2 - 0.04), -0.032), verts=8, bevel=0.003))
    o = join(parts, "vent_grate")
    set_mat(o, "grate")
    finish(o, res=256)


# ------------------------------------------------------------------ pipe details (unit radius, scaled to the pipe)
def pipe_flange():
    reset()
    # axis along Blender Z = glTF/Godot Y (the CylinderMesh axis), unit pipe radius 1.0
    parts = [cyl("ring", 1.45, 0.35, (0, 0, 0), rot=(0, 0, 0), verts=16, bevel=0.06)]
    parts.append(cyl("ring2", 1.35, 0.5, (0, 0, 0), verts=16))
    for i in range(6):
        a = i * math.tau / 6
        parts.append(cyl("bolt", 0.12, 0.62, (math.cos(a) * 1.25, math.sin(a) * 1.25, 0), verts=5))
    o = join(parts, "pipe_flange")
    set_mat(o, "pipe")
    finish(o, res=128)


def pipe_hanger():
    reset()
    # clamp around a unit pipe (axis along glTF Y in pipe space -> placed by the game), threaded rod up
    parts = [torus("clamp", 1.1, 0.12, (0, 0, 0), rot=(math.pi / 2, 0, 0), maj=14, mn=4)]
    for sx in (1, -1):
        parts.append(box("ear", (0.35, 0.3, 0.12), (sx * 0.0, 0, 1.15), bevel=0.03))
    parts.append(cyl("rod", 0.08, 3.0, (0, 0, 2.6), verts=8))
    parts.append(cyl("nut", 0.16, 0.15, (0, 0, 1.33), verts=6))
    o = join(parts, "pipe_hanger")
    set_mat(o, "dark")
    finish(o, res=128)


for name, fn in [("door", lambda: (door_panel(), door_jamb(), door_header())), ("locker", locker),
                 ("lamp", lamp_fixture), ("vent", vent_grate), ("pipe", lambda: (pipe_flange(), pipe_hanger()))]:
    if want(name):
        fn()
print("PROPS DONE")
