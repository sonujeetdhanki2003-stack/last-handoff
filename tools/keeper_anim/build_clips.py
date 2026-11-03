"""Authors the Keeper's keyframed clips in Blender and exports them with the rig and mesh.

    blender -b -P tools/keeper_anim/build_clips.py
writes assets/characters/keeper/KeeperAnimated.glb (Keeper mesh + rig + 13 actions, 30 fps).
Every clip is in place (no root motion): the game moves the Keeper and scales the locomotion
clips' playback by its real speed (NATIVE speeds below), so planted feet don't skate.
Gameplay-timed clips match keeper.gd exactly: kp_scream 15 f = LUNGE_TELEGRAPH 0.5 s,
kp_lunge 9 f = LUNGE_TIME 0.3 s, kp_stagger 30 f = LUNGE_RECOVER 1.0 s.
"""
import bpy, math, os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib, keeper_rig
importlib.reload(keeper_rig)
from keeper_rig import *

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "characters", "keeper", "KeeperAnimated.glb")
NATIVE = {"kp_stalk": 1.25, "kp_run": 3.4, "kp_crawl": 1.2}


def lerp(a, b, t):
    return a + (b - a) * t


def smooth(u):
    return u * u * (3 - 2 * u)


# ------------------------------------------------------------------ base poses
def hunch(b=0.0, low=0.0):
    """The standing stance: folded forward ~50 deg, long neck jutting, head craned up to see, arms
    hanging long. b = breath (0 exhale .. 1 inhale), low = extra crouch."""
    return {
        "loc": (0.0, 0.04 + 0.06 * low, -0.10 - 0.22 * low + 0.012 * b),
        "pelvis": (14 + 18 * low, 0, 0),
        "spine_01": (12 - 2 * b, 0, 0), "spine_02": (14 - 3 * b, 0, 0), "spine_03": (10 - 3 * b, 0, 0),
        "neck_01": (18, 0, 0), "Head": (-58 + 3 * b - 14 * low, 10, 0),
        "clavicle_*": (0, 10 - 5 * b, -14),
        "upperarm_*": Dir(0.14, -0.32 - 0.25 * low, -1, -10),
        "lowerarm_*": Dir(0.06, -0.55 - 0.2 * low, -1, -20),
        "hand_*": Dir(0.0, -0.35, -1, -20),
        "fing_*": (22 + 4 * b, 30, 32),
        "thumb_02_*": (0, 10, 0),
        "wleg_*": 1.0, "ikf_*": (0.03, 0.0, 0.0),
    }


def crawl_pose(head_twist=38.0):
    return {
        "loc": (0.0, 0.0, -0.33),
        "pelvis": (68, 0, 0),
        "spine_01": (8, 0, 0), "spine_02": (6, 0, 0), "spine_03": (2, 0, 0),
        "neck_01": (-28, 0, 0), "Head": Dir(0, -0.95, 0.35, head_twist),
        "clavicle_*": (0, 8, -22),
        "wleg_*": 1.0, "warm_*": 1.0,
        "ikh_*": (0.42, -0.78, 0.075), "ikhr_*": (0, 0, -55),
        "pe_*": (0.45, -0.55, -0.55),
        "pk_*": (0.55, -0.1, -0.2),
        "ikf_*": (0.10, 0.12, 0.0),
        "fing_*": (10, 25, 35),
    }


def gait(L, stance, S, lift, phase, hitch=False, y0=0.0, x=0.0, z0=0.0, pitch=25.0):
    """Per-frame planted/swing track for one IK end effector. Stance: moves back at exactly the
    clip's native ground speed (no skate). Swing: forward with lift; hitch = a stop-start swing
    that hangs in the air, then snaps down."""
    pos, rot = [], []
    for f in range(L + 1):
        t = ((f / L) - phase) % 1.0
        if t < stance:
            u = t / stance
            y = -S / 2 + S * u
            z = 0.0
            r = 0.0
        else:
            u = (t - stance) / (1 - stance)
            if hitch:
                p = 0.45 * smooth(min(1, u / 0.35)) if u < 0.62 else 0.45 + 0.55 * smooth((u - 0.62) / 0.38)
                zl = lift * (math.sin(math.pi * min(1, u / 0.7)) ** 0.6 if u < 0.7 else (1 - (u - 0.7) / 0.3) ** 1.6)
            else:
                p = smooth(u)
                zl = lift * math.sin(math.pi * u) ** 0.8
            y = S / 2 - S * p
            z = zl
            r = pitch * math.sin(math.pi * min(1, u * 1.6))
        pos.append((f, (x, y + y0, z + z0)))
        rot.append((f, (r, 0, 0)))
    return pos, rot


