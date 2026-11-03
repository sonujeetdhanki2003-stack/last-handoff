# Last Handoff - Godot 4 project (v1.2.0)

Third-person survival horror in Halden Deep Research Station. Each run is one
expedition; later phases add the handoff (what you leave for the next expedition).

* Engine: **Godot 4.7.2 stable**, GDScript, **Forward+** renderer (Vulkan / D3D12).
  The project also opens in the Compatibility renderer (`--rendering-method gl_compatibility`);
  `world_env.gd` then swaps volumetric fog / SSAO / SSIL for depth fog.
* Open `project.godot` in Godot 4.7.x. Main scene: `scenes/ui/main_menu.tscn`.

## Controls (all rebindable: Settings > Controls, keyboard and gamepad columns)
| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Look | Mouse | Right stick |
| Run (hold or toggle) | Shift | L3 / LB |
| Crouch (toggle or hold) | C / Ctrl | B |
| Show objective | J | D-pad up |
| Skip intro / cinematic | Space / Esc | A / Start |
| Debug overlay (Keeper state, noise rings) | F3 | - |
| Interact (tap or hold) | E | A |
| Flashlight | F | Y |
| Swap battery cell | R | X |
| Inventory | Tab / I  (U = use, G = drop) | Back |
| Switch shoulder | V | R3 |
| Pause | Esc | Start |

## The prototype mission (5-10 min)
Shaft (handoff crate: keycard, cell, note) -> corridor -> generator room (hold E to crank the
generator: emergency power, breaker for the corridor lights, fuse 1) -> security office (needs
power: memo with this expedition's 4-digit lab code, fuse 2, charging dock) -> storage (blue keycard:
fuse 3, spare cell) -> fuse panel (3 fuses) + master switch -> Lab 3 keypad (the code) -> research
drive -> back to the lift.

## Folder structure
```
autoload/      Settings (settings.cfg + input map), Events (signal bus), GameState (expedition state),
               Harness (screenshots/automation, inactive without args), Sfx
scripts/systems/      pure-data systems: Inventory, PowerGrid, ObjectiveTracker, BatteryModel, ItemDB
scripts/interaction/  Interactable base + Pickup, Door, Lever, Generator, FusePanel, Keypad, ChargingDock, Lift
scripts/player/       Player (movement/interaction), CameraRig, Flashlight, PlayerAnimator (AnimationTree)
scripts/world/        Level, WorldEnv (quality-scaled environment), PoweredLight, TriggerFlag, Notes, game.gd
scripts/ui/           HUD (prompt, battery, objective, inventory, notes, keypad, end screen), menus, settings
scenes/               game.tscn, player.tscn, levels/facility_greybox.tscn, ui/*.tscn
tools/build_scenes.*  regenerates player/level/game scenes + materials + theme from code
tests/                headless test runner + one test file per system
audio/sfx, assets/    sounds, character, textures, fonts, materials
```

## Regenerating scenes
`facility_greybox.tscn`, `player.tscn`, `game.tscn`, `assets/materials/*.tres` and `ui/theme.tres`
are generated: `godot --headless --path . res://tools/build_scenes.tscn`. Edit `tools/build_scenes.gd`
(or stop using the generator and edit the scenes in the editor from Phase 3 on; the scripts do not
depend on the generator).

## Tests (headless, print PASS/FAIL, exit code 0 = all green)
```
godot --headless --path . --import                       # first time / after adding class_name scripts
godot --headless --path . res://tests/run_tests.tscn     # everything
godot --headless --path . res://tests/run_tests.tscn -- --tests=inventory,doors
```
Systems: inventory, power, objectives, battery, settings, interaction, doors, switches, puzzles,
movement, camera (collision sweep), playthrough (completes the whole mission through the player's
own aim + interact path).

## Screenshots (needs a display; xvfb works)
`godot --path . -- --shot=dark --out=/tmp/dark.png` (scenarios in autoload/harness.gd).

## Export
Presets in `export_presets.cfg`: "Windows Desktop" (single exe, PCK embedded) and "Linux".
`godot --headless --path . --export-release "Windows Desktop" ../export/windows/LastHandoff.exe`

