"""Shared rig helpers for authoring the Keeper's keyframed clips in Blender.

Run through tools/keeper_anim/build_clips.py:  blender -b -P tools/keeper_anim/build_clips.py

Conventions (Blender armature space after the glTF import of Keeper.gltf):
  +X = the Keeper's LEFT, -Y = FORWARD, +Z = UP.  The rest pose is the sculpt's T-pose with the
  soles ~0.1 m below the origin, so every clip carries a hips lift (LIFT) like the old poser did.

A pose is a dict of bone -> (rx, ry, rz) degrees, a rotation expressed in rest armature axes and
applied at the bone's head on top of its parent (plain FK). Keys ending in "_*" are written for the
left side and mirrored to the right ((rx, -ry, -rz)). "fing_*" curls all four fingers (+ = into the
palm). Special keys:
  "loc"        pelvis offset in metres (armature axes), added to the LIFT
  "ikf_*"      IK foot target offset from the rest ankle (metres)      "ikfr_*" foot pitch (deg, + = heel up)
  "ikh_*"      IK hand target, absolute armature position (metres)     "ikhr_*" hand rotation (deg)
  "pk_*"/"pe_*" knee/elbow pole offsets (metres)  "wleg_*"/"warm_*" IK influence 0..1
Animation is authored as sparse keys (Bezier or snapped) with per-bone lag (overlapping action:
children trail their parents), F-curve Noise modifiers for tremor, then the IK is baked down to
plain FK rotations on the deform bones so the exported glTF needs no constraints.
"""
import bpy, math
from mathutils import Euler, Quaternion, Vector, Matrix

FPS = 30
LIFT = 0.113
KEEPER = "/home/user/tab/files/last_handoff/project/assets/characters/keeper/Keeper.gltf"
FINGERS = ["index", "middle", "ring", "pinky"]
LAG = {"pelvis": 0.0, "spine_01": 0.4, "spine_02": 0.8, "spine_03": 1.2, "neck_01": 1.8, "Head": 2.4,
       "clavicle": 1.4, "upperarm": 2.0, "lowerarm": 2.8, "hand": 3.6, "finger": 4.4, "thumb": 4.0,
       "thigh": 0.0, "calf": 0.0, "foot": 0.0, "ball": 0.0}
CTRL = []   # control (non-deform) bones we add


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=KEEPER)
    for o in list(bpy.data.objects):
        if o.type not in ("ARMATURE", "MESH") or o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    _add_controls(arm)
    return arm


def _mode(arm, m):
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    if bpy.context.object.mode != m:
        bpy.ops.object.mode_set(mode=m)


def _add_controls(arm):
    _mode(arm, "EDIT")
    eb = arm.data.edit_bones
    root = eb["root"]
    def mk(name, head, tail, roll_from=None):
        b = eb.new(name)
        b.head = head
        b.tail = tail
        if roll_from is not None:
            b.roll = eb[roll_from].roll
        b.parent = root
        b.use_deform = False
        CTRL.append(name)
        return b
    for s in "lr":
        f = eb["foot_" + s]
        mk("ik_foot_" + s, f.head.copy(), f.tail.copy(), "foot_" + s)
        k = eb["calf_" + s].head.copy()
        mk("pole_knee_" + s, k + Vector((0, -0.7, 0)), k + Vector((0, -0.8, 0)))
        h = eb["hand_" + s]
        mk("ik_hand_" + s, h.head.copy(), h.tail.copy(), "hand_" + s)
        e = eb["lowerarm_" + s].head.copy()
        mk("pole_elbow_" + s, e + Vector((0, 0.6, 0)), e + Vector((0, 0.7, 0)))
    _mode(arm, "POSE")
    for s in "lr":
        pb = arm.pose.bones
        c = pb["calf_" + s].constraints.new("IK")
        c.name = "IK"; c.target = arm; c.subtarget = "ik_foot_" + s; c.pole_target = arm
        c.pole_subtarget = "pole_knee_" + s; c.chain_count = 2; c.influence = 0.0
        c = pb["foot_" + s].constraints.new("COPY_ROTATION")
        c.name = "IKrot"; c.target = arm; c.subtarget = "ik_foot_" + s; c.influence = 0.0
        c = pb["lowerarm_" + s].constraints.new("IK")
        c.name = "IK"; c.target = arm; c.subtarget = "ik_hand_" + s; c.pole_target = arm
        c.pole_subtarget = "pole_elbow_" + s; c.chain_count = 2; c.influence = 0.0
        c = pb["hand_" + s].constraints.new("COPY_ROTATION")
        c.name = "IKrot"; c.target = arm; c.subtarget = "ik_hand_" + s; c.influence = 0.0
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    _calibrate_poles(arm)


