# Last Handoff v1.0.1 - BUGFIX list (fresh-eyes QA pass, 2026-11-03)

Format: what - where - how found. Every fix has a regression check in tests/test_v101.gd
unless noted.

## Android / touch
1. Android BACK button quit the whole game instantly (Godot's default quit_on_go_back) and did
   nothing in menus. Now it acts like Esc: closes the open panel, opens/closes the pause menu, steps
   back through settings/history/credits; on the main menu the first press goes to QUIT, a second
   quits. - project.godot, autoload/ux.gd go_back(), scripts/ui/main_menu.gd - code review.
2. No app lifecycle handling: switching apps, a phone call, the home button, or alt-tab left the
   expedition running (the Keeper kept hunting) with audio playing. Now focus loss / app pause
   opens the pause menu, mutes audio, and autosaves the run (Android may kill a backgrounded app);
   panels like the inventory freeze the world until you return. Closing the window also autosaves.
   - autoload/ux.gd _notification - code review.
3. Rebinding on a touchscreen: tapping a key slot then tapping anywhere bound the action to
   "Left Mouse", making every tap fire it (e.g. every tap = interact); a pad slot on a phone got
   stuck listening. Taps now cancel listening. - scripts/ui/settings_menu.gd _capture - code review.
4. Touch buttons ignored the notch / rounded corners / gesture bar, and were spaced by screen width
   (stretched apart on 20:9, cramped differently on 4:3). Now placed inside the safe area with
   height-based spacing; re-laid out on rotation (sensor landscape flips the notch side). HUD corner
   widgets (objective, field device, toasts, area title) also step out of the notch. - touch_controls.gd,
   hud.gd apply_safe_area, ux.gd safe_margins - code review; tested at 16:9 / 20:9 / 4:3 with and without
   a simulated notch.
5. Toasts sat under the BAG / II touch buttons (top right). Moved below them on touchscreens. - hud.gd -
   phone preview screenshot.
6. No way to swap a battery cell by touch except digging into the bag. Added a CELL button that shows only
   when you carry a spare cell. - touch_controls.gd - code review.
7. Prompts on a phone showed keyboard keys ("[E]", "Esc", "[R] SWAP", "Press R to swap a cell") and
   keyboard/pad hint bars. Prompts now name the on-screen buttons (USE, LIGHT, CELL, BACK...) and the hint
   bars hide on touch. - ux.gd glyph, glyph_badge.gd, hint_bar.gd - code review + screenshot.
8. Soft keyboard covered the handoff message box (bottom half of a landscape phone). The form now lifts
   above the keyboard while typing; Enter/Done closes it and moves to "Leave the handoff". -
   handoff_screen.gd - code review.
9. "Windowed" display mode on a phone would turn off immersive mode (status + navigation bars over the
   game). Phones are always full screen and the option is hidden there. - settings.gd, settings_menu.gd -
   code review.
10. Phones requested mouse pointer capture on every tap. Skipped on phones. - player.gd - code review.

## Visuals / renderers
11. Phone preset (and Low) much too dark: the v1.0 phone preview rendered ~85 % of the screen near black
    (mean luminance 8.9/255). Without volumetric fog these presets used thicker black depth fog and lost
    the fog's ambient light. Now same depth fog as High, ambient x1.8 / exposure x1.25 on Phone, x1.3 / x1.1
    on Low. Phone render now mean 74/255 (desktop High shots: 60-80). - quality.gd - luminance measurement
    of the renders. (Note: before/after shots are of different views.)
12. Gas pockets (a hazard that explodes if your flashlight is on) were INVISIBLE on Phone, Low and the
    GLES3 fallback: their green haze is a volumetric FogVolume, which only renders with Forward+ volumetric
    fog. Added a translucent haze fallback; the GLES3 build no longer tries to compile the unsupported fog
    shader (it logged "shader type fog not supported in OpenGL renderer"). - gas_pocket.gd - Compatibility
    renderer run log.
13. Main menu: with CONTINUE showing, QUIT overlapped the footer hint bar at every 16:9/20:9 resolution
    (worse with the save-repaired notice). The column now fits above the footer. - main_menu.gd - GLES3
    screenshot.

## Gameplay / text / data
14. Controller unplugged mid-run: the member kept walking on the last stick input. Held input is now released
    and the game pauses. - ux.gd _on_joy_connection - code review.
15. The player's own handoff words were parsed as BBCode on the crate / wall notes ("[/i]", "[color]",
    "[img]res://..." changed or broke the note). Now shown literally. - chain_director.gd _note_body - code review.
16. A second ending trigger while an ending sequence was already playing could start a second sequence.
    Now ignored. - game.gd _on_ending - code review.
17. Hard-coded key names: "Hiding. Press E to come out.", "Battery dead. Press R to swap a cell",
    keypad "Step away [Esc]" - wrong after rebinding, on a gamepad and on a phone. Now use the current
    binding / device. - hiding_spot.gd, flashlight.gd, hud.gd - grep.
18. Tape subtitles: 20 lines in 4 tapes overlapped the next line by ~0.3 s, so two lines flickered stacked at
    every change. Trimmed to end just before the next line. - audio/logs/subtitles.json - timing script vs the
    .ogg durations.
19. Engine warning on every expedition load: "agent_radius is ceiled to cell_size voxel units" (17 per test
    run). Radius set to the exact value it was being rounded to (0.5 m), no behaviour change. -
    nav_baker.gd - grep of the full headless run output.

## Checked, no bug found
- 25 expeditions in a row through save/load: valid save, no lost/duplicated expedition numbers, own words
  intact (unicode, quotes, %s, backslashes), marks/notes stay capped, expedition 26 boots on the floor.
- Scripted session (menu -> intro -> all 9 areas -> locker -> Keeper -> death -> handoff -> next member ->
  pause/settings -> save & quit -> Continue -> extract -> handoff -> Seal ending -> end card): no script errors,
  player never fell out of the map. (autoload/harness.gd --shot=session)
- Ending fires once; START A NEW CHAIN after an ending; Continue after save & quit.
- Text: no doubled words / common misspellings found in UI, notes, lore or subtitles.
- Remaining output noise is engine-level: "ObjectDB instances leaked at exit" (sound playbacks still
  alive at quit; exit-time only, not per expedition) and renderer-capability warnings on Mobile/GLES3
  (SSAO / SSR / SSS / volumetric fog unavailable - expected, the presets turn them off).