clips = []


def finish(c):
    clips.append(c)


def idle(arm):
    c = Clip(arm, "kp_idle", 72, loop=True, lag=1.2)
    A = lambda s: {"upperarm_l": Dir(0.1, -0.25 - 0.12 * s, -1, -10), "lowerarm_l": Dir(0.03, -0.5 - 0.2 * s, -1, -20)}
    c.key(0, merge(hunch(0.0), {"loc": (-0.03, 0, 0), "pelvis": (0, -3, 4), "spine_03": (0, 2, -4), "Head": (0, 4, 6)}, A(0)))
    c.key(30, merge(hunch(1.0), {"loc": (0.0, 0, 0), "clavicle_r": (0, -6, 0)}, A(1)))
    c.key(50, merge(hunch(0.6), {"loc": (0.03, 0, 0), "pelvis": (0, 3, -4), "spine_03": (0, -2, 4), "Head": (0, -5, -6)}, A(-0.6)))
    c.tremor("Head", 0.012, 6.0)
    c.tremor("fing_*" if False else "index_02_l", 0.03, 3.0)
    finish(c)


def breath_at(f, L=72):
    return 0.5 - 0.5 * math.cos(2 * math.pi * min(f, 30) / 60.0) if f <= 30 else 0.5 + 0.5 * math.cos(math.pi * (f - 30) / (L - 30))


def idle_head(arm):
    """Head twitch: two jerky snaps, a trembling hold, then a slow unwinding roll."""
    c = Clip(arm, "kp_idle_head", 72, loop=False, lag=1.0)
    H = lambda f, extra, it="BEZIER": c.key(f, merge(hunch(breath_at(f)), extra), it)
    H(0, {})
    H(12, {}, "LINEAR")
    H(14, {"Head": (10, 52, 34), "neck_01": (0, 12, 10), "clavicle_l": (0, -10, 0)})
    H(25, {"Head": (12, 55, 36), "neck_01": (0, 12, 10), "clavicle_l": (0, -10, 0)}, "LINEAR")
    H(26, {"Head": (-6, 26, -24), "neck_01": (0, 4, -8)})
    H(40, {"Head": (-4, 30, -22), "neck_01": (0, 4, -8)}, "EASE")
    H(58, {"Head": (0, -6, 4)}, "LINEAR")
    H(60, {"Head": (0, 2, 0)})
    H(72, {})
    c.tremor("Head", 0.035, 1.2, 14, 40)
    finish(c)


def idle_fingers(arm):
    """It lifts a hand and studies its own fingers as they curl one by one, then splay."""
    c = Clip(arm, "kp_idle_fingers", 72, loop=False, lag=1.0)
    up = {"upperarm_l": Dir(0.35, -0.85, -0.45, -30), "lowerarm_l": Dir(-0.25, -0.8, 0.55, -60),
          "hand_l": Dir(-0.5, -0.4, 0.75, -60), "Head": (-8, 16, -24)}
    F = lambda f, extra, it="BEZIER": c.key(f, merge(hunch(breath_at(f)), extra), it)
    def fingers(cur):
        d = {}
        for n, v in zip(FINGERS, cur):
            for i in range(3):
                d["%s_0%d_l" % (n, i + 1)] = (0, v * (1 + 0.15 * i), 0)
        return d
    F(0, {})
    F(16, merge(up, fingers([20, 20, 20, 20])))
    F(22, merge(up, fingers([20, 20, 20, 20])), "LINEAR")
    F(23, merge(up, fingers([85, 20, 20, 20])), "LINEAR")
    F(27, merge(up, fingers([85, 85, 20, 20])), "LINEAR")
    F(29, merge(up, fingers([85, 85, 85, 20])), "LINEAR")
    F(34, merge(up, fingers([85, 85, 85, 85])), "LINEAR")
    F(35, merge(up, fingers([-25, -25, -25, -25]), {"Head": (-4, 26, -30)}))
    F(46, merge(up, fingers([-20, -28, -22, -30]), {"Head": (-4, 26, -30)}), "LINEAR")
    F(47, merge(up, fingers([40, 40, 40, 40]), {"Head": (0, 4, 0)}))
    F(72, {})
    c.tremor("index_02_l", 0.05, 1.0, 35, 46)
    c.tremor("hand_l", 0.02, 1.5, 16, 46)
    finish(c)