def _calibrate_poles(arm):
    """Pick each IK pole angle so that a target at the rest position reproduces the rest pose."""
    pb = arm.pose.bones
    for s in "lr":
        for chain, mid in (("calf_", "thigh_"), ("lowerarm_", "upperarm_")):
            c = pb[chain + s].constraints["IK"]
            c.influence = 1.0
            best, best_e = 0.0, 1e9
            for a in range(-180, 181, 5):
                c.pole_angle = math.radians(a)
                bpy.context.view_layer.update()
                e = (pb[chain + s].matrix.to_quaternion().rotation_difference(
                    arm.data.bones[chain + s].matrix_local.to_quaternion())).angle
                e += (pb[mid + s].matrix.to_quaternion().rotation_difference(
                    arm.data.bones[mid + s].matrix_local.to_quaternion())).angle
                if e < best_e:
                    best, best_e = a, e
            c.pole_angle = math.radians(best)
            c.influence = 0.0
            print("pole", chain + s, best, round(best_e, 4))


def _q(deg):
    return Euler([math.radians(v) for v in deg], "XYZ").to_quaternion()


class Dir:
    """Point a bone (head->tail) along vec, given in ARMATURE axes (world-ish, not parent-relative),
    then twist it about its length by twist degrees. Resolved through the posed parent chain."""
    def __init__(self, x, y, z, twist=0.0):
        self.v = Vector((x, y, z)).normalized()
        self.twist = twist

    def mirrored(self):
        return Dir(-self.v.x, self.v.y, self.v.z, -self.twist)


def mirror_name(n):
    return n[:-2] + "_r" if n.endswith("_l") else n


def expand(pose):
    """Pose dict -> {bone: ('rot', quat_armature) | ('loc', vec) | ('w', f) ...} with mirroring."""
    out = {}
    for k, v in pose.items():
        sides = [("l", 1), ("r", -1)] if k.endswith("_*") else [(None, 1)]
        for s, sg in sides:
            name = k[:-1] + s if s else k
            if isinstance(v, (int, float)):
                out[name] = float(v)
                continue
            if isinstance(v, Dir):
                out[name] = v.mirrored() if s == "r" else v
                continue
            v = tuple(v)
            if s == "r":
                if name.startswith(("ikf_", "ikh_", "pk_", "pe_")):
                    v = (-v[0], v[1], v[2])
                else:
                    v = (v[0], -v[1], -v[2])
            out[name] = v
    # finger curl shorthand
    for k in list(out):
        if k.startswith("fing_"):
            s = k[-1]
            c = out.pop(k)
            c = c if isinstance(c, tuple) else (c, c * 1.1, c * 1.2)
            sg = 1 if s == "l" else -1
            for f in FINGERS:
                for i in range(3):
                    out.setdefault("%s_0%d_%s" % (f, i + 1, s), (0, sg * c[i], 0))
    return out


def merge(*poses):
    """Add poses together (rotations add per axis; later scalar/IK entries win)."""
    out = {}
    for p in poses:
        for k, v in p.items():
            if isinstance(v, Dir) or isinstance(out.get(k), Dir):
                out[k] = v
            elif k in out and isinstance(v, (tuple, list)) and not k.startswith(("ikh_", "ikf_")):
                out[k] = tuple(a + b for a, b in zip(out[k], v))
            else:
                out[k] = tuple(v) if isinstance(v, (tuple, list)) else v
    return out


def lag_of(name):
    base = name[:-2] if name.endswith(("_l", "_r")) else name
    for f in FINGERS:
        if base.startswith(f):
            return LAG["finger"]
    if base.startswith("thumb"):
        return LAG["thumb"]
    return LAG.get(base, 0.0)


_ORDER = None


def resolve(arm, ex):
    """Turn Dir entries into rotations: walk the chain accumulating P_b = P_parent * D_b."""
    global _ORDER
    if _ORDER is None:
        _ORDER = sorted([b for b in arm.data.bones if b.use_deform], key=lambda b: len(b.parent_recursive))
    P = {}
    for b in _ORDER:
        par = P.get(b.parent.name, Quaternion()) if b.parent else Quaternion()
        v = ex.get(b.name)
        if isinstance(v, Dir):
            rest = (b.tail_local - b.head_local).normalized()
            Q = rest.rotation_difference(v.v)
            Q = Quaternion(v.v, math.radians(v.twist)) @ Q
            D = par.inverted() @ Q
            ex[b.name] = D
        elif isinstance(v, tuple):
            D = _q(v)
        elif isinstance(v, Quaternion):
            D = v
        else:
            D = Quaternion()
        P[b.name] = par @ D
    return ex


