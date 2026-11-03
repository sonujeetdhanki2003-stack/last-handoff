"""v1.1 baked room AO, step 2 of 3 (Blender): bakes ambient occlusion for the station's walls,
floors and ceilings into one atlas, so corners, skirting, under-shelf and behind-crate contact
shadows read on every preset (Phone/Low have no SSAO).

    blender -b -P tools/gfx_blender/bake_level_ao.py [-- --res=4096 --samples=64 --dist=0.9]

Reads tools/gfx_blender/build/level_receivers.json + level_occluders.bin (export_level.tscn).
Writes assets/props_v11/level_ao.glb (one mesh per receiver box, named R<i>, with a lightmap UV2)
and assets/props_v11/level_ao.png (8-bit AO atlas). Coordinates stay in Godot's space.
The atlas keeps its bottom-left corner white: meshes without a UV2 sample (0,0) and are untouched.
"""
import bpy, bmesh, os, sys, json, time
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
B = os.path.join(ROOT, "tools", "gfx_blender", "build")
OUT = os.path.join(ROOT, "assets", "props_v11")
ARGS = {}
if "--" in sys.argv:
    for a in sys.argv[sys.argv.index("--") + 1:]:
        if a.startswith("--") and "=" in a:
            k, v = a[2:].split("=", 1)
            ARGS[k] = v
RES = int(ARGS.get("res", "4096"))
SAMPLES = int(ARGS.get("samples", "64"))
DIST = float(ARGS.get("dist", "0.9"))
T0 = time.time()
def log(*a):
    print("AO %6.1fs" % (time.time() - T0), *a, flush=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = SAMPLES
w = bpy.data.worlds.new("W"); w.color = (1, 1, 1); sc.world = w
w.light_settings.distance = DIST

rec = json.load(open(os.path.join(B, "level_receivers.json")))
objs = []
for i, r in enumerate(rec):
    sx, sy, sz = r["size"]
    me = bpy.data.meshes.new("R%d" % i)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((sx, sy, sz)), verts=bm.verts)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new("R%d" % i, me)
    sc.collection.objects.link(o)
    bx, by, bz = r["basis"]
    m = Matrix(((bx[0], by[0], bz[0], r["origin"][0]), (bx[1], by[1], bz[1], r["origin"][1]), (bx[2], by[2], bz[2], r["origin"][2]), (0, 0, 0, 1)))
    o.matrix_world = m
    me.uv_layers.new(name="UVMap")
    me.uv_layers.new(name="AO")
    for p in me.polygons:
        p.use_smooth = False
    objs.append(o)
log("receivers", len(objs))

# occluders: one triangle-soup mesh
tri = np.fromfile(os.path.join(B, "level_occluders.bin"), dtype=np.float32).reshape(-1, 3)
nv = len(tri); nf = nv // 3
om = bpy.data.meshes.new("occ")
om.vertices.add(nv); om.vertices.foreach_set("co", tri.ravel())
om.loops.add(nv); om.loops.foreach_set("vertex_index", np.arange(nv, dtype=np.int32))
om.polygons.add(nf)
om.polygons.foreach_set("loop_start", np.arange(0, nv, 3, dtype=np.int32))
om.polygons.foreach_set("loop_total", np.full(nf, 3, np.int32))
om.update(calc_edges=False)
occ = bpy.data.objects.new("occ", om)
sc.collection.objects.link(occ)
log("occluder tris", nf)

# one lightmap atlas over all receivers (areas kept proportional)
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
    o.data.uv_layers.active = o.data.uv_layers["AO"]
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.0, island_margin=0.0, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
bpy.ops.uv.average_islands_scale()
bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
bpy.ops.object.mode_set(mode="OBJECT")
# shrink into [0.02, 1] so the corner texel block stays white
for o in objs:
    uv = o.data.uv_layers["AO"].data
    a = np.empty(len(uv) * 2, np.float32); uv.foreach_get("uv", a)
    a = 0.02 + a * 0.98
    uv.foreach_set("uv", a)
log("packed")

img = bpy.data.images.new("level_ao", RES, RES, alpha=False, float_buffer=True)
img.colorspace_settings.name = "Non-Color"
mat = bpy.data.materials.new("bake"); mat.use_nodes = True
t = mat.node_tree.nodes.new("ShaderNodeTexImage"); t.image = img
uvn = mat.node_tree.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "AO"
mat.node_tree.links.new(uvn.outputs[0], t.inputs[0])
mat.node_tree.nodes.active = t
for o in objs:
    o.data.materials.append(mat)
    o.data.uv_layers.active = o.data.uv_layers["AO"]
sc.render.bake.margin = 4
sc.render.bake.use_selected_to_active = False
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.bake(type="AO")
log("baked")
a = np.array(img.pixels[:], np.float32).reshape(RES, RES, 4)[..., 0]
np.save(os.path.join(B, "level_ao_raw.npy"), a)
# 3x3 blur to take the sampling noise out (islands have margin)
p = np.pad(a, 1, mode="edge")
a = sum(p[1 + dy:RES + 1 + dy, 1 + dx:RES + 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9.0
c = int(RES * 0.018)
a[:, :c] = 1.0           # the whole u < 0.018 strip (no islands there) is white, so (0,0) is white
                         # whichever way up the engine reads V
out = bpy.data.images.new("level_ao_out", RES, RES, alpha=False)
out.colorspace_settings.name = "Non-Color"
px = np.ones((RES, RES, 4), np.float32); px[..., 0] = a; px[..., 1] = a; px[..., 2] = a
out.pixels[:] = px.ravel()
out.filepath_raw = os.path.join(OUT, "level_ao.png"); out.file_format = "PNG"
out.save()
log("saved png")
bpy.data.objects.remove(occ, do_unlink=True)
for o in objs:
    o.data.materials.clear()
    o.data.uv_layers.active = o.data.uv_layers["UVMap"]
    o.matrix_world = Matrix.Identity(4)     # meshes are local; the game keeps each node's transform
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "level_ao.glb"), export_format="GLB", use_selection=True,
                          export_yup=False, export_texcoords=True, export_normals=True, export_materials="NONE")
log("exported")
# v1.2: the runtime map (receiver i -> mesh R<i>) ships beside the atlas
import shutil
shutil.copy(os.path.join(B, "level_receivers.json"), os.path.join(OUT, "level_ao.json"))
log("map copied")