def stalk(arm):
    """Patrol walk, 1.25 m/s native: long slow strides with a hitch in the left leg (it hangs in
    the air, then stamps down), arms dragging behind the body's sway."""
    L, st = 36, 0.6
    S = NATIVE["kp_stalk"] * st * L / FPS
    c = Clip(arm, "kp_stalk", L, loop=True, lag=1.6)
    pl, rl = gait(L, st, S, 0.20, 0.0, hitch=True, x=0.02)
    pr, rr = gait(L, st, S, 0.13, 0.5, x=-0.0)
    c.track("ikf_l", pl); c.track("ikfr_l", rl); c.track("ikf_r", pr); c.track("ikfr_r", rr)
    base = merge(hunch(0.5), {"pelvis": (6, 0, 0), "spine_02": (4, 0, 0), "Head": (-10, 0, 0)})
    del base["ikf_*"]
    def P(f, bob, sway, armph, extra=None):
        d = merge(base, {"loc": (0.03 * sway, 0, bob), "pelvis": (0, 4 * sway, 9 * sway),
                         "spine_02": (0, -2 * sway, -6 * sway), "spine_03": (0, -2 * sway, -5 * sway),
                         "Head": (0, 3 * sway, 8 * sway)}, extra or {})
        d["upperarm_l"] = Dir(0.16, -0.3 - 0.35 * armph, -1, -10)
        d["upperarm_r"] = Dir(-0.16, -0.3 + 0.35 * armph, -1, 10)
        d["lowerarm_l"] = Dir(0.06, -0.5 - 0.45 * armph, -1, -20)
        d["lowerarm_r"] = Dir(-0.06, -0.5 + 0.45 * armph, -1, 20)
        return d
    # left contact at 0 (stance 0..21), right contact at 18
    c.key(0, P(0, -0.05, 1, -1))
    c.key(8, P(1, 0.0, 0.6, -0.4))
    c.key(18, P(2, -0.05, -1, 1))
    c.key(24, P(3, 0.01, -0.5, 0.6, {"Head": (2, -14, 6)}), "LINEAR")    # head tick mid-swing
    c.key(26, P(4, 0.0, -0.2, 0.2, {"Head": (0, -10, 4)}))
    # (no noise: locomotion stays clean)
    for k in range(len(c.keys)):
        pass
    finish(c)


def run(arm):
    """Chase, 3.4 m/s native: pitched forward, arms reaching out ahead and flailing loose."""
    L, st = 20, 0.36
    S = NATIVE["kp_run"] * st * L / FPS
    c = Clip(arm, "kp_run", L, loop=True, lag=1.3)
    pl, rl = gait(L, st, S, 0.28, 0.0, y0=-0.05, pitch=35)
    pr, rr = gait(L, st, S, 0.28, 0.5, y0=-0.05, pitch=35)
    c.track("ikf_l", pl); c.track("ikfr_l", rl); c.track("ikf_r", pr); c.track("ikfr_r", rr)
    def P(bob, sway, a, extra=None):
        d = {"loc": (0.02 * sway, -0.06, -0.14 + bob), "pelvis": (22, 3 * sway, 12 * sway),
             "spine_01": (10, 0, -4 * sway), "spine_02": (10, -3 * sway, -6 * sway), "spine_03": (6, 0, -4 * sway),
             "neck_01": (8, 0, 0), "Head": (-52, 6, 10 * sway),
             "clavicle_*": (0, 4, -18),
             "upperarm_l": Dir(0.3, -1, -0.25 - 0.45 * a, -40), "upperarm_r": Dir(-0.3, -1, -0.25 + 0.45 * a, 40),
             "lowerarm_l": Dir(0.1, -1, 0.05 - 0.3 * a, -60), "lowerarm_r": Dir(-0.1, -1, 0.05 + 0.3 * a, 60),
             "hand_*": Dir(0.0, -1, -0.1, -40), "fing_*": (-12, 20, 40),
             "wleg_*": 1.0}
        return merge(d, extra or {})
    c.key(0, P(-0.04, 1, 1))
    c.key(4, P(0.03, 0.6, 0.5))
    c.key(10, P(-0.04, -1, -1))
    c.key(14, P(0.03, -0.6, -0.5))
    finish(c)


