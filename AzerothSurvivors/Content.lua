-- Azeroth Survivors: game content (enemies, weapons, passives, waves). Pure data, no WoW API.
local _, ns = ...
local C = {}
ns.Content = C

C.RUN_SECONDS = 600     -- survive this long to win
C.MAX_ENEMIES = 350     -- live cap (raise with /azs cap N to stress test)
C.MAX_GEMS = 300
C.WEAPON_SLOTS = 5
C.PASSIVE_SLOTS = 5

-- hp/dmg are base values; hp scales with time (see Sim.HpScale)
C.ENEMIES = {
  ghoul  = { hp = 9,    speed = 52, r = 11, dmg = 6,  xp = 1,   size = 42 },
  bat    = { hp = 5,    speed = 92, r = 8,  dmg = 4,  xp = 1,   size = 34 },
  wraith = { hp = 22,   speed = 66, r = 12, dmg = 9,  xp = 2,   size = 44 },
  brute  = { hp = 70,   speed = 38, r = 19, dmg = 14, xp = 5,   size = 66 },
  elite  = { hp = 450,  speed = 48, r = 24, dmg = 22, xp = 30,  size = 88, elite = true, drop = "potion", chest = 1, coins = 4, coinValue = 3 },
  boss   = { hp = 9000, speed = 44, r = 40, dmg = 35, xp = 300, size = 160, boss = true, name = "The Frost Lich", chest = 3, coins = 16, coinValue = 6 },
  -- ai picks a behaviour in Sim (AI table); no ai = chase. stay = never wrapped around the player when far.
  caster  = { hp = 16,  speed = 58, r = 11, dmg = 5,  xp = 2, size = 46, ai = "ranged", keep = 220, fireCd = 3.2, boltSpeed = 150, boltDmg = 5 },
  charger = { hp = 38,  speed = 50, r = 14, dmg = 11, xp = 3, size = 56, ai = "charge", tele = 0.75, dashSpeed = 360, dashTime = 0.55, dashCd = 3.0, dashRange = 300 },
  ooze    = { hp = 40,  speed = 40, r = 16, dmg = 7,  xp = 2, size = 54, ai = "split", split = "oozelet", splitN = 2 },
  oozelet = { hp = 10,  speed = 72, r = 9,  dmg = 4,  xp = 1, size = 30, art = "ooze" },
  skeleton = { hp = 12, speed = 70, r = 11, dmg = 6,  xp = 1, size = 42, art = "ghoul", tint = { 0.85, 0.85, 0.95 } },
  goblin  = { hp = 60,  speed = 112, r = 12, dmg = 0, xp = 5, size = 46, ai = "flee", stay = true, life = 15, coins = 15, coinValue = 4 },
  brazier = { hp = 12,  speed = 0,  r = 14, dmg = 0,  xp = 1, size = 50, ai = "static", stay = true },
}
-- gold: any other kill drops a coin worth 1 with this chance (the elite and boss drop piles, see coins above)
C.COIN_CHANCE = 0.05
C.MAX_ITEMS = 120 -- coins over this are banked into the next coin that drops
C.CHEST_GOLD = 25 -- a chest upgrade with nothing left to level gives this much gold

-- spawn weights by time (seconds): first matching row from the bottom whose t <= now
C.WAVES = {
  { t = 0,   mix = { ghoul = 1 } },
  { t = 45,  mix = { ghoul = 3, bat = 2 } },
  { t = 120, mix = { ghoul = 3, bat = 2, wraith = 2 } },
  { t = 150, mix = { ghoul = 3, bat = 2, wraith = 2, caster = 0.6, ooze = 0.6 } },
  { t = 200, mix = { ghoul = 2, bat = 2, wraith = 3, brute = 1, caster = 0.7, charger = 0.6, ooze = 0.6 } },
  { t = 330, mix = { ghoul = 1, bat = 3, wraith = 3, brute = 2, caster = 0.8, charger = 0.8, ooze = 0.7 } },
  { t = 450, mix = { bat = 2, wraith = 3, brute = 3, caster = 0.8, charger = 1, ooze = 0.8 } },
}
C.ELITE_EVERY = 60      -- an elite at 1:00, 2:00, ...
C.SWARM_EVERY = 90      -- a ring of bats closing in
C.BOSS_AT = 480         -- 8:00

-- target population over time
function C.TargetPop(t) return 12 + t * 0.75 end

-- Classes. Each brings its own five skills; passives are shared.
C.CLASSES = {
  paladin = {
    name = "Paladin", icon = "Interface\\Icons\\ClassIcon_Paladin", hero = "hero", color = { 0.96, 0.55, 0.73 },
    desc = "Sturdy holy warrior. Strikes, hammers and holy ground.",
    hp = 120, speed = 130, armor = 1, crit = 0.05, regen = 0,
    start = "crusader", kit = { "crusader", "consecrate", "hammers", "avenger", "dstorm" },
  },
  rogue = {
    name = "Rogue", icon = "Interface\\Icons\\ClassIcon_Rogue", hero = "hero_rogue", color = { 1, 0.96, 0.41 },
    desc = "Fast and fragile. Blades, poison and critical hits.",
    hp = 85, speed = 165, armor = 0, crit = 0.15, regen = 0,
    start = "sinister", kit = { "sinister", "fan", "shuriken", "flurry", "poison" },
  },
  druid = {
    name = "Druid", icon = "Interface\\Icons\\ClassIcon_Druid", hero = "hero_druid", color = { 1, 0.49, 0.04 },
    desc = "Nature caster. Spells from afar, roots and thorns. Slowly heals.",
    hp = 110, speed = 140, armor = 0, crit = 0.05, regen = 0.5,
    start = "wrath", kit = { "wrath", "moonfire", "starfall", "thorns", "roots" },
  },
}
C.CLASSES.mage = {
  name = "Mage", icon = "Interface\\Icons\\ClassIcon_Mage", hero = "hero_mage", color = { 0.41, 0.8, 0.94 },
  desc = "Spellcaster. Frost slows, fire explodes, arcane seeks.", trait = "slowly heals",
  hp = 110, speed = 140, armor = 0, crit = 0.05, regen = 0.4,
  start = "frostbolt", kit = { "frostbolt", "fireball", "arcane", "blizzard", "frostnova" },
}
C.CLASSES.warlock = {
  name = "Warlock", icon = "Interface\\Icons\\ClassIcon_Warlock", hero = "hero_warlock", color = { 0.58, 0.51, 0.79 },
  desc = "Curses that spread, fel fire, an imp, and life drained from foes.", trait = "drains life",
  hp = 100, speed = 130, armor = 0, crit = 0.05, regen = 0,
  start = "shadowbolt", kit = { "shadowbolt", "corruption", "rainfire", "drainlife", "imp" },
}
C.CLASSES.hunter = {
  name = "Hunter", icon = "Interface\\Icons\\ClassIcon_Hunter", hero = "hero_hunter", color = { 0.67, 0.83, 0.45 },
  desc = "Piercing arrows, traps, volleys and a loyal wolf.", trait = "pet",
  hp = 105, speed = 145, armor = 0, crit = 0.10, regen = 0,
  start = "autoshot", kit = { "autoshot", "multishot", "trap", "volley", "wolf" },
}
C.CLASS_ORDER = { "paladin", "rogue", "druid", "mage", "warlock", "hunter" }

