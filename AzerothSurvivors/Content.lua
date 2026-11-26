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

-- Weapons. levels[i] = changes applied when reaching level i (level 1 = base stats).
C.WEAPONS = {
  bolt = {
    name = "Arcane Missiles", icon = "Interface\\Icons\\Spell_Nature_StarFall",
    desc = "Fires missiles at the nearest enemies.",
    base = { dmg = 12, cd = 0.9, count = 1, speed = 420, pierce = 1, life = 1.4 },
    levels = {
      [2] = { count = 1, text = "+1 missile" },
      [3] = { dmg = 5, text = "+5 damage" },
      [4] = { count = 1, text = "+1 missile" },
      [5] = { pierce = 1, text = "Pierces +1 enemy" },
      [6] = { cdMul = 0.75, count = 1, text = "-25% cooldown, +1 missile" },
    },
  },
  orbit = {
    name = "Holy Spheres", icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
    desc = "Spheres of light circle you.",
    base = { dmg = 9, count = 2, radius = 75, spin = 3.0, hitcd = 0.55 },
    levels = {
      [2] = { count = 1, text = "+1 sphere" },
      [3] = { dmg = 5, radius = 15, text = "+5 damage, wider orbit" },
      [4] = { count = 1, text = "+1 sphere" },
      [5] = { spin = 1.2, dmg = 5, text = "Faster, +5 damage" },
      [6] = { count = 2, text = "+2 spheres" },
    },
  },
  aura = {
    name = "Consecration", icon = "Interface\\Icons\\Spell_Holy_InnerFire",
    desc = "Burns enemies standing near you.",
    base = { dmg = 4, radius = 62, tick = 0.5 },
    levels = {
      [2] = { radius = 14, text = "+20% area" },
      [3] = { dmg = 3, text = "+3 damage" },
      [4] = { radius = 14, text = "+20% area" },
      [5] = { dmg = 4, text = "+4 damage" },
      [6] = { tickMul = 0.7, radius = 14, text = "Ticks faster, more area" },
    },
  },
  nova = {
    name = "Frost Nova", icon = "Interface\\Icons\\Spell_Frost_FrostNova",
    desc = "Blasts and slows everything around you.",
    base = { dmg = 14, cd = 4.0, radius = 130, slow = 2.0 },
    levels = {
      [2] = { dmg = 8, text = "+8 damage" },
      [3] = { radius = 30, text = "+30 radius" },
      [4] = { cdMul = 0.8, text = "-20% cooldown" },
      [5] = { dmg = 12, slow = 1.0, text = "+12 damage, longer slow" },
      [6] = { radius = 40, cdMul = 0.8, text = "Bigger, faster" },
    },
  },
  chain = {
    name = "Chain Lightning", icon = "Interface\\Icons\\Spell_Nature_ChainLightning",
    desc = "Strikes an enemy and jumps to others.",
    base = { dmg = 18, cd = 2.2, jumps = 2, range = 170 },
    levels = {
      [2] = { jumps = 1, text = "+1 jump" },
      [3] = { dmg = 10, text = "+10 damage" },
      [4] = { jumps = 2, text = "+2 jumps" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dmg = 15, jumps = 2, text = "+15 damage, +2 jumps" },
    },
  },
}
C.WEAPON_ORDER = { "bolt", "orbit", "aura", "nova", "chain" }
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
}
C.PASSIVE_ORDER = { "might", "haste", "swift", "fort", "regen", "magnet", "armor", "area" }
C.MAX_PASSIVE_LEVEL = 5

C.PLAYER = { hp = 100, speed = 140, magnet = 55, r = 12, iframes = 0.45 }

-- XP needed for the next level
function C.XpForLevel(level)
  if level < 20 then return 5 + (level - 1) * 4 end
  if level < 40 then return 81 + (level - 20) * 7 end
  return 221 + (level - 40) * 12
end