class Clip:
    """One action: sparse keys (frame, pose, interp) -> F-curves on the control action."""
    def __init__(self, arm, name, length, loop, lag=1.0):
        self.arm, self.name, self.length, self.loop, self.lag = arm, name, length, loop, lag
        self.keys = []          # (frame, expanded pose, interp)
        self.track_keys = {}    # per-frame control keys for IK targets: name -> [(frame, vec)]
        self.noise = []         # (bone, strength, scale, f0, f1)

    def key(self, f, pose, interp="BEZIER"):
        self.keys.append((f, resolve(self.arm, expand(pose)), interp))
        return self

    def track(self, name, frames_vals):
        self.track_keys[name] = frames_vals

    def tremor(self, bone, strength=0.02, scale=1.5, f0=None, f1=None):
        names = [bone[:-1] + "l", bone[:-1] + "r"] if bone.endswith("_*") else [bone]
        for n in names:
            self.noise.append((n, strength, scale, f0, f1))

    # ---- write control action
    def build(self):
        arm = self.arm
        act = bpy.data.actions.new("ctl_" + self.name)
        arm.animation_data_create()
        arm.animation_data.action = act
        pb = arm.pose.bones
        bones_used = set()
        for _, p, _ in self.keys:
            bones_used |= set(p)
        # all deform rotation bones get a full set of keys (missing entries = identity), so clips
        # don't inherit each other's poses
        series = {}
        for f, p, interp in self.keys:
            for name in bones_used:
                series.setdefault(name, []).append((f, p.get(name, None), interp))
        for name, seq in series.items():
            self._write(act, name, seq)
        for name, seq in self.track_keys.items():
            for f, v in seq:
                self._write_one(act, name, f, v, "LINEAR", kind="track")
        for fc in act.fcurves:
            if self.loop:
                m = fc.modifiers.new("CYCLES")
        for bone, st, sc, f0, f1 in self.noise:
            for fc in act.fcurves:
                if fc.data_path == 'pose.bones["%s"].rotation_quaternion' % bone and fc.array_index > 0:
                    m = fc.modifiers.new("NOISE")
                    m.strength = st
                    m.scale = sc
                    m.phase = hash((bone, fc.array_index, self.name)) % 97
                    if f0 is not None:
                        m.use_restricted_range = True
                        m.frame_start = f0
                        m.frame_end = f1
                        m.blend_in = 2
                        m.blend_out = 3
        return act

    def _rest_q(self, name):
        return self.arm.data.bones[name].matrix_local.to_quaternion()

    def _write(self, act, name, seq):
        lag = 0.0 if name.startswith(("ikf_", "ikh_", "pk_", "pe_", "wleg", "warm", "loc", "ikfr_", "ikhr_")) else lag_of(name) * self.lag
        pts = []
        for f, v, interp in seq:
            ff = f + lag
            if not self.loop:
                ff = min(ff, self.length) if f < self.length else f
            pts.append((ff, v, interp))
        if self.loop:
            # closing key one period later = the first key
            f0, v0, i0 = seq[0]
            pts.append((f0 + self.length + lag, v0, i0))
        last = None
        seen = set()
        for ff, v, interp in pts:
            if round(ff, 2) in seen:
                continue
            seen.add(round(ff, 2))
            self._write_one(act, name, ff, v, interp)

    def _write_one(self, act, name, f, v, interp, kind=None):
        arm = self.arm
        pbs = arm.pose.bones
        def put(path, idx, val, group):
            fc = act.fcurves.find(path, index=idx) or act.fcurves.new(path, index=idx, action_group=group)
            k = fc.keyframe_points.insert(f, val, options={"FAST"})
            k.interpolation = "LINEAR" if interp in ("LINEAR", "SNAP") else "BEZIER"
            if interp == "BEZIER":
                k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
            elif interp == "EASE":
                k.handle_left_type = k.handle_right_type = "AUTO_CLAMPED"
                k.easing = "EASE_IN_OUT"
        if name.startswith(("wleg", "warm")):   # IK weights: wleg_l / warm_l
            s = name[-1]
            chain = ("calf_", "foot_") if name.startswith("wleg") else ("lowerarm_", "hand_")
            for b, c in ((chain[0] + s, "IK"), (chain[1] + s, "IKrot")):
                put('pose.bones["%s"].constraints["%s"].influence' % (b, c), 0, float(v or 0.0), b)
            return
        if name == "loc":
            v = Vector(v or (0, 0, 0)) + Vector((0, 0, LIFT))
            rq = self._rest_q("pelvis")
            lv = rq.inverted() @ v
            for i in range(3):
                put('pose.bones["pelvis"].location', i, lv[i], "pelvis")
            return
        if name.startswith(("ikf_", "ikh_", "pk_", "pe_")):
            s = name[-1]
            bn = {"ikf": "ik_foot_", "ikh": "ik_hand_", "pk": "pole_knee_", "pe": "pole_elbow_"}[name.split("_")[0]] + s
            b = arm.data.bones[bn]
            if name.startswith("ikh_"):
                target = Vector(v or b.head_local)
                off = target - b.head_local
            else:
                off = Vector(v or (0, 0, 0))
                if name.startswith("ikf_"):
                    off = off + Vector((0, 0, LIFT))
            lv = b.matrix_local.to_quaternion().inverted() @ off
            for i in range(3):
                put('pose.bones["%s"].location' % bn, i, lv[i], bn)
            return
        if name.startswith(("ikfr_", "ikhr_")):
            s = name[-1]
            bn = ("ik_foot_" if name.startswith("ikfr") else "ik_hand_") + s
            name, v = bn, v
        if name not in pbs:
            return
        rq = self._rest_q(name)
        d = v if isinstance(v, Quaternion) else (_q(v) if v is not None else Quaternion())
        lq = rq.inverted() @ d @ rq
        fc0 = act.fcurves.find('pose.bones["%s"].rotation_quaternion' % name, index=0)
        if fc0 is not None and len(fc0.keyframe_points):
            prev = Quaternion([act.fcurves.find('pose.bones["%s"].rotation_quaternion' % name, index=i).keyframe_points[-1].co[1] for i in range(4)])
            if prev.dot(lq) < 0:
                lq = -lq
        for i in range(4):
            put('pose.bones["%s"].rotation_quaternion' % name, i, lq[i], name)


