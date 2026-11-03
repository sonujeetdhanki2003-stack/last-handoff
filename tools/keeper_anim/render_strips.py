"""Renders contact strips of the exported Keeper clips (Workbench clay, so the motion reads).

    blender -b -P tools/keeper_anim/render_strips.py -- --out=/tmp/strips [--clips=a,b] [--n=8] [--view=side|front|three] [--res=320]
One PNG per clip and view: N evenly spaced frames side by side (stitch/label with PIL afterwards).
"""
import bpy, os, sys, math
from mathutils import Vector
args = {}
if "--" in sys.argv:
    for a in sys.argv[sys.argv.index("--") + 1:]:
        k, _, v = a.lstrip("-").partition("=")
        args[k] = v
OUT = args.get("out", "/tmp/strips")
N = int(args.get("n", "8"))
RES = int(args.get("res", "320"))
VIEWS = args.get("view", "side,three").split(",")
GLB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "characters", "keeper", "KeeperAnimated.glb")
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(GLB))
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for o in list(bpy.data.objects):
    if o.type == "EMPTY" or o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
s = bpy.context.scene
s.render.engine = "BLENDER_WORKBENCH"
s.display.shading.light = "STUDIO"
s.display.shading.color_type = "SINGLE"
s.display.shading.single_color = (0.55, 0.5, 0.46)
s.display.shading.show_cavity = True
s.display.shading.show_shadows = True
s.display.shading.shadow_intensity = 0.6
s.display.shading.show_object_outline = True
s.render.resolution_x = RES
s.render.resolution_y = int(RES * 1.25)
s.render.film_transparent = False
s.world = bpy.data.worlds.new("w")
s.world.color = (0.08, 0.08, 0.09)
bpy.ops.mesh.primitive_plane_add(size=12)
floor = bpy.context.object
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 3.15))     # the ceiling vent slab (vent drop)
slab = bpy.context.object
slab.scale = (3, 3, 0.3)
slab.hide_render = True
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
s.collection.objects.link(cam)
s.camera = cam
cam.data.lens = float(args.get("lens", "58"))
pos = {"side": Vector((4.6, 0, 1.2)), "front": Vector((0, -4.6, 1.2)), "three": Vector((3.4, -3.4, 1.3)), "far": Vector((9, -9, 1.6))}
for a in bpy.data.actions:
    if a.name.endswith("_Armature"):
        a.name = a.name[:-len("_Armature")]
names = args.get("clips")
acts = [a for a in bpy.data.actions if a.name.startswith("kp_")]
if names:
    acts = [a for a in acts if a.name in names.split(",")]
arm.animation_data_create()
for a in acts:
    arm.animation_data.action = a
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    tall = a.name == "kp_vent_drop"
    slab.hide_render = not tall
    for v in VIEWS:
        p = pos[v].copy()
        tgt = Vector((0, -0.2, 1.5 if tall else 0.85))
        if tall:
            p = p * 1.6 + Vector((0, 0, 0.4))
        cam.location = p
        cam.rotation_euler = (tgt - p).to_track_quat("-Z", "Y").to_euler()
        for i in range(N):
            f = round(f0 + (f1 - f0) * i / max(1, N - 1)) if N > 1 else f0
            s.frame_set(f)
            s.render.filepath = os.path.join(OUT, "%s_%s_%02d_f%02d.png" % (a.name, v, i, f))
            bpy.ops.render.render(write_still=True)
print("RENDERED", len(acts))
