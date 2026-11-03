"""v1.1: the Keeper's high-poly sculpt + bake, in Blender (headless, reproducible).

    blender -b -P tools/gfx_blender/keeper_sculpt_bake.py [-- --levels=3 --res=1024 --samples=64]

1. Imports the game Keeper (assets/characters/keeper/KeeperAnimated.glb, rig at rest).
2. Builds a high-poly copy of the body (3 levels of Catmull-Clark subdivision, ~0.6M faces) and sculpts it with
   displacement: the ribcage, sternum, collarbones, vertebrae and scapulae (the same anatomy
   field tools/keeper_sculpt/sculpt_keeper.py painted into v1.0's texture, now as real relief),
   sinew striations along every limb bone, skin folds at the elbows, knees and neck,
   ridged veins, wrinkles and pores.
3. Bakes, onto the game mesh's own UVs (the rig, weights and all 13 animations are untouched):
   tangent-space normal (selected-to-active), ambient occlusion, and cavity.
4. Writes assets/characters/keeper/T_Keeper_Normal_v11.png (the bake merged with v1.0's muscle
   normal), T_Keeper_ORM_v11.png (R = AO, G = cavity) and T_Keeper_BaseColor_v11.png
   (v1.0 colour with cavity grime in the creases).
"""
import bpy, bmesh, os, sys, math, time
import numpy as np
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
KD = os.path.join(ROOT, "assets", "characters", "keeper")
ARGS = {}
if "--" in sys.argv:
    for a in sys.argv[sys.argv.index("--") + 1:]:
        if a.startswith("--") and "=" in a:
            k, v = a[2:].split("=", 1)
            ARGS[k] = v
LEVELS = int(ARGS.get("levels", "3"))
RES = int(ARGS.get("res", "1024"))
SAMPLES = int(ARGS.get("samples", "64"))
T0 = time.time()
def log(*a):
    print("KSB %6.1fs" % (time.time() - T0), *a, flush=True)


# ---------------------------------------------------------------- anatomy field (from sculpt_keeper.py)
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return (h & 0xffff) / 65535.0


def vnoise(p, freq, seed=0):
    q = p * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * _hash(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def fbm(p, freq, oct=4, seed=0):
    s = 0; a = 1; t = 0
    for o in range(oct):
        s = s + a * vnoise(p, freq * (2 ** o), seed + o * 17); t += a; a *= 0.5
    return s / t


def anatomy(O):
    x = O[..., 0]; y = O[..., 1]; z = O[..., 2]; ax = np.abs(x)
    h = np.zeros(x.shape)
    torso = smoothstep(0.02, 0.05, ax) * (1 - smoothstep(0.17, 0.2, ax)) * smoothstep(1.08, 1.14, y) * (1 - smoothstep(1.36, 1.42, y))
    front_side = smoothstep(-0.09, -0.02, z)
    for k in range(8):
        yk = 1.355 - k * 0.03 - 0.55 * ax ** 1.35 + 0.04 * smoothstep(0.0, 0.12, -z)
        h += 0.9 * np.exp(-((y - yk) / 0.0085) ** 2)
    h *= torso * front_side
    vcut = smoothstep(0.0, 0.03, ax - (1.30 - y) * 0.9)
    h *= np.where(z > 0.06, vcut, 1.0)
    h += 0.7 * np.exp(-(x / 0.012) ** 2) * smoothstep(1.22, 1.26, y) * (1 - smoothstep(1.42, 1.45, y)) * smoothstep(0.05, 0.09, z)
    cl = 1.46 + 0.12 * ax
    h += 0.9 * np.exp(-((y - cl) / 0.012) ** 2) * smoothstep(0.02, 0.04, ax) * (1 - smoothstep(0.17, 0.2, ax)) * smoothstep(0.0, 0.05, z)
    vb = 0.5 + 0.5 * np.cos((y - 1.0) / 0.031 * 2 * np.pi)
    h += 0.8 * np.exp(-(x / 0.018) ** 2) * vb ** 2 * smoothstep(0.95, 1.0, y) * (1 - smoothstep(1.55, 1.6, y)) * smoothstep(-0.02, -0.07, z)
    h += 0.5 * np.exp(-((ax - 0.1 - (1.45 - y) * 0.15) / 0.012) ** 2) * smoothstep(1.28, 1.32, y) * (1 - smoothstep(1.46, 1.5, y)) * smoothstep(-0.03, -0.08, z)
    return h


# ---------------------------------------------------------------- scene
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(KD, "KeeperAnimated.glb"))
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
arm.data.pose_position = "REST"
for o in list(bpy.data.objects):
    if o.type == "MESH" and not o.name.startswith("KeeperBody"):
        bpy.data.objects.remove(o, do_unlink=True)