def crawl(arm):
    """On all fours, low: lateral-sequence gait (hind L, fore L, hind R, fore R), elbows cocked up
    and out like an insect, head craned forward and turned on its side, with a twitch."""
    L, st = 28, 0.7
    S = NATIVE["kp_crawl"] * st * L / FPS
    c = Clip(arm, "kp_crawl", L, loop=True, lag=1.4)
    for name, ph, x, y0, z0, lift in (("ikf_l", 0.0, 0.10, 0.12, 0.0, 0.14), ("ikf_r", 0.5, -0.10, 0.12, 0.0, 0.14)):
        p, r = gait(L, st, S, lift, ph, x=x, y0=y0, z0=z0, pitch=20)
        c.track(name, p); c.track("ikfr_" + name[-1], r)
    for name, ph, x in (("ikh_l", 0.25, 0.42), ("ikh_r", 0.75, -0.42)):
        p, r = gait(L, st, S, 0.17, ph, x=x, y0=-0.78, z0=0.075)
        c.track(name, p)
    base = crawl_pose()
    for k in ("ikh_*", "ikf_*"):
        base.pop(k)
    def P(sw, extra=None):
        return merge(base, {"pelvis": (0, 0, 7 * sw), "spine_01": (0, 0, -4 * sw), "spine_02": (0, 0, -5 * sw),
                            "spine_03": (0, 0, -4 * sw), "loc": (0.02 * sw, 0, 0.02 * abs(sw))}, extra or {})
    c.key(0, P(1))
    c.key(7, P(0))
    c.key(14, P(-1), "LINEAR")
    c.key(15, P(-0.9, {"Head": Dir(0.25, -0.9, 0.45, -18)}))     # head snaps the other way
    c.key(20, P(-0.2, {"Head": Dir(0.2, -0.92, 0.4, -14)}), "LINEAR")
    c.key(21, P(0))
    c.tremor("Head", 0.02, 2.0)
    finish(c)


def coiled():
    """Spring-loaded: sunk low and pitched at you, arms drawn back wide and low like wings, claws forward."""
    return {"loc": (0, 0.1, -0.17), "pelvis": (16, 0, 0), "spine_01": (10, 0, 0), "spine_02": (10, 0, 0),
            "spine_03": (6, 0, 0), "neck_01": (12, 0, 0), "Head": Dir(0.08, -0.45, 1, 14),
            "clavicle_*": (0, 4, 14),
            "upperarm_*": Dir(0.55, 0.6, -0.55, -50), "lowerarm_*": Dir(0.3, -0.9, -0.2, -70),
            "hand_*": Dir(0.1, -1, 0.0, -50), "fing_*": (-25, 15, 35),
            "wleg_*": 1.0, "ikf_l": (0.07, -0.22, 0), "ikf_r": (-0.02, 0.26, 0), "ikfr_r": (28, 0, 0)}


