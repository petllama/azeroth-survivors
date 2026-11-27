# Azeroth Survivors

A Vampire Survivors-style arcade game that runs inside WoW: Forever as an addon. Survive the Scourge for 10 minutes; spells cast themselves, you move and pick upgrades.

## Install

Download `AzerothSurvivors-<version>.zip` from [Releases](https://github.com/petllama/azeroth-survivors/releases) and unzip it into `World of Warcraft/_forever_/Interface/AddOns/` so you get `AddOns/AzerothSurvivors/AzerothSurvivors.toc`. A first install needs a full game restart; updates need `/reload`.

Built for WoW: Forever (interface 16001, a retail-based client). It uses only plain frames and textures, so it may work on other retail-based clients with the `## Interface` line changed; untested.

## Play

- `/azs` (or `/survivors`, or the addon compartment button) opens the window. `SPACE` starts a run.
- `WASD` / arrow keys move. `1` `2` `3` (or click) pick a level-up. `ESC` pauses; `Q` in the pause screen ends the run.
- Movement keys are captured only while a run is playing; on the title, pause and game-over screens your character can walk.
- Entering real combat pauses the game and releases the keyboard (WoW forbids changing keyboard capture in combat).

On the game-over screen `SPACE` replays the same class and `C` returns to class select.

**Pause and quick save:** `P` / `ESC` or the Pause button pause; `F6` quick saves, `F9` quick loads (one slot, kept across `/reload` and logout; a run in progress is also saved on logout). A saved run shows as **Continue** on the class screen.

**Flights:** like Polestar's Freedoom Arcade. On a flight with a minute or more to go (out of combat, outside instances) a small card asks *Do you want to play Azeroth Survivors while waiting?* (Play, Not now, Don't ask again); after that a *Play Azeroth Survivors* button stays while you fly. When the flight time is known (learned on an earlier landing of that route, or taken from Polestar's own flight recordings), the run is saved, paused and closed ten seconds before landing; on a route with only an estimate (first flight, no Polestar record) it stays open until you actually land. A fight on the way or the landing itself also saves, pauses and closes it, so your keys are yours again. It sits under Polestar's flight timer when that is shown. `/azs flight` turns the offer on or off.

Other commands: `/azs save` / `/azs load`, `/azs flight`, `/azs anim` (movement animations on/off), `/azs debug` (fps / sim / draw ms overlay), `/azs stress 600` (stress test with 600 enemies, invulnerable), `/azs numbers` (damage numbers on/off), `/azs scale 0.8`, `/azs reset` (window position).

## Classes

Pick a class on the title screen (`1`-`6` or click). Each has its own five skills; passives are shared.

| Class | Style | Skills |
|---|---|---|
| Paladin | 120 hp, armored | **Crusader Strike** (start, frontal swing), Consecration (burning ground), Blessed Hammers (orbiting), Avenger's Shield (bounces between enemies), Divine Storm (spin that heals per enemy hit) |
| Rogue | 85 hp, fast, 15% crit | **Sinister Strike** (start, quick stabs), Fan of Knives (ring of knives), Shuriken Toss (piercing star), Blade Flurry (tight orbiting blades), Deadly Poison (all hits poison) |
| Druid | 110 hp, regenerates | **Wrath** (start, nature bolts), Moonfire (strikes + burn), Starfall (falling stars, area damage), Thorns (aura + damages attackers), Entangling Roots (roots everything nearby) |
| Mage | 90 hp, fragile | **Frostbolt** (start, bolts that slow), Fireball (explodes in an area), Arcane Missiles (homing volley), Blizzard (ice storm on the thickest pack: damage + slow), Frost Nova (freezes everything around you) |
| Warlock | 100 hp, drains life | **Shadow Bolt** (start), Corruption (damage over time that spreads when the victim dies), Rain of Fire (falling fel fire zones), Drain Life (beam on the nearest enemies that heals you), Summon Imp (a pet that follows you and throws firebolts) |
| Hunter | 105 hp, 10% crit | **Auto Shot** (start, piercing arrows), Multi-Shot (fan of arrows), Explosive Trap (mines that explode when stepped on), Volley (arrows rain on a pack), Call Wolf (a pet that hunts down and bites enemies) |

Passives (5 slots, level 5 max): Might, Haste, Sprint, Fortitude, Renew, Greed, Devotion, Arcane Reach, Precision (crit). Critical hits deal double damage (orange numbers); burns and poison tick in green.

Every Mage, Warlock and Hunter skill has an evolved form (recipe: skill at level 6 + a passive, opened from a chest): Frostfire Bolt (Haste), Pyroblast (Might), Arcane Barrage (Precision), Frozen Tempest (Arcane Reach), Deep Freeze (Devotion), Chaos Bolt (Might), Unstable Affliction (Renew), Hellfire Rain (Arcane Reach), Drain Soul (Fortitude), Demonic Legion (Haste), Aimed Shot (Precision), Barrage (Haste), Expert Trapper (Arcane Reach), Hail of Arrows (Might), The Beast Within (Sprint).

## Enemies and events

Ghouls, bats, wraiths, brutes, an elite death knight every minute (drops a potion), bat swarms every 90 s, the Frost Lich at 8:00. Win at 10:00. Best run is saved per class.

From 2:30 new enemies join the waves:
- **Skeleton mages** keep about 220 px away and fire slow bolts: dodge them (armor and the hit grace period apply).
- **Worgen** stop, glow orange and show their dash line, then charge in a straight line.
- **Oozes** split into two small oozelets when they die.

Map events: a **ring of skeletons** closes in at 3:30 and 6:30; a **gold goblin** appears at 1:40, 4:20 and 7:00 and flees: catch it before it escapes (15 s) for a pile of coins. **Braziers** burn near you every 30 s (up to 3): break them for a pickup: **magnet** (every crystal flies to you), **chicken** (heals 30%) or **bomb** (damages everything on screen).

## Zones

The arena takes the look of where you play: Tirisfal (and other dark lands), the Barrens (and other dry lands), Elwynn (green lands) or the frozen north. Each theme has its own ground and leans the waves (more skeleton mages in Tirisfal, worgen in the Barrens, oozes in Elwynn, wraiths and bats in the snow). The zone comes from your map (`C_Map.GetBestMapForUnit`), walking up to the continent by name; elsewhere the arena keeps the default ground.

## Layout

- `AzerothSurvivors/Content.lua` data and balance; `Sim.lua` pure-Lua simulation (no WoW API, spatial grid, pooled entities); `Render.lua` pooled textures/lines/numbers; `UI.lua` HUD and panels; `Main.lua` window, keyboard, loop, slash commands.
- `AzerothSurvivors/Art/*.tga` sprites made with the local FLUX model (`tools/art/`, see its README).
- `CLASS=rogue [ZONE=barrens] tests/run_sim.lua [seed] play|stress [cap]` headless run with a bot (`VACUUM=1` = perfect pickup), prints result and ms per step.
- `tests/test_save.lua` save/load round trip for every class (zone, event cursors and pickup values kept; enemy bolts, ground zones, traps and pets are transient and start fresh).
- `tests/run_addon.lua [seconds]` loads the whole addon on a mock client and plays: open, start, move, level-ups, pause, combat pause, quit, restart, class select and a run with every class, quick save/load, a mocked flight (card, play, landing guard, learned time, not now, fight, don't ask again), stress; plus content checks on the sim: pets deal damage, an enemy bolt hits the player, the charger telegraphs and dashes, oozes split, brazier pickups (magnet, chicken, bomb, coin), the goblin, Corruption spreading, and a zone theme from a mocked map.
- `tools/install.sh` syntax check + offline test, then copies into `_forever_/Interface/AddOns/AzerothSurvivors`. First install (and any new file) needs a full game restart, not `/reload`.

## Performance

Sim cost (Lua 5.1 offline, this machine): ~0.1 ms per frame in normal play, ~0.45 ms with 600 enemies. Drawing is one SetPoint per visible entity; check the real cost in game with `/azs debug` and `/azs stress N`.

## License

MIT (see `LICENSE`). Sprites are original images generated locally with FLUX; World of Warcraft spell icons are referenced from the game client, not redistributed. Not affiliated with Blizzard Entertainment.