## Settings file
`user://settings.cfg` (Windows: %APPDATA%/Godot/app_userdata/Last Handoff/settings.cfg):
volumes (master/music/sfx/ambience), mouse + gamepad sensitivity, invert Y, camera shoulder,
fullscreen, v-sync, quality (Low/Medium/High), resolution scale (FSR below 100%), FOV, brightness.


## Phase 5 (UI and polish)
* One UI language (worn field terminal): `scripts/ui/ui_kit.gd` (palette, fonts, theme), `term_panel.gd`,
  `term_button.gd`, `hint_bar.gd` (prompts follow the last-used device; colour-blind-safe shapes),
  `settings_menu.gd` (Audio / Controls with rebinding / Graphics / Accessibility), `brightness_screen.gd`
  (first-launch calibration), `subtitle_box.gd`, `title_card.gd`. `autoload/ux.gd`: device tracking,
  UI sounds, fades between scenes, subtitles, title cards.
* Keeper: its own body (`scripts/threat/keeper_body.gd`, generated skinned mesh on the stretched rig) and a
  procedural pose layer (`keeper_poser.gd`, a SkeletonModifier3D): hunch, head tilt, search sniff,
  lunge/grab reach, shielding from light, crawl; animated vent climb/duct/drop.
* Cold open (`scripts/world/intro_director.gd`): the cage descends the shaft, PA announcement, gate,
  camera on the previous member's crate, "Expedition N / name" title card. Skippable.
* Endings: camera sway, sound design, end card with the chain record (`scripts/ui/end_card.gd`).
* Audio: `autoload/sfx.gd` (surface footsteps, positional world sounds with captions, PA, tape subtitles
  from `audio/logs/subtitles.json`). Credits in CREDITS.md.
* Balance: `godot --headless --fixed-fps 60 --path . res://tools/balance_sim.tscn -- --runs=5`
  (scripted player vs the real Keeper; see BALANCE.md).
* Tests: `ui` (every screen reachable/escapable by keyboard AND gamepad via real input events) and
  `polish` (rebinding save/load, hold/toggle, subtitles, intro, title card, surnames, F3 overlay).


## Release builds (v1.0.0)
* **Windows:** `godot --headless --path . --export-release "Windows Desktop" out/LastHandoff.exe`
  (single exe with the pck embedded, icon from `icon.ico`).
* **Android:** `GODOT=/path/to/godot python3 tools/build_android.py out/LastHandoff.apk` - copies the
  project to a scratch dir, caps textures at 512 px (characters 1024 px), imports ETC2, exports the
  "Android" preset (arm64-v8a, minSdk 24, Mobile renderer with GLES3 fallback). Signing comes from
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD` (the keystore is not in the source zip).
  Needs Android build-tools + JDK 17 in the editor settings and the 4.7.2 Android export templates.
* **Graphics presets** live in one table, `scripts/systems/quality.gd` (Low / Medium / High / Phone):
  shadow atlas + soft-shadow filter, MSAA/FXAA, SSAO/SSIL/volumetric fog, small/medium prop draw
  distance, lamp fade + shadow fade distance, shadowed-lamp budget, mesh LOD threshold. Occluders are
  built at load from the station's opaque wall/slab boxes. Phones start on Phone at 75 % resolution.
* **Touch controls** (`scripts/ui/touch_controls.gd`) appear only on touchscreens: floating left
  stick, right-half swipe look, USE / LIGHT / CROUCH / RUN / BAG / II buttons, BACK while a panel is open.
* **Profiling:** `xvfb-run godot --path . res://tools/perf_probe.tscn -- --q=0,1,2,3` prints draw calls,
  objects, primitives and frame time per area per preset. Balance: `tools/balance_sim.tscn` (BALANCE.md).
* **Keeper asset:** `tools/keeper_sculpt/sculpt_keeper.py` (the sculpt/texture-bake functions used to make
  `assets/characters/keeper/`; needs numpy/scipy/Pillow and the CC0 base mesh, not shipped).


