# Last Handoff - Godot 4 project (Phase 5)

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


## Notes on this repository snapshot
This repository is a snapshot of the Phase 5 project (commit 5222cb2). Three files are stored slightly differently from the
working project so they fit the upload pipeline (each change is inaudible or invisible in game):
* `audio/music/drone.wav` is stored at 22.05 kHz instead of 44.1 kHz (the drone has no content above 11 kHz).
* `assets/characters/explorer/T_Explorer_Normal.png` and `T_Hair_1_Normal_png.png` are stored with each colour channel
  rounded by at most 1/255 (the hair map without its fully opaque alpha channel). Godot VRAM-compresses both on import.