low = [o for o in bpy.data.objects if o.name.startswith("KeeperBody")][0]
bpy.context.view_layer.update()

# high-poly copy at rest, unparented
hi = low.copy()
hi.data = low.data.copy()
hi.name = "KeeperHi"
bpy.context.scene.collection.objects.link(hi)
for m in list(hi.modifiers):
    hi.modifiers.remove(m)
mw = low.matrix_world.copy()
hi.parent = None
hi.matrix_world = mw
bpy.context.view_layer.objects.active = hi
sub = hi.modifiers.new("sub", "SUBSURF")
sub.levels = LEVELS
sub.render_levels = LEVELS
sub.subdivision_type = "CATMULL_CLARK"
sub.boundary_smooth = "PRESERVE_CORNERS"
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True)
bpy.ops.object.modifier_apply(modifier="sub")
me = hi.data
n = len(me.vertices)
log("hi verts", n, "faces", len(me.polygons))

co = np.empty(n * 3, np.float32); me.vertices.foreach_get("co", co); co = co.reshape(n, 3).astype(np.float64)
me.update()
nr = np.empty(n * 3, np.float32); me.vertices.foreach_get("normal", nr); nr = nr.reshape(n, 3).astype(np.float64)
M = np.array(mw)
W = co @ M[:3, :3].T + M[:3, 3]                     # blender world (Z up)
O = np.stack([W[:, 0], W[:, 2], -W[:, 1]], 1)       # game / glTF space (Y up)
NW = nr @ M[:3, :3].T
NW /= np.linalg.norm(NW, axis=1, keepdims=True) + 1e-12
log("height range", O[:, 1].min(), O[:, 1].max())

# --- 1. skeleton anatomy as real relief
d = 0.0042 * anatomy(O)

# --- 2. sinew: striations running along every limb bone, ropy and uneven
bones = {b.name: (np.array(arm.matrix_world @ b.head_local), np.array(arm.matrix_world @ b.tail_local)) for b in arm.data.bones}
limb = [b for b in bones if any(k in b for k in ("upperarm", "lowerarm", "thigh", "calf", "neck", "hand_"))]
best = np.full(n, 1e9); along = np.zeros(n); ang = np.zeros(n); seglen = np.ones(n)
for bn in limb:
    a, b = bones[bn]
    ab = b - a
    L = np.linalg.norm(ab) + 1e-9
    u = ab / L
    t = np.clip(((W - a) @ u) / L, 0, 1)
    p = a + t[:, None] * ab
    dv = W - p
    dist = np.linalg.norm(dv, axis=1)
    sel = dist < best
    # angle around the bone, from a stable reference axis
    ref = np.cross(u, [0, 0, 1.0]) if abs(u[2]) < 0.9 else np.cross(u, [1.0, 0, 0])
    ref /= np.linalg.norm(ref)
    ref2 = np.cross(u, ref)
    an = np.arctan2(dv @ ref2, dv @ ref)
    best = np.where(sel, dist, best); along = np.where(sel, t * L, along); ang = np.where(sel, an, ang); seglen = np.where(sel, L, seglen)
