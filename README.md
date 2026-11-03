# LAST HANDOFF

**A third-person survival horror game where every expedition hands off to the next.**
Made in Godot 4 by **Sonujeet**. Single-player, fully offline.

> 🚧 **Status: v1.0 in progress.** Phases 1–5 of 6 are done (foundation, core gameplay, world and atmosphere,
> survival and the handoff, UI and polish). Phase 6 (full testing, performance and the Windows release) is underway.

![Main menu](docs/screenshots/menu.jpg)

## The pitch

Halden Deep Research Station, Level B2. Something went wrong down here, and you are not the first one sent to find out.
The cage goes down one person per trip. You restore power, solve your way through a dead facility with a flashlight
that keeps running out, and try to bring Dr. Varga's research drive back up, while something in the dark listens for you.

You probably won't make it. That's fine. Someone comes after you.

## The handoff

Every run is one **expedition**, played by a new named member of the team. When your run ends (death, extraction, or giving up):

- you leave a **message** for the next expedition (templates or your own words),
- you leave **one item** in the handoff crate at the bottom of the shaft,
- you leave a **chalk mark** where your run ended.

The next member starts at that crate, finds your item and your note, sees the marks every earlier expedition left,
and inherits the world exactly as you left it: doors you opened stay open, generators you fixed keep running, puzzles stay solved.
**Decisions stick across expeditions** and decide which of the **3 endings** the chain reaches. The main menu keeps
a local **expedition history**: every member, how deep they got, how it ended, what they left and what they decided.

## Features

- Third-person explorer with an over-the-shoulder camera, flashlight + battery cells, stamina, injuries and limping
- **The Keeper:** a creature that hunts by sound on a navmesh (patrol, investigate, chase, lose track), backs off from
  your flashlight, crawls through the vents, and checks lockers it saw you get into. Hide in lockers or under cots
- Hazards: steam bursts, live wires once the power is back, gas that punishes a lit flashlight
- Puzzles: a generator, breakers, a fuse panel, keycards and a keypad code that changes every expedition
- Environmental storytelling: voiced audio logs, research documents, scrawls and camps from earlier expeditions
- Atmosphere: PBR materials, volumetric fog, power-tied and emergency lighting, room-tone ambience and a tension layer
- Cold-open lift descent, "Expedition N" title cards, in-engine ending sequences with end cards
- Save/continue with atomic writes, a backup slot and corrupt-save recovery
- Full settings: audio, graphics presets, keyboard **and gamepad** rebinding, hold/toggle sprint and crouch,
  subtitles and sound captions, colour-blind-safe prompts, camera shake, brightness calibration
- 729 headless automated checks across every system (`tests/`)

## Screenshots

| | |
|---|---|
| ![In play: HUD and subtitles](docs/screenshots/hud.jpg) | ![Cold open: the lift descent](docs/screenshots/intro.jpg) |
| ![Expedition title card](docs/screenshots/titlecard.jpg) | ![Main menu](docs/screenshots/menu.jpg) |

## Controls

All rebindable in **Settings › Controls** (keyboard and gamepad).

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Look | Mouse | Right stick |
| Run (hold or toggle) | Shift | L3 / LB |
| Crouch (toggle or hold) | C / Ctrl | B |
| Interact (tap or hold) | E | A |
| Flashlight | F | Y |
| Swap battery cell | R | X |
| Inventory (U use, G drop) | Tab / I | Back |
| Show objective | J | D-pad up |
| Switch shoulder | V | R3 |
| Skip intro / cinematic | Space / Esc | A / Start |
| Pause | Esc | Start |
| Debug overlay (off by default) | F3 | – |

## Open it in Godot

1. Install **Godot 4.7** (developed on 4.7.2 stable, standard build, GDScript only, no C#).
2. Clone this repo, then in the Project Manager choose **Import** and pick `project.godot`.
3. The first import takes a minute (the `.godot/` cache is not in the repo). Press **F5** to play; the main scene is `scenes/ui/main_menu.tscn`.

Renderer: **Forward+** (Vulkan / D3D12). It also runs with `--rendering-method gl_compatibility` (fog and SSAO swap for simpler depth fog).

Run the test suite headless:

```bash
godot --headless --path . --import
godot --headless --path . res://tests/run_tests.tscn
```

Export presets for **Windows Desktop** (single .exe with the pack embedded) and **Linux** are in `export_presets.cfg`.
Developer notes (folder layout, generators, screenshot harness, balance simulator) are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
and [BALANCE.md](BALANCE.md).

## Credits

Design, code and direction: **Sonujeet**.
Third-party assets (Quaternius characters and animations, Poly Haven textures and props, Google Fonts) are CC0 or OFL;
sound effects, voices and music were generated for the project. Everything is listed with its licence in [CREDITS.md](CREDITS.md).

## License

**Source-available, all rights reserved.** You're welcome to read the code; you may not copy, modify, redistribute
or republish it or the game. See [LICENSE](LICENSE). Third-party assets keep their own licences (see CREDITS.md).
