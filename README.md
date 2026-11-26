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

Other commands: `/azs debug` (fps / sim / draw ms overlay), `/azs stress 600` (stress test with 600 enemies, invulnerable), `/azs numbers` (damage numbers on/off), `/azs scale 0.8`, `/azs reset` (window position).

## Content (0.1.0)

- Weapons (5 slots, level 6 max): Arcane Missiles, Holy Spheres, Consecration, Frost Nova, Chain Lightning.
- Passives (5 slots, level 5 max): Might, Haste, Sprint, Fortitude, Renew, Greed, Devotion, Arcane Reach.
- Enemies: ghouls, bats, wraiths, brutes, an elite death knight every minute (drops a potion), bat swarms every 90 s, the Frost Lich at 8:00. Win at 10:00.

## Layout

- `AzerothSurvivors/Content.lua` data and balance; `Sim.lua` pure-Lua simulation (no WoW API, spatial grid, pooled entities); `Render.lua` pooled textures/lines/numbers; `UI.lua` HUD and panels; `Main.lua` window, keyboard, loop, slash commands.
- `AzerothSurvivors/Art/*.tga` sprites made with the local FLUX model (`tools/art/`, see its README).
- `tests/run_sim.lua [seed] play|stress [cap]` headless run with a bot (`VACUUM=1` = perfect pickup), prints result and ms per step.
- `tests/run_addon.lua [seconds]` loads the whole addon on a mock client and plays: open, start, move, level-ups, pause, combat pause, quit, restart, stress.
- `tools/install.sh` syntax check + offline test, then copies into `_forever_/Interface/AddOns/AzerothSurvivors`. First install (and any new file) needs a full game restart, not `/reload`.

## Performance

Sim cost (Lua 5.1 offline, this machine): ~0.1 ms per frame in normal play, ~0.45 ms with 600 enemies. Drawing is one SetPoint per visible entity; check the real cost in game with `/azs debug` and `/azs stress N`.

## License

MIT (see `LICENSE`). Sprites are original images generated locally with FLUX; World of Warcraft spell icons are referenced from the game client, not redistributed. Not affiliated with Blizzard Entertainment.