def scream(arm):
    """The telegraph, exactly 15 frames (0.5 s): it snaps upright and rears back, arms flung wide,
    head thrown back shaking, then coils forward for the lunge."""
    c = Clip(arm, "kp_scream", 15, loop=False, lag=0.6)
    c.key(0, hunch(0.4), "LINEAR")
    # rears up on its toes and looms over you like a mantis: tall through the hips, the upper back and
    # the long neck curling down at you, elbows hoisted high and wide, forearms and open claws hooked
    # in and down toward you, head cocked and shaking. Elbows bent so it never reads as a T-pose.
    c.key(3, {"loc": (0, 0.03, 0.06), "pelvis": (-4, 0, 0), "spine_01": (2, 0, 0), "spine_02": (12, 0, 0),
              "spine_03": (20, 0, 0), "neck_01": (28, 0, 0), "Head": Dir(0.05, -0.75, 0.7, 10),
              "clavicle_*": (0, -22, -8), "upperarm_*": Dir(0.75, -0.3, 0.6, -40), "lowerarm_*": Dir(0.05, -0.8, 0.05, -80),
              "hand_*": Dir(-0.05, -0.55, -0.85, -40), "fing_*": (-20, 25, 45),
              "wleg_*": 1.0, "ikf_*": (0.07, 0, 0.03), "ikfr_*": (22, 0, 0)})
    c.key(8, {"loc": (0, 0.02, 0.08), "pelvis": (-5, 0, 0), "spine_01": (2, 0, 0), "spine_02": (16, 0, 0),
              "spine_03": (24, 0, 0), "neck_01": (30, 0, 0), "Head": Dir(0.15, -0.8, 0.6, 22),
              "clavicle_*": (0, -26, -10), "upperarm_*": Dir(0.75, -0.25, 0.68, -40), "lowerarm_*": Dir(0.0, -0.75, 0.15, -80),
              "hand_*": Dir(-0.1, -0.5, -0.85, -40), "fing_*": (-25, 30, 50),
              "wleg_*": 1.0, "ikf_*": (0.07, 0, 0.04), "ikfr_*": (26, 0, 0)}, "LINEAR")
    c.key(15, coiled())
    c.tremor("Head", 0.07, 0.8, 3, 13)
    c.tremor("neck_01", 0.03, 0.8, 3, 13)
    c.tremor("hand_*", 0.05, 0.7, 3, 13)
    c.tremor("lowerarm_*", 0.02, 0.9, 3, 13)
    finish(c)


def lunged(hook):
    return {"loc": (0, -0.38, -0.18), "pelvis": (28, 0, 0), "spine_01": (18, 0, 0), "spine_02": (16, 0, 0),
            "spine_03": (12, 0, 0), "neck_01": (6, 0, 0), "Head": Dir(0, -0.4, 1, 0),
            "clavicle_*": (0, 0, -26),
            "upperarm_*": Dir(0.18, -1, 0.05 - 0.2 * hook, -40), "lowerarm_*": Dir(0.05, -1, 0.0 - 0.15 * hook, -60),
            "hand_*": Dir(-0.05, -1, -0.15 - 0.3 * hook, -50), "fing_*": (-20 + 85 * hook, 20 + 70 * hook, 20 + 70 * hook),
            "thigh_l": Dir(0.05, -0.75, -1), "calf_l": Dir(0.05, 0.35, -1),
            "thigh_r": Dir(-0.05, 0.75, -1), "calf_r": Dir(-0.05, 1, -0.55), "ikf_r": (0, 0, 0)}


def lunge(arm):
    """The strike, 9 frames (0.3 s): it launches flat out, arms spearing forward, claws hooking shut."""
    c = Clip(arm, "kp_lunge", 9, loop=False, lag=0.5)
    c.key(0, coiled(), "LINEAR")
    c.key(2, merge(lunged(0.0), {"wleg_*": 0.0}))
    c.key(5, merge(lunged(0.1), {"wleg_*": 0.0}), "LINEAR")
    c.key(7, merge(lunged(1.0), {"wleg_*": 0.0}))
    c.key(9, merge(lunged(1.0), {"loc": (0, -0.42, -0.24), "wleg_*": 0.3, "ikf_l": (0.05, -0.55, 0)}))
    finish(c)