onlimb = (best < 0.09).astype(np.float64)
mid = smoothstep(0.0, 0.12, along / seglen) * (1 - smoothstep(0.85, 1.0, along / seglen))
warp = fbm(O, 6.0, 2, 41) * 2.5
fib = np.abs(np.sin(ang * 9.0 + warp))              # cords running down the limb
fib = 1 - fib                                       # thin sharp ridges between soft grooves
fib = fib ** 5
cord = fbm(np.stack([ang * 0.6, along * 1.5, best * 10], 1), 3.0, 2, 77)
d += 0.0013 * fib * mid * onlimb * (0.4 + cord)

# --- 3. skin folds where joints bend: elbows, knees, the neck base, the waist
for bn, rad, wl, amp in [("lowerarm_l", 0.07, 0.009, 0.0016), ("lowerarm_r", 0.07, 0.009, 0.0016), ("calf_l", 0.08, 0.011, 0.0016),
                         ("calf_r", 0.08, 0.011, 0.0016), ("neck_01", 0.09, 0.01, 0.0018), ("spine_01", 0.12, 0.014, 0.0012), ("hand_l", 0.05, 0.006, 0.0009), ("hand_r", 0.05, 0.006, 0.0009)]:
    if bn not in bones:
        continue
    a, b = bones[bn]
    u = (b - a) / (np.linalg.norm(b - a) + 1e-9)
    s = (W - a) @ u
    r = np.linalg.norm((W - a) - s[:, None] * u, axis=1)
    fall = np.exp(-(s / rad) ** 2) * (r < rad * 1.6)
    wob = fbm(O, 9.0, 2, 13) * 0.02
    d += amp * fall * (np.cos((s + wob) / wl * 2 * np.pi) * 0.5 + 0.5) ** 2 - amp * 0.5 * fall

# --- 4. ridged veins, crêpe wrinkles, pores
vn = 1 - np.abs(fbm(O, 8.0, 3, 9) * 2 - 1)
d += 0.0011 * smoothstep(0.86, 0.97, vn)
wr = 1 - np.abs(fbm(O * np.array([1.0, 2.6, 1.0]), 28.0, 2, 21) * 2 - 1)
d -= 0.0005 * smoothstep(0.7, 0.95, wr)
d += 0.00018 * (fbm(O, 140.0, 2, 3) - 0.5)
log("disp mm min/max", d.min() * 1000, d.max() * 1000)

Wn = W + NW * d[:, None]
Mi = np.linalg.inv(M)
cn = Wn @ Mi[:3, :3].T + Mi[:3, 3]
me.vertices.foreach_set("co", cn.astype(np.float32).ravel())
me.update()
for p in me.polygons:
    p.use_smooth = True
log("sculpted")

# ---------------------------------------------------------------- bakes onto the game mesh's UVs
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES
sc.cycles.use_denoising = False
w = bpy.data.worlds.new("W"); w.color = (1, 1, 1); sc.world = w
w.light_settings.distance = 0.12
sc.render.bake.use_selected_to_active = True
sc.render.bake.cage_extrusion = 0.012
sc.render.bake.max_ray_distance = 0.03
sc.render.bake.margin = 8
# the low mesh at rest: drop its armature deform so it lines up with the sculpt
for m in list(low.modifiers):
    low.modifiers.remove(m)
low.parent = None
low.matrix_world = mw
hi.data.materials.clear()
hm = bpy.data.materials.new("hi_cav")
hm.use_nodes = True
nt = hm.node_tree
for x in list(nt.nodes):
    nt.nodes.remove(x)
geo = nt.nodes.new("ShaderNodeNewGeometry")
rmp = nt.nodes.new("ShaderNodeMapRange")
rmp.inputs["From Min"].default_value = 0.44
rmp.inputs["From Max"].default_value = 0.56
em = nt.nodes.new("ShaderNodeEmission")
outn = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(geo.outputs["Pointiness"], rmp.inputs["Value"])
nt.links.new(rmp.outputs["Result"], em.inputs["Color"])
nt.links.new(em.outputs[0], outn.inputs["Surface"])
hi.data.materials.append(hm)


