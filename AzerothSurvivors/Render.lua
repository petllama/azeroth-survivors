-- Azeroth Survivors: drawing. Turns the sim's entities into pooled textures on the arena frame.
local _, ns = ...
local C = ns.Content
local R = {}
ns.Render = R

local sin, floor, min, max, abs, tremove = math.sin, math.floor, math.min, math.max, math.abs, table.remove

-- Movement animation per kind. rate: cycle speed; bob: px; hover: smooth float instead of steps;
-- rot: sway in radians; sq: squash and stretch; flap: wing beat (width); alpha: fade low point.
local ANIM = {
  ghoul  = { rate = 7,   bob = 3,   rot = 0.14, sq = 0.04 },
  bat    = { rate = 16,  bob = 4,   rot = 0.06, sq = 0,    hover = true, flap = 0.22 },
  wraith = { rate = 3,   bob = 5,   rot = 0.06, sq = 0.03, hover = true, alpha = 0.6 },
  brute  = { rate = 4.5, bob = 4,   rot = 0.08, sq = 0.07 },
  elite  = { rate = 6,   bob = 2.5, rot = 0.08, sq = 0.03 },
  boss   = { rate = 2.2, bob = 7,   rot = 0.03, sq = 0.03, hover = true },
  caster   = { rate = 3,  bob = 4,   rot = 0.05, sq = 0.03, hover = true },
  charger  = { rate = 9,  bob = 3,   rot = 0.12, sq = 0.05 },
  ooze     = { rate = 5,  bob = 1,   rot = 0.03, sq = 0.14 },
  oozelet  = { rate = 8,  bob = 1,   rot = 0.03, sq = 0.14 },
  skeleton = { rate = 8,  bob = 3,   rot = 0.15, sq = 0.04 },
  goblin   = { rate = 14, bob = 4,   rot = 0.15, sq = 0.05 },
  brazier  = { rate = 10, bob = 0,   rot = 0.02, sq = 0.04 },
  -- pets (drawn from the weapon's pets)
  imp      = { rate = 5,  bob = 4,   rot = 0.08, sq = 0.04, hover = true },
  wolf     = { rate = 12, bob = 3,   rot = 0.10, sq = 0.06 },
}
local HERO_WALK = { rate = 11, bob = 3.5, rot = 0.1, sq = 0.05 }
local heroAt = 0
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ART = "Interface\\AddOns\\AzerothSurvivors\\Art\\"

-- Art/*.tga ships with the addon. Fallbacks (raid icons, circles) keep the game playable without it.
R.USE_ART = true
local FALLBACK = {
  ghoul  = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", 0.75, 0.95, 0.65 },
  bat    = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", 0.9, 0.6, 0.9 },
  wraith = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", 0.6, 0.8, 1 },
  brute  = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", 0.6, 1, 0.6 },
  elite  = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", 1, 1, 1 },
  boss   = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", 0.6, 0.85, 1 },
  caster   = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", 0.85, 0.55, 1 },
  charger  = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", 0.8, 0.7, 0.6 },
  ooze     = { "Interface\\CharacterFrame\\TempPortraitAlphaMask", 0.4, 1, 0.35 },
  oozelet  = { "Interface\\CharacterFrame\\TempPortraitAlphaMask", 0.5, 1, 0.45 },
  skeleton = { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", 0.95, 0.95, 1 },
  goblin   = { "Interface\\Icons\\INV_Misc_Coin_02", 1, 1, 1 },
  brazier  = { "Interface\\Icons\\Spell_Fire_Fire", 1, 1, 1 },
}
-- pickups: art key -> WoW icon fallback, size
local ITEMS = {
  coin    = { "Interface\\Icons\\INV_Misc_Coin_01", 16 },
  magnet  = { "Interface\\Icons\\INV_Misc_Magnet", 24 },
  chicken = { "Interface\\Icons\\Spell_Magic_PolymorphChicken", 24 },
  bomb    = { "Interface\\Icons\\INV_Misc_Bomb_05", 24 },
}

-- Art drawn facing left (everything else faces right); mirrored so it faces where it moves.
local FACES_LEFT = { wolf = true }

local W, H = 1000, 700
local frame, world, fxLayer
local pools = {}
local playerTex, playerHp, groundTex, flashTex
local orbTex, auraTex, petTex = {}, {}, {} -- per weapon id
local bgTex, bombFlash
local sprites = {} -- fading fx sprites (slashes, falling stars, shields)
local lines, rings, numbers = {}, {}, {}
local gridLines = {}
local numBudget = 0
local now = 0

local function newPool(name, layer, sub, setup)
  local p = { free = {}, layer = layer, sub = sub, setup = setup, name = name }
  pools[name] = p
  return p
end

local function acquire(p)
  local t = tremove(p.free)
  if not t then
    t = world:CreateTexture(nil, p.layer, nil, p.sub)
    t.pool = p
    p.setup(t)
  end
  t:Show()
  return t
end

-- sim hook: an entity died / was collected
function R.Release(_, o)
  local t = o.tex
  t:Hide()
  local f = t.pool.free
  f[#f + 1] = t
  o.vis = nil
end

-- Returns true when the art file loaded; otherwise applies the fallback (if any).
local function art(t, name, fallback)
  t.isArt = R.USE_ART and t:SetTexture(ART .. name) and true or false
  if not t.isArt and fallback then
    t:SetTexture(fallback[1])
    t:SetVertexColor(fallback[2], fallback[3], fallback[4])
  end
  return t.isArt
end

function R.Init(parent, w, h)
  frame, W, H = parent, w, h
  world = CreateFrame("Frame", nil, frame)
  world:SetAllPoints()
  world:SetClipsChildren(true)
  R.world = world

  local bg = world:CreateTexture(nil, "BACKGROUND", nil, -8)
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.06, 0.05, 1)
  bgTex = bg

  groundTex = world:CreateTexture(nil, "BACKGROUND", nil, -7)
  groundTex:SetAllPoints()
  if R.USE_ART and groundTex:SetTexture(ART .. "ground", "REPEAT", "REPEAT") then
    groundTex:SetVertexColor(0.8, 0.8, 0.8)
  else
    groundTex:Hide()
    groundTex = nil
    for i = 1, 40 do
      local l = world:CreateTexture(nil, "BACKGROUND", nil, -6)
      l:SetColorTexture(1, 1, 1, 0.04)
      gridLines[i] = l
    end
  end


  for kind, d in pairs(C.ENEMIES) do
    newPool(kind, "ARTWORK", d.boss and 3 or (d.elite and 2 or 1), function(t)
      art(t, d.art or kind, FALLBACK[kind])
      t:SetSize(d.size, d.size)
    end)
  end
  newPool("gem", "ARTWORK", -2, function(t)
    if not art(t, "gem") then t:SetTexture(WHITE); t:SetRotation(math.pi / 4) end
  end)
  newPool("potion", "ARTWORK", -1, function(t)
    if not art(t, "potion") then t:SetTexture("Interface\\Icons\\INV_Potion_54") end
    t:SetSize(22, 22)
  end)
  newPool("chest", "ARTWORK", 0, function(t)
    if not art(t, "chest") then t:SetTexture("Interface\\Icons\\INV_Misc_TreasureChest02b"); t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    t:SetSize(36, 36)
  end)
  for kind, it in pairs(ITEMS) do
    newPool(kind, "ARTWORK", -1, function(t)
      if not art(t, kind) then t:SetTexture(it[1]); t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
      t:SetSize(it[2], it[2])
    end)
  end
  newPool("enemybolt", "OVERLAY", 2, function(t)
    if not art(t, "enemybolt") then t:SetTexture(CIRCLE); t:SetVertexColor(1, 0.3, 0.55) end
    t:SetBlendMode("ADD")
    t:SetSize(22, 22)
  end)
  newPool("trap", "BORDER", 1, function(t)
    if not art(t, "trap") then t:SetTexture("Interface\\Icons\\Spell_Fire_SelfDestruct"); t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  end)

  playerTex = world:CreateTexture(nil, "ARTWORK", nil, 5)
  playerTex:SetSize(52, 52)
  playerTex:SetPoint("CENTER", world, "BOTTOMLEFT", W / 2, H / 2)

  playerHp = CreateFrame("StatusBar", nil, world)
  playerHp:SetSize(40, 4)
  playerHp:SetPoint("TOP", playerTex, "BOTTOM", 0, 4)
  playerHp:SetStatusBarTexture(WHITE)
  playerHp:SetStatusBarColor(0.9, 0.15, 0.15)
  local hb = playerHp:CreateTexture(nil, "BACKGROUND")
  hb:SetAllPoints()
  hb:SetColorTexture(0, 0, 0, 0.7)

  fxLayer = CreateFrame("Frame", nil, world)
  fxLayer:SetAllPoints()
  fxLayer:SetFrameLevel(world:GetFrameLevel() + 5)

  flashTex = fxLayer:CreateTexture(nil, "OVERLAY", nil, 7)
  flashTex:SetAllPoints()
  flashTex:SetColorTexture(0.8, 0, 0, 1)
  flashTex:SetAlpha(0)
  flashTex.a = 0

  bombFlash = fxLayer:CreateTexture(nil, "OVERLAY", nil, 6)
  bombFlash:SetAllPoints()
  bombFlash:SetColorTexture(1, 0.85, 0.6, 1)
  bombFlash:SetAlpha(0)
  bombFlash.a = 0
end

-- ground art and tint for a zone theme (C.ZONES key or nil); missing zone art falls back to the plain ground
function R.SetZone(zkey)
  local z = zkey and C.ZONES[zkey]
  local c = z and z.tint or { 1, 1, 1 }
  if groundTex then
    if not (z and R.USE_ART and groundTex:SetTexture(ART .. z.ground, "REPEAT", "REPEAT")) then
      groundTex:SetTexture(ART .. "ground", "REPEAT", "REPEAT")
    end
    groundTex:SetVertexColor(0.8 * c[1], 0.8 * c[2], 0.8 * c[3])
  end
  bgTex:SetColorTexture(0.05 * c[1], 0.06 * c[2], 0.05 * c[3], 1)
  R.zone = zkey
end

-- glowing sprites are drawn additive; solid ones (knife, shuriken, hammer, shield) normal
local GLOW = { wrath = true, star = true, slash = true, bolt = true, orb = true,
  frostbolt = true, fireball = true, arcane = true, blizzard = true, shadowbolt = true, felfire = true, enemybolt = true }

local function projPool(w)
  local d = w.def
  local name = "proj_" .. (d.sprite or "bolt")
  return pools[name] or newPool(name, "OVERLAY", 1, function(t)
    if not art(t, d.sprite or "bolt") then
      t:SetTexture(CIRCLE)
      t:SetVertexColor(d.color[1], d.color[2], d.color[3])
      t:SetBlendMode("ADD")
    elseif GLOW[d.sprite] then
      t:SetBlendMode("ADD")
    end
    t:SetSize(d.base.size or 18, d.base.size or 18)
  end)
end

local function zonePool(d)
  local name = "zone_" .. (d.zoneSprite or "plain")
  return pools[name] or newPool(name, "BORDER", 0, function(t)
    if not (d.zoneSprite and art(t, d.zoneSprite)) then
      t:SetTexture(CIRCLE)
      t:SetVertexColor(d.color[1], d.color[2], d.color[3])
    end
    t:SetBlendMode("ADD")
  end)
end

function R.SetClass(cdef)
  playerTex:SetTexCoord(0, 1, 0, 1)
  if not art(playerTex, cdef.hero) then playerTex:SetTexture(cdef.icon) end
end

local function getSprite(name, color)
  local t
  for i = 1, #sprites do if not sprites[i].on then t = sprites[i]; break end end
  if not t then
    if #sprites >= 60 then return nil end
    t = world:CreateTexture(nil, "OVERLAY", nil, 3)
    sprites[#sprites + 1] = t
  end
  if t.name ~= name then
    t.name = name
    t.ok = art(t, name)
    if not t.ok then t:SetTexture(CIRCLE) end
  end
  t:SetBlendMode((not t.ok or GLOW[name]) and "ADD" or "BLEND")
  t:SetVertexColor(color[1], color[2], color[3])
  if t.mirrored then t:SetTexCoord(0, 1, 0, 1); t.mirrored = nil end
  t.on = true
  t:Show()
  return t
end

-- a sprite moving from (x1,y1) to (x2,y2) over dur, fading out over the last `fade` fraction
local function fxSprite(name, color, x1, y1, x2, y2, size, rot, dur, fade, grow)
  local t = getSprite(name, color)
  if not t then return end
  t.x1, t.y1, t.x2, t.y2, t.size, t.t0, t.dur, t.fade, t.grow = x1, y1, x2, y2, size, now, dur, fade or 1, grow or 1
  t:SetRotation(rot or 0)
  t:SetSize(size, size)
end

function R.Resize(w, h)
  W, H = w, h
  playerTex:SetPoint("CENTER", world, "BOTTOMLEFT", W / 2, H / 2)
end

---------------------------------------------------------------------------
-- effects
---------------------------------------------------------------------------
local function getLine()
  for i = 1, #lines do if not lines[i].on then return lines[i] end end
  if #lines >= 60 then return nil end
  local l = fxLayer:CreateLine(nil, "OVERLAY")
  l:SetTexture(WHITE)
  l:SetBlendMode("ADD")
  lines[#lines + 1] = l
  return l
end

local function getRing()
  for i = 1, #rings do if not rings[i].on then return rings[i] end end
  if #rings >= 12 then return nil end
  local t = world:CreateTexture(nil, "OVERLAY", nil, 2)
  t:SetTexture(CIRCLE)
  t:SetBlendMode("ADD")
  rings[#rings + 1] = t
  return t
end

local function ring(x, y, r, color, dur)
  local t = getRing()
  if t then
    t.on, t.x, t.y, t.r, t.t0, t.dur = true, x, y, r, now, dur or 0.35
    t:SetVertexColor(color[1], color[2], color[3])
    t:Show()
  end
end

local function line(x1, y1, x2, y2, color, thick, dur)
  local l = getLine()
  if not l then return end
  l.on, l.t0, l.dur = true, now, dur or 0.2
  l.x1, l.y1, l.x2, l.y2 = x1, y1, x2, y2
  l:SetVertexColor(color[1], color[2], color[3], 1)
  l:SetThickness(thick or 3)
  l:Show()
end

function R.Fx(S, kind, a, b, c, d, e)
  if kind == "nova" then -- x, y, r, weapon
    ring(a, b, c, d.def.color)
  elseif kind == "impact" then
    ring(a, b, c, d.def.color, 0.3)
  elseif kind == "slash" then -- x, y, angle, reach, weapon
    fxSprite("slash", e.def.color, a, b, a, b, d * 2, c, 0.16, 0.6, 1.1)
    if e.double then fxSprite("slash", e.def.color, a, b, a, b, d * 1.8, c + 0.5, 0.2, 0.6, 1.1) end
  elseif kind == "fall" then -- x, y, delay, weapon
    fxSprite(d.def.sprite or "star", d.def.color, a + 60, b + 320, a, b, 40, 0, c, 0.15)
  elseif kind == "beam" then
    line(a, b + 420, a, b, d.def.color, 5, 0.25)
    ring(a, b, 22, d.def.color, 0.25)
  elseif kind == "chain" then -- pts, n, weapon
    local pts, np, w = a, b, c
    local col = w.def.color
    for i = 1, np - 2, 2 do
      line(pts[i], pts[i + 1], pts[i + 2], pts[i + 3], col, w.def.sprite and 2 or 3)
      if w.def.sprite then
        fxSprite(w.def.sprite, { 1, 1, 1 }, pts[i], pts[i + 1], pts[i + 2], pts[i + 3], 30, 0, 0.12 + i * 0.03, 0.3)
      end
    end
  elseif kind == "zonefall" then -- x, y, delay, weapon
    fxSprite(d.def.zoneSprite or "felfire", d.def.color, a + 40, b + 300, a, b, 36, 0, c, 0.15)
  elseif kind == "rain" then -- x, y, r, weapon: a few arrows dropping into the area
    for _ = 1, 2 do
      local rx, ry = a + (math.random() - 0.5) * c * 1.4, b + (math.random() - 0.5) * c * 1.4
      fxSprite("arrow", { 1, 1, 1 }, rx + 20, ry + 160, rx, ry, 24, -1.69, 0.22, 0.3)
    end
  elseif kind == "curse" or kind == "bite" then -- x, y, 0, weapon
    ring(a, b, kind == "bite" and 16 or 22, d.def.color, kind == "bite" and 0.18 or 0.3)
  elseif kind == "drain" or kind == "spread" then -- x1, y1, x2, y2, weapon
    line(a, b, c, d, e.def.color, kind == "drain" and 3 or 2, kind == "drain" and 0.27 or 0.3)
  elseif kind == "telegraph" then -- x1, y1, x2, y2, duration: the charger's dash line
    line(a, b, c, d, { 1, 0.35, 0.15 }, 4, e)
  elseif kind == "bomb" then -- x, y, r
    ring(a, b, c, { 1, 0.7, 0.3 }, 0.5)
    bombFlash.a = 0.45
  elseif kind == "magnet" then
    ring(a, b, 90, { 0.4, 0.8, 1 }, 0.4)
  elseif kind == "ring" then
    ns.UI.Banner("A ring of skeletons closes in!", 0.9, 0.9, 0.95)
  elseif kind == "goblin" then
    ns.UI.Banner("A gold goblin! Catch it before it escapes!", 1, 0.85, 0.2)
  elseif kind == "goblinGone" then
    ns.UI.Banner("The goblin got away with its gold.", 0.8, 0.7, 0.4)
  elseif kind == "goblinKilled" then
    ns.UI.Banner("Gold!", 1, 0.85, 0.2)
    ring(a, b, 50, { 1, 0.85, 0.2 }, 0.4)
  elseif kind == "swarm" then
    ns.UI.Banner("A swarm of bats closes in!", 0.9, 0.6, 1)
  elseif kind == "boss" then -- a = how many times it came before (Endless)
    ns.UI.Banner((a or 0) > 0 and "The Frost Lich returns, stronger!" or "The Frost Lich has come for you!", 0.5, 0.8, 1)
    ns.Sfx("boss")
  elseif kind == "enrage" then
    ns.UI.Banner("The Frost Lich enrages!", 1, 0.35, 0.3)
    ring(a, b, 120, { 1, 0.3, 0.2 }, 0.6)
    ns.Sfx("boss")
  elseif kind == "revive" then -- shop Revival: a bright flash
    bombFlash.a = 0.7
    ring(S.p.x, S.p.y, 160, { 1, 0.9, 0.5 }, 0.8)
  elseif kind == "evolve" then -- weapon
    local p = S.p
    ring(p.x, p.y, 120, a.def.color, 0.6)
    ring(p.x, p.y, 70, { 1, 1, 1 }, 0.4)
  end
end

function R.Number(S, x, y, amt, crit, isDot)
  if (numBudget <= 0 and not crit) or not ns.db.numbers then return end
  local fs
  for i = 1, #numbers do if not numbers[i].on then fs = numbers[i]; break end end
  if not fs then
    if #numbers >= 50 then return end
    fs = fxLayer:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    numbers[#numbers + 1] = fs
  end
  numBudget = numBudget - 1
  fs.on, fs.x, fs.y, fs.t0 = true, x + (math.random() - 0.5) * 10, y, now
  fs:SetText(floor(amt + 0.5))
  fs:SetFont(STANDARD_TEXT_FONT, crit and 16 or 12, "OUTLINE")
  if crit then fs:SetTextColor(1, 0.5, 0.1)
  elseif isDot then fs:SetTextColor(0.5, 1, 0.4)
  elseif amt >= 40 then fs:SetTextColor(1, 0.8, 0.2)
  else fs:SetTextColor(1, 1, 1) end
  fs:Show()
end

-- dying enemies pop: the sprite flashes red, swells and fades
function R.Kill(S, e)
  if not ns.db.anim or e.vis == false then return end
  local d = e.def
  local t = getSprite(d.art or e.kind, { 1, 0.4, 0.4 })
  if not t then return end
  t:SetBlendMode("BLEND")
  t.x1, t.y1, t.x2, t.y2, t.size, t.t0, t.dur, t.fade, t.grow = e.x, e.y, e.x, e.y + 10, d.size, now, 0.25, 1, 1.35
  t:SetRotation(0)
  t:SetSize(d.size, d.size)
  -- mirrored like the enemy it replaces (art faces right unless FACES_LEFT)
  if t.ok and (e.face < 0) ~= (FACES_LEFT[d.art or e.kind] or false) then
    t:SetTexCoord(1, 0, 0, 1); t.mirrored = true
  end
  return t
end

function R.Heal(S, amt)
  if amt >= 1 then R.Number(S, S.p.x, S.p.y + 30, amt, false, true) end
end

function R.Hurt()
  flashTex.a = 0.28
end

function R.Clear()
  for i = 1, #lines do lines[i].on = false; lines[i]:Hide() end
  for i = 1, #rings do rings[i].on = false; rings[i]:Hide() end
  for i = 1, #numbers do numbers[i].on = false; numbers[i]:Hide() end
  for _, list in pairs(orbTex) do for i = 1, #list do list[i]:Hide() end end
  for _, t in pairs(auraTex) do t:Hide() end
  for _, list in pairs(petTex) do for i = 1, #list do list[i]:Hide() end end
  bombFlash.a = 0
  bombFlash:SetAlpha(0)
  for i = 1, #sprites do sprites[i].on = false; sprites[i]:Hide() end
  playerTex:SetTexCoord(0, 1, 0, 1)
  playerTex:SetAlpha(1)
  flashTex.a = 0
  flashTex:SetAlpha(0)
end

-- Return every texture of a finished run to its pool.
function R.ReleaseAll(S)
  for _, list in ipairs({ S.enemies, S.projs, S.gems, S.items, S.ebolts or {}, S.zones or {}, S.traps or {} }) do
    for i = 1, #list do
      local o = list[i]
      if o.tex then R.Release(S, o); o.tex = nil end
    end
  end
  R.Clear()
end

---------------------------------------------------------------------------
-- frame draw
---------------------------------------------------------------------------
local function place(t, sx, sy)
  t:SetPoint("CENTER", world, "BOTTOMLEFT", sx, sy)
end

local drawN = 0
function R.Draw(S, elapsed)
  now = now + elapsed
  drawN = drawN + 1
  numBudget = 6
  local p = S.p
  local ox, oy = W / 2 - p.x, H / 2 - p.y

  -- ground
  if groundTex then
    local T = 256
    local u0, v0 = (-ox / T) % 1, (oy / T) % 1
    groundTex:SetTexCoord(u0, u0 + W / T, v0, v0 + H / T)
  else
    local G = 64
    local n = 0
    local x0 = ox % G
    for x = x0, W, G do
      n = n + 1
      local l = gridLines[n]
      if not l then break end
      l:ClearAllPoints(); l:SetPoint("TOPLEFT", world, "TOPLEFT", x, 0); l:SetSize(1, H); l:Show()
    end
    local y0 = oy % G
    for y = y0, H, G do
      n = n + 1
      local l = gridLines[n]
      if not l then break end
      l:ClearAllPoints(); l:SetPoint("BOTTOMLEFT", world, "BOTTOMLEFT", 0, y); l:SetSize(W, 1); l:Show()
    end
    for i = n + 1, #gridLines do gridLines[i]:Hide() end
  end

  -- enemies (procedural animation: each kind has its own gait, see ANIM)
  local E = S.enemies
  local anim = ns.db.anim
  for i = 1, S.nE do
    local e = E[i]
    local sx, sy = e.x + ox, e.y + oy
    local d = e.def
    local m = d.size * 0.6 + 6
    if sx > -m and sx < W + m and sy > -m and sy < H + m then
      local t = e.tex
      if not t then
        t = acquire(pools[e.kind]); e.tex = t; e.vis = true; e.tint = nil; e.tface = nil
        e.at = math.random() * 6.3
      elseif not e.vis then
        t:Show(); e.vis = true
      end
      local tint = (e.flash > 0 and 1) or (e.aiS == 2 and d.ai == "charge" and 4) or (e.root > 0 and 3) or (e.slow > 0 and 2) or 0
      if anim then
        local a = ANIM[e.kind]
        local rate = a.rate * (e.root > 0 and 0 or (e.slow > 0 and 0.45 or 1))
        local at = e.at + elapsed * rate
        e.at = at
        local s1, s2 = sin(at), sin(at * 2)
        local bob = a.hover and (s1 * a.bob) or (abs(s1) * a.bob)
        local size = d.size
        if a.flap then
          t:SetSize(size * (1 + a.flap * s2), size * (1 - a.flap * 0.3 * s2))
        else
          t:SetSize(size * (1 + a.sq * s2), size * (1 - a.sq * s2))
        end
        t:SetRotation(a.rot * s1 * e.face)
        if a.alpha then t:SetAlpha(a.alpha + (1 - a.alpha) * (0.5 + 0.5 * s2)) end
        place(t, sx, sy + bob)
      else
        place(t, sx, sy)
      end
      if tint ~= e.tint then
        e.tint = tint
        if tint == 1 then t:SetVertexColor(1, 0.35, 0.35)
        elseif tint == 2 then t:SetVertexColor(0.55, 0.75, 1)
        elseif tint == 3 then t:SetVertexColor(0.55, 1, 0.45)
        elseif tint == 4 then t:SetVertexColor(1, 0.55, 0.2) -- charger about to dash
        elseif t.isArt then local c = d.tint; t:SetVertexColor(c and c[1] or 1, c and c[2] or 1, c and c[3] or 1)
        else local f = FALLBACK[e.kind]; t:SetVertexColor(f[2], f[3], f[4]) end
      end
      if e.face ~= e.tface then
        e.tface = e.face
        if (e.face < 0) ~= (t.isArt and FACES_LEFT[d.art or e.kind] or false) then t:SetTexCoord(1, 0, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
      end
    elseif e.vis then
      e.tex:Hide(); e.vis = false
    end
  end

  -- gems
  local G = S.gems
  for i = 1, S.nG do
    local g = G[i]
    local sx, sy = g.x + ox, g.y + oy
    if sx > -20 and sx < W + 20 and sy > -20 and sy < H + 20 then
      local t = g.tex
      if not t then t = acquire(pools.gem); g.tex = t; g.vis = true; g.tc = nil
      elseif not g.vis then t:Show(); g.vis = true end
      place(t, sx, sy)
      local tc = g.xp >= 20 and 3 or (g.xp >= 5 and 2 or 1)
      if tc ~= g.tc then
        g.tc = tc
        local s = tc == 3 and 18 or (tc == 2 and 14 or 11)
        t:SetSize(s, s)
        if tc == 3 then t:SetVertexColor(1, 0.35, 0.3)
        elseif tc == 2 then t:SetVertexColor(0.4, 1, 0.45)
        else t:SetVertexColor(0.45, 0.85, 1) end
      end
    elseif g.vis then
      g.tex:Hide(); g.vis = false
    end
  end

  -- items
  for i = 1, S.nI do
    local it = S.items[i]
    local t = it.tex
    if not t then t = acquire(pools[it.kind] or pools.potion); it.tex = t end
    place(t, it.x + ox, it.y + oy + sin(now * 4) * 3)
  end

  -- projectiles
  local P = S.projs
  for i = 1, S.nP do
    local pr = P[i]
    local t = pr.tex
    local d = pr.w.def
    if not t then
      t = acquire(projPool(pr.w)); pr.tex = t
      if not d.spinSprite then t:SetRotation(math.atan2(pr.vy, pr.vx)) end
    end
    if d.spinSprite then t:SetRotation(now * 14) elseif d.homing then t:SetRotation(math.atan2(pr.vy, pr.vx)) end
    place(t, pr.x + ox, pr.y + oy)
  end

  -- enemy projectiles, ground zones, traps
  for i = 1, (S.nEB or 0) do
    local b = S.ebolts[i]
    local t = b.tex
    if not t then t = acquire(pools.enemybolt); b.tex = t end
    t:SetRotation(now * 6)
    place(t, b.x + ox, b.y + oy)
  end
  for i = 1, (S.nZ or 0) do
    local z = S.zones[i]
    local d = z.w.def
    local t = z.tex
    if not t then t = acquire(zonePool(d)); z.tex = t end
    t:SetSize(z.r * 2, z.r * 2)
    if z.delay > 0 then t:SetAlpha(0.15)
    else t:SetAlpha((d.zoneSprite and 0.75 or 0.3) * min(1, z.t * 2, (z.dur - z.t) * 6 + 0.3)) end
    if d.zoneSprite then t:SetRotation(now * 0.7) end
    place(t, z.x + ox, z.y + oy)
  end
  for i = 1, (S.nTr or 0) do
    local tr = S.traps[i]
    local t = tr.tex
    if not t then t = acquire(pools.trap); tr.tex = t end
    local sz = tr.w.size or 34
    t:SetSize(sz, sz)
    t:SetAlpha(tr.arm > 0 and 0.45 or (0.8 + 0.2 * sin(now * 6 + i)))
    place(t, tr.x + ox, tr.y + oy)
  end

  -- weapons with persistent visuals
  local wl = S.wlist
  for wi = 1, #wl do
    local w = wl[wi]
    local d = w.def
    if d.type == "orbit" then
      local list = orbTex[w.id]
      if not list then list = {}; orbTex[w.id] = list end
      list.seen = drawN
      local cnt = ns.Sim.Count(S, w)
      for k = 1, cnt do
        local t = list[k]
        if not t then
          t = world:CreateTexture(nil, "OVERLAY", nil, 0)
          if not art(t, d.sprite or "orb") then
            t:SetTexture(CIRCLE); t:SetVertexColor(d.color[1], d.color[2], d.color[3]); t:SetBlendMode("ADD")
          end
          list[k] = t
        end
        local sz = (w.size or 26) * p.area
        t:SetSize(sz, sz)
        if d.spinSprite then t:SetRotation(now * 9 + k) end
        place(t, (w.orbs[2 * k - 1] or p.x) + ox, (w.orbs[2 * k] or p.y) + oy)
        t:Show()
      end
      for k = cnt + 1, #list do list[k]:Hide() end
    elseif d.type == "aura" then
      local t = auraTex[w.id]
      if not t then
        t = world:CreateTexture(nil, "BORDER")
        t:SetTexture(CIRCLE)
        t:SetBlendMode("ADD")
        t:SetVertexColor(d.color[1], d.color[2], d.color[3])
        auraTex[w.id] = t
      end
      t.seen = drawN
      local dd = w.radius * p.area * 2
      t:SetSize(dd, dd)
      t:SetAlpha(0.16 + 0.06 * sin(now * 5))
      place(t, W / 2, H / 2)
      t:Show()
    elseif d.type == "pet" and w.pets then
      local list = petTex[w.id]
      if not list then list = {}; petTex[w.id] = list end
      list.seen = drawN
      local a = ANIM[d.petSprite] or HERO_WALK
      for k = 1, #w.pets do
        local pet = w.pets[k]
        local t = list[k]
        if not t then
          t = world:CreateTexture(nil, "ARTWORK", nil, 4)
          if not art(t, d.petSprite) then t:SetTexture(d.icon); t:SetTexCoord(0.08, 0.92, 0.08, 0.92); t.icon = true end
          t.at = k
          list[k] = t
        end
        local sz = d.petSize or 36
        local bob = 0
        if anim then
          t.at = t.at + elapsed * (pet.moving and a.rate or 2.5)
          local s1, s2 = sin(t.at), sin(t.at * 2)
          bob = a.hover and s1 * a.bob or (pet.moving and abs(s1) * a.bob or 0)
          t:SetSize(sz * (1 + a.sq * s2), sz * (1 - a.sq * s2))
          t:SetRotation(pet.moving and a.rot * s1 * pet.face or 0)
        else
          t:SetSize(sz, sz)
        end
        if not t.icon then
          local flip = (pet.face < 0) ~= (FACES_LEFT[d.petSprite] or false)
          if flip ~= t.flip then
            t.flip = flip
            if flip then t:SetTexCoord(1, 0, 0, 1) else t:SetTexCoord(0, 1, 0, 1) end
          end
        end
        place(t, pet.x + ox, pet.y + oy + bob)
        t:Show()
      end
      for k = #w.pets + 1, #list do list[k]:Hide() end
    end
  end

  -- visuals of a weapon that is gone (evolved into another id)
  for _, list in pairs(petTex) do
    if list.seen ~= drawN then for k = 1, #list do list[k]:Hide() end end
  end
  for _, list in pairs(orbTex) do
    if list.seen ~= drawN then for k = 1, #list do list[k]:Hide() end end
  end
  for _, t in pairs(auraTex) do
    if t.seen ~= drawN then t:Hide() end
  end

  -- player
  if p.fx < -0.05 then playerTex:SetTexCoord(1, 0, 0, 1) elseif p.fx > 0.05 then playerTex:SetTexCoord(0, 1, 0, 1) end
  if anim then
    local a = HERO_WALK
    if p.moving then
      heroAt = heroAt + elapsed * a.rate
      local s1, s2 = sin(heroAt), sin(heroAt * 2)
      playerTex:SetSize(52 * (1 + a.sq * s2), 52 * (1 - a.sq * s2))
      playerTex:SetRotation(a.rot * s1 * (p.fx < 0 and -1 or 1))
      playerTex:SetPoint("CENTER", world, "BOTTOMLEFT", W / 2, H / 2 + abs(s1) * a.bob)
    else -- idle: slow breathing
      heroAt = heroAt + elapsed * 2.5
      local s = sin(heroAt)
      playerTex:SetSize(52 * (1 - 0.02 * s), 52 * (1 + 0.025 * s))
      playerTex:SetRotation(0)
      playerTex:SetPoint("CENTER", world, "BOTTOMLEFT", W / 2, H / 2 + 1 + s)
    end
  end
  playerTex:SetAlpha(p.iframes > 0 and (floor(now * 20) % 2 == 0 and 0.4 or 1) or 1)
  playerHp:SetMinMaxValues(0, p.maxhp)
  playerHp:SetValue(p.hp)

  -- fx
  for i = 1, #sprites do
    local t = sprites[i]
    if t.on then
      local f = (now - t.t0) / t.dur
      if f >= 1 then t.on = false; t:Hide()
      else
        local sz = t.size * (1 + (t.grow - 1) * f)
        t:SetSize(sz, sz)
        place(t, t.x1 + (t.x2 - t.x1) * f + ox, t.y1 + (t.y2 - t.y1) * f + oy)
        local fadeStart = 1 - t.fade
        t:SetAlpha(f > fadeStart and (1 - (f - fadeStart) / t.fade) or 1)
      end
    end
  end
  for i = 1, #rings do
    local t = rings[i]
    if t.on then
      local f = (now - t.t0) / t.dur
      if f >= 1 then t.on = false; t:Hide()
      else
        local d = t.r * 2 * (0.3 + 0.7 * f)
        t:SetSize(d, d)
        t:SetAlpha(0.5 * (1 - f))
        place(t, t.x + ox, t.y + oy)
      end
    end
  end
  for i = 1, #lines do
    local l = lines[i]
    if l.on then
      local f = (now - l.t0) / l.dur
      if f >= 1 then l.on = false; l:Hide()
      else
        l:SetStartPoint("BOTTOMLEFT", world, l.x1 + ox, l.y1 + oy)
        l:SetEndPoint("BOTTOMLEFT", world, l.x2 + ox, l.y2 + oy)
        l:SetAlpha(1 - f)
      end
    end
  end
  for i = 1, #numbers do
    local fs = numbers[i]
    if fs.on then
      local f = (now - fs.t0) / 0.6
      if f >= 1 then fs.on = false; fs:Hide()
      else
        fs:SetPoint("CENTER", world, "BOTTOMLEFT", fs.x + ox, fs.y + oy + f * 24)
        fs:SetAlpha(1 - f * f)
      end
    end
  end
  if bombFlash.a > 0 then
    bombFlash.a = max(0, bombFlash.a - elapsed * 1.5)
    bombFlash:SetAlpha(bombFlash.a)
  end
  if flashTex.a > 0 then
    flashTex.a = max(0, flashTex.a - elapsed * 1.2)
    flashTex:SetAlpha(flashTex.a)
  end
end
