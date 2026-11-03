# Balance pass (Phase 5)

Tool: `godot --headless --fixed-fps 60 --path . res://tools/balance_sim.tscn -- --runs=5`
A scripted player in the real station against the real Keeper (navmesh, senses, doors, lights).
Scenarios: **flee** (spotted at 6/9/12 m in view, sprint to the nearest locker that does not run past it),
**light** (spotted, stand and hold the torch on it), **hide** (120 s in a locker while it patrols),
**still** (crouched, torch off, in a dark corner for 120 s while it patrols).

## Before (Phase 4 values), 5 runs per row
| Scenario | caught | of which fatal | note |
|---|---|---|---|
| flee 6 m | 4/5 | 1 | mostly a non-fatal strike (55 dmg) then it backs off |
| flee 9 m | 3/5 | 2 | fatal = it watched you climb into the locker from < 10 m |
| flee 12 m | 4/5 | 1 | |
| light 6/9/12 m | 0/15 | 0 | repelled in 0.5-0.9 s every time |
| hide 120 s | 0/5 | 0 | it investigates the steam vent, never the locker |
| still 120 s | 0/5 | 0 | crouched + dark is invisible beyond 4.5 m |

Reading: the torch was a guaranteed answer (too strong, no tension), and running for a locker was a
coin flip that often ended in an instant fatal pull-out because "seen going in" reached 10 m.

## Changes
* `CHASE_WINDUP` 0.55 s: when it first spots you it straightens and screams before it comes (the alert
  sting plays). A head start you can use; it does not apply when it re-acquires you mid-chase.
* `REPEL_BEAM_TIME` 0.45 -> 0.6 s: the torch still works, but you have to hold it on its face.
* `SEEN_HIDING_RANGE` 10 -> 7 m: it has to be close to see which locker you used.
* While already investigating, station noises (steam, vents, doors it opens itself) no longer pull it
  off; anything the player makes still does.
* Vent exit is now an animated climb / duct / drop (about 2.4 s instead of an instant teleport), with
  the crawl audible in the duct overhead before it drops: fair warning.
* Kept: chase 3.6 m/s < run 4.4 m/s (you can outrun it while stamina lasts), patrol 1.25, search 1.6,
  wake 240 s or on generator power, 60 % drift toward the player's area, steam 5.0 s idle / 1.3 s warning /
  1.5 s burst (a crouch-walk crosses the vent zone well inside the idle window).

## Always a way out
* At full health the first catch is a strike, not death (only an injured member is grabbed).
* The torch repels it from up to 10 m (costs battery); lit rooms stop it at their edge.
* Lockers are safe unless it watched you get in from close range.
* It cannot enter the crawlspace; the coded lab door stops it.

