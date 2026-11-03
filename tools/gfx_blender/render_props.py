"""Quick clay look at the v1.1 props: blender -b -P tools/gfx_blender/render_props.py -- --out=/tmp/props.png"""
import bpy, os, sys, math
from mathutils import Vector
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
D = os.path.join(ROOT, "assets", "props_v11")
out = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--out=")][0]
names = ["door_panel", "locker_body", "locker_door", "lamp_fixture", "vent_grate", "door_jamb", "pipe_flange", "pipe_hanger"]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.show_cavity = True
sc.display.shading.cavity_type = "BOTH"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x = 1600
sc.render.resolution_y = 800
x = 0.0
for n in names:
    bpy.ops.import_scene.gltf(filepath=os.path.join(D, n + ".glb"))
    objs = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    img = bpy.data.images.load(os.path.join(D, n + "_bake.png"))
    for o in objs:
        m = bpy.data.materials.new(n)
        m.use_nodes = True
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        uv = m.node_tree.nodes.new("ShaderNodeUVMap")
        uv.uv_map = o.data.uv_layers[-1].name
        m.node_tree.links.new(uv.outputs[0], t.inputs[0])
        sep = m.node_tree.nodes.new("ShaderNodeSeparateColor")
        m.node_tree.links.new(t.outputs[0], sep.inputs[0])
        m.node_tree.nodes.active = t
        o.data.materials.clear()
        o.data.materials.append(m)
        dims = max(o.dimensions)
        s = 1.0 if n not in ("pipe_flange", "pipe_hanger") else 0.25
        o.scale = (s, s, s)
        o.location = (x, 0, 0)
        o.rotation_euler = (0, 0, math.radians(-25)) if n != "vent_grate" else (math.radians(-110), 0, 0)
    x += 1.4
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = x + 0.4
cam.location = (x / 2 - 0.7, -8, 1.2)
cam.rotation_euler = (math.radians(88), 0, 0)
sc.camera = cam
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