def stagger(arm):
    """A missed lunge, 30 frames (1.0 s): it overshoots, stumbles a step, slaps a hand to the floor,
    head whipping around to find you, then hauls itself back up."""
    c = Clip(arm, "kp_stagger", 30, loop=False, lag=1.2)
    c.key(0, merge(lunged(1.0), {"loc": (0, -0.42, -0.24), "wleg_*": 0.3, "ikf_l": (0.05, -0.55, 0)}))
    down = {"loc": (0, -0.3, -0.36), "pelvis": (34, 0, 6), "spine_01": (16, 0, 0), "spine_02": (16, 0, -6),
            "spine_03": (10, 0, -4), "neck_01": (6, 0, 0), "Head": (-50, 0, 0),
            "clavicle_*": (0, 6, -16), "upperarm_l": Dir(1, -0.25, -0.55, -20), "lowerarm_l": Dir(0.7, -0.35, -0.75, -20),
            "hand_l": Dir(0.6, -0.4, -0.7, 0),
            "warm_r": 1.0, "ikh_r": (-0.4, -0.75, 0.075), "ikhr_r": (0, 0, 40), "pe_r": (-0.3, -0.5, -0.6),
            "fing_*": (10, 30, 40),
            "wleg_*": 1.0, "ikf_l": (0.05, -0.5, 0), "ikf_r": (-0.02, 0.25, 0), "ikfr_r": (30, 0, 0)}
    c.key(5, down, "LINEAR")
    c.key(8, merge(down, {"loc": (0, 0, 0.03)}), "LINEAR")
    c.key(9, merge(down, {"Head": (-10, 20, 55), "neck_01": (0, 0, 14)}))          # whips left
    c.key(14, merge(down, {"Head": (-12, 24, 58), "neck_01": (0, 0, 14)}), "LINEAR")
    c.key(15, merge(down, {"Head": (-20, -12, -40), "neck_01": (0, 0, -10)}))      # snaps right
    up = merge(hunch(0.3), {"ikf_l": (0.03, -0.25, 0), "ikf_r": (-0.03, 0.12, 0)})
    c.key(21, merge(down, {"loc": (0, -0.2, -0.26), "pelvis": (-8, 0, 0), "Head": (-6, -8, -20),
                           "warm_r": 0.6}))
    c.key(30, up)
    c.tremor("Head", 0.03, 1.0, 15, 30)
    finish(c)


def grab(arm):
    """Pull-out: it reaches in, the claws snap shut, and it yanks back with its whole body."""
    c = Clip(arm, "kp_grab", 24, loop=False, lag=0.9)
    base = hunch(0.4)
    c.key(0, base)
    reach = merge(base, {"loc": (0, -0.14, 0.0), "pelvis": (-6, 0, 0), "spine_02": (4, 0, 0), "Head": (12, 0, 0),
                         "clavicle_*": (0, -6, -10),
                         "upperarm_*": Dir(0.12, -1, -0.05, -30), "lowerarm_*": Dir(0.02, -1, 0.0, -50),
                         "hand_*": Dir(-0.05, -1, -0.1, -50), "fing_*": (-25, 0, 0),
                         "ikf_l": (0.03, -0.25, 0)})
    c.key(5, reach, "LINEAR")
    c.key(7, merge(reach, {"fing_*": (-10, 0, 0)}), "LINEAR")
    shut = merge(reach, {"fing_*": (85, 80, 70), "upperarm_*": Dir(0.08, -1, -0.12, -30)})
    c.key(8, shut, "LINEAR")
    yank = merge(base, {"loc": (0, 0.08, -0.04), "pelvis": (4, 0, -14), "spine_01": (0, 0, -10),
                        "spine_02": (2, 0, -12), "spine_03": (2, 0, -8), "Head": (26, 8, 10),
                        "upperarm_l": Dir(0.5, 0.25, -0.75, -50), "upperarm_r": Dir(-0.3, 0.1, -0.9, 40),
                        "lowerarm_l": Dir(-0.4, -0.85, 0.2, -80), "lowerarm_r": Dir(0.3, -0.9, 0.1, 70),
                        "hand_*": Dir(-0.4, -0.6, 0.4, -40), "fing_*": (85, 80, 70),
                        "ikf_l": (0.03, -0.2, 0), "ikf_r": (-0.04, 0.34, 0), "ikfr_r": (20, 0, 0)})
    c.key(12, yank)
    c.key(15, merge(yank, {"Head": (40, 14, 10), "loc": (0, 0.06, -0.08), "spine_02": (8, 0, -12)}), "LINEAR")
    c.key(24, merge(yank, {"Head": (34, 10, 12), "loc": (0, 0.07, -0.07), "spine_02": (8, 0, -12)}))
    c.tremor("hand_*", 0.04, 1.0, 12, 24)
    c.tremor("Head", 0.05, 1.0, 12, 24)
    finish(c)


