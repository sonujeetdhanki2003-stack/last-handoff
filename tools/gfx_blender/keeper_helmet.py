"""v1.1: the Keeper's cracked, fused miner's helmet, modelled + baked in Blender.

    blender -b -P tools/gfx_blender/keeper_helmet.py

Authored in the helmet node's own space (keeper.gd puts it on the Head bone), replacing v1.0's
primitive hemisphere/box parts. A low mesh (~2.5k tris) gets normal, AO, colour and roughness
baked from a sculpted high mesh: impact cracks through the shell (voronoi cell edges, only some
of them, plus one long split from the lamp to the crown), dents, chipped paint showing rusted steel,
a cracked dead lamp lens. Writes assets/characters/keeper/KeeperHelmet.glb (textures embedded).
"""
import bpy, bmesh, os, sys, math
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "characters", "keeper", "KeeperHelmet.glb")
RES = 512
rng = np.random.default_rng(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 48
w = bpy.data.worlds.new("W"); w.color = (1, 1, 1); sc.world = w
w.light_settings.distance = 0.05


def apply_all(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def build(prefix, segs):
    parts = []
    # shell: a hemisphere (Blender Z up = Godot Y; Blender -Y = Godot +Z, the front)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=0.094)
    sh = bpy.context.active_object
    bm = bmesh.new(); bm.from_mesh(sh.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.0005], context="VERTS")
    bm.to_mesh(sh.data); bm.free()
    sh.scale = (0.95, 1.15, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    so = sh.modifiers.new("so", "SOLIDIFY"); so.thickness = 0.005; so.offset = -1
    parts.append(sh)
    # brim
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=0.101, depth=0.014, location=(0, 0, 0.002))
    br = bpy.context.active_object
    br.scale = (0.95, 1.15, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    bv = br.modifiers.new("bv", "BEVEL"); bv.width = 0.003; bv.segments = 2
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=0.088, depth=0.03, location=(0, 0, 0.002))
    hole = bpy.context.active_object
    hole.scale = (0.95, 1.15, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    bo = br.modifiers.new("hole", "BOOLEAN"); bo.object = hole; bo.operation = "DIFFERENCE"; bo.solver = "EXACT"
    apply_all(br)
    bpy.data.objects.remove(hole, do_unlink=True)
    parts.append(br)
    # crown ridge, front to back
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.0, 0.088))
    rg = bpy.context.active_object
    rg.scale = (0.022, 0.2, 0.016)
    bpy.ops.object.transform_apply(scale=True)
    bv = rg.modifiers.new("bv", "BEVEL"); bv.width = 0.006; bv.segments = 3
    sd = rg.modifiers.new("sd", "SIMPLE_DEFORM"); sd.deform_method = "BEND"; sd.angle = math.radians(-70); sd.deform_axis = "X"
    parts.append(rg)
    # lamp: bracket + housing + lens, tilted up like v1.0's
    tilt = math.pi / 2 - 0.35
    bpy.ops.mesh.primitive_cylinder_add(vertices=max(12, segs // 2), radius=0.022, depth=0.035, location=(0, -0.1, 0.045), rotation=(tilt, 0, 0))
    lp = bpy.context.active_object
    bv = lp.modifiers.new("bv", "BEVEL"); bv.width = 0.003; bv.segments = 2
    parts.append(lp)
    bpy.ops.mesh.primitive_cylinder_add(vertices=max(12, segs // 2), radius=0.026, depth=0.006, location=(0, -0.116, 0.05), rotation=(tilt, 0, 0))
    rim = bpy.context.active_object
    parts.append(rim)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.088, 0.06))
    bk = bpy.context.active_object
    bk.scale = (0.03, 0.02, 0.03)
    bk.rotation_euler = (0.4, 0, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    bv = bk.modifiers.new("bv", "BEVEL"); bv.width = 0.003
    parts.append(bk)
    for o in parts:
        apply_all(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = prefix
    for p in o.data.polygons:
        p.use_smooth = True
    return o


low = build("KeeperHelmet", 40)
hi = build("HelmetHi", 64)
s = hi.modifiers.new("sub", "SUBSURF"); s.levels = 2
apply_all(hi)
me = hi.data
n = len(me.vertices)
co = np.empty(n * 3, np.float32); me.vertices.foreach_get("co", co); co = co.reshape(n, 3).astype(np.float64)
nr = np.empty(n * 3, np.float32); me.vertices.foreach_get("normal", nr); nr = nr.reshape(n, 3).astype(np.float64)
# voronoi cells over the shell; cracks on SOME cell borders + one long split
seeds = rng.normal(size=(30, 3)); seeds /= np.linalg.norm(seeds, axis=1, keepdims=True); seeds *= 0.1; seeds[:, 2] = np.abs(seeds[:, 2])
dd = np.linalg.norm(co[:, None, :] - seeds[None], axis=2)
idx = np.argsort(dd, axis=1)
d1 = dd[np.arange(n), idx[:, 0]]; d2 = dd[np.arange(n), idx[:, 1]]
edge = (d2 - d1) * 0.5
pair = np.minimum(idx[:, 0], idx[:, 1]) * 31 + np.maximum(idx[:, 0], idx[:, 1])
live = ((pair * 2654435761) % 1000) / 1000.0 < 0.33
on_shell = (co[:, 2] > 0.012).astype(np.float64)
crack = np.clip(1 - edge / 0.0016, 0, 1) * live * on_shell
# the long split: a jagged line from the lamp up over the crown
t = np.arctan2(co[:, 0], -co[:, 1])
jag = 0.012 * np.sin(co[:, 2] * 160) + 0.006 * np.sin(co[:, 2] * 410 + 1.3)
split = np.clip(1 - np.abs(co[:, 0] - 0.018 - jag) / 0.0018, 0, 1) * (co[:, 1] < 0.03) * on_shell
crack = np.maximum(crack, split)
dent = np.zeros(n)
for c in rng.normal(size=(6, 3)):
    c = c / np.linalg.norm(c) * 0.1; c[2] = abs(c[2])
    dent += np.exp(-np.sum((co - c) ** 2, 1) / (0.02 ** 2))
disp = -0.0035 * crack ** 1.5 - 0.004 * dent * on_shell
co += nr * disp[:, None]
me.vertices.foreach_set("co", co.astype(np.float32).ravel()); me.update()
# colour + roughness as vertex colours on the sculpt (baked down below)
paint = np.array([0.52, 0.43, 0.2])      # faded safety-yellow
steel = np.array([0.16, 0.10, 0.07])
chipn = np.sin(co[:, 0] * 211 + np.sin(co[:, 1] * 173)) * np.sin(co[:, 1] * 157 + co[:, 2] * 97) * np.sin(co[:, 2] * 263 + co[:, 0] * 61)
chip = np.clip((chipn - 0.25) * 4, 0, 1) * 0.8 + np.clip(1 - edge / 0.006, 0, 1) * live * 0.7
chip = np.clip(chip + dent * 0.5, 0, 1)
col = paint[None] * (1 - chip[:, None]) + steel[None] * chip[:, None]
grime = np.clip(0.4 + 0.6 * (co[:, 2] < 0.03), 0, 1)
col *= (1 - 0.35 * grime)[:, None]
col *= (1 - 0.92 * crack)[:, None]
flesh = (co[:, 2] < 0.012) * 0.0
rough = np.clip(0.72 - 0.25 * chip + 0.2 * crack, 0.1, 1.0)
for name, vals in (("col", col), ("rough", np.stack([rough] * 3, 1))):
    a = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    rgba = np.ones((n, 4), np.float32); rgba[:, :3] = vals
    a.data.foreach_set("color", rgba.ravel())

# low: UVs
bpy.ops.object.select_all(action="DESELECT")
low.select_set(True); bpy.context.view_layer.objects.active = low
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.02)
bpy.ops.object.mode_set(mode="OBJECT")

sc.render.bake.use_selected_to_active = True
sc.render.bake.cage_extrusion = 0.006
sc.render.bake.max_ray_distance = 0.015
sc.render.bake.margin = 6
hm = bpy.data.materials.new("hi"); hm.use_nodes = True
nt = hm.node_tree
for x in list(nt.nodes): nt.nodes.remove(x)
attr = nt.nodes.new("ShaderNodeAttribute"); attr.attribute_name = "col"
em = nt.nodes.new("ShaderNodeEmission"); outn = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(attr.outputs["Color"], em.inputs["Color"]); nt.links.new(em.outputs[0], outn.inputs["Surface"])
hi.data.materials.clear(); hi.data.materials.append(hm)


def bake(kind, name, colorspace="Non-Color"):
    img = bpy.data.images.new(name, RES, RES, alpha=False)
    img.colorspace_settings.name = colorspace
    mat = bpy.data.materials.new("b_" + name); mat.use_nodes = True
    t = mat.node_tree.nodes.new("ShaderNodeTexImage"); t.image = img; mat.node_tree.nodes.active = t
    low.data.materials.clear(); low.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    hi.select_set(True); low.select_set(True); bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type=kind)
    return img


img_col = bake("EMIT", "KeeperHelmet_BaseColor", "sRGB")
attr.attribute_name = "rough"
img_r = bake("EMIT", "KeeperHelmet_Rough")
img_n = bake("NORMAL", "KeeperHelmet_Normal")
img_ao = bake("AO", "KeeperHelmet_AO")
# glTF wants ORM in one image: R = AO, G = roughness, B = metal
W_ = RES
ao = np.array(img_ao.pixels[:]).reshape(W_, W_, 4)[..., 0]
rg = np.array(img_r.pixels[:]).reshape(W_, W_, 4)[..., 0]
orm = bpy.data.images.new("KeeperHelmet_ORM", W_, W_, alpha=False); orm.colorspace_settings.name = "Non-Color"
px = np.ones((W_, W_, 4), np.float32); px[..., 0] = ao; px[..., 1] = rg; px[..., 2] = 0.25
orm.pixels[:] = px.ravel()
for im in (img_col, img_n, orm):
    im.pack()
# final material on the low mesh
m = bpy.data.materials.new("M_KeeperHelmet"); m.use_nodes = True
nt = m.node_tree; bsdf = nt.nodes["Principled BSDF"]
tc = nt.nodes.new("ShaderNodeTexImage"); tc.image = img_col
nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
to = nt.nodes.new("ShaderNodeTexImage"); to.image = orm
sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(to.outputs["Color"], sep.inputs[0])
nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = img_n
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tn.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
# glTF occlusion: a glTF Settings group node
gs = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
gs.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
gn = nt.nodes.new("ShaderNodeGroup"); gn.node_tree = gs
nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])
low.data.materials.clear(); low.data.materials.append(m)
bpy.data.objects.remove(hi, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT"); low.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_image_format="JPEG", export_jpeg_quality=90)
print("HELMET tris", sum(len(p.vertices) - 2 for p in low.data.polygons), "->", OUT)
