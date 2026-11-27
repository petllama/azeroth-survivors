-- Azeroth Survivors: the hidden Death Knight class. Pure data, no WoW API (loaded right after Content.lua).
-- The class stays invisible (class screen, keys, other classes' 6th-slot offers, achievements list) until
-- db.unlockedDK is set: kill The Frost Lich in a run with 2 or more curses, with any class.
local _, ns = ...
local C = ns.Content

C.CLASSES.deathknight = {
  name = "Death Knight", icon = "Interface\\Icons\\ClassIcon_DeathKnight", hero = "hero_dk", color = { 0.77, 0.12, 0.23 },
  desc = "Risen champion. Runeblade cleaves, frost, plague and ghouls.", trait = "armored",
  hp = 125, speed = 128, armor = 1, crit = 0.05, regen = 0,
  start = "obliterate", kit = { "obliterate", "deathcoil", "dnd", "howlingblast", "raisedead" },
  unlock = "unlockedDK", -- db flag (and Sim unlocks key) that reveals the class
}
C.CLASS_ORDER[#C.CLASS_ORDER + 1] = "deathknight"

-- Is the class shown and selectable? flags = db (db.unlockedDK) or a Sim unlocks table.
function C.ClassVisible(id, flags)
  local cd = C.CLASSES[id]
  if not cd then return false end
  return not cd.unlock or (flags and flags[cd.unlock]) and true or false
end

-- C.CLASS_ORDER without the classes still hidden for these flags (keys 1..n follow this list)
function C.VisibleClasses(flags)
  local out = {}
  for _, id in ipairs(C.CLASS_ORDER) do
    if C.ClassVisible(id, flags) then out[#out + 1] = id end
  end
  return out
end

-- Skills. Existing weapon types only: melee, missile (homing, heals on hit), zone, nova, pet.
local DK = {
  obliterate = {
    type = "melee", name = "Obliterate", icon = "Interface\\Icons\\Spell_DeathKnight_ClassIcon",
    desc = "A heavy two-handed cleave in front of you.", color = { 0.55, 0.8, 1 },
    base = { dmg = 22, cd = 1.0, range = 110, arc = 0.4, knock = 150 },
    levels = {
      [2] = { dmg = 7, text = "+7 damage" },
      [3] = { range = 18, text = "+25% reach" },
      [4] = { arc = 0.3, text = "Wider cleave" },
      [5] = { cdMul = 0.8, text = "-20% cooldown" },
      [6] = { dmg = 10, arc = 0.3, text = "+10 damage, cleaves wider" },
    },
  },
  deathcoil = {
    type = "missile", name = "Death Coil", icon = "Interface\\Icons\\Spell_Shadow_DeathCoil",
    desc = "Unholy bolts that seek enemies and heal you a little per hit.", sprite = "deathcoil", homing = true,
    hit = "heal", color = { 0.6, 1, 0.35 },
    base = { dmg = 17, cd = 1.3, count = 1, speed = 300, pierce = 1, life = 2.0, size = 26, turn = 5, heal = 0.5 },
    levels = {
      [2] = { count = 1, text = "+1 coil" },
      [3] = { dmg = 6, text = "+6 damage" },
      [4] = { heal = 0.3, count = 1, text = "+1 coil, heals more" },
      [5] = { cdMul = 0.8, text = "-20% cooldown" },
      [6] = { dmg = 6, count = 1, text = "+6 damage, +1 coil" },
    },
  },
  dnd = {
    type = "zone", name = "Death and Decay", icon = "Interface\\Icons\\Spell_Shadow_DeathAndDecay",
    desc = "Corrupts the ground under a pack of enemies, hurting and slowing them.", zoneSprite = "dnd", color = { 0.45, 0.9, 0.35 },
    base = { dmg = 5, cd = 5.0, count = 1, radius = 70, dur = 3.5, tick = 0.5, slow = 1.0, delay = 0 },
    levels = {
      [2] = { radius = 15, text = "+20% area" },
      [3] = { dmg = 2, text = "+2 damage" },
      [4] = { dur = 1.5, text = "Lasts longer" },
      [5] = { cdMul = 0.8, text = "-20% cooldown" },
      [6] = { radius = 15, dmg = 2, text = "+20% area, +2 damage" },
    },
  },
  howlingblast = {
    type = "nova", name = "Howling Blast", icon = "Interface\\Icons\\Spell_Frost_ArcticWinds",
    desc = "An icy blast around you that slows every enemy it hits.", novaSprite = "howlingblast", color = { 0.55, 0.85, 1 },
    base = { dmg = 14, cd = 4.0, radius = 120, slow = 1.5 },
    levels = {
      [2] = { dmg = 8, text = "+8 damage" },
      [3] = { radius = 25, text = "+25 radius" },
      [4] = { slow = 1.0, text = "Slows 1 sec longer" },
      [5] = { cdMul = 0.75, text = "-25% cooldown" },
      [6] = { dmg = 14, radius = 30, text = "+14 damage, bigger" },
    },
  },
  raisedead = {
    type = "pet", name = "Raise Dead", icon = "Interface\\Icons\\Spell_Shadow_AnimateDead",
    desc = "A ghoul rises to chase down enemies near you and claw them.", petSprite = "dk_ghoul", mode = "melee",
    petAlt = "ghoul", petTint = { 0.55, 1, 0.5 }, -- without dk_ghoul.tga: the enemy ghoul art, tinted green
    petSize = 44, color = { 0.55, 0.9, 0.45 },
    base = { dmg = 14, cd = 0.7, count = 1, range = 300, move = 210, knock = 60 },
    levels = {
      [2] = { dmg = 5, text = "+5 damage" },
      [3] = { move = 30, cdMul = 0.85, text = "Faster, claws faster" },
      [4] = { count = 1, text = "A second ghoul" },
      [5] = { dmg = 6, text = "+6 damage" },
      [6] = { count = 1, dmg = 5, text = "A third ghoul, +5 damage" },
    },
  },
}
for id, d in pairs(DK) do C.WEAPONS[id] = d end

local DK_EVO = {
  obliterate_evo = {
    type = "melee", name = "Frostreaper", icon = "Interface\\Icons\\Spell_DeathKnight_FrozenRuneWeapon",
    desc = "Evolved Obliterate: a frozen runeblade sweeps all around you.", color = { 0.6, 0.9, 1 },
    base = { dmg = 40, cd = 0.65, range = 150, arc = 1, knock = 200 },
  },
  deathcoil_evo = {
    type = "missile", name = "Death's Embrace", icon = "Interface\\Icons\\Spell_Shadow_DeathsEmbrace",
    desc = "Evolved Death Coil: a stream of coils that pierce and heal you.", sprite = "deathcoil", homing = true,
    hit = "heal", color = { 0.7, 1, 0.4 },
    base = { dmg = 24, cd = 0.9, count = 5, speed = 340, pierce = 2, life = 2.0, size = 30, turn = 7, heal = 0.4 },
  },
  dnd_evo = {
    type = "zone", name = "Defile", icon = "Interface\\Icons\\Spell_DeathKnight_Defile",
    desc = "Evolved Death and Decay: two wide pools of blight.", zoneSprite = "dnd", color = { 0.5, 1, 0.35 },
    base = { dmg = 8, cd = 3.5, count = 2, radius = 115, dur = 4.5, tick = 0.45, slow = 1.5, delay = 0 },
  },
  howlingblast_evo = {
    type = "nova", name = "Remorseless Winter", icon = "Interface\\Icons\\Ability_DeathKnight_RemorselessWinters2",
    desc = "Evolved Howling Blast: a freezing storm that slows everything near you.", novaSprite = "howlingblast", color = { 0.6, 0.9, 1 },
    base = { dmg = 34, cd = 2.5, radius = 185, slow = 2.5 },
  },
  raisedead_evo = {
    type = "pet", name = "Army of the Dead", icon = "Interface\\Icons\\Spell_DeathKnight_ArmyOfTheDead",
    desc = "Evolved Raise Dead: four ghouls tear through the horde.", petSprite = "dk_ghoul", mode = "melee",
    petAlt = "ghoul", petTint = { 0.6, 1, 0.55 },
    petSize = 46, color = { 0.6, 1, 0.5 },
    base = { dmg = 32, cd = 0.55, count = 4, range = 380, move = 290, knock = 90 },
  },
}
for id, d in pairs(DK_EVO) do d.evolved = true; d.levels = {}; C.WEAPONS[id] = d end

C.EVOLUTIONS = C.EVOLUTIONS or {}
for _, r in ipairs({
  { weapon = "obliterate",   passive = "might", into = "obliterate_evo" },
  { weapon = "deathcoil",    passive = "regen", into = "deathcoil_evo" },
  { weapon = "dnd",          passive = "area",  into = "dnd_evo" },
  { weapon = "howlingblast", passive = "haste", into = "howlingblast_evo" },
  { weapon = "raisedead",    passive = "fort",  into = "raisedead_evo" },
}) do C.EVOLUTIONS[#C.EVOLUTIONS + 1] = r end

-- Achievements. `hidden` = db flag that must be set before the row shows in the list.
-- `final` checks pass only on the results screen (sum.final); `unlockFlag` sets that db flag when earned;
-- `toastHead` / `toastSound` make it the class-unlock toast instead of a plain achievement toast.
C.ACHIEVEMENTS[#C.ACHIEVEMENTS + 1] = {
  id = "unlock_dk", name = "Death Knight", icon = "Interface\\Icons\\ClassIcon_DeathKnight",
  desc = "Kill The Frost Lich with 2 or more curses active.", hidden = "unlockedDK", final = true,
  unlockFlag = "unlockedDK", unlockText = "Unlocks the Death Knight", toastHead = "A new class has risen from the grave",
  toastSound = "unlock",
  check = function(s) return s.final and s.bossKilled and (s.curses or 0) >= 2 end,
}
C.ACHIEVEMENTS[#C.ACHIEVEMENTS + 1] = {
  id = "win_deathknight", name = "Lord of the Scourge", icon = "Interface\\Icons\\Spell_DeathKnight_FrostPresence",
  desc = "Win as a Death Knight.", hidden = "unlockedDK",
  check = function(s) return s.won and s.class == "deathknight" end,
}
-- Champion of Azeroth stays at the six base classes
for _, a in ipairs(C.ACHIEVEMENTS) do
  if a.id == "allclasses" then
    a.check = function(s)
      for _, c in ipairs(C.CLASS_ORDER) do
        if not C.CLASSES[c].unlock and not s.have["win_" .. c] then return false end
      end
      return true
    end
  end
end