def bake(kind, name):
    img = bpy.data.images.new(name, RES, RES, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new("low_" + name)
    mat.use_nodes = True
    t = mat.node_tree.nodes.new("ShaderNodeTexImage")
    t.image = img
    mat.node_tree.nodes.active = t
    low.data.materials.clear()
    low.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    hi.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    if kind == "NORMAL":
        sc.render.bake.normal_space = "TANGENT"
    bpy.ops.object.bake(type=kind)
    log("baked", kind)
    return np.array(img.pixels[:], np.float32).reshape(RES, RES, 4)[::-1]   # top row first (PIL order)


nb = bake("NORMAL", "kn")
aob = bake("AO", "kao")
cvb = bake("EMIT", "kcav")


# ---------------------------------------------------------------- merge with v1.0's maps, write PNGs
def load_png(path):
    im = bpy.data.images.load(path)
    im.colorspace_settings.name = "Non-Color"
    w_, h_ = im.size
    a = np.array(im.pixels[:], np.float32).reshape(h_, w_, 4)[::-1]
    if (w_, h_) != (RES, RES):
        ys = (np.arange(RES) * h_ / RES).astype(int); xs = (np.arange(RES) * w_ / RES).astype(int)
        a = a[ys][:, xs]
    return a


def save_png(arr, path, srgb=False):
    h_, w_ = arr.shape[:2]
    im = bpy.data.images.new(os.path.basename(path), w_, h_, alpha=False)
    if not srgb:
        im.colorspace_settings.name = "Non-Color"
    px = np.ones((h_, w_, 4), np.float32)
    px[..., :3] = arr[..., :3]
    im.pixels[:] = px[::-1].ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()


# baked texels: where the bake wrote something (outside the UV islands it stays at the clear colour)
base_n = load_png(os.path.join(KD, "T_Keeper_Normal.png"))[..., :3] * 2 - 1
det = nb[..., :3] * 2 - 1
# whiteout/RNM blend: v1.0's muscle + painted detail at 60 % under the sculpt
t_ = base_n.copy(); t_[..., :2] *= 0.6; t_[..., 2] = np.maximum(t_[..., 2], 0.2)
t_ /= np.linalg.norm(t_, axis=-1, keepdims=True)
tt = t_ + np.array([0, 0, 1.0])
uu = det * np.array([-1, -1, 1.0])
r_ = tt * np.sum(tt * uu, -1, keepdims=True) / tt[..., 2:3] - uu
r_ /= np.linalg.norm(r_, axis=-1, keepdims=True) + 1e-9
save_png(r_ * 0.5 + 0.5, os.path.join(KD, "T_Keeper_Normal_v11.png"))
ao = np.clip(aob[..., 0], 0, 1)
cav = np.clip(cvb[..., 0], 0, 1)          # 0 = crease, 1 = ridge
orm = np.stack([ao, cav, np.zeros_like(ao)], -1)
save_png(orm, os.path.join(KD, "T_Keeper_ORM_v11.png"))
col = load_png(os.path.join(KD, "T_Keeper_BaseColor.png"))[..., :3]   # stays sRGB-encoded values
lin = col ** 2.2
crease = np.clip(1 - cav * 2.0, 0, 1)[..., None]
ridge = np.clip(cav * 2.0 - 1.0, 0, 1)[..., None]
lin = lin * (1 - 0.3 * crease) * (0.6 + 0.4 * ao[..., None]) + ridge * 0.03 * np.array([0.9, 0.85, 0.75])
save_png(np.clip(lin, 0, 1) ** (1 / 2.2), os.path.join(KD, "T_Keeper_BaseColor_v11.png"), srgb=False)
log("wrote v11 maps")