def vent_drop(arm):
    """Out of the ceiling vent (opening ~3 m up) to the floor, 36 f: it pours out head first, arms
    groping for the floor, drops, lands on its hands, its legs slap down behind it, it freezes
    low, and then unfolds. The game holds its origin on the floor under the vent."""
    c = Clip(arm, "kp_vent_drop", 36, loop=False, lag=1.0)
    hang_arms = {"upperarm_*": Dir(0.25, 0.1, -1, -10), "lowerarm_*": Dir(0.2, -0.1, -1, -10),
                 "hand_*": Dir(0.15, -0.1, -1, 0), "fing_*": (-20, 10, 10), "clavicle_*": (0, -10, 0)}
    c.key(0, merge(hang_arms, {"loc": (0, -0.1, 2.05), "pelvis": (168, 0, 0), "spine_02": (-4, 0, 0),
                               "Head": (-20, 0, 0), "thigh_*": (0, 0, 0), "calf_*": (0, 0, 0)}))
    c.key(6, merge(hang_arms, {"loc": (0, -0.15, 1.55), "pelvis": (160, 0, 4), "spine_02": (-6, 0, 0),
                               "Head": (-40, 10, 0), "upperarm_*": Dir(0.35, -0.2, -1, -10)}), "LINEAR")
    c.key(7, merge(hang_arms, {"loc": (0, -0.16, 1.45), "pelvis": (158, 0, 4), "spine_02": (-6, 0, 0),
                               "Head": (-38, 12, 0), "upperarm_*": Dir(0.35, -0.25, -1, -10)}))
    c.key(12, merge(hang_arms, {"loc": (0, -0.1, 0.55), "pelvis": (132, 0, 0), "spine_02": (-2, 0, 0),
                                "Head": (-50, 0, 0), "thigh_*": (-40, 0, 0), "calf_*": (60, 0, 0),
                                "upperarm_*": Dir(0.4, -0.5, -1, -10)}))
    land = merge(crawl_pose(20), {"loc": (0, -0.05, -0.2), "pelvis": (100, 0, 0),
                                  "ikh_*": (0.38, -0.65, 0.075), "wleg_*": 0.0,
                                  "thigh_*": (-90, 0, 0), "calf_*": (40, 0, 0), "pe_*": (0.3, -0.3, -0.7)})
    c.key(16, land, "LINEAR")
    c.key(17, merge(land, {"loc": (0, -0.05, -0.28), "spine_02": (8, 0, 0)}))
    low = merge(crawl_pose(25), {"ikh_*": (0.38, -0.7, 0.075), "loc": (0, 0.02, -0.38)})
    c.key(20, low)
    c.key(24, merge(low, {"Head": Dir(0, -0.95, 0.3, 25)}), "LINEAR")
    c.key(25, merge(low, {"Head": Dir(-0.15, -0.95, 0.4, -15)}))                    # head snaps up
    c.key(28, merge(low, {"Head": Dir(-0.15, -0.95, 0.4, -15), "loc": (0, 0.02, -0.36)}))
    c.key(36, merge(hunch(0.3, low=0.35), {"warm_*": 0.0}))
    c.tremor("Head", 0.03, 1.0, 20, 30)
    finish(c)


