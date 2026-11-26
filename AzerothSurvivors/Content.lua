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
  elite  = { hp = 450,  speed = 48, r = 24, dmg = 22, xp = 30,  size = 88, elite = true, drop = "potion" },
  boss   = { hp = 9000, speed = 44, r = 40, dmg = 35, xp = 300, size = 160, boss = true, name = "The Frost Lich" },
}

-- spawn weights by time (seconds): first matching row from the bottom whose t <= now
C.WAVES = {
  { t = 0,   mix = { ghoul = 1 } },
  { t = 45,  mix = { ghoul = 3, bat = 2 } },
  { t = 120, mix = { ghoul = 3, bat = 2, wraith = 2 } },
  { t = 200, mix = { ghoul = 2, bat = 2, wraith = 3, brute = 1 } },
  { t = 330, mix = { ghoul = 1, bat = 3, wraith = 3, brute = 2 } },
  { t = 450, mix = { bat = 2, wraith = 3, brute = 3 } },
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
C.CLASS_ORDER = { "paladin", "rogue", "druid" }

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
    base = { dmg = 10, count = 2, radius = 80, spin = 3.0, hitcd = 0.55, size = 28 },
    levels = {
      [2] = { count = 1, text = "+1 hammer" },
      [3] = { dmg = 5, radius = 15, text = "+5 damage, wider orbit" },
      [4] = { count = 1, text = "+1 hammer" },
      [5] = { spin = 1.2, dmg = 5, text = "Faster, +5 damage" },
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