## After
Same scripted scenarios, 5 runs each, after the changes:
```
flee d=6       runs 5  caught 4 (fatal 2)  noticed []
flee d=9       runs 5  caught 3 (fatal 2)  noticed []
flee d=12      runs 5  caught 4 (fatal 1)  noticed []
light d=6      runs 5  caught 0 (fatal 0)  noticed []
light d=9      runs 5  caught 0 (fatal 0)  noticed []
light d=12     runs 5  caught 0 (fatal 0)  noticed []
hide d=0       runs 5  caught 0 (fatal 0)  noticed [6.2, 6.2, 6.2, 6.2, 6.2]
still d=0      runs 5  caught 0 (fatal 0)  noticed [6.2, 6.2, 6.2, 6.2, 6.2]
```
("noticed" at 6.2 s is the Keeper going to check the steam vent's first burst, not finding the player.)

Honest reading: the torch stays a reliable answer (it now has to be held ~0.6 s); hiding and staying
still in the dark are safe; the scripted "sprint for the nearest locker" bot still gets struck in most
runs when spotted inside 12 m. Most of those strikes are non-fatal (full health); the fatal ones are
the bot climbing into a locker while it watches. The bot is naive (it never uses the torch, lit rooms
or doors while fleeing, and the nearest locker is often back past the Keeper), so treat the flee row as
a worst case, not the expected player experience. Next lever if playtests agree: chase speed 3.6 -> 3.3.



# Phase 6 fairness pass

Complaint: "sprint to the nearest locker gets struck 11/15". Two causes, both fixed:

1. **The bot itself.** The Phase 5 flee bot often never left the room: it ran into the closed
   generator door and stood there. Doors in the way are now opened (and it sidesteps when stuck), so the
   numbers below are real chases, not a bot pinned to a door.
2. **The Keeper struck from a run with no tell.** Now:
   * **Lunge with a telegraph.** Inside 2.1 m it stops, rears up and screams (0.5 s, pad rumble), then
     dashes 0.3 s in a straight line at 7 m/s and only hits within 1 m of where you are. A miss leaves it
     staggering for 1 s. Sprinting or sidestepping during the scream beats it.
   * **Parry.** Torchlight on its face during the rear-up counts 3x: it is repelled before it can lunge
     (test: 0.20 s).
   * **Chase build-up.** A fresh chase starts at 2.3 m/s and builds to 3.4 m/s over 3 s (was a flat 3.6).
     The player runs at 4.4.
   * **Stamina.** Sprint drains 0.16/s (6.25 s of sprint, was 5 s).
   * **Lockers.** "Seen going in" range 7 -> 5 m. When it does see you go in, it pulls you out with a
     **strike** (survivable at full health), not an instant kill; only an injured member is killed.
     The locker door is quicker (0.12 s open, 0.14 s close).

New scenario **careful** (a player using what the game teaches): avoid lockers that are past the Keeper,
only hide while unseen, torch it when close, cornered or during the telegraph.

## Results (5 runs per row, `-- --runs=5`, same seeds as Phase 5)
| Scenario | caught | fatal | Phase 5 caught (fatal) |
|---|---|---|---|
| flee 6 m (naive) | 3/5 | 0 | 4/5 (2) |
| flee 9 m (naive) | 3/5 | 0 | 3/5 (2) |
| flee 12 m (naive) | 4/5 | 0 | 4/5 (1) |
| careful 6 m | 0/5 | 0 | - |
| careful 9 m | 1/5 | 0 | - |
| careful 12 m | 1/5 | 0 | - |
| light 6/9/12 m | 0/15 | 0 | 0/15 |
| hide 120 s | 0/5 | 0 | 0/5 |
| still 120 s | 0/5 | 0 | 0/5 |

Reading: a naive sprint for the nearest locker is still struck 10/15 times, but **no run is fatal any more**
(was 5/15 fatal); the strike costs health and the Keeper backs off. A player who plays the way the
game teaches (torch, lockers it did not see, sidestep the scream) is struck 2/15 and killed 0/15.
Regression tests: `tests/test_fairness.gd` (telegraph before every strike, sprint escapes the lunge,
parry, chase build-up, outrun at full speed) and the locker rules in `tests/test_hiding.gd`.


# v1.1 (Blender Keeper animations): fairness re-check

Only the presentation changed (clips + AnimationTree); every gameplay constant is the same
(telegraph 0.5 s, lunge 0.3 s at 7 m/s, stagger 1.0 s, chase 2.3 -> 3.4 m/s, sprint 6.25 s) and
`tests/test_anim.gd` pins them. Same sim, same seeds, `--runs=5` per row:
```
flee d=6       runs 5  caught 3 (fatal 0)
flee d=9       runs 5  caught 3 (fatal 0)
flee d=12      runs 5  caught 4 (fatal 0)
careful d=6    runs 5  caught 0 (fatal 0)
careful d=9    runs 5  caught 0 (fatal 0)
careful d=12   runs 5  caught 1 (fatal 0)
light d=6/9/12 runs 15 caught 0 (fatal 0)
hide d=0       runs 5  caught 0 (fatal 0)
still d=0      runs 5  caught 0 (fatal 0)
```
Naive flee: struck 10/15, fatal 0/15 (v1.0.1: 10/15, 0/15). Careful: struck 1/15, fatal 0/15
(v1.0.1: 2/15, 0/15). Torch / hide / still: never caught. Same or better on every row.


# v1.2 (winch room, fake-outs, heartbeat): fairness re-check

The winch room is on the Keeper's nav mesh and patrol; fake-outs make no sound the Keeper hears and the heartbeat
only reads its real distance. Same sim, same seeds, `--runs=5` per row:
```
flee d=6       runs 5  caught 3 (fatal 0)
flee d=9       runs 5  caught 2 (fatal 0)
flee d=12      runs 5  caught 4 (fatal 0)
careful d=6    runs 5  caught 1 (fatal 0)
careful d=9    runs 5  caught 0 (fatal 0)
careful d=12   runs 5  caught 0 (fatal 0)
light d=6/9/12 runs 15 caught 0 (fatal 0)
hide d=0       runs 5  caught 0 (fatal 0)
still d=0      runs 5  caught 0 (fatal 0)
```
Naive flee: struck 9/15, fatal 0/15 (v1.1: 9-10/15, 0). Careful: struck 1/15, fatal 0/15 (v1.1: 0-1/15). Torch /
hide / still: never caught.