-- Skills. type picks the behaviour in Sim (melee, proj, burst, orbit, aura, nova, chain, strike, poison).
-- levels[i] = changes applied when reaching level i: numbers add, *Mul multiply, text is shown on the card.
C.WEAPONS = {
  ------------------------------------------------------------------ paladin
  crusader = {
    type = "melee", name = "Crusader Strike", icon = "Interface\\Icons\\Spell_Holy_CrusaderStrike",
    desc = "Strikes enemies in front of you.", color = { 1, 0.85, 0.4 },
    base = { dmg = 18, cd = 0.9, range = 105, arc = 0.35, knock = 160 },
    levels = {
      [2] = { dmg = 6, text = "+6 damage" },
      [3] = { range = 18, text = "+25% reach" },
      [4] = { arc = 0.35, text = "Wider swing" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dmg = 14, arc = 0.6, text = "+14 damage, strikes all around you" },
    },
  },
  consecrate = {
    type = "aura", name = "Consecration", icon = "Interface\\Icons\\Spell_Holy_InnerFire",
    desc = "Burns enemies standing near you.", color = { 1, 0.8, 0.3 },
    base = { dmg = 4, radius = 62, tick = 0.5 },
    levels = {
      [2] = { radius = 14, text = "+20% area" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { radius = 14, text = "+20% area" },
      [5] = { dmg = 4, text = "+4 damage" },
      [6] = { tickMul = 0.7, radius = 14, text = "Ticks faster, more area" },
    },
  },
  hammers = {
    type = "orbit", name = "Blessed Hammers", icon = "Interface\\Icons\\Spell_Holy_SealOfMight",
    desc = "Holy hammers circle you.", sprite = "hammer", spinSprite = true, color = { 1, 0.85, 0.4 },
    base = { dmg = 6, count = 1, radius = 80, spin = 2.4, hitcd = 0.8, size = 28, knock = 25 },
    levels = {
      [2] = { count = 1, text = "+1 hammer" },
      [3] = { dmg = 3, radius = 15, text = "+3 damage, wider orbit" },
      [4] = { count = 1, text = "+1 hammer" },
      [5] = { spin = 0.6, dmg = 5, text = "Faster, +5 damage" },
      [6] = { count = 2, text = "+2 hammers" },
    },
  },
  avenger = {
    type = "chain", name = "Avenger's Shield", icon = "Interface\\Icons\\Spell_Holy_AvengersShield",
    desc = "A shield that bounces between enemies.", sprite = "shield", color = { 1, 0.85, 0.35 },
    base = { dmg = 24, cd = 2.6, jumps = 2, range = 190 },
    levels = {
      [2] = { jumps = 1, text = "+1 bounce" },
      [3] = { dmg = 12, text = "+12 damage" },
      [4] = { jumps = 2, text = "+2 bounces" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dmg = 18, jumps = 2, text = "+18 damage, +2 bounces" },
    },
  },
  dstorm = {
    type = "nova", name = "Divine Storm", icon = "Interface\\Icons\\Ability_Paladin_DivineStorm",
    desc = "Whirls to hit everything nearby and heals you per enemy hit.", color = { 1, 0.9, 0.5 },
    base = { dmg = 16, cd = 3.5, radius = 100, slow = 0, heal = 0.5, healCap = 8 },
    levels = {
      [2] = { dmg = 8, text = "+8 damage" },
      [3] = { radius = 25, text = "+25 radius" },
      [4] = { heal = 0.5, healCap = 6, text = "Heals more" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dmg = 16, radius = 30, text = "+16 damage, bigger" },
    },
  },
  ------------------------------------------------------------------ rogue
  sinister = {
    type = "melee", name = "Sinister Strike", icon = "Interface\\Icons\\Spell_Shadow_RitualOfSacrifice",
    desc = "Quick stabs at enemies in front of you.", color = { 0.9, 0.9, 1 },
    base = { dmg = 10, cd = 0.45, range = 85, arc = 0.3, knock = 60 },
    levels = {
      [2] = { dmg = 4, text = "+4 damage" },
      [3] = { range = 14, text = "+25% reach" },
      [4] = { cdMul = 0.8, text = "-20% cooldown" },
      [5] = { dmg = 6, arc = 0.3, text = "+6 damage, wider" },
      [6] = { double = 1, text = "Strikes twice" },
    },
  },
  fan = {
    type = "burst", name = "Fan of Knives", icon = "Interface\\Icons\\Ability_Rogue_FanOfKnives",
    desc = "Throws knives in every direction.", sprite = "knife", color = { 0.85, 0.85, 0.9 },
    base = { dmg = 8, cd = 2.0, count = 8, speed = 400, pierce = 1, life = 0.55, size = 26 },
    levels = {
      [2] = { count = 4, text = "+4 knives" },
      [3] = { dmg = 4, text = "+4 damage" },
      [4] = { life = 0.25, pierce = 1, text = "Knives fly farther and pierce" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { count = 6, dmg = 5, text = "+6 knives, +5 damage" },
    },
  },
  shuriken = {
    type = "proj", name = "Shuriken Toss", icon = "Interface\\Icons\\INV_ThrowingKnife_07",
    desc = "A spinning star that cuts through lines of enemies.", sprite = "shuriken", spinSprite = true,
    color = { 0.8, 0.85, 0.95 },
    base = { dmg = 14, cd = 1.3, count = 1, speed = 520, pierce = 4, life = 1.2, size = 22 },
    levels = {
      [2] = { count = 1, text = "+1 shuriken" },
      [3] = { pierce = 3, text = "Pierces +3" },
      [4] = { dmg = 8, text = "+8 damage" },
      [5] = { count = 1, cdMul = 0.8, text = "+1 shuriken, -20% cooldown" },
      [6] = { pierce = 6, dmg = 8, text = "Pierces +6, +8 damage" },
    },
  },
  flurry = {
    type = "orbit", name = "Blade Flurry", icon = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
    desc = "Blades whirl tightly around you.", sprite = "knife", spinSprite = true, color = { 0.9, 0.9, 1 },
    base = { dmg = 6, count = 2, radius = 46, spin = 7.0, hitcd = 0.3, size = 26 },
    levels = {
      [2] = { count = 1, text = "+1 blade" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { count = 1, radius = 10, text = "+1 blade, wider" },
      [5] = { dmg = 4, text = "+4 damage" },
      [6] = { count = 2, spin = 2, text = "+2 blades, faster" },
    },
  },
  poison = {
    type = "poison", name = "Deadly Poison", icon = "Interface\\Icons\\Ability_Rogue_DualWeild",
    desc = "All your hits poison enemies, dealing damage over time.", color = { 0.3, 1, 0.3 },
    base = { dps = 4, dur = 3 },
    levels = {
      [2] = { dps = 2, text = "+2 poison damage / sec" },
      [3] = { dur = 1, text = "Lasts 1 sec longer" },
      [4] = { dps = 3, text = "+3 poison damage / sec" },
      [5] = { dps = 3, text = "+3 poison damage / sec" },
      [6] = { dps = 6, text = "+6 poison damage / sec" },
    },
  },
  ------------------------------------------------------------------ druid
  wrath = {
    type = "proj", name = "Wrath", icon = "Interface\\Icons\\Spell_Nature_WrathV2",
    desc = "Hurls nature bolts at the nearest enemies.", sprite = "wrath", color = { 0.7, 1, 0.3 },
    base = { dmg = 14, cd = 0.9, count = 1, speed = 400, pierce = 1, life = 1.5, size = 20 },
    levels = {
      [2] = { count = 1, text = "+1 bolt" },
      [3] = { dmg = 6, text = "+6 damage" },
      [4] = { count = 1, text = "+1 bolt" },
      [5] = { pierce = 1, text = "Pierces +1 enemy" },
      [6] = { cdMul = 0.75, count = 1, text = "-25% cooldown, +1 bolt" },
    },
  },
  moonfire = {
    type = "strike", name = "Moonfire", icon = "Interface\\Icons\\Spell_Nature_StarFall",
    desc = "Moonlight strikes random enemies and burns them over time.", color = { 0.6, 0.75, 1 },
    base = { dmg = 8, cd = 1.6, count = 2, radius = 0, delay = 0, dot = 5, dotDur = 4 },
    levels = {
      [2] = { count = 1, text = "+1 target" },
      [3] = { dot = 3, text = "+3 burn damage / sec" },
      [4] = { count = 2, text = "+2 targets" },
      [5] = { dmg = 8, cdMul = 0.8, text = "+8 damage, -20% cooldown" },
      [6] = { count = 3, dot = 4, text = "+3 targets, hotter burn" },
    },
  },
  starfall = {
    type = "strike", name = "Starfall", icon = "Interface\\Icons\\Ability_Druid_Starfall",
    desc = "Stars rain down on enemies, hurting all near the impact.", sprite = "star", color = { 0.85, 0.7, 1 },
    base = { dmg = 20, cd = 3.0, count = 3, radius = 48, delay = 0.4 },
    levels = {
      [2] = { count = 1, text = "+1 star" },
      [3] = { dmg = 10, text = "+10 damage" },
      [4] = { radius = 14, count = 1, text = "+1 star, bigger impacts" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { count = 3, dmg = 10, text = "+3 stars, +10 damage" },
    },
  },
  thorns = {
    type = "aura", name = "Thorns", icon = "Interface\\Icons\\Spell_Nature_Thorns",
    desc = "Brambles hurt nearby enemies, and anything that hits you.", color = { 0.45, 0.9, 0.3 },
    base = { dmg = 3, radius = 52, tick = 0.5, reflect = 12 },
    levels = {
      [2] = { reflect = 10, text = "+10 damage to attackers" },
      [3] = { radius = 12, dmg = 2, text = "Wider, +2 damage" },
      [4] = { reflect = 15, text = "+15 damage to attackers" },
      [5] = { dmg = 3, text = "+3 damage" },
      [6] = { radius = 18, tickMul = 0.7, reflect = 25, text = "Wider, faster, crueler" },
    },
  },
  roots = {
    type = "nova", name = "Entangling Roots", icon = "Interface\\Icons\\Spell_Nature_StrangleVines",
    desc = "Roots every enemy around you in place.", color = { 0.5, 0.85, 0.3 },
    base = { dmg = 6, cd = 5.0, radius = 115, slow = 2.0, root = 1 },
    levels = {
      [2] = { radius = 25, text = "+25 radius" },
      [3] = { slow = 1.0, text = "Roots last 1 sec longer" },
      [4] = { dmg = 10, text = "+10 damage" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { radius = 40, slow = 1.0, text = "Bigger, longer" },
    },
  },
}
C.MAX_WEAPON_LEVEL = 6

-- Mage, Warlock and Hunter skills. New types: missile (homing), zone (ground area that ticks), dot (spreading
-- curse), beam (channel on the nearest enemy), fan (spread of projectiles), trap (mines), pet (a minion with
-- its own position and AI). proj skills may name a `hit` effect (chill, explode) applied by the projectile.
local NEW_WEAPONS = {
  ------------------------------------------------------------------ mage
  frostbolt = {
    type = "proj", name = "Frostbolt", icon = "Interface\\Icons\\Spell_Frost_FrostBolt02",
    desc = "Bolts of frost that chill (slow) what they hit.", sprite = "frostbolt", hit = "chill", color = { 0.5, 0.8, 1 },
    base = { dmg = 16, cd = 0.85, count = 1, speed = 380, pierce = 2, life = 1.5, size = 26, slow = 1.5 },
    levels = {
      [2] = { count = 1, text = "+1 bolt" },
      [3] = { dmg = 6, text = "+6 damage" },
      [4] = { pierce = 1, slow = 0.5, text = "Pierces +1, chills longer" },
      [5] = { count = 1, text = "+1 bolt" },
      [6] = { cdMul = 0.75, dmg = 6, text = "-25% cooldown, +6 damage" },
    },
  },
  fireball = {
    type = "proj", name = "Fireball", icon = "Interface\\Icons\\Spell_Fire_FlameBolt",
    desc = "A slow ball of fire that explodes on impact.", sprite = "fireball", hit = "explode", color = { 1, 0.5, 0.15 },
    base = { dmg = 24, cd = 1.6, count = 1, speed = 300, pierce = 1, life = 1.6, size = 32, radius = 60, splash = 0.75 },
    levels = {
      [2] = { dmg = 8, text = "+8 damage" },
      [3] = { radius = 15, text = "Bigger explosion" },
      [4] = { count = 1, text = "+1 fireball" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dmg = 12, radius = 20, text = "+12 damage, bigger explosion" },
    },
  },
  arcane = {
    type = "missile", name = "Arcane Missiles", icon = "Interface\\Icons\\Spell_Arcane_StarFire",
    desc = "A volley of missiles that seek out enemies.", sprite = "arcane", homing = true, color = { 0.85, 0.5, 1 },
    base = { dmg = 9, cd = 1.3, count = 3, speed = 330, pierce = 1, life = 1.8, size = 20, turn = 6 },
    levels = {
      [2] = { count = 1, text = "+1 missile" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { count = 2, text = "+2 missiles" },
      [5] = { cdMul = 0.8, text = "-20% cooldown" },
      [6] = { count = 2, dmg = 3, text = "+2 missiles, +3 damage" },
    },
  },
  blizzard = {
    type = "zone", name = "Blizzard", icon = "Interface\\Icons\\Spell_Frost_IceStorm",
    desc = "Ice storms the thickest pack of enemies, hurting and slowing them.", zoneSprite = "blizzard", color = { 0.6, 0.85, 1 },
    base = { dmg = 6, cd = 4.5, count = 1, radius = 70, dur = 3, tick = 0.5, slow = 1.0, delay = 0 },
    levels = {
      [2] = { radius = 15, text = "+20% area" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { count = 1, text = "+1 storm" },
      [5] = { dur = 1.5, cdMul = 0.85, text = "Lasts longer, -15% cooldown" },
      [6] = { dmg = 4, radius = 20, text = "+4 damage, bigger" },
    },
  },
  frostnova = {
    type = "nova", name = "Frost Nova", icon = "Interface\\Icons\\Spell_Frost_FrostNova",
    desc = "Freezes every enemy around you in place.", color = { 0.6, 0.85, 1 },
    base = { dmg = 10, cd = 4.5, radius = 110, slow = 1.5, root = 1 },
    levels = {
      [2] = { radius = 20, text = "+20 radius" },
      [3] = { dmg = 10, text = "+10 damage" },
      [4] = { slow = 1.0, text = "Freezes 1 sec longer" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { radius = 35, dmg = 10, text = "Bigger, +10 damage" },
    },
  },
  ------------------------------------------------------------------ warlock
  shadowbolt = {
    type = "proj", name = "Shadow Bolt", icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
    desc = "Hurls bolts of shadow at the nearest enemies.", sprite = "shadowbolt", color = { 0.7, 0.4, 1 },
    base = { dmg = 19, cd = 1.0, count = 1, speed = 360, pierce = 1, life = 1.5, size = 28 },
    levels = {
      [2] = { count = 1, text = "+1 bolt" },
      [3] = { dmg = 7, text = "+7 damage" },
      [4] = { pierce = 1, text = "Pierces +1 enemy" },
      [5] = { count = 1, cdMul = 0.85, text = "+1 bolt, -15% cooldown" },
      [6] = { dmg = 10, count = 1, text = "+10 damage, +1 bolt" },
    },
  },
  corruption = {
    type = "dot", name = "Corruption", icon = "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
    desc = "Curses enemies with shadow damage over time. It spreads when they die.", color = { 0.65, 0.3, 0.8 },
    base = { dmg = 3, cd = 2.0, count = 2, dot = 5, dotDur = 6, spread = 2, range = 150, jumps = 1 },
    levels = {
      [2] = { count = 1, text = "+1 target" },
      [3] = { dot = 3, text = "+3 damage / sec" },
      [4] = { spread = 1, count = 1, text = "Spreads to +1, +1 target" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dot = 3, count = 1, text = "+3 damage / sec, +1 target" },
    },
  },
  rainfire = {
    type = "zone", name = "Rain of Fire", icon = "Interface\\Icons\\Spell_Shadow_RainOfFire",
    desc = "Fel fire falls on packs of enemies and keeps burning.", zoneSprite = "felfire", color = { 0.5, 1, 0.3 },
    base = { dmg = 7, cd = 3.5, count = 2, radius = 48, dur = 2.5, tick = 0.5, delay = 0.5 },
    levels = {
      [2] = { count = 1, text = "+1 fire" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { radius = 12, text = "+25% area" },
      [5] = { cdMul = 0.8, text = "-20% cooldown" },
      [6] = { count = 2, dmg = 4, text = "+2 fires, +4 damage" },
    },
  },
  drainlife = {
    type = "beam", name = "Drain Life", icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02",
    desc = "Drains the nearest enemy, healing you.", color = { 0.45, 1, 0.45 },
    base = { dmg = 4, tick = 0.25, range = 240, heal = 0.3, count = 1 },
    levels = {
      [2] = { dmg = 2, text = "+2 damage per tick" },
      [3] = { range = 40, text = "Longer reach" },
      [4] = { count = 1, text = "Drains +1 enemy" },
      [5] = { dmg = 3, heal = 0.1, text = "+3 damage, heals more" },
      [6] = { count = 1, dmg = 3, text = "Drains +1 enemy, +3 damage" },
    },
  },
  imp = {
    type = "pet", name = "Summon Imp", icon = "Interface\\Icons\\Spell_Shadow_SummonImp",
    desc = "An imp follows you and throws firebolts.", petSprite = "imp", sprite = "felfire", mode = "ranged",
    petSize = 36, color = { 0.5, 1, 0.3 },
    base = { dmg = 10, cd = 1.2, count = 1, speed = 400, pierce = 1, life = 1.4, size = 24, range = 330, move = 210 },
    levels = {
      [2] = { dmg = 4, text = "+4 damage" },
      [3] = { cdMul = 0.8, text = "-20% cooldown" },
      [4] = { count = 1, text = "A second imp" },
      [5] = { dmg = 6, text = "+6 damage" },
      [6] = { pierce = 1, cdMul = 0.8, text = "Pierces +1, -20% cooldown" },
    },
  },
  ------------------------------------------------------------------ hunter
  autoshot = {
    type = "proj", name = "Auto Shot", icon = "Interface\\Icons\\INV_Weapon_Bow_07",
    desc = "Arrows that pierce through lines of enemies.", sprite = "arrow", color = { 0.9, 0.8, 0.6 },
    base = { dmg = 13, cd = 0.85, count = 1, speed = 560, pierce = 3, life = 1.0, size = 30 },
    levels = {
      [2] = { dmg = 5, text = "+5 damage" },
      [3] = { pierce = 2, text = "Pierces +2" },
      [4] = { count = 1, text = "+1 arrow" },
      [5] = { cdMul = 0.8, text = "-20% cooldown" },
      [6] = { dmg = 8, count = 1, text = "+8 damage, +1 arrow" },
    },
  },
  multishot = {
    type = "fan", name = "Multi-Shot", icon = "Interface\\Icons\\Ability_UpgradeMoonGlaive",
    desc = "A fan of arrows toward the nearest enemy.", sprite = "arrow", color = { 0.9, 0.8, 0.6 },
    base = { dmg = 11, cd = 2.0, count = 5, speed = 520, pierce = 2, life = 0.8, size = 28, spread = 0.6 },
    levels = {
      [2] = { count = 2, text = "+2 arrows" },
      [3] = { dmg = 4, text = "+4 damage" },
      [4] = { pierce = 1, text = "Pierces +1" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { count = 3, dmg = 4, text = "+3 arrows, +4 damage" },
    },
  },
  trap = {
    type = "trap", name = "Explosive Trap", icon = "Interface\\Icons\\Spell_Fire_SelfDestruct",
    desc = "Drops traps that explode when enemies step on them.", sprite = "trap", color = { 1, 0.5, 0.15 },
    base = { dmg = 38, cd = 2.5, count = 2, radius = 75, trigger = 30, life = 20, size = 34 },
    levels = {
      [2] = { count = 1, text = "+1 trap" },
      [3] = { dmg = 15, text = "+15 damage" },
      [4] = { radius = 20, text = "Bigger explosion" },
      [5] = { cdMul = 0.7, text = "-30% cooldown" },
      [6] = { count = 2, dmg = 20, text = "+2 traps, +20 damage" },
    },
  },
  volley = {
    type = "zone", name = "Volley", icon = "Interface\\Icons\\Ability_Hunter_WildQuiver",
    desc = "Arrows rain down on the thickest pack of enemies.", rain = true, color = { 0.9, 0.75, 0.5 },
    base = { dmg = 7, cd = 4.0, count = 1, radius = 85, dur = 2.5, tick = 0.4, delay = 0 },
    levels = {
      [2] = { radius = 15, text = "+20% area" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { count = 1, text = "+1 volley" },
      [5] = { cdMul = 0.8, dur = 1, text = "-20% cooldown, lasts longer" },
      [6] = { dmg = 4, radius = 20, text = "+4 damage, bigger" },
    },
  },
  wolf = {
    type = "pet", name = "Call Wolf", icon = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    desc = "A wolf hunts down enemies near you and bites them.", petSprite = "wolf", mode = "melee",
    petSize = 46, color = { 0.75, 0.7, 0.6 },
    base = { dmg = 18, cd = 0.6, count = 1, range = 320, move = 240, knock = 80 },
    levels = {
      [2] = { dmg = 6, text = "+6 damage" },
      [3] = { move = 40, cdMul = 0.85, text = "Faster, bites faster" },
      [4] = { count = 1, text = "A second wolf" },
      [5] = { dmg = 8, text = "+8 damage" },
      [6] = { count = 1, dmg = 6, text = "A third wolf, +6 damage" },
    },
  },
}
for id, d in pairs(NEW_WEAPONS) do C.WEAPONS[id] = d end

-- Evolved forms (only chests evolve, see C.EVOLUTIONS): same type, stronger base, no levels, never offered on level-up.
local EVOLVED = {
  frostbolt_evo = { type = "proj", name = "Frostfire Bolt", icon = "Interface\\Icons\\Ability_Mage_FrostFireBolt",
    desc = "Evolved Frostbolt: more, faster, piercing bolts that chill.", sprite = "frostbolt", hit = "chill", color = { 0.7, 0.75, 1 },
    base = { dmg = 34, cd = 0.6, count = 4, speed = 420, pierce = 3, life = 1.5, size = 30, slow = 2.5 } },
  fireball_evo = { type = "proj", name = "Pyroblast", icon = "Interface\\Icons\\Spell_Fire_Fireball02",
    desc = "Evolved Fireball: huge explosions.", sprite = "fireball", hit = "explode", color = { 1, 0.45, 0.1 },
    base = { dmg = 60, cd = 1.4, count = 2, speed = 320, pierce = 1, life = 1.6, size = 40, radius = 110, splash = 1 } },
  arcane_evo = { type = "missile", name = "Arcane Barrage", icon = "Interface\\Icons\\Ability_Mage_ArcaneBarrage",
    desc = "Evolved Arcane Missiles: a storm of seeking missiles.", sprite = "arcane", homing = true, color = { 0.9, 0.55, 1 },
    base = { dmg = 18, cd = 1.0, count = 10, speed = 380, pierce = 2, life = 1.8, size = 24, turn = 8 } },
  blizzard_evo = { type = "zone", name = "Frozen Tempest", icon = "Interface\\Icons\\Spell_Frost_FrozenOrb",
    desc = "Evolved Blizzard: three great storms.", zoneSprite = "blizzard", color = { 0.65, 0.9, 1 },
    base = { dmg = 16, cd = 3.5, count = 3, radius = 125, dur = 5, tick = 0.4, slow = 1.5, delay = 0 } },
  frostnova_evo = { type = "nova", name = "Deep Freeze", icon = "Interface\\Icons\\Spell_Frost_Glacier",
    desc = "Evolved Frost Nova: freezes a huge area.", color = { 0.65, 0.9, 1 },
    base = { dmg = 45, cd = 3.5, radius = 185, slow = 3.0, root = 1 } },
  shadowbolt_evo = { type = "proj", name = "Chaos Bolt", icon = "Interface\\Icons\\Ability_Warlock_ChaosBolt",
    desc = "Evolved Shadow Bolt: bolts that tear through everything.", sprite = "shadowbolt", color = { 0.8, 0.45, 1 },
    base = { dmg = 36, cd = 1.0, count = 3, speed = 400, pierce = 4, life = 1.6, size = 34 } },
  corruption_evo = { type = "dot", name = "Unstable Affliction", icon = "Interface\\Icons\\Spell_Shadow_UnstableAffliction_3",
    desc = "Evolved Corruption: a plague that leaps from corpse to corpse.", color = { 0.7, 0.3, 0.9 },
    base = { dmg = 6, cd = 1.5, count = 6, dot = 14, dotDur = 6, spread = 3, range = 170, jumps = 2 } },
  rainfire_evo = { type = "zone", name = "Hellfire Rain", icon = "Interface\\Icons\\Spell_Fire_FelFlameStrike",
    desc = "Evolved Rain of Fire: a downpour of fel fire.", zoneSprite = "felfire", color = { 0.55, 1, 0.3 },
    base = { dmg = 13, cd = 2.6, count = 5, radius = 72, dur = 3, tick = 0.45, delay = 0.4 } },
  drainlife_evo = { type = "beam", name = "Drain Soul", icon = "Interface\\Icons\\Spell_Shadow_Haunting",
    desc = "Evolved Drain Life: drains four enemies at once.", color = { 0.5, 1, 0.5 },
    base = { dmg = 12, tick = 0.25, range = 300, heal = 0.4, count = 3 } },
  imp_evo = { type = "pet", name = "Demonic Legion", icon = "Interface\\Icons\\Spell_Shadow_SummonInfernal",
    desc = "Evolved Summon Imp: four imps hurl fel fire.", petSprite = "imp", sprite = "felfire", mode = "ranged",
    petSize = 38, color = { 0.55, 1, 0.3 },
    base = { dmg = 19, cd = 0.75, count = 3, speed = 440, pierce = 3, life = 1.4, size = 28, range = 360, move = 240 } },
  autoshot_evo = { type = "proj", name = "Aimed Shot", icon = "Interface\\Icons\\Ability_Hunter_AimedShot",
    desc = "Evolved Auto Shot: arrows that never stop.", sprite = "arrow", color = { 1, 0.85, 0.55 },
    base = { dmg = 40, cd = 0.6, count = 3, speed = 640, pierce = 8, life = 1.1, size = 34 } },
  multishot_evo = { type = "fan", name = "Barrage", icon = "Interface\\Icons\\Ability_Hunter_RapidRegeneration",
    desc = "Evolved Multi-Shot: a wide, fast barrage.", sprite = "arrow", color = { 1, 0.85, 0.55 },
    base = { dmg = 22, cd = 1.1, count = 14, speed = 560, pierce = 3, life = 0.9, size = 30, spread = 1.4 } },
  trap_evo = { type = "trap", name = "Expert Trapper", icon = "Interface\\Icons\\Ability_Hunter_TrapLauncher",
    desc = "Evolved Explosive Trap: a minefield.", sprite = "trap", color = { 1, 0.55, 0.15 },
    base = { dmg = 100, cd = 1.4, count = 7, radius = 120, trigger = 34, life = 25, size = 38 } },
  volley_evo = { type = "zone", name = "Hail of Arrows", icon = "Interface\\Icons\\Ability_Hunter_Crossfire",
    desc = "Evolved Volley: three endless rains of arrows.", rain = true, color = { 1, 0.8, 0.5 },
    base = { dmg = 18, cd = 2.8, count = 3, radius = 140, dur = 4, tick = 0.35, delay = 0 } },
  wolf_evo = { type = "pet", name = "The Beast Within", icon = "Interface\\Icons\\Ability_Hunter_BeastWithin",
    desc = "Evolved Call Wolf: a pack of four savage wolves.", petSprite = "wolf", mode = "melee",
    petSize = 50, color = { 0.9, 0.6, 0.5 },
    base = { dmg = 46, cd = 0.5, count = 4, range = 380, move = 320, knock = 120 } },
}
for id, d in pairs(EVOLVED) do d.evolved = true; d.levels = {}; C.WEAPONS[id] = d end

C.PASSIVES = {
  might  = { name = "Might",        icon = "Interface\\Icons\\Spell_Nature_Strength",     text = "+12% damage",         stat = "might",  add = 0.12 },
  haste  = { name = "Haste",        icon = "Interface\\Icons\\Spell_Nature_Bloodlust",    text = "-8% cooldowns",       stat = "haste",  mul = 0.92 },
  swift  = { name = "Sprint",       icon = "Interface\\Icons\\Ability_Rogue_Sprint",      text = "+10% move speed",     stat = "speed",  mulAdd = 0.10 },
  fort   = { name = "Fortitude",    icon = "Interface\\Icons\\Spell_Holy_WordFortitude",  text = "+25 max health",      stat = "maxhp",  add = 25 },
  regen  = { name = "Renew",        icon = "Interface\\Icons\\Spell_Holy_Renew",          text = "+0.6 health / sec",   stat = "regen",  add = 0.6 },
  magnet = { name = "Greed",        icon = "Interface\\Icons\\INV_Misc_Coin_01",          text = "+35% pickup range",   stat = "magnet", mulAdd = 0.35 },
  armor  = { name = "Devotion",     icon = "Interface\\Icons\\Spell_Holy_DevotionAura",   text = "-1 damage taken",     stat = "armor",  add = 1 },
  area   = { name = "Arcane Reach", icon = "Interface\\Icons\\Spell_Arcane_ArcaneResilience", text = "+10% area",         stat = "area",   add = 0.10 },
  crit   = { name = "Precision",    icon = "Interface\\Icons\\Ability_Marksmanship",      text = "+6% critical strike (double damage)", stat = "crit", add = 0.06 },
}
C.PASSIVE_ORDER = { "might", "haste", "swift", "fort", "regen", "magnet", "armor", "area", "crit" }
C.MAX_PASSIVE_LEVEL = 5

C.PLAYER = { magnet = 55, r = 12, iframes = 0.45 } -- hp/speed/armor/crit/regen come from the class

-- XP needed for the next level
function C.XpForLevel(level)
  -- about half the old pace: ~level 3 at 1:00, 10 at 2:00, 35-60 by 10:00 depending on the build
  return 5 + (level - 1) * 6 + math.floor((level - 1) ^ 2 * 0.15)
end

---------------------------------------------------------------------------
-- Weapon evolutions. A chest evolves `weapon` into `into` when the weapon is at C.MAX_WEAPON_LEVEL and
-- `passive` is owned (any level). Evolved weapons keep the type, hit harder, have no levels and are
-- never offered on level-up.
---------------------------------------------------------------------------
C.EVOLUTIONS = {
  { weapon = "crusader",   passive = "might", into = "crusader_evo" },
  { weapon = "consecrate", passive = "area",  into = "consecrate_evo" },
  { weapon = "hammers",    passive = "haste", into = "hammers_evo" },
  { weapon = "avenger",    passive = "crit",  into = "avenger_evo" },
  { weapon = "dstorm",     passive = "fort",  into = "dstorm_evo" },
  { weapon = "sinister",   passive = "crit",  into = "sinister_evo" },
  { weapon = "fan",        passive = "haste", into = "fan_evo" },
  { weapon = "shuriken",   passive = "area",  into = "shuriken_evo" },
  { weapon = "flurry",     passive = "swift", into = "flurry_evo" },
  { weapon = "poison",     passive = "might", into = "poison_evo" },
  { weapon = "wrath",      passive = "might", into = "wrath_evo" },
  { weapon = "moonfire",   passive = "regen", into = "moonfire_evo" },
  { weapon = "starfall",   passive = "area",  into = "starfall_evo" },
  { weapon = "thorns",     passive = "armor", into = "thorns_evo" },
  { weapon = "roots",      passive = "magnet", into = "roots_evo" },
}

local EVO = {
  ------------------------------------------------------------------ paladin
  crusader_evo = {
    type = "melee", name = "Templar's Verdict", icon = "Interface\\Icons\\Spell_Paladin_TemplarsVerdict",
    desc = "Evolved Crusader Strike: a holy blow all around you.", color = { 1, 0.95, 0.55 },
    base = { dmg = 48, cd = 0.6, range = 150, arc = 1, knock = 220 },
  },
  consecrate_evo = {
    type = "aura", name = "Hallowed Ground", icon = "Interface\\Icons\\Spell_Paladin_DivineCircle",
    desc = "Evolved Consecration: wide holy ground that sears.", color = { 1, 0.85, 0.35 },
    base = { dmg = 14, radius = 135, tick = 0.3 },
  },
  hammers_evo = {
    type = "orbit", name = "Hammer of the Righteous", icon = "Interface\\Icons\\Ability_Paladin_HammeroftheRighteous",
    desc = "Evolved Blessed Hammers: a ring of six heavy hammers.", sprite = "hammer", spinSprite = true, color = { 1, 0.9, 0.5 },
    base = { dmg = 16, count = 6, radius = 105, spin = 3.4, hitcd = 0.6, size = 34, knock = 40 },
  },
  avenger_evo = {
    type = "chain", name = "Holy Avenger", icon = "Interface\\Icons\\Ability_Paladin_HolyAvenger",
    desc = "Evolved Avenger's Shield: bounces through a whole pack.", sprite = "shield", color = { 1, 0.95, 0.5 },
    base = { dmg = 60, cd = 1.3, jumps = 10, range = 220 },
  },
  dstorm_evo = {
    type = "nova", name = "Avenging Storm", icon = "Interface\\Icons\\Spell_Holy_AvengineWrath",
    desc = "Evolved Divine Storm: bigger, faster and heals more.", color = { 1, 0.95, 0.6 },
    base = { dmg = 50, cd = 2.0, radius = 185, slow = 0, heal = 1.5, healCap = 20 },
  },
  ------------------------------------------------------------------ rogue
  sinister_evo = {
    type = "melee", name = "Eviscerate", icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",
    desc = "Evolved Sinister Strike: wide double cuts.", color = { 1, 0.6, 0.6 },
    base = { dmg = 26, cd = 0.3, range = 115, arc = 0.75, knock = 90, double = 1 },
  },
  fan_evo = {
    type = "burst", name = "Blade Dance", icon = "Interface\\Icons\\Ability_Warrior_Bladestorm",
    desc = "Evolved Fan of Knives: a storm of piercing knives.", sprite = "knife", color = { 0.9, 0.9, 1 },
    base = { dmg = 20, cd = 1.0, count = 24, speed = 460, pierce = 4, life = 0.9, size = 30 },
  },
  shuriken_evo = {
    type = "proj", name = "Shuriken Storm", icon = "Interface\\Icons\\Ability_Rogue_ShurikenStorm",
    desc = "Evolved Shuriken Toss: five huge stars that cut through everything.", sprite = "shuriken", spinSprite = true,
    color = { 0.85, 0.9, 1 },
    base = { dmg = 34, cd = 0.7, count = 5, speed = 560, pierce = 20, life = 1.4, size = 32 },
  },
  flurry_evo = {
    type = "orbit", name = "Killing Spree", icon = "Interface\\Icons\\Ability_Rogue_MurderSpree",
    desc = "Evolved Blade Flurry: eight blades, wider and faster.", sprite = "knife", spinSprite = true, color = { 1, 0.85, 0.85 },
    base = { dmg = 17, count = 8, radius = 70, spin = 10, hitcd = 0.22, size = 30 },
  },
  poison_evo = {
    type = "poison", name = "Deadly Brew", icon = "Interface\\Icons\\Ability_Rogue_DeadlyBrew",
    desc = "Evolved Deadly Poison: a far stronger, longer poison.", color = { 0.4, 1, 0.3 },
    base = { dps = 26, dur = 5 },
  },
  ------------------------------------------------------------------ druid
  wrath_evo = {
    type = "proj", name = "Starsurge", icon = "Interface\\Icons\\Spell_Arcane_Arcane03",
    desc = "Evolved Wrath: five piercing star bolts.", sprite = "wrath", color = { 0.8, 0.6, 1 },
    base = { dmg = 28, cd = 0.5, count = 5, speed = 480, pierce = 3, life = 1.5, size = 26 },
  },
  moonfire_evo = {
    type = "strike", name = "Sunfire", icon = "Interface\\Icons\\Ability_Mage_FireStarter",
    desc = "Evolved Moonfire: solar beams on a dozen enemies, burning hot.", color = { 1, 0.7, 0.3 },
    base = { dmg = 22, cd = 1.0, count = 12, radius = 0, delay = 0, dot = 17, dotDur = 4 },
  },
  starfall_evo = {
    type = "strike", name = "Celestial Alignment", icon = "Interface\\Icons\\Ability_Druid_Eclipse",
    desc = "Evolved Starfall: a constant rain of big stars.", sprite = "star", color = { 0.9, 0.75, 1 },
    base = { dmg = 46, cd = 1.6, count = 12, radius = 80, delay = 0.4 },
  },
  thorns_evo = {
    type = "aura", name = "Brambles", icon = "Interface\\Icons\\Spell_Nature_NatureGuardian",
    desc = "Evolved Thorns: a wide thicket that tears attackers apart.", color = { 0.5, 1, 0.3 },
    base = { dmg = 11, radius = 110, tick = 0.3, reflect = 90 },
  },
  roots_evo = {
    type = "nova", name = "Ursol's Vortex", icon = "Interface\\Icons\\Spell_Druid_UrsolsVortex",
    desc = "Evolved Entangling Roots: a huge snare that holds longer.", color = { 0.5, 1, 0.5 },
    base = { dmg = 24, cd = 3.0, radius = 230, slow = 4.5, root = 1 },
  },
}
for id, d in pairs(EVO) do d.evolved = true; d.levels = {}; C.WEAPONS[id] = d end

---------------------------------------------------------------------------
-- Meta shop: permanent upgrades bought with banked gold. cost(rank) = floor(cost * grow ^ rank).
-- Sim.New({ meta = { might = 2, ... } }) applies the ranks.
---------------------------------------------------------------------------
C.SHOP = {
  { id = "might",    name = "Might",     icon = "Interface\\Icons\\Spell_Nature_Strength",    text = "+5% damage",            max = 5, cost = 60,  grow = 1.6 },
  { id = "armor",    name = "Armor",     icon = "Interface\\Icons\\Spell_Holy_DevotionAura",  text = "-1 damage taken",       max = 3, cost = 120, grow = 1.9 },
  { id = "maxhp",    name = "Max HP",    icon = "Interface\\Icons\\Spell_Holy_WordFortitude", text = "+10% max health",       max = 5, cost = 60,  grow = 1.6 },
  { id = "recovery", name = "Recovery",  icon = "Interface\\Icons\\Spell_Holy_Renew",         text = "+0.2 health / sec",     max = 5, cost = 60,  grow = 1.6 },
  { id = "swift",    name = "Swiftness", icon = "Interface\\Icons\\Ability_Rogue_Sprint",     text = "+5% move speed",        max = 3, cost = 80,  grow = 1.7 },
  { id = "greed",    name = "Greed",     icon = "Interface\\Icons\\INV_Misc_Coin_01",         text = "+20% pickup range",     max = 3, cost = 50,  grow = 1.6 },
  { id = "growth",   name = "Growth",    icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",  text = "+5% experience",        max = 5, cost = 80,  grow = 1.6 },
  { id = "reroll",   name = "Reroll",    icon = "Interface\\Icons\\INV_Misc_Dice_01",         text = "+1 reroll per run (R)", max = 3, cost = 100, grow = 1.8 },
  { id = "skip",     name = "Skip",      icon = "Interface\\Icons\\Spell_Nature_TimeStop",    text = "+1 skip per run (S)",   max = 3, cost = 60,  grow = 1.8 },
  { id = "insight",  name = "Insight",   icon = "Interface\\Icons\\INV_Misc_Book_09",         text = "4 cards on level-up",   max = 1, cost = 600, grow = 1 },
}
C.SHOP_BY_ID = {}
for _, s in ipairs(C.SHOP) do C.SHOP_BY_ID[s.id] = s end

function C.ShopCost(id, rank)
  local s = C.SHOP_BY_ID[id]
  if not s or rank >= s.max then return nil end
  return math.floor(s.cost * s.grow ^ rank)
end

---------------------------------------------------------------------------
-- Curses: optional, stacking difficulty. Each active curse adds +25% XP and +50% gold.
---------------------------------------------------------------------------
C.CURSES = {
  { id = "horde",  name = "Horde",  icon = "Interface\\Icons\\Spell_Shadow_UnholyFrenzy",      text = "+50% spawn rate",   spawn = 1.5 },
  { id = "brutal", name = "Brutal", icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",  text = "+60% enemy health", hp = 1.6 },
  { id = "haste",  name = "Haste",  icon = "Interface\\Icons\\Spell_Shadow_CurseOfAchimonde",  text = "+25% enemy speed",  speed = 1.25 },
  { id = "frail",  name = "Frail",  icon = "Interface\\Icons\\Ability_Creature_Cursed_02",     text = "-30% max health",   maxhp = 0.7 },
}
C.CURSE_XP, C.CURSE_GOLD = 0.25, 0.5

-- XP and gold multipliers for a curse set ({ horde = true, ... })
function C.CurseMult(curses)
  local n = 0
  for _, c in ipairs(C.CURSES) do if curses and curses[c.id] then n = n + 1 end end
  return 1 + n * C.CURSE_XP, 1 + n * C.CURSE_GOLD, n
end

---------------------------------------------------------------------------
-- Achievements. check(sum) is a pure function of the run summary:
--   { class, t, won, kills, level, bossKilled, evolved, curses (count), gold, have = { [id] = true } }
-- `have` already holds the achievements earned before (and earlier in the same pass).
-- unlock: "reroll" (+1 reroll per run), "slot" (6th weapon slot), "title" (class screen title).
---------------------------------------------------------------------------
C.ACHIEVEMENTS = {
  { id = "survive5",  name = "Still Standing",    icon = "Interface\\Icons\\Spell_Holy_BorrowedTime",       desc = "Survive 5 minutes.",
    check = function(s) return s.t >= 300 end },
  { id = "survive10", name = "Survivor",          icon = "Interface\\Icons\\Achievement_General",           desc = "Survive 10 minutes.",
    check = function(s) return s.t >= 600 end },
  { id = "rogue10",   name = "Shadow of Azeroth", icon = "Interface\\Icons\\ClassIcon_Rogue",               desc = "Survive 10 minutes as a Rogue.",
    unlock = "reroll", unlockText = "Unlocks +1 Reroll every run",
    check = function(s) return s.class == "rogue" and s.t >= 600 end },
  { id = "win_paladin", name = "Light's Champion", icon = "Interface\\Icons\\ClassIcon_Paladin",          desc = "Win as a Paladin.",
    check = function(s) return s.won and s.class == "paladin" end },
  { id = "win_rogue", name = "Untouchable",       icon = "Interface\\Icons\\Ability_Rogue_Eviscerate",     desc = "Win as a Rogue.",
    check = function(s) return s.won and s.class == "rogue" end },
  { id = "win_druid", name = "Keeper of the Grove", icon = "Interface\\Icons\\ClassIcon_Druid",            desc = "Win as a Druid.",
    check = function(s) return s.won and s.class == "druid" end },
  { id = "win_mage",  name = "Archmage",          icon = "Interface\\Icons\\ClassIcon_Mage",                desc = "Win as a Mage.",
    check = function(s) return s.won and s.class == "mage" end },
  { id = "win_warlock", name = "Master of Shadows", icon = "Interface\\Icons\\ClassIcon_Warlock",           desc = "Win as a Warlock.",
    check = function(s) return s.won and s.class == "warlock" end },
  { id = "win_hunter", name = "Master of the Hunt", icon = "Interface\\Icons\\ClassIcon_Hunter",           desc = "Win as a Hunter.",
    check = function(s) return s.won and s.class == "hunter" end },
  { id = "boss",      name = "Lich Slayer",       icon = "Interface\\Icons\\Achievement_Boss_LichKing",     desc = "Kill The Frost Lich.",
    check = function(s) return s.bossKilled end },
  { id = "kills1000", name = "Thousand Cuts",     icon = "Interface\\Icons\\Achievement_BG_KillXEnemies_GeneralsRoom", desc = "Kill 1000 enemies in one run.",
    check = function(s) return s.kills >= 1000 end },
  { id = "evolve",    name = "Evolution",         icon = "Interface\\Icons\\Spell_Holy_SummonChampion",     desc = "Evolve a weapon.",
    unlock = "slot", unlockText = "Unlocks a 6th weapon slot (any class's skills)",
    check = function(s) return (s.evolved or 0) >= 1 end },
  { id = "cursed",    name = "Glutton for Punishment", icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth", desc = "Win with 2 or more curses.",
    check = function(s) return s.won and (s.curses or 0) >= 2 end },
  { id = "allclasses", name = "Champion of Azeroth", icon = "Interface\\Icons\\Achievement_Arena_2v2_7",   desc = "Win with all six classes.",
    unlock = "title", unlockText = "Unlocks the title Champion of Azeroth",
    check = function(s)
      local h = s.have
      for _, c in ipairs(C.CLASS_ORDER) do if not h["win_" .. c] then return false end end
      return true
    end },
}
C.TITLE = "Champion of Azeroth"

-- Bonuses from earned achievements ({ [id] = anything truthy }): { reroll = n, slot = n, title = bool }
function C.UnlockBonus(ach)
  local b = { reroll = 0, slot = 0, title = false }
  for _, a in ipairs(C.ACHIEVEMENTS) do
    if ach and ach[a.id] and a.unlock then
      if a.unlock == "title" then b.title = true else b[a.unlock] = b[a.unlock] + 1 end
    end
  end
  return b
end

-- Evolution recipes for Mage, Warlock and Hunter (the mechanism lives with the chests; this is data only).
-- Appended: keep any earlier C.EVOLUTIONS = { ... } definition above this block.
C.EVOLUTIONS = C.EVOLUTIONS or {}
for _, r in ipairs({
  { weapon = "frostbolt",  passive = "haste",  into = "frostbolt_evo" },
  { weapon = "fireball",   passive = "might",  into = "fireball_evo" },
  { weapon = "arcane",     passive = "crit",   into = "arcane_evo" },
  { weapon = "blizzard",   passive = "area",   into = "blizzard_evo" },
  { weapon = "frostnova",  passive = "armor",  into = "frostnova_evo" },
  { weapon = "shadowbolt", passive = "might",  into = "shadowbolt_evo" },
  { weapon = "corruption", passive = "regen",  into = "corruption_evo" },
  { weapon = "rainfire",   passive = "area",   into = "rainfire_evo" },
  { weapon = "drainlife",  passive = "fort",   into = "drainlife_evo" },
  { weapon = "imp",        passive = "haste",  into = "imp_evo" },
  { weapon = "autoshot",   passive = "crit",   into = "autoshot_evo" },
  { weapon = "multishot",  passive = "haste",  into = "multishot_evo" },
  { weapon = "trap",       passive = "area",   into = "trap_evo" },
  { weapon = "volley",     passive = "might",  into = "volley_evo" },
  { weapon = "wolf",       passive = "swift",  into = "wolf_evo" },
}) do C.EVOLUTIONS[#C.EVOLUTIONS + 1] = r end

-- Map events (seconds). Rings of skeletons close in; a gold goblin flees and vanishes after its life;
-- braziers burn near you and drop a pickup when broken.
C.EVENTS = {
  rings = { 210, 390 }, ringBase = 22,           -- count = ringBase + t / 15
  goblins = { 100, 260, 420 },
  brazierFirst = 25, brazierEvery = 30, brazierMax = 3,
  pickups = { magnet = 4, chicken = 3.5, bomb = 2.5 }, -- brazier drop weights
}
C.PICKUPS = {
  magnet  = { text = "All crystals fly to you" },
  chicken = { heal = 0.3, text = "Heals 30%" },
  bomb    = { dmg = 80, text = "Damages everything on screen" }, -- scaled by Sim.HpScale(t)
}

-- Zone themes: ground art, tint and wave weight multipliers (mix: kind = factor) picked from the player's map.
C.ZONES = {
  tirisfal = { name = "Tirisfal Glades", ground = "ground_tirisfal", tint = { 0.78, 0.86, 0.74 }, mix = { ghoul = 1.4, caster = 1.5, wraith = 1.2 } },
  barrens  = { name = "The Barrens",     ground = "ground_barrens",  tint = { 1, 0.92, 0.75 },    mix = { charger = 1.6, brute = 1.2, bat = 0.8 } },
  elwynn   = { name = "Elwynn Forest",   ground = "ground_elwynn",   tint = { 0.86, 1, 0.82 },    mix = { ooze = 1.6, ghoul = 0.9 } },
  snow     = { name = "the frozen north", ground = "ground_snow",    tint = { 0.92, 0.96, 1 },    mix = { wraith = 1.4, bat = 1.2 } },
}
-- Classic uiMapIDs (exact hits); everything else goes by name keywords on the map and its parents.
C.ZONE_MAPS = {
  [1420] = "tirisfal", [1421] = "tirisfal", [1458] = "tirisfal",
  [1411] = "barrens", [1412] = "barrens", [1413] = "barrens", [1454] = "barrens", [1456] = "barrens",
  [1429] = "elwynn", [1436] = "elwynn", [1453] = "elwynn",
  [1416] = "snow", [1426] = "snow", [1452] = "snow", [1455] = "snow",
}
-- Ordered: zones first, continents (fallbacks) last.
C.ZONE_KEYWORDS = {
  { "tirisfal", "tirisfal" }, { "undercity", "tirisfal" }, { "silverpine", "tirisfal" }, { "plaguelands", "tirisfal" },
  { "deathknell", "tirisfal" }, { "brill", "tirisfal" }, { "gilneas", "tirisfal" }, { "duskwood", "tirisfal" },
  { "deadwind", "tirisfal" }, { "swamp of sorrows", "tirisfal" }, { "felwood", "tirisfal" }, { "ghostlands", "tirisfal" },
  { "shadowmoon", "tirisfal" }, { "scholomance", "tirisfal" }, { "stratholme", "tirisfal" }, { "shadowfang", "tirisfal" },
  { "winterspring", "snow" }, { "dun morogh", "snow" }, { "ironforge", "snow" }, { "alterac", "snow" },
  { "northrend", "snow" }, { "icecrown", "snow" }, { "dragonblight", "snow" }, { "storm peaks", "snow" },
  { "howling fjord", "snow" }, { "borean", "snow" }, { "grizzly", "snow" }, { "zul'drak", "snow" },
  { "coldridge", "snow" }, { "kharanos", "snow" }, { "frost", "snow" }, { "snow", "snow" },
  { "barrens", "barrens" }, { "durotar", "barrens" }, { "orgrimmar", "barrens" }, { "mulgore", "barrens" },
  { "thunder bluff", "barrens" }, { "desolace", "barrens" }, { "tanaris", "barrens" }, { "thousand needles", "barrens" },
  { "badlands", "barrens" }, { "searing gorge", "barrens" }, { "burning steppes", "barrens" }, { "blasted lands", "barrens" },
  { "silithus", "barrens" }, { "stonetalon", "barrens" }, { "dustwallow", "barrens" }, { "hellfire", "barrens" },
  { "ragefire", "barrens" }, { "razorfen", "barrens" }, { "uldum", "barrens" }, { "ahn'qiraj", "barrens" },
  { "elwynn", "elwynn" }, { "stormwind", "elwynn" }, { "westfall", "elwynn" }, { "redridge", "elwynn" },
  { "loch modan", "elwynn" }, { "wetlands", "elwynn" }, { "arathi", "elwynn" }, { "hillsbrad", "elwynn" },
  { "hinterlands", "elwynn" }, { "stranglethorn", "elwynn" }, { "ashenvale", "elwynn" }, { "darkshore", "elwynn" },
  { "teldrassil", "elwynn" }, { "darnassus", "elwynn" }, { "feralas", "elwynn" }, { "moonglade", "elwynn" },
  { "azshara", "elwynn" }, { "un'goro", "elwynn" }, { "nagrand", "elwynn" }, { "goldshire", "elwynn" },
  -- continents
  { "kalimdor", "barrens" }, { "outland", "barrens" }, { "eastern kingdoms", "elwynn" },
}

-- Theme key for a map name (case-insensitive keyword match), or nil.
function C.ZoneForName(name)
  if type(name) ~= "string" then return nil end
  name = name:lower()
  for _, kw in ipairs(C.ZONE_KEYWORDS) do
    if name:find(kw[1], 1, true) then return kw[2] end
  end
  return nil
end
