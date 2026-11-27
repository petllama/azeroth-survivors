# Azeroth Survivors

A Vampire Survivors-style arcade game that runs inside WoW: Forever as an addon. Survive the Scourge for 10 minutes; spells cast themselves, you move and pick upgrades.

Version 0.5.0 has six classes with 30 skills and 30 evolutions, treasure chests, gold and a permanent Shop, optional curses, map events (skeleton rings, a gold goblin, braziers with pickups), new enemies (skeleton mages, charging worgen, splitting oozes), arenas themed on the zone you play in, a results screen with damage per skill, achievements with unlocks, a guild leaderboard and sound effects.

Version 0.6.0 adds progression for players who have won it all: **Limit Break** level-ups once everything is maxed, an **Endless** mode after the win at 10:00, a bigger **Shop** (Revival, Amount, Cooldown, Area, Luck, Banish, Magnet, and prestige ranks 6-10) and **Ascension** levels A1-A10 per class.

## Install

Download `AzerothSurvivors-<version>.zip` from [Releases](https://github.com/petllama/azeroth-survivors/releases) and unzip it into `World of Warcraft/_forever_/Interface/AddOns/` so you get `AddOns/AzerothSurvivors/AzerothSurvivors.toc`. A first install needs a full game restart; updates need `/reload`, except 0.5.0, which adds a file (`Social.lua`): restart the game once.

Built for WoW: Forever (interface 16001, a retail-based client). It uses only plain frames and textures, so it may work on other retail-based clients with the `## Interface` line changed; untested.

## Play

- `/azs` (or `/survivors`, or the addon compartment button) opens the window. On the class screen `1`-`6` (or a click) starts that class and `SPACE` the highlighted one; the Shop, Curses, Achievements and Guild buttons open panels that `ESC` closes.
- `WASD` / arrow keys move. `1` `2` `3` (`4` with Insight) or a click picks a level-up; `R` rerolls the cards, `S` skips the level and `B` banishes a card when you have rerolls / skips / banishes (see the Shop). At 10:00 `C` cashes out and `E` keeps going (Endless). `ESC` pauses; `Q` in the pause screen ends the run.
- A treasure chest opens with `SPACE` (or `ENTER` / `1` / the button); `SPACE` again reveals the rest and continues.
- Movement keys are captured only while a run is playing; on the title, pause and game-over screens your character can walk.
- Entering real combat pauses the game and releases the keyboard (WoW forbids changing keyboard capture in combat).

On the game-over screen `SPACE` replays the same class and `C` returns to class select.

**Pause and quick save:** `P` / `ESC` or the Pause button pause; `F6` quick saves, `F9` quick loads (one slot, kept across `/reload` and logout; a run in progress is also saved on logout). A saved run shows as **Continue** on the class screen.

**Flights:** like Polestar's Freedoom Arcade. On a flight with a minute or more to go (out of combat, outside instances) a small card asks *Do you want to play Azeroth Survivors while waiting?* (Play, Not now, Don't ask again); after that a *Play Azeroth Survivors* button stays while you fly. When the flight time is known (learned on an earlier landing of that route, or taken from Polestar's own flight recordings), the run is saved, paused and closed ten seconds before landing; on a route with only an estimate (first flight, no Polestar record) it stays open until you actually land. A fight on the way or the landing itself also saves, pauses and closes it, so your keys are yours again. It sits under Polestar's flight timer when that is shown. `/azs flight` turns the offer on or off.

Other commands: `/azs save` / `/azs load`, `/azs flight`, `/azs sound` (sound effects on/off), `/azs board` (guild leaderboard in chat), `/azs anim` (movement animations on/off), `/azs debug` (fps / sim / draw ms overlay), `/azs stress 600` (stress test with 600 enemies, invulnerable), `/azs numbers` (damage numbers on/off), `/azs scale 0.8`, `/azs reset` (window position).

## Classes

Pick a class on the title screen (`1`-`6` or click). Each has its own five skills; passives are shared.

| Class | Style | Skills |
|---|---|---|
| Paladin | 120 hp, armored | **Crusader Strike** (start, frontal swing), Consecration (burning ground), Blessed Hammers (orbiting), Avenger's Shield (bounces between enemies), Divine Storm (spin that heals per enemy hit) |
| Rogue | 85 hp, fast, 15% crit | **Sinister Strike** (start, quick stabs), Fan of Knives (ring of knives), Shuriken Toss (piercing star), Blade Flurry (tight orbiting blades), Deadly Poison (all hits poison) |
| Druid | 110 hp, regenerates | **Wrath** (start, nature bolts), Moonfire (strikes + burn), Starfall (falling stars, area damage), Thorns (aura + damages attackers), Entangling Roots (roots everything nearby) |
| Mage | 110 hp, slowly heals | **Frostbolt** (start, bolts that slow), Fireball (explodes in an area), Arcane Missiles (homing volley), Blizzard (ice storm on the thickest pack: damage + slow), Frost Nova (freezes everything around you) |
| Warlock | 100 hp, drains life | **Shadow Bolt** (start), Corruption (damage over time that spreads when the victim dies), Rain of Fire (falling fel fire zones), Drain Life (beam on the nearest enemies that heals you), Summon Imp (a pet that follows you and throws firebolts) |
| Hunter | 105 hp, 10% crit | **Auto Shot** (start, piercing arrows), Multi-Shot (fan of arrows), Explosive Trap (mines that explode when stepped on), Volley (arrows rain on a pack), Call Wolf (a pet that hunts down and bites enemies) |

Passives (5 slots, level 5 max): Might, Haste, Sprint, Fortitude, Renew, Greed, Devotion, Arcane Reach, Precision (crit). Critical hits deal double damage (orange numbers); burns and poison tick in green.

## Enemies and events

Ghouls, bats, wraiths, brutes, an elite death knight every minute (drops a potion), bat swarms every 90 s, the Frost Lich at 8:00. Win at 10:00. Best run is saved per class.

From 2:30 new enemies join the waves:
- **Skeleton mages** keep about 220 px away and fire slow bolts: dodge them (armor and the hit grace period apply).
- **Worgen** stop, glow orange and show their dash line, then charge in a straight line.
- **Oozes** split into two small oozelets when they die.

Map events: a **ring of skeletons** closes in at 3:30 and 6:30; a **gold goblin** appears at 1:40, 4:20 and 7:00 and flees: catch it before it escapes (15 s) for a pile of gold coins. **Braziers** burn near you every 30 s (up to 3): break them for a pickup: **magnet** (every crystal flies to you), **chicken** (heals 30%) or **bomb** (damages everything on screen).

## Zones

The arena takes the look of where you play: Tirisfal (and other dark lands), the Barrens (and other dry lands), Elwynn (green lands) or the frozen north. Each theme has its own ground and leans the waves (more skeleton mages in Tirisfal, worgen in the Barrens, oozes in Elwynn, wraiths and bats in the snow). The zone comes from your map (`C_Map.GetBestMapForUnit`), walking up to the continent by name; elsewhere the arena keeps the default ground.

## Chests and evolutions

Elites drop a treasure chest (1 upgrade) and The Frost Lich drops a big one (3 upgrades). Picking it up pauses the game; open it to reveal the upgrades one after another. An upgrade is a **weapon evolution** when one is ready, otherwise a level of a skill or passive you own, otherwise gold.

A skill evolves when it is at level 6 and you own its passive (any level). Only chests evolve; the evolved skill replaces the old one in the same slot and is never offered on level-up.

| Class | Skill + passive | Evolution |
|---|---|---|
| Paladin | Crusader Strike + Might | Templar's Verdict |
| Paladin | Consecration + Arcane Reach | Hallowed Ground |
| Paladin | Blessed Hammers + Haste | Hammer of the Righteous |
| Paladin | Avenger's Shield + Precision | Holy Avenger |
| Paladin | Divine Storm + Fortitude | Avenging Storm |
| Rogue | Sinister Strike + Precision | Eviscerate |
| Rogue | Fan of Knives + Haste | Blade Dance |
| Rogue | Shuriken Toss + Arcane Reach | Shuriken Storm |
| Rogue | Blade Flurry + Sprint | Killing Spree |
| Rogue | Deadly Poison + Might | Deadly Brew |
| Druid | Wrath + Might | Starsurge |
| Druid | Moonfire + Renew | Sunfire |
| Druid | Starfall + Arcane Reach | Celestial Alignment |
| Druid | Thorns + Devotion | Brambles |
| Druid | Entangling Roots + Greed | Ursol's Vortex |
| Mage | Frostbolt + Haste | Frostfire Bolt |
| Mage | Fireball + Might | Pyroblast |
| Mage | Arcane Missiles + Precision | Arcane Barrage |
| Mage | Blizzard + Arcane Reach | Frozen Tempest |
| Mage | Frost Nova + Devotion | Deep Freeze |
| Warlock | Shadow Bolt + Might | Chaos Bolt |
| Warlock | Corruption + Renew | Unstable Affliction |
| Warlock | Rain of Fire + Arcane Reach | Hellfire Rain |
| Warlock | Drain Life + Fortitude | Drain Soul |
| Warlock | Summon Imp + Haste | Demonic Legion (four imps) |
| Hunter | Auto Shot + Precision | Aimed Shot |
| Hunter | Multi-Shot + Haste | Barrage |
| Hunter | Explosive Trap + Arcane Reach | Expert Trapper |
| Hunter | Volley + Might | Hail of Arrows |
| Hunter | Call Wolf + Sprint | The Beast Within (four wolves) |

## Gold and the Shop

Kills sometimes drop gold coins; elites and the gold goblin drop a pile and the boss a lot. Coins fly to you like crystals. Gold from a run (shown under the kill count) is banked when the run ends, also when you quit or die. The **Shop** button on the class screen spends it on permanent upgrades with ranks and rising prices:

Might (+5% damage), Armor (-1 damage taken), Max HP (+10%), Recovery (+0.2 health/sec), Swiftness (+5% speed), Greed (+20% pickup range), Growth (+5% XP), **Reroll** (+1 reroll per run, `R` on the level-up screen), **Skip** (+1 skip per run, `S`), Insight (a 4th card on level-up).

New in 0.6, with steep prices so gold always has a use (the shop shows two columns):

| Item | Effect | Ranks |
|---|---|---|
| **Revival** | When you would die, you get back up once per rank with half your health, 2 s untouchable and a flash | 2 |
| **Amount** | +1 projectile / count on every skill that has one (bolts, knives, hammers, stars, storms, traps, pets...) | 1, very expensive |
| Cooldown | -3% cooldowns | 5 |
| Area | +5% area | 5 |
| Luck | Each chest has a 15% chance per rank to give one more upgrade; more kills drop gold | 3 |
| **Banish** | +1 banish per run: press `B` on the level-up screen (or the Banish button), then a card: that skill or passive is never offered again in this run, and you get new cards | 3 |
| Magnet | +10% pickup range | 2 |

**Prestige:** once you own all five ranks of Might, Max HP, Recovery or Growth, five more ranks (6-10) go on sale at a much higher price.

## Limit Break

When there is nothing left to offer on level-up (every weapon and passive slot full and maxed, or everything else banished), the cards become **Limit Break** bonuses that stack without end: +3% damage, +10 max health, +2% critical strike, -2% cooldowns (never below half), +5% area, +4% move speed (up to +40%), +5% pickup range, and every fifth pick or so +1 projectile on bolt, fan and missile skills. Each card shows what you have so far ("Might +12%"); the stacks are listed under your skill icons and on the pause screen, and they are kept in quick saves.

## Endless

Surviving to 10:00 is a win, and it counts at once: achievements, your best time, the gold you have so far (banked right away) and the guild board. Then choose:

- **Cash out** (`C`): the results screen, as before.
- **Keep going** (`E`): **Endless**. The Scourge keeps growing stronger, faster and more numerous and shrugs off roots and slows more and more, the Frost Lich returns every 5 minutes (15:00, 20:00, ...) stronger each time, and gold per kill rises 10% for every minute past 10:00. The run ends when you fall (or quit); it still counts as a victory, the results show *Endless +m:ss*, and only the gold earned after 10:00 is banked then. Your best run and the guild board keep the longest time. Quick saves work in Endless.

## Ascension

Win with a class with all four curses on and that class unlocks **Ascension 1**. A selector (`-` / `+`) then appears on the class screen, above the gold line, for the highlighted class (the last one you played). Each win at your highest unlocked level unlocks the next, up to **A10**. Every level keeps the twists of the levels below it and adds one:

| Level | Twist |
|---|---|
| A1 | Elites every 45 s |
| A2 | Enemies +10% speed |
| A3 | The Frost Lich comes at 7:00 |
| A4 | One card fewer on level-up (at least 2) |
| A5 | Enemy bolts hit 50% harder |
| A6 | Potions and healing pickups heal half |
| A7 | Elites +50% health |
| A8 | +25% spawn rate |
| A9 | Chests give one upgrade fewer (at least 1) |
| A10 | The Frost Lich enrages at half health (+50% speed and damage) |

Every level also makes enemies (the Frost Lich too) tougher, gently at first and steeply at the top: about +3% health at A1, +75% at A5 and four times the health and 3.5 times the damage at A10. Each level gives +20% gold. Curses are separate and stack on top. The results screen, your best runs and the guild board show the level as *A3*.

## Curses

The **Curses** button turns on optional, stacking difficulty: Horde (+50% spawn rate), Brutal (+60% enemy health), Haste (+25% enemy speed), Frail (-30% max health). Each active curse gives +25% XP and +50% gold; the class screen shows the current multipliers. Curses stay on until you turn them off.

## Results, achievements and the guild board

- The results screen shows time, level, kills, gold earned and the damage of every skill (and of Bombs from braziers) as bars with its DPS (damage over the time you had the skill). Overkill is not counted.
- **Achievements** (button on the class screen, a toast when earned): survive 5 and 10 minutes, win with each of the six classes, kill the boss, 1000 kills in one run, evolve a weapon, win with 2+ curses, and *Champion of Azeroth*: win with all six classes. Some unlock things: *survive 10 minutes as a Rogue* gives +1 reroll every run, *evolve a weapon* a 6th weapon slot (level-ups may then offer other classes' skills, pets included), *Champion of Azeroth* the title on the class screen.
- **Guild:** when a run ends (and at the win at 10:00) and you are in a guild, the addon sends one hidden addon message to your guild with class, time, kills, level and win; an Endless or Ascension run also sends a second line with the Endless time and the Ascension level, which 0.5 clients ignore (they still read the first). Guild members with the addon keep the best run per player and class; the **Guild** button lists the top entries and `/azs board` prints them.
- **Sound:** level-up, chest, evolution, coins, getting hit (and hit by an enemy bolt), the boss, the gold goblin (appears and killed), skeleton rings, bombs, chickens, magnets, breaking a brazier, death, victory and achievements play built-in WoW sounds (no files shipped, rapid repeats are throttled); `/azs sound` turns them off.

Saves from 0.4 and 0.5 still load; a run keeps the shop ranks, curses and Ascension level it started with.

## Layout

- `AzerothSurvivors/Content.lua` data and balance; `Sim.lua` pure-Lua simulation (no WoW API, spatial grid, pooled entities); `Render.lua` pooled textures/lines/numbers; `UI.lua` HUD, panels (level-up, chest, results, shop, curses, achievements, guild, toast); `Social.lua` guild leaderboard (addon messages); `Main.lua` window, keyboard, loop, sound, achievements, slash commands.
- `AzerothSurvivors/Art/*.tga` sprites made with the local FLUX model (`tools/art/`, see its README).
- `CLASS=rogue [ZONE=barrens] tests/run_sim.lua [seed] play|stress [cap]` headless run with a bot (`VACUUM=1` = perfect pickup, `META=max` (base ranks), `META=full` (prestige too) or `META=might:3,armor:1` shop ranks, `CURSES=horde,brutal`, `ASC=n` Ascension level, `ENDLESS=1` keep going after 10:00; the bot plays at the in-game view radius 677, `VIEWR=` overrides), prints result, gold, chests, evolutions, damage share per skill and ms per step.
- `tests/test_save.lua` save/load round trip for every class (shop ranks, curses, evolutions, gold, chests, zone, event cursors and pickup values kept; enemy bolts, ground zones, traps and pets are transient and start fresh; version 1 saves still load).
- `tests/run_addon.lua [seconds]` loads the whole addon on a mock client and plays: open, start, move, level-ups, pause, combat pause, quit, restart, class select and a run with every class, quick save/load, a mocked flight (card, play, landing guard, learned time, not now, fight, don't ask again), stress; chests, evolutions, shop, curses, achievements, results screen and guild board; plus content checks on the sim: pets deal damage, an enemy bolt hits the player, the charger telegraphs and dashes, oozes split, brazier pickups (magnet, chicken, bomb, coin), the goblin, Corruption spreading, and a zone theme from a mocked map; and the 0.6 progression: Limit Break cards and stacks, the 10:00 victory panel (cash out, Endless, gold banked once, guild lines old clients still read), every new shop item and prestige rank, Ascension unlock, selector and twists, the shop's two-column layout and mirrored kill pops.
- `tools/install.sh` syntax check + offline test, then copies into `_forever_/Interface/AddOns/AzerothSurvivors`. First install (and any new file) needs a full game restart, not `/reload`.

## Performance

Sim cost (Lua 5.1 offline, this machine): ~0.1 ms per frame in normal play, ~0.45 ms with 600 enemies. Drawing is one SetPoint per visible entity; check the real cost in game with `/azs debug` and `/azs stress N`.

## License

MIT (see `LICENSE`). Sprites are original images generated locally with FLUX; World of Warcraft spell icons are referenced from the game client, not redistributed. Not affiliated with Blizzard Entertainment.
