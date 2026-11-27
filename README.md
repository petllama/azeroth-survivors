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

## Classes (0.2.0)

Pick a class on the title screen (`1` `2` `3` or click). Each has its own five skills; passives are shared.

| Class | Style | Skills |
|---|---|---|
| Paladin | 120 hp, armored | **Crusader Strike** (start, frontal swing), Consecration (burning ground), Blessed Hammers (orbiting), Avenger's Shield (bounces between enemies), Divine Storm (spin that heals per enemy hit) |
| Rogue | 85 hp, fast, 15% crit | **Sinister Strike** (start, quick stabs), Fan of Knives (ring of knives), Shuriken Toss (piercing star), Blade Flurry (tight orbiting blades), Deadly Poison (all hits poison) |
| Druid | 110 hp, regenerates | **Wrath** (start, nature bolts), Moonfire (strikes + burn), Starfall (falling stars, area damage), Thorns (aura + damages attackers), Entangling Roots (roots everything nearby) |

Passives (5 slots, level 5 max): Might, Haste, Sprint, Fortitude, Renew, Greed, Devotion, Arcane Reach, Precision (crit). Critical hits deal double damage (orange numbers); burns and poison tick in green.

Enemies: ghouls, bats, wraiths, brutes, an elite death knight every minute (drops a potion), bat swarms every 90 s, the Frost Lich at 8:00. Win at 10:00. Best run is saved per class.

## Layout

- `AzerothSurvivors/Content.lua` data and balance; `Sim.lua` pure-Lua simulation (no WoW API, spatial grid, pooled entities); `Render.lua` pooled textures/lines/numbers; `UI.lua` HUD and panels; `Main.lua` window, keyboard, loop, slash commands.
- `AzerothSurvivors/Art/*.tga` sprites made with the local FLUX model (`tools/art/`, see its README).
- `CLASS=rogue tests/run_sim.lua [seed] play|stress [cap]` headless run with a bot (`VACUUM=1` = perfect pickup), prints result and ms per step.
- `tests/test_save.lua` save/load round trip for every class.
- `tests/run_addon.lua [seconds]` loads the whole addon on a mock client and plays: open, start, move, level-ups, pause, combat pause, quit, restart, class select and a run with every class, quick save/load, a mocked flight (card, play, landing guard, learned time, not now, fight, don't ask again), stress.
- `tools/install.sh` syntax check + offline test, then copies into `_forever_/Interface/AddOns/AzerothSurvivors`. First install (and any new file) needs a full game restart, not `/reload`.

## Performance

Sim cost (Lua 5.1 offline, this machine): ~0.1 ms per frame in normal play, ~0.45 ms with 600 enemies. Drawing is one SetPoint per visible entity; check the real cost in game with `/azs debug` and `/azs stress N`.

## License

MIT (see `LICENSE`). Sprites are original images generated locally with FLUX; World of Warcraft spell icons are referenced from the game client, not redistributed. Not affiliated with Blizzard Entertainment.
