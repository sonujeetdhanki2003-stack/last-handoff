# Performance (Phase 6)

Measured with `tools/perf_probe.tscn` (the player's own camera, centre of each area, looking down the
room's long axis, torch on, aux power on). This box has **no GPU**: frame times are Mesa llvmpipe
(software Vulkan on the CPU, 960x540) and only useful as a *relative* cost between presets. Draw
calls, objects and primitives are renderer counts and do not depend on the machine.

| Area | Low | Medium | High | Phone |
|---|---|---|---|---|
| shaft | 748 dc / 404k tris / 232 ms | 803 dc / 491k tris / 322 ms | 831 dc / 586k tris / 397 ms | 745 dc / 390k tris / 174 ms |
| corridor | 1278 dc / 734k tris / 312 ms | 1287 dc / 853k tris / 400 ms | 1308 dc / 1033k tris / 512 ms | 980 dc / 438k tris / 272 ms |
| generator | 568 dc / 270k tris / 268 ms | 579 dc / 357k tris / 679 ms | 584 dc / 416k tris / 658 ms | 565 dc / 252k tris / 229 ms |
| security | 670 dc / 250k tris / 217 ms | 679 dc / 317k tris / 317 ms | 673 dc / 444k tris / 425 ms | 671 dc / 217k tris / 170 ms |
| storage | 450 dc / 394k tris / 216 ms | 455 dc / 465k tris / 293 ms | 450 dc / 578k tris / 414 ms | 254 dc / 158k tris / 167 ms |
| lab | 202 dc / 80k tris / 158 ms | 201 dc / 105k tris / 234 ms | 201 dc / 126k tris / 286 ms | 200 dc / 75k tris / 132 ms |
| archive | 137 dc / 76k tris / 144 ms | 147 dc / 85k tris / 190 ms | 147 dc / 99k tris / 248 ms | 149 dc / 80k tris / 107 ms |
| crawlspace | 238 dc / 194k tris / 140 ms | 239 dc / 211k tris / 200 ms | 239 dc / 261k tris / 275 ms | 251 dc / 183k tris / 111 ms |
| deep | 150 dc / 73k tris / 146 ms | 155 dc / 92k tris / 221 ms | 153 dc / 125k tris / 264 ms | 156 dc / 63k tris / 110 ms |

Occlusion culling (occluders built from the station's opaque wall/slab boxes) on vs off at Medium:
shaft 803 vs 1038 draw calls, generator 579 vs 665, storage 455 vs 605 (about 15-25 % fewer).

Presets (scripts/systems/quality.gd): shadow atlas 1024/2048/4096/1024, soft-shadow filter very-low/low/medium/hard,
MSAA off/off/2x/off, SSAO -/on/on/-, SSIL and volumetric fog only on High, small-prop draw distance
14/20/34/12 m, lamp fade 16/24/40/14 m, shadow fade 9/14/24/7 m, shadowed lamps 6/10/all/3, mesh LOD
threshold 4/2/1/6.

## Honest 60 fps estimate at Medium (not measured on real hardware)
Worst view is the corridor: ~1,300 draw calls (shadow passes included) and ~0.85 M triangles. That is a
light load for Forward+ on a discrete GPU. My estimate: **60 fps at 1080p Medium on a GTX 1060 / RX 580
class GPU or better**; integrated graphics (Iris Xe / Vega 8) about 30-45 fps at 1080p Medium, 60 fps
at Low with 75 % resolution scale. Phones (Phone preset, Mobile renderer, 75 % scale): expect 30 fps on
a 2021+ mid-range phone (Adreno 640-class); not measured, no device or emulator here.


## v1.1 Keeper animation cost
Same skeleton (65 bones, one skinned body + rags), so GPU skinning cost is unchanged on every preset,
including Phone (checked: the Mobile renderer with the Phone preset skins and shades the new clips correctly).
CPU, `godot --headless --path . res://tools/keeper_anim/anim_cost.tscn` (12 Keepers, 600 frames):
no animation 6.932 ms/frame, v1.1 AnimationTree + head look-at 6.971 ms, v1.0-style AnimationPlayer +
full procedural poser 7.028 ms, i.e. about 0.003 ms per Keeper per frame for the new tree (less than v1.0's
procedural layer). The game has one Keeper.


## v1.1.0 graphics pass (Blender props, Keeper bake, room AO)
Same probe (`tools/perf_probe.tscn -- --q=1,3 --areas=corridor,security,shaft,generator`, 960x540), v1.0.1 look via
`--nogfx11` vs the v1.1 look, same build:

| area | preset | draw calls | primitives |
|---|---|---|---|
| corridor | High (q1) | 1045 -> 985 | 663k -> 692k |
| security | High (q1) | 695 -> 612 | 334k -> 348k |
| shaft | High (q1) | 809 -> 761 | 482k -> 496k |
| generator | High (q1) | 597 -> 564 | 372k -> 381k |
| corridor | Phone (q3) | 834 -> 798 | 357k -> 385k |
| security | Phone (q3) | 679 -> 592 | 221k -> 231k |
| shaft | Phone (q3) | 723 -> 678 | 377k -> 391k |
| generator | Phone (q3) | 586 -> 561 | 267k -> 275k |

Draw calls go down (one Blender mesh replaces 3-9 boxes per door, locker and lamp). Triangles go up 2-8%.
Detailed meshes cast no shadow; an invisible box of the old size casts it instead
(`GfxAssets.shadow_proxy`), because omni lamps render every caster six times. Pipe flanges/hangers are one MultiMesh
each, cast no shadow and fade out past 26 m. The room AO is one extra texture read per pixel on the facility shader
(2048 atlas in the APK). Worst view: corridor on Phone, 834 -> 798 draws, 357k -> 386k primitives.
Frame times on this box are CPU-rendered (llvmpipe) and not a phone measure.


## v1.2.0 (lift/shaft remodel, winch room)
Same probe and order (`-- --q=1,3 --areas=corridor,security,shaft,generator`, 960x540). v1.1 numbers from the table
above; v1.2 with and without the new meshes (`--nogfx12`; the winch room geometry is in both):

| area | preset | v1.1 | v1.2 --nogfx12 | v1.2 |
|---|---|---|---|---|
| corridor | Phone (q3) | 798 dc / 385k | 774 dc / 359k | 810 dc / 359k |
| shaft | Phone (q3) | 678 dc / 391k | 674 dc / 391k | 748 dc / 393k |
| corridor | High (q1) | 985 dc / 692k | 985 dc / 693k | 1034 dc / 693k |
| shaft | High (q1) | 761 dc / 496k | 757 dc / 496k | 833 dc / 498k |
| winch (new) | Phone (q3) | - | 209 dc / 69k | 211 dc / 77k |

Worst view (corridor, Phone) +1.5 % draws, -7 % primitives. The remodelled view itself (shaft, Phone) is the
biggest change: +70 draws (+10 %), +0.5 % primitives. The old cage was ~60 boxes; the new one is one mesh, the
shaft steel is two MultiMeshes (one draw each), nothing new casts a shadow except two invisible slabs for the
cage. All v1.2 meshes together are 52k triangles. Note: this probe's counts depend on the order of areas and
presets in one run (shadow atlas state carries over), so only same-order runs are compared.
