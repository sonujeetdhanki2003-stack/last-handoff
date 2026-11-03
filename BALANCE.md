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