## v1.0.1 (bug-fix release)
19 fixes from a fresh QA pass, listed with where/how found in `BUGFIX_v1.0.1.md`; regression checks in
`tests/test_v101.gd` (suite total 1057). Highlights: Android back button = Esc (no longer quits), focus loss /
app background pauses + mutes + autosaves (`autoload/ux.gd`), safe-area-aware touch layout with a CELL button,
touch prompts, soft-keyboard lift on the handoff form, brighter Phone/Low presets, gas-pocket haze fallback where
volumetric fog is off, controller-unplug pause, literal handoff words in notes, subtitle overlap fix.
* Scripted smoke session: `godot --path . -- --shot=session [--fpe=N --speed=S]` (also runs in the exported exe,
  e.g. `wine LastHandoff.exe --headless -- --shot=session`); prints `SESSION step ...` and `SESSION DONE`.


## v1.1.0: Keeper animations made in Blender
* 13 keyframed clips for the Keeper, authored in Blender 4.2 LTS by script (reproducible):
  `blender -b -P tools/keeper_anim/build_clips.py` -> `assets/characters/keeper/KeeperAnimated.glb`, then
  `godot --headless --path . --import` and `godot --headless --path . -s res://tools/keeper_anim/extract_library.gd`
  -> `assets/characters/keeper/keeper_anims.res` (what the game loads). Clay contact strips:
  `blender -b -P tools/keeper_anim/render_strips.py -- --out=/tmp/strips`.
* Rig (`keeper_rig.py`): the Keeper glTF imported into Blender, plus foot/hand IK and knee/elbow poles built in
  Blender; clips are sparse keys with per-bone lag (overlapping action), snapped keys for twitches, F-curve
  noise for tremor; the IK is baked to plain FK on the deform bones, so the export needs no constraints.
* In game (`keeper.gd`): an AnimationTree (Transition with per-clip cross-fades -> TimeScale -> an upper-body
  strike OneShot) driven by the AI state. Locomotion clips are in place and keyed at the game's own speeds
  (stalk 1.25, run 3.4, crawl 1.2 m/s); playback is scaled by the real velocity so the feet don't skate.
  `keeper_poser.gd` now only turns the head toward you. Gameplay timings are unchanged and the clips match
  them: scream 0.5 s = LUNGE_TELEGRAPH, lunge 0.3 s, stagger 1.0 s (tests/test_anim.gd).
* Preview reel: `xvfb-run godot --path . --write-movie /tmp/k.avi --fixed-fps 30 --resolution 854x480 -- --shot=keeper_preview --fastshadow=1`.