DEFORM = None


def bake(arm, clip, act):
    """Evaluate the control action (FK + IK + noise) frame by frame into a plain FK action."""
    global DEFORM
    scn = bpy.context.scene
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        for c in pb.constraints:
            c.influence = 0.0
    deform = [pb for pb in arm.pose.bones if arm.data.bones[pb.name].use_deform]
    frames = range(0, clip.length + 1)
    data = {pb.name: [] for pb in deform}
    for f in frames:
        scn.frame_set(f)
        for pb in deform:
            m = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space="POSE", to_space="LOCAL")
            data[pb.name].append((m.to_translation(), m.to_quaternion()))
    out = bpy.data.actions.new(clip.name)
    out.use_fake_user = True
    for name, seq in data.items():
        prev = None
        cols = {"location": [], "rotation_quaternion": []}
        for t, q in seq:
            if prev is not None and prev.dot(q) < 0:
                q = -q
            prev = q
            cols["location"].append(t)
            cols["rotation_quaternion"].append(q)
        for path, vals, n in (("location", cols["location"], 3), ("rotation_quaternion", cols["rotation_quaternion"], 4)):
            if path == "location" and name != "pelvis":
                continue
            for i in range(n):
                fc = out.fcurves.new('pose.bones["%s"].%s' % (name, path), index=i, action_group=name)
                fc.keyframe_points.add(len(vals))
                co = []
                for fi, v in zip(frames, vals):
                    co += [fi, v[i]]
                fc.keyframe_points.foreach_set("co", co)
                for k in fc.keyframe_points:
                    k.interpolation = "LINEAR"
                fc.update()
    out.use_frame_range = True
    out.frame_start = 0
    out.frame_end = clip.length
    out.use_cyclic = clip.loop
    return out


def finalize(arm, baked):
    """Drop the controls/constraints and the control actions, leave only the baked clips."""
    _mode(arm, "POSE")
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    for a in list(bpy.data.actions):
        if a.name.startswith("ctl_"):
            bpy.data.actions.remove(a)
    _mode(arm, "EDIT")
    for n in CTRL:
        arm.data.edit_bones.remove(arm.data.edit_bones[n])
    _mode(arm, "OBJECT")
    arm.animation_data.action = None
    # each clip on its own NLA track so the exporter's ACTIONS mode finds them all
    for a in baked:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = a.name
        st = tr.strips.new(a.name, 0, a)
        tr.mute = True