def search(arm):
    """Sniffing in place: low and folded, one hand on the floor, the head sweeping close to the ground
    in jerky stages, with a fast sniffing tremor."""
    c = Clip(arm, "kp_search", 60, loop=True, lag=1.3)
    base = merge(hunch(0.4, low=1.0), {"spine_01": (6, 0, 0), "spine_02": (6, 0, 0), "neck_01": (10, 0, 0),
                                       "warm_l": 1.0, "ikh_l": (0.38, -0.62, 0.075), "ikhr_l": (0, 0, -40),
                                       "pe_l": (0.4, -0.3, -0.8), "Head": (-50, 0, 0)})
    c.key(0, merge(base, {"Head": (-50, 6, 34), "neck_01": (0, 0, 10)}))
    c.key(14, merge(base, {"Head": (-46, 10, 38), "neck_01": (0, 0, 12)}), "LINEAR")
    c.key(16, merge(base, {"Head": (-56, -4, 0), "neck_01": (0, 0, 0)}))
    c.key(30, merge(base, {"Head": (-50, -8, -36), "neck_01": (0, 0, -12), "pelvis": (0, 0, -4)}), "LINEAR")
    c.key(32, merge(base, {"Head": (-40, -34, -30), "neck_01": (0, 0, -12), "pelvis": (0, 0, -4)}))   # cocks its head
    c.key(44, merge(base, {"Head": (-42, -30, -28), "neck_01": (0, 0, -10)}), "EASE")
    c.tremor("Head", 0.03, 0.6)
    c.tremor("index_02_r", 0.05, 2.0)
    finish(c)


def recoil(arm):
    """Torchlight in its face: it flinches back, forearms crossed over the head, and cowers, shaking."""
    c = Clip(arm, "kp_recoil", 36, loop=False, lag=0.8)
    c.key(0, hunch(0.4), "LINEAR")
    shield = {"loc": (0, 0.16, -0.06), "pelvis": (-6, 0, 0), "spine_01": (-6, 0, 0), "spine_02": (-8, 0, -6),
              "spine_03": (-4, 0, -6), "neck_01": (0, 0, -10), "Head": (-10, 16, -36),
              "clavicle_*": (0, -10, -12), "upperarm_*": Dir(0.35, -0.6, 0.72, -40), "lowerarm_*": Dir(-0.8, -0.45, 0.35, -60),
              "hand_*": Dir(-0.6, -0.2, 0.75, -40), "fing_*": (50, 50, 50),
              "wleg_*": 1.0, "ikf_l": (0.05, 0.22, 0), "ikf_r": (-0.02, 0.32, 0), "ikfr_r": (15, 0, 0)}
    c.key(3, shield)
    cower = merge(shield, {"loc": (0, 0.12, -0.18), "pelvis": (34, 0, 0), "spine_01": (16, 0, 0), "spine_02": (16, 0, 0),
                           "spine_03": (10, 0, 0), "Head": (-40, 20, -36)})
    c.key(9, cower)
    c.key(36, merge(cower, {"loc": (0, 0.12, -0.2), "Head": (-38, 24, -40)}))
    c.tremor("Head", 0.04, 1.0, 4, 36)
    c.tremor("lowerarm_*", 0.03, 0.9, 4, 36)
    c.tremor("hand_*", 0.04, 0.8, 4, 36)
    c.tremor("spine_03", 0.015, 1.2, 4, 36)
    finish(c)


ALL = [idle, idle_head, idle_fingers, stalk, run, crawl, scream, lunge, stagger, grab, vent_drop, search, recoil]


def main():
    only = None
    if "--" in sys.argv:
        a = sys.argv[sys.argv.index("--") + 1:]
        for x in a:
            if x.startswith("--only="):
                only = x.split("=", 1)[1].split(",")
    arm = setup()
    for fn in ALL:
        fn(arm)
    baked = []
    meta = {}
    for c in clips:
        if only and c.name not in only:
            continue
        act = c.build()
        b = bake(arm, c, act)
        baked.append(b)
        meta[c.name] = {"frames": c.length, "seconds": c.length / FPS, "loop": c.loop, "native_speed": NATIVE.get(c.name, 0.0)}
        print("baked", c.name, c.length)
    finalize(arm, baked)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(OUT), export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
                              export_def_bones=True, export_anim_single_armature=True, export_reset_pose_bones=True,
                              export_optimize_animation_size=False, export_image_format="NONE",
                              export_materials="EXPORT", export_yup=True, export_apply=False, export_morph=False,
                              export_bake_animation=False, export_anim_slide_to_zero=False, export_extras=False)
    json.dump(meta, open(os.path.join(os.path.dirname(os.path.abspath(OUT)), "keeper_clips.json"), "w"), indent=1)
    print("EXPORTED", os.path.abspath(OUT))


main()