## v1.1.0: graphics made in Blender
Everything is generated by scripts in `tools/gfx_blender/` (Blender 4.2 LTS headless, `blender -b -P <script>`),
so it can be rebuilt. `-- --nogfx11` turns the whole pass off at runtime, for A/B captures.
* **Keeper sculpt** (`keeper_sculpt_bake.py`, ~30 s): a 0.6M-face Catmull-Clark copy of the game body, displaced
  with the ribcage/sternum/spine/scapula anatomy, sinew cords along every limb bone, skin folds at the joints,
  veins, wrinkles and pores, then baked (selected-to-active) onto the game mesh's own UVs: tangent normal
  (merged with v1.0's muscle normal), AO and cavity -> `T_Keeper_Normal_v11.png`, `T_Keeper_ORM_v11.png`,
  `T_Keeper_BaseColor_v11.png`. Rig, weights and the 13 clips are untouched.
* **Fused helmet** (`keeper_helmet.py`): a modelled helmet (shell, brim, crown ridge, lamp + bracket), baked from a
  sculpted copy with voronoi impact cracks, a long split, dents, chipped paint over rust -> `KeeperHelmet.glb`.
* **Hero props** (`build_props.py`): door panel + jamb + header, locker body + louvred door, caged batten fixture,
  ceiling vent grate, pipe flange + hanger, each modelled at the game's exact size with bevels, a lightmap UV2 and
  a baked AO x grime map (`assets/props_v11/`), applied as a multiply detail over the existing triplanar
  materials. Doors and lockers keep their colliders and node names; lamps keep their lights. Godot generates LODs.
* **Room AO** (`export_level.tscn` -> `bake_level_ao.py` -> loaded by `GfxUpgrade`): the 70 wall/floor/ceiling
  boxes get a lightmap UV2 and one 4096 AO atlas baked in Cycles with every prop as an occluder (~8 min), sampled
  by `facility_surface.gdshader` with a contrast curve, so corners and contact shadows read on every preset,
  including Phone/Low (no SSAO). Lights stay dynamic (power circuits switch them), so AO, not lightmaps.
* **Wet + grime**: puddles pool in the AO-dark corners of wet floors, walls stay damp along the drip streaks and
  the bottom 25 cm (lower roughness), a dripping vent with a puddle under it, rust runs from the pipe joints.
* Shots: `xvfb-run godot --path . --resolution 1280x720 res://tools/gfx_blender/gfx_shots.tscn -- --out=/tmp/s --tag=after --q=2`
  (fixed camera spots; prints draw calls / primitives per view). Tests: `tests/test_gfx.gd`.

## v1.2.0: haptics, the winch room, chapters, achievements, fake-outs, How to Play
* **Heartbeat + vibration** (`scripts/systems/threat_feedback.gd`): a synthesised heartbeat that speeds up
  (62 -> 150 bpm) and gets louder as the Keeper gets closer (16 m -> 2 m) or turns hostile (search, chase,
  lunge). Each beat is one short buzz: `Input.vibrate_handheld` on phones (25-70 ms, at least 0.38 s apart,
  nothing below level 0.3), pad rumble on desktop. Silent when paused, unfocused, dead or with a dormant Keeper.
  Settings: Audio > Heartbeat, Controls > Vibration (phone and controller); both default on. The APK asks for
  `VIBRATE` (an install-time permission, no prompt).
* **Fake-out scares** (`scripts/world/fakeout_director.gd`): locker rattle, lamp brownout, distant thud,
  distant footsteps, vent creak. None in the first 50 s, 75-120 s apart, never during or 25 s after a
  chase/search/investigation, never with the Keeper within 14 m, always 12+ m from it, and they make no noise
  the Keeper can hear. Brownouts are skipped with Reduce flashes on. Tests: `tests/test_v12.gd`.
* **Lift + shaft remodel and the winch room**: `blender -b -P tools/gfx_blender/build_lift_v12.py [-- --only=name]`
  -> `assets/props_v12/` (cage, rails, ropes, counterweight, shaft H-columns and buntons, call box, hoist winch,
  records-shelf fill), applied at load by `scripts/world/gfx_v12.gd` (visual only; `-- --nogfx12` turns it
  off, `-- --v12skip=a,b` drops single meshes for perf A/B). The winch room (x 4.15..10, z 1..7) is behind a
  door in the shaft's east wall: hoist winch, records shelves, a locker, the lift engineer's log
  (`Notes "lift_log"`), on the Keeper's nav mesh and patrol. `godot --headless --path . res://tools/build_scenes.tscn -- --only=level`
  rebuilds just the level scene (materials, theme, player and game untouched). Room AO re-baked
  (`export_level.tscn -- --noao` -> `bake_level_ao.py`, which now also copies the receiver map).
* **Chapters + achievements** (`autoload/progress.gd`, `user://progress.json`, separate from the chain save so
  1.0/1.1 saves load unchanged; the first 1.2 launch quietly unlocks what an old save already reached).
  Chapters: I The Descent, II Emergency Power, III Lab 3, IV The Way Up; each opens when you first reach it.
  A chapter run is practice: it never writes the chain, tapes or decisions. 14 achievements (3 hidden as "???"
  until earned): First Descent, Emergency Power, Three of Three, Clearance, The Drive, Rode It Up, Not Today,
  Hold Your Breath, Winch Room, Pass It On, The Relay, Her Voice*, Where It Began*, Last Handoff* (*hidden).
  Toast on unlock; Main menu > Achievements / Chapters (touch, keyboard, controller).
* **How to Play** (`scripts/ui/how_to_play.gd`): Goal, Controls (touch / keyboard + mouse / controller, read
  from the live bindings), Survival tips, Saving & chapters. No spoilers (tested).
* **RUN on phones**: touch devices default to Toggle sprint (old touch saves migrate once unless the player
  chose a mode); tapping RUN then pushing the stick works (0.45 s grace); RUN while crouched stands you up;
  RUN glows amber while running and flashes red with a reason ("Too tired to run", "Out of breath", "Too hurt
  to run", "Push the stick to run", "No room to stand up"), hints at most every 2.5 s; a stamina ring around
  RUN and a thicker stamina bar on touch; the 8 px dead ring around the touch buttons is gone.
* UI shots: `-- --shot=menu_howto|menu_achievements|menu_chapters [--demo_progress] [--page=N]`.
