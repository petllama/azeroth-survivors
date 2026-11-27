-- Azeroth Survivors: the simulation. Pure Lua 5.1, no WoW API, so it runs offline (tests/run_sim.lua).
-- The render layer listens through S.hooks; entities carry a render handle in .tex that the sim never reads.
local _, ns = ...
local C = ns.Content
local Sim = {}
ns.Sim = Sim

local sqrt, floor, ceil, random, min, max, cos, sin = math.sqrt, math.floor, math.ceil, math.random, math.min, math.max, math.cos, math.sin
local tremove = table.remove
local TAU = math.pi * 2
local CELL = 64
local MAX_R = 40 -- largest enemy radius (boss); grid queries widen by this

local function noop() end
-- victory: the run reached 10:00. Without a handler (headless runs) it cashes out at once.
local NOHOOKS = { release = noop, number = noop, fx = noop, levelup = noop, hurt = noop, kill = noop, over = noop, pickup = noop, heal = noop,
  chest = noop, evolve = noop, revive = noop, victory = function(S) Sim.CashOut(S) end }

-- enemy health over time; past 10:00 (Endless) it climbs faster
function Sim.HpScale(t)
  local h = 1 + t / 300 + (t / 550) ^ 2
  if t > C.RUN_SECONDS then
    local d = t - C.RUN_SECONDS
    h = h * (1 + d / C.ENDLESS.hpRamp + (d / C.ENDLESS.hpRamp2) ^ 2)
  end
  return h
end

-- plain copy of a flat table of numbers/booleans (meta ranks, curse set)
local function copyFlat(t)
  local o = {}
  if type(t) == "table" then
    for k, v in pairs(t) do
      if type(k) == "string" and (type(v) == "number" or type(v) == "boolean") then o[k] = v end
    end
  end
  return o
end

-- the evolution recipe that made weapon `into`, if any
local function recipeOf(into)
  for _, r in ipairs(C.EVOLUTIONS) do if r.into == into then return r end end
end
Sim.RecipeOf = recipeOf

---------------------------------------------------------------------------
-- setup
-- opts: class, viewR, hooks, cap, stress, invuln, weapon,
--   meta    = { might = rank, armor, maxhp, recovery, swift, greed, growth, reroll, skip, insight } (shop ranks)
--   curses  = { horde = true, brutal = true, haste = true, frail = true }
--   unlocks = { reroll = n, slot = n } (achievement bonuses)
--   asc     = n (Ascension level 0-10, see C.AscRules)
---------------------------------------------------------------------------
function Sim.New(opts)
  opts = opts or {}
  local P = C.PLAYER
  local cls = C.CLASSES[opts.class or "paladin"] and (opts.class or "paladin") or "paladin"
  local cd = C.CLASSES[cls]
  local meta, curses, unlocks = copyFlat(opts.meta), copyFlat(opts.curses), copyFlat(opts.unlocks)
  local xpMul, goldMul = C.CurseMult(curses)
  local asc = C.AscRules(opts.asc)
  local S = {
    class = cls, cdef = cd, impacts = {}, nImp = 0, xpBank = 0, coinBank = 0,
    t = 0, kills = 0, state = "play", dmgDone = 0,
    meta = meta, curses = curses, unlocks = unlocks,
    gold = 0, dmgBy = {}, gotAt = {}, evolved = {}, nEvolved = 0, chestN = 0,
    xpMul = xpMul * (1 + 0.05 * (meta.growth or 0)), goldMul = goldMul * asc.gold,
    spawnMul = asc.spawn, eHpMul = asc.hp, eSpeedMul = asc.eSpeed, eDmgMul = asc.dmg,
    rerolls = (meta.reroll or 0) + (unlocks.reroll or 0), skips = meta.skip or 0,
    nChoices = math.max(2, ((meta.insight or 0) > 0 and 4 or 3) - asc.choicesLess),
    -- 0.6: shop extras, Limit Break stacks, Ascension, Endless
    revives = meta.revival or 0, banishes = meta.banish or 0, banished = {}, luck = meta.luck or 0, amount = meta.amount or 0,
    limit = {}, lbPicks = 0, lbAmtAt = 0,
    asc = asc.level, ascR = asc, eliteEvery = asc.eliteEvery or C.ELITE_EVERY,
    nextBoss = asc.bossAt or C.BOSS_AT, bossN = 0,
    wslots = C.WEAPON_SLOTS + (unlocks.slot or 0),
    viewR = opts.viewR or 600,
    cap = opts.cap or C.MAX_ENEMIES,
    stress = opts.stress, invuln = opts.invuln or opts.stress,
    hooks = setmetatable(opts.hooks or {}, { __index = NOHOOKS }),
    p = { x = 0, y = 0, r = P.r, hp = cd.hp, maxhp = cd.hp, speed = cd.speed, magnet = P.magnet, regen = cd.regen,
          armor = cd.armor, crit = cd.crit, might = 1, haste = 1, area = 1, iframes = 0, level = 1, xp = 0,
          xpNext = C.XpForLevel(1), fx = 1, fy = 0, moving = false },
    enemies = {}, nE = 0, projs = {}, nP = 0, gems = {}, nG = 0, items = {}, nI = 0,
    enemyPool = {}, projPool = {}, gemPool = {},
    weapons = {}, wlist = {}, passives = {}, plist = {},
    spawnAcc = 0, nextElite = asc.eliteEvery or C.ELITE_EVERY, nextSwarm = C.SWARM_EVERY,
    pendingLevels = 0, choices = nil,
    grid = {}, gridUsed = {}, nUsed = 0, nBuckets = 0, q = {}, q2 = {}, targets = {},
    nextId = 0, castId = 0,
  }
  -- meta shop ranks
  local p = S.p
  p.might = p.might + 0.05 * (meta.might or 0)
  p.armor = p.armor + (meta.armor or 0)
  p.maxhp = p.maxhp + cd.hp * 0.10 * (meta.maxhp or 0)
  p.regen = p.regen + 0.2 * (meta.recovery or 0)
  p.speed = p.speed + cd.speed * 0.05 * (meta.swift or 0)
  p.magnet = p.magnet + P.magnet * 0.20 * (meta.greed or 0) + P.magnet * 0.10 * (meta.magnet or 0)
  p.haste = p.haste * 0.97 ^ (meta.cooldown or 0)
  p.area = p.area + 0.05 * (meta.area or 0)
  -- curses
  for _, c in ipairs(C.CURSES) do
    if curses[c.id] then
      if c.spawn then S.spawnMul = S.spawnMul * c.spawn end
      if c.hp then S.eHpMul = S.eHpMul * c.hp end
      if c.speed then S.eSpeedMul = S.eSpeedMul * c.speed end
      if c.maxhp then p.maxhp = p.maxhp * c.maxhp end
    end
  end
  p.maxhp = floor(p.maxhp + 0.5)
  p.hp = p.maxhp
  Sim.InitContent(S, opts)
  Sim.AddWeapon(S, opts.weapon or cd.start)
  return S
end

---------------------------------------------------------------------------
-- upgrades
---------------------------------------------------------------------------
function Sim.AddWeapon(S, id)
  local def = C.WEAPONS[id]
  local w = { id = id, def = def, level = 1, timer = 0.4, angle = 0, orbs = {}, pts = {}, npts = 0 }
  for k, v in pairs(def.base) do w[k] = v end
  S.weapons[id] = w
  S.wlist[#S.wlist + 1] = w
  if not S.gotAt[id] then S.gotAt[id] = S.t end
  if def.type == "poison" then S.poison = w end
  if def.reflect or w.reflect then S.thorns = w end
  return w
end

-- Replace the recipe's weapon by its evolution in the same slot.
function Sim.Evolve(S, r)
  local old = S.weapons[r.weapon]
  local def = C.WEAPONS[r.into]
  if not old or not def then return nil end
  local w = { id = r.into, def = def, level = 1, timer = old.timer, angle = old.angle or 0, orbs = {}, pts = {}, npts = 0 }
  for k, v in pairs(def.base) do w[k] = v end
  for i = 1, #S.wlist do if S.wlist[i] == old then S.wlist[i] = w end end
  S.weapons[r.weapon] = nil
  S.weapons[r.into] = w
  S.evolved[r.weapon] = r.into
  S.nEvolved = S.nEvolved + 1
  if not S.gotAt[r.into] then S.gotAt[r.into] = S.t end
  if S.poison == old then S.poison = nil end
  if S.thorns == old then S.thorns = nil end
  if def.type == "poison" then S.poison = w end
  if def.reflect or w.reflect then S.thorns = w end
  S.picks = (S.picks or 0) + 1
  S.hooks.evolve(S, w, r)
  return w
end

-- recipes whose weapon is maxed and whose passive is owned
function Sim.EligibleEvolutions(S)
  local out = {}
  for _, r in ipairs(C.EVOLUTIONS) do
    local w = S.weapons[r.weapon]
    if w and not w.def.evolved and w.level >= C.MAX_WEAPON_LEVEL and S.passives[r.passive] and C.WEAPONS[r.into] then
      out[#out + 1] = r
    end
  end
  return out
end

function Sim.LevelWeapon(S, id)
  local w = S.weapons[id]
  w.level = w.level + 1
  for k, v in pairs(w.def.levels[w.level] or {}) do
    if k == "cdMul" then w.cd = w.cd * v
    elseif k == "tickMul" then w.tick = w.tick * v
    elseif k ~= "text" then w[k] = (w[k] or 0) + v end
  end
end

function Sim.AddPassive(S, id)
  local d, p = C.PASSIVES[id], S.p
  local lv = (S.passives[id] or 0) + 1
  S.passives[id] = lv
  if lv == 1 then S.plist[#S.plist + 1] = id end
  if d.stat == "might" then p.might = p.might + d.add
  elseif d.stat == "haste" then p.haste = p.haste * d.mul
  elseif d.stat == "speed" then p.speed = p.speed + S.cdef.speed * d.mulAdd
  elseif d.stat == "crit" then p.crit = p.crit + d.add
  elseif d.stat == "maxhp" then p.maxhp = p.maxhp + d.add; p.hp = p.hp + d.add
  elseif d.stat == "regen" then p.regen = p.regen + d.add
  elseif d.stat == "magnet" then p.magnet = p.magnet + C.PLAYER.magnet * d.mulAdd
  elseif d.stat == "armor" then p.armor = p.armor + d.add
  elseif d.stat == "area" then p.area = p.area + d.add end
end

-- a skill's effective count: its own, +1 per shop Amount (any skill with a count), +1 per Limit Break Amount
-- (bolt, fan and missile skills). Render reads it too.
function Sim.Count(S, w)
  local t = w.def.type
  local n = w.count or 0
  if C.COUNT_TYPES[t] then n = n + (S.amount or 0) end
  if C.LIMIT_AMOUNT_TYPES[t] then n = n + (S.limit and S.limit.amount or 0) end
  return n
end
local wcount = Sim.Count

-- one Limit Break stack (C.LIMIT)
function Sim.AddLimit(S, id)
  local p, P = S.p, C.PLAYER
  S.limit[id] = (S.limit[id] or 0) + 1
  if id == "might" then p.might = p.might + 0.03
  elseif id == "maxhp" then p.maxhp = p.maxhp + 10; p.hp = p.hp + 10
  elseif id == "crit" then p.crit = p.crit + 0.02
  elseif id == "haste" then p.haste = math.max(C.LIMIT_HASTE_FLOOR, p.haste * 0.98)
  elseif id == "area" then p.area = p.area + 0.05
  elseif id == "speed" then p.speed = p.speed + S.cdef.speed * 0.04
  elseif id == "magnet" then p.magnet = p.magnet + P.magnet * 0.05 end
end

-- Limit Break cards that may be offered now
local function limitOffers(S)
  local out = {}
  for _, l in ipairs(C.LIMIT) do
    local n = S.limit[l.id] or 0
    local ok = not l.cap or n < l.cap
    if l.id == "haste" and S.p.haste * 0.98 < C.LIMIT_HASTE_FLOOR then ok = false end
    if l.id == "crit" and S.p.crit >= 1 then ok = false end
    if l.every and S.lbPicks - (S.lbAmtAt or 0) < l.every - 1 then ok = false end
    if ok then out[#out + 1] = l.id end
  end
  return out
end
Sim.LimitOffers = limitOffers

-- skills a class may take: its kit, then (with a 6th weapon slot unlocked) other classes' skills.
-- A hidden class (cd.unlock) adds its skills only when S.unlocks[cd.unlock] is set.
local foreignCache = {}
local function foreignSkills(S)
  local key = ""
  for _, cid in ipairs(C.CLASS_ORDER) do
    local cd = C.CLASSES[cid]
    if cd and cd.unlock and S.unlocks[cd.unlock] then key = key .. cid .. ";" end
  end
  local list = foreignCache[key]
  if not list then
    list = {}
    foreignCache[key] = list
    local seen = {}
    for _, cid in ipairs(C.CLASS_ORDER) do
      local cd = C.CLASSES[cid]
      if cd and (not cd.unlock or S.unlocks[cd.unlock]) then
        for _, id in ipairs(cd.kit or {}) do
          if not seen[id] and C.WEAPONS[id] and not C.WEAPONS[id].evolved then seen[id] = true; list[#list + 1] = id end
        end
      end
    end
  end
  return list
end

-- S.nChoices (3, 4 with Insight) weighted picks without replacement; upgrades of owned things weigh double.
-- Evolved weapons (and the weapons they replaced) are never offered.
function Sim.RollChoices(S)
  local pool, wts = {}, {}
  local banished = S.banished or {}
  local function add(c, wt) if not banished[c.id] then pool[#pool + 1] = c; wts[#wts + 1] = wt end end
  local inKit = {}
  for _, id in ipairs(S.cdef.kit) do
    inKit[id] = true
    local w = S.weapons[id]
    if w then
      if w.level < C.MAX_WEAPON_LEVEL then add({ kind = "weapon", id = id, level = w.level + 1 }, 2) end
    elseif not S.evolved[id] and #S.wlist < S.wslots then
      add({ kind = "weapon", id = id, level = 1 }, 1.2)
    end
  end
  if S.wslots > C.WEAPON_SLOTS then
    for _, id in ipairs(foreignSkills(S)) do
      if not inKit[id] then
        local w = S.weapons[id]
        if w then
          if w.level < C.MAX_WEAPON_LEVEL then add({ kind = "weapon", id = id, level = w.level + 1 }, 2) end
        elseif not S.evolved[id] and #S.wlist < S.wslots then
          add({ kind = "weapon", id = id, level = 1 }, 0.25)
        end
      end
    end
  end
  for _, id in ipairs(C.PASSIVE_ORDER) do
    local lv = S.passives[id]
    if lv then
      if lv < C.MAX_PASSIVE_LEVEL then add({ kind = "passive", id = id, level = lv + 1 }, 1.5) end
    elseif #S.plist < C.PASSIVE_SLOTS then
      add({ kind = "passive", id = id, level = 1 }, 1)
    end
  end
  local picks = {}
  for _ = 1, S.nChoices or 3 do
    local total = 0
    for i = 1, #wts do total = total + wts[i] end
    if total <= 0 then break end
    local r = random() * total
    for i = 1, #wts do
      r = r - wts[i]
      if r <= 0 and wts[i] > 0 then picks[#picks + 1] = pool[i]; wts[i] = 0; break end
    end
  end
  if #picks == 0 then -- nothing left to offer: Limit Break
    local lb = limitOffers(S)
    for _ = 1, S.nChoices or 3 do
      if #lb == 0 then break end
      local id = table.remove(lb, random(#lb))
      picks[#picks + 1] = { kind = "limit", id = id, level = (S.limit[id] or 0) + 1 }
    end
  end
  if #picks == 0 then picks[1] = { kind = "heal" } end
  S.choices = picks
  return picks
end

function Sim.ChoiceText(c)
  if c.kind == "heal" then return "Healing Potion", "Restore 40 health.", "Interface\\Icons\\INV_Potion_54" end
  if c.kind == "limit" then
    local l = C.LIMIT_BY_ID[c.id]
    return "Limit Break: " .. l.name, l.text .. ".  Now " .. C.LimitLabel(c.id, (c.level or 1) - 1) .. ", then " .. C.LimitLabel(c.id, c.level or 1) .. ".", l.icon
  end
  if c.kind == "gold" then return c.amount .. " gold", "A pile of gold for the shop.", "Interface\\Icons\\INV_Misc_Coin_01" end
  if c.kind == "evolve" then
    local d, from = C.WEAPONS[c.id], C.WEAPONS[c.from]
    return d.name, "Evolution! " .. (from and from.name or "?") .. " becomes " .. d.name .. ". " .. d.desc, d.icon
  end
  if c.kind == "weapon" then
    local d = C.WEAPONS[c.id]
    local text = c.level == 1 and ("New! " .. d.desc) or (d.levels[c.level] and d.levels[c.level].text or "")
    return d.name .. (c.level > 1 and (" " .. c.level) or ""), text, d.icon
  end
  local d = C.PASSIVES[c.id]
  return d.name .. (c.level > 1 and (" " .. c.level) or ""), (c.level == 1 and "New! " or "") .. d.text, d.icon
end

local function apply(S, c)
  if c.kind == "heal" then S.p.hp = min(S.p.maxhp, S.p.hp + 40 * S.ascR.healMul)
  elseif c.kind == "limit" then
    Sim.AddLimit(S, c.id)
    S.lbPicks = S.lbPicks + 1
    if c.id == "amount" then S.lbAmtAt = S.lbPicks end
  elseif c.kind == "gold" then S.gold = S.gold + c.amount
  elseif c.kind == "weapon" then
    if S.weapons[c.id] then Sim.LevelWeapon(S, c.id) else Sim.AddWeapon(S, c.id) end
  elseif c.kind == "passive" then Sim.AddPassive(S, c.id) end
  S.picks = (S.picks or 0) + 1
end

-- after a pick / skip / chest: next level-up, or back to play
local function nextOrPlay(S)
  if S.pendingLevels > 0 then
    S.state = "levelup"
    Sim.RollChoices(S)
    S.hooks.levelup(S)
  else
    S.state = "play"
  end
end

function Sim.Choose(S, i)
  local c = S.choices and S.choices[i]
  if not c or S.state ~= "levelup" then return false end
  apply(S, c)
  S.choices = nil
  S.pendingLevels = S.pendingLevels - 1
  nextOrPlay(S)
  return true
end

-- R on the level-up screen: new cards, uses one reroll
function Sim.Reroll(S)
  if S.state ~= "levelup" or (S.rerolls or 0) <= 0 then return false end
  S.rerolls = S.rerolls - 1
  Sim.RollChoices(S)
  S.hooks.levelup(S)
  return true
end

-- B on the level-up screen, then a card: that card's skill or passive is never offered again this run (new cards)
function Sim.Banish(S, i)
  local c = S.choices and S.choices[i]
  if S.state ~= "levelup" or (S.banishes or 0) <= 0 or not c or (c.kind ~= "weapon" and c.kind ~= "passive") then return false end
  S.banishes = S.banishes - 1
  S.banished[c.id] = true
  Sim.RollChoices(S)
  S.hooks.levelup(S)
  return true
end

-- S on the level-up screen: take nothing for this level, uses one skip
function Sim.Skip(S)
  if S.state ~= "levelup" or (S.skips or 0) <= 0 then return false end
  S.skips = S.skips - 1
  S.choices = nil
  S.pendingLevels = S.pendingLevels - 1
  nextOrPlay(S)
  return true
end

---------------------------------------------------------------------------
-- chests: picked up -> state "chest"; OpenChest rolls and applies the upgrades; CloseChest resumes
---------------------------------------------------------------------------
local function chestReward(S)
  local evo = Sim.EligibleEvolutions(S)
  if #evo > 0 then
    local r = evo[random(#evo)]
    Sim.Evolve(S, r)
    return { kind = "evolve", id = r.into, from = r.weapon }
  end
  local opts = {}
  for _, w in ipairs(S.wlist) do
    if not w.def.evolved and w.level < C.MAX_WEAPON_LEVEL then opts[#opts + 1] = { kind = "weapon", id = w.id, level = w.level + 1 } end
  end
  for _, id in ipairs(S.plist) do
    if S.passives[id] < C.MAX_PASSIVE_LEVEL then opts[#opts + 1] = { kind = "passive", id = id, level = S.passives[id] + 1 } end
  end
  local c
  if #opts > 0 then c = opts[random(#opts)]
  else c = { kind = "gold", amount = floor(C.CHEST_GOLD * S.goldMul + 0.5) } end
  apply(S, c)
  return c
end

function Sim.OpenChest(S)
  if S.state ~= "chest" or S.chestN <= 0 then return nil end
  local list = {}
  for i = 1, S.chestN do list[i] = chestReward(S) end
  S.chestN = 0
  S.chestRewards = list
  S.chests = (S.chests or 0) + 1
  return list
end

function Sim.CloseChest(S)
  if S.state ~= "chest" then return false end
  if S.chestN > 0 then Sim.OpenChest(S) end
  S.chestRewards = nil
  nextOrPlay(S)
  return true
end

---------------------------------------------------------------------------
-- spatial grid
---------------------------------------------------------------------------
local function key(cx, cy) return (cx + 30000) * 65536 + (cy + 30000) end

local function gridBuild(S)
  if S.nBuckets > 3000 then S.grid, S.nBuckets, S.nUsed = {}, 0, 0 end
  local used, grid, E = S.gridUsed, S.grid, S.enemies
  for i = 1, S.nUsed do used[i].n = 0 end
  local nU = 0
  for i = 1, S.nE do
    local e = E[i]
    if not e.dead then
      local k = key(floor(e.x / CELL), floor(e.y / CELL))
      local b = grid[k]
      if not b then b = { n = 0 }; grid[k] = b; S.nBuckets = S.nBuckets + 1 end
      if b.n == 0 then nU = nU + 1; used[nU] = b end
      b.n = b.n + 1
      b[b.n] = e
    end
  end
  S.nUsed = nU
end

-- Fill `out` with live enemies whose body touches the circle (x, y, r). Returns the count.
local function query(S, x, y, r, out)
  local n, grid = 0, S.grid
  local x0, x1 = floor((x - r - MAX_R) / CELL), floor((x + r + MAX_R) / CELL)
  local y0, y1 = floor((y - r - MAX_R) / CELL), floor((y + r + MAX_R) / CELL)
  for cx = x0, x1 do
    for cy = y0, y1 do
      local b = grid[key(cx, cy)]
      if b then
        for j = 1, b.n do
          local e = b[j]
          if not e.dead then
            local dx, dy, rr = e.x - x, e.y - y, r + e.r
            if dx * dx + dy * dy <= rr * rr then n = n + 1; out[n] = e end
          end
        end
      end
    end
  end
  return n
end
Sim.Query = query

local function separate(S)
  local used = S.gridUsed
  for i = 1, S.nUsed do
    local b = used[i]
    local n = b.n
    for a = 1, n do
      local ea = b[a]
      for c = a + 1, min(n, a + 6) do
        local eb = b[c]
        local dx, dy = eb.x - ea.x, eb.y - ea.y
        local rr = (ea.r + eb.r) * 0.85
        local d2 = dx * dx + dy * dy
        if d2 < rr * rr then
          local d = sqrt(d2)
          if d < 0.01 then dx, dy, d = random() - 0.5, random() - 0.5, 0.5 end
          local push = (rr - d) * 0.5 / d
          local wa = eb.r / (ea.r + eb.r) -- heavier (bigger) enemies get pushed less
          ea.x, ea.y = ea.x - dx * push * wa * 2, ea.y - dy * push * wa * 2
          eb.x, eb.y = eb.x + dx * push * (1 - wa) * 2, eb.y + dy * push * (1 - wa) * 2
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- entities
---------------------------------------------------------------------------
local function spawnEnemy(S, kind, x, y, force)
  if S.nE >= S.cap and not force then return nil end
  local d = C.ENEMIES[kind]
  local e = tremove(S.enemyPool) or {}
  local hs = (d.boss and 1 or Sim.HpScale(S.t)) * S.eHpMul * (d.elite and S.ascR.eliteHp or 1)
  e.kind, e.def, e.x, e.y, e.r = kind, d, x, y, d.r
  e.hp = d.hp * hs; e.maxhp = e.hp
  e.speed = d.speed * (0.9 + random() * 0.2) * S.eSpeedMul
  e.dmg = d.dmg * (1 + S.t / 600) * S.eDmgMul
  if S.t > C.RUN_SECONDS then -- Endless: harder hitting and faster
    local d = S.t - C.RUN_SECONDS
    e.dmg = e.dmg * (1 + d / C.ENDLESS.dmgRamp)
    e.speed = e.speed * min(C.ENDLESS.speedMax, 1 + d / C.ENDLESS.speedRamp)
  end
  e.enraged = nil
  e.slow, e.flash, e.kx, e.ky, e.orbT, e.lastProj, e.chainId = 0, 0, 0, 0, -1, 0, 0
  e.root, e.dot, e.dotT, e.pdps, e.pT, e.dotAcc = 0, 0, 0, 0, 0, 0
  e.dotSrc, e.pSrc = nil, nil
  e.dead, e.face, e.tex = false, 1, nil
  e.aiS, e.aiT, e.ux, e.uy, e.corr, e.corrGen, e.gone = 0, 0, 0, 0, nil, nil, false -- ai state, corruption, silent removal
  S.nE = S.nE + 1
  S.enemies[S.nE] = e
  if d.boss then S.boss = e end
  return e
end
Sim.SpawnEnemy = spawnEnemy

local function ringPos(S, dist)
  local p = S.p
  local a = random() * TAU
  -- lean spawns toward where the player is heading
  if p.moving and random() < 0.5 then a = math.atan2(p.fy, p.fx) + (random() - 0.5) * 1.6 end
  return p.x + cos(a) * dist, p.y + sin(a) * dist
end

-- zmix: the zone theme's weight multipliers (C.ZONES[z].mix), or nil
local function pickKind(t, zmix)
  local mix = C.WAVES[1].mix
  for i = #C.WAVES, 1, -1 do
    if t >= C.WAVES[i].t then mix = C.WAVES[i].mix; break end
  end
  local total = 0
  for kind, wt in pairs(mix) do total = total + wt * (zmix and zmix[kind] or 1) end
  local r = random() * total
  for kind, wt in pairs(mix) do
    r = r - wt * (zmix and zmix[kind] or 1)
    if r <= 0 then return kind end
  end
  return "ghoul"
end

-- Crystals left far behind (or over the cap) bank their XP into the next crystal that drops, so it is never lost.
local function dropGem(S, x, y, xp)
  if S.nG >= C.MAX_GEMS then
    S.xpBank = S.xpBank + xp
    return
  end
  xp = xp + S.xpBank
  S.xpBank = 0
  local g = tremove(S.gemPool) or {}
  g.x, g.y, g.xp, g.pull, g.dead, g.tex = x + random() * 8 - 4, y + random() * 8 - 4, xp, false, false, nil
  S.nG = S.nG + 1
  S.gems[S.nG] = g
end

-- items: potion, chest (value = number of upgrades), coin (value = gold before the curse multiplier)
local function dropItem(S, kind, x, y, value)
  if kind == "coin" then
    if S.nI >= C.MAX_ITEMS then S.coinBank = S.coinBank + (value or 1); return end
    value = (value or 1) + S.coinBank
    S.coinBank = 0
  end
  local it = { kind = kind, x = x, y = y, dead = false, value = value }
  S.nI = S.nI + 1
  S.items[S.nI] = it
  return it
end
Sim.DropItem = dropItem

-- dot/dotDur: apply (refresh) a burn; S.poison adds poison to every direct hit. isDot = tick, no crit/knock.
local function damage(S, e, amt, kx, ky, dot, dotDur, isDot)
  if e.dead then return end
  local p = S.p
  amt = amt * p.might
  local crit = false
  if not isDot then
    if random() < p.crit then amt = amt * 2; crit = true end
    if dot and dot * dotDur > e.dot * e.dotT then e.dot, e.dotT, e.dotSrc = dot, dotDur, S.curSrc end
    local pw = S.poison
    if pw then
      if pw.dps > e.pdps or e.pT < pw.dur then e.pdps, e.pT, e.pSrc = pw.dps, pw.dur, pw.id end
    end
  end
  local dealt = min(amt, max(0, e.hp)) -- overkill is not credited (a bomb on a pack of 10 hp mobs)
  e.hp = e.hp - amt
  e.flash = 0.12
  S.dmgDone = S.dmgDone + dealt
  local src = S.curSrc or "other"
  S.dmgBy[src] = (S.dmgBy[src] or 0) + dealt
  if kx and not e.def.boss then
    local k = e.def.elite and 0.3 or 1
    e.kx, e.ky = e.kx + kx * k, e.ky + ky * k
  end
  S.hooks.number(S, e.x, e.y + e.r, amt, crit, isDot)
  if e.hp <= 0 then
    e.dead = true
    S.kills = S.kills + 1
    local d = e.def
    dropGem(S, e.x, e.y, d.xp)
    if d.drop then dropItem(S, d.drop, e.x, e.y) end
    if d.chest then dropItem(S, "chest", e.x + 14, e.y, d.chest) end
    if d.coins then
      for k = 1, d.coins do
        local a = k * TAU / d.coins
        dropItem(S, "coin", e.x + cos(a) * 26, e.y + sin(a) * 26, d.coinValue or 1)
      end
    elseif random() < C.COIN_CHANCE * (1 + 0.25 * (S.luck or 0)) then
      dropItem(S, "coin", e.x, e.y, 1)
    end
    if e == S.boss then S.boss = nil; S.bossKilled = true; S.bossKilledAt = S.bossKilledAt or S.t; S.bossKills = (S.bossKills or 0) + 1 end
    S.hooks.kill(S, e)
  elseif e == S.boss and S.ascR.enrage and not e.enraged and e.hp < e.maxhp * 0.5 then
    -- Ascension 10: the Frost Lich enrages at half health
    e.enraged = true
    e.speed, e.dmg = e.speed * 1.5, e.dmg * 1.5
    S.hooks.fx(S, "enrage", e.x, e.y)
  end
end
Sim.Damage = damage

local function addXp(S, xp)
  local p = S.p
  p.xp = p.xp + xp * S.xpMul
  while p.xp >= p.xpNext do
    p.xp = p.xp - p.xpNext
    p.level = p.level + 1
    p.xpNext = C.XpForLevel(p.level)
    S.pendingLevels = S.pendingLevels + 1
  end
end

local function hurtPlayer(S, e)
  local p = S.p
  if p.iframes > 0 then return end
  local dmg = max(1, e.dmg - p.armor)
  S.lastHit = e
  p.hp = p.hp - dmg
  if S.thorns and e.def then -- not on enemy projectiles
    local prev = S.curSrc
    S.curSrc = S.thorns.id
    damage(S, e, S.thorns.reflect)
    S.curSrc = prev
  end
  p.iframes = C.PLAYER.iframes
  S.hooks.hurt(S, dmg)
  if p.hp <= 0 then
    if S.invuln then p.hp = p.maxhp
    elseif (S.revives or 0) > 0 then -- shop Revival: back at half health, 2 s untouchable
      S.revives = S.revives - 1
      S.revived = (S.revived or 0) + 1
      p.hp = p.maxhp * 0.5
      p.iframes = 2
      S.hooks.revive(S)
    else p.hp = 0; S.state = "dead"; S.hooks.over(S, false) end
  end
end

local function spawnProj(S, x, y, vx, vy, w)
  local pr = tremove(S.projPool) or {}
  S.nextId = S.nextId + 1
  pr.id, pr.x, pr.y, pr.vx, pr.vy = S.nextId, x, y, vx, vy
  pr.dmg, pr.pierce, pr.life, pr.dead, pr.tex, pr.w, pr.src = w.dmg, w.pierce, w.life, false, nil, w, w.id
  S.nP = S.nP + 1
  S.projs[S.nP] = pr
end

-- compact an entity list, returning dead ones to their pool
local function compact(S, list, n, pool)
  local j, release = 0, S.hooks.release
  for i = 1, n do
    local o = list[i]
    if o.dead then
      if o.tex then release(S, o) end
      o.tex = nil
      if pool then pool[#pool + 1] = o end
    else
      j = j + 1
      list[j] = o
    end
  end
  for i = j + 1, n do list[i] = nil end
  return j
end

---------------------------------------------------------------------------
-- weapons
---------------------------------------------------------------------------
local W = {}

-- k nearest distinct live enemies within maxD of (x, y) into S.targets; returns the count
local function nearest(S, x, y, k, maxD)
  local E, T = S.enemies, S.targets
  local nT, lim = 0, maxD * maxD
  for _ = 1, k do
    local best, bd = nil, lim
    for i = 1, S.nE do
      local e = E[i]
      if not e.dead then
        local dx, dy = e.x - x, e.y - y
        local d2 = dx * dx + dy * dy
        if d2 < bd then
          local taken = false
          for j = 1, nT do if T[j] == e then taken = true; break end end
          if not taken then best, bd = e, d2 end
        end
      end
    end
    if not best then break end
    nT = nT + 1
    T[nT] = best
  end
  for j = nT + 1, #T do T[j] = nil end
  return nT
end

local function ready(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return false end
  w.timer = (w.cd or w.tick) * S.p.haste
  return true
end

-- aimed projectiles at the nearest enemies (Wrath, Shuriken Toss)
function W.proj(S, w, dt)
  if not ready(S, w, dt) then return end
  local p, T = S.p, S.targets
  local cnt = wcount(S, w)
  local nT = nearest(S, p.x, p.y, cnt, S.viewR * 0.9)
  for k = 1, cnt do
    local t = T[((k - 1) % max(nT, 1)) + 1]
    local a
    if nT > 0 and t then a = math.atan2(t.y - p.y, t.x - p.x) else a = math.atan2(p.fy, p.fx) end
    if k > nT and nT > 0 then a = a + (random() - 0.5) * 0.5 end
    spawnProj(S, p.x, p.y, cos(a) * w.speed, sin(a) * w.speed, w)
  end
end

-- a ring of projectiles (Fan of Knives)
function W.burst(S, w, dt)
  if not ready(S, w, dt) then return end
  local p = S.p
  local a0 = random() * TAU
  local cnt = wcount(S, w)
  for k = 1, cnt do
    local a = a0 + k * TAU / cnt
    spawnProj(S, p.x, p.y, cos(a) * w.speed, sin(a) * w.speed, w)
  end
end

-- a swing in front of you, aimed at the nearest enemy in reach (Crusader / Sinister Strike)
function W.melee(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return end
  local p, q, T = S.p, S.q, S.targets
  local R = w.range * p.area
  if nearest(S, p.x, p.y, 1, R + 40) == 0 then w.timer = 0.1; return end
  w.timer = w.cd * p.haste
  local a = math.atan2(T[1].y - p.y, T[1].x - p.x)
  local fx, fy = cos(a), sin(a)
  local cosArc = 1 - 2 * min(w.arc, 1) -- arc 0.25 = 90 deg cone, 0.5 = half circle, 1 = full circle
  for swing = 1, 1 + (w.double or 0) do
    local n = query(S, p.x, p.y, R, q)
    for i = 1, n do
      local e = q[i]
      local dx, dy = e.x - p.x, e.y - p.y
      local d = sqrt(dx * dx + dy * dy) + 0.01
      if (dx * fx + dy * fy) / d >= cosArc or d < e.r + p.r then
        damage(S, e, w.dmg, dx / d * w.knock, dy / d * w.knock)
      end
    end
  end
  S.hooks.fx(S, "slash", p.x, p.y, a, R, w)
end

function W.orbit(S, w, dt)
  local p, q = S.p, S.q
  w.angle = (w.angle + w.spin * dt) % TAU
  local R = w.radius * p.area
  local hitR = 11 * p.area
  local cnt = wcount(S, w)
  for k = 1, cnt do
    local a = w.angle + (k - 1) * TAU / cnt
    local ox, oy = p.x + cos(a) * R, p.y + sin(a) * R
    w.orbs[2 * k - 1], w.orbs[2 * k] = ox, oy
    local n = query(S, ox, oy, hitR, q)
    for i = 1, n do
      local e = q[i]
      if S.t - e.orbT >= w.hitcd then
        e.orbT = S.t
        local dx, dy = e.x - p.x, e.y - p.y
        local d = sqrt(dx * dx + dy * dy) + 0.01
        local kb = w.knock or 90
        damage(S, e, w.dmg, dx / d * kb, dy / d * kb)
      end
    end
  end
end

function W.aura(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return end
  w.timer = w.tick
  local p, q = S.p, S.q
  local n = query(S, p.x, p.y, w.radius * p.area, q)
  for i = 1, n do damage(S, q[i], w.dmg) end
end

-- burst around you: slow or root, optional heal per enemy hit (Divine Storm, Entangling Roots)
function W.nova(S, w, dt)
  if not ready(S, w, dt) then return end
  local p, q = S.p, S.q
  local R = w.radius * p.area
  local n = query(S, p.x, p.y, R, q)
  for i = 1, n do
    local e = q[i]
    if w.slow > 0 then
      local sl = w.slow * (S.ccMul or 1)
      if w.root and not e.def.boss then e.root = sl else e.slow = sl end
    end
    damage(S, e, w.dmg)
  end
  if w.heal and n > 0 then
    local h = min(n * w.heal, w.healCap)
    p.hp = min(p.maxhp, p.hp + h)
    S.hooks.heal(S, h)
  end
  S.hooks.fx(S, "nova", p.x, p.y, R, w)
end

function W.chain(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return end
  local p, q = S.p, S.q
  local n = query(S, p.x, p.y, w.range * 1.6 * p.area, q)
  if n == 0 then w.timer = 0.2; return end
  w.timer = w.cd * S.p.haste
  S.castId = S.castId + 1
  local id = S.castId
  local cur = q[random(n)]
  local pts = w.pts
  pts[1], pts[2] = p.x, p.y
  local np = 2
  for _ = 0, w.jumps do
    cur.chainId = id
    np = np + 2
    pts[np - 1], pts[np] = cur.x, cur.y
    damage(S, cur, w.dmg)
    local m = query(S, cur.x, cur.y, w.range * p.area, q)
    local best, bd = nil, math.huge
    for i = 1, m do
      local e = q[i]
      if e.chainId ~= id then
        local dx, dy = e.x - cur.x, e.y - cur.y
        local d2 = dx * dx + dy * dy
        if d2 < bd then best, bd = e, d2 end
      end
    end
    if not best then break end
    cur = best
  end
  w.npts = np
  S.hooks.fx(S, "chain", pts, np, w)
end

-- strikes on random on-screen enemies; with delay > 0 they land later as an area impact (Moonfire, Starfall)
function W.strike(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return end
  local p, q = S.p, S.q
  local n = query(S, p.x, p.y, S.viewR * 0.55, q) -- near enough that the crystals can be collected
  if n == 0 then w.timer = 0.2; return end
  w.timer = w.cd * p.haste
  for _ = 1, wcount(S, w) do
    local e = q[random(n)]
    if w.delay > 0 then
      local imp = { x = e.x, y = e.y, t = w.delay, w = w, src = w.id }
      S.nImp = S.nImp + 1
      S.impacts[S.nImp] = imp
      S.hooks.fx(S, "fall", e.x, e.y, w.delay, w)
    else
      damage(S, e, w.dmg, nil, nil, w.dot, w.dotDur)
      S.hooks.fx(S, "beam", e.x, e.y, 0, w)
    end
  end
end

function W.poison() end -- passive: S.poison is read by damage()

local function stepImpacts(S, dt)
  local j, q = 0, S.q2
  for i = 1, S.nImp do
    local imp = S.impacts[i]
    imp.t = imp.t - dt
    if imp.t <= 0 then
      local w = imp.w
      local R = w.radius * S.p.area
      local n = query(S, imp.x, imp.y, R, q)
      S.curSrc = imp.src
      for k = 1, n do damage(S, q[k], w.dmg) end
      S.hooks.fx(S, "impact", imp.x, imp.y, R, w)
    else
      j = j + 1
      S.impacts[j] = imp
    end
  end
  for i = j + 1, S.nImp do S.impacts[i] = nil end
  S.nImp = j
end

---------------------------------------------------------------------------
-- content (0.5): new weapon types, enemy AI, enemy projectiles, zones, traps, map events, pickups
---------------------------------------------------------------------------
local atan2, abs = math.atan2, math.abs

function Sim.InitContent(S, opts)
  S.ebolts, S.nEB, S.ebPool = {}, 0, {}   -- enemy projectiles (transient: not saved)
  S.zones, S.nZ, S.zonePool = {}, 0, {}   -- ground areas (Blizzard, Rain of Fire, Volley; transient)
  S.traps, S.nTr, S.trapPool = {}, 0, {}  -- Explosive Traps (transient)
  S.zone = opts.zone and C.ZONES[opts.zone] and opts.zone or nil
  S.zdef = S.zone and C.ZONES[S.zone] or nil
  S.ev = { ring = 1, goblin = 1, brazier = C.EVENTS.brazierFirst }
  S.gold = S.gold or 0
end

-- event cursors from a save, or (older saves) the ones already past at S.t
function Sim.RestoreEvents(S, ev)
  local E = C.EVENTS
  if type(ev) == "table" and ev[1] then
    S.ev.ring, S.ev.goblin, S.ev.brazier = ev[1], ev[2], ev[3]
    return
  end
  local r, g = 1, 1
  while E.rings[r] and E.rings[r] <= S.t do r = r + 1 end
  while E.goblins[g] and E.goblins[g] <= S.t do g = g + 1 end
  S.ev.ring, S.ev.goblin, S.ev.brazier = r, g, max(S.t + 5, E.brazierFirst)
end

local function lastProj(S) return S.projs[S.nP] end

-- arcane missiles: turn toward the target (or the nearest enemy when it died)
local function steer(S, pr, dt)
  local t = pr.tgt
  if not t or t.dead then
    local q = S.q
    local n = query(S, pr.x, pr.y, 260, q)
    local bd = math.huge
    t = nil
    for k = 1, n do
      local e = q[k]
      local dx, dy = e.x - pr.x, e.y - pr.y
      local d2 = dx * dx + dy * dy
      if d2 < bd and e.lastProj ~= pr.id then t, bd = e, d2 end
    end
    pr.tgt = t
    if not t then return end
  end
  local w = pr.w
  local cur = atan2(pr.vy, pr.vx)
  local da = (atan2(t.y - pr.y, t.x - pr.x) - cur + math.pi) % TAU - math.pi
  local mt = w.turn * dt
  if da > mt then da = mt elseif da < -mt then da = -mt end
  cur = cur + da
  pr.vx, pr.vy = cos(cur) * w.speed, sin(cur) * w.speed
end

-- on-hit effects of projectiles (def.hit)
local HIT = {}
function HIT.chill(S, pr, e)
  local sl = pr.w.slow or 1
  sl = sl * (S.ccMul or 1)
  if e.slow < sl then e.slow = sl end
end
-- heals the player per enemy hit (Death Coil); w.heal per hit, like Drain Life's per-tick heal
function HIT.heal(S, pr, e)
  local p = S.p
  if p.hp < p.maxhp then p.hp = min(p.maxhp, p.hp + (pr.w.heal or 0)) end
end
function HIT.explode(S, pr, e)
  local w, q = pr.w, S.q
  local R = w.radius * S.p.area
  S.curSrc = pr.src or w.id
  local n = query(S, e.x, e.y, R, q)
  for k = 1, n do
    local o = q[k]
    if o ~= e then damage(S, o, pr.dmg * w.splash) end
  end
  S.hooks.fx(S, "impact", e.x, e.y, R, w)
end

-- homing missiles launched in a spread in front of you (Arcane Missiles)
function W.missile(S, w, dt)
  if not ready(S, w, dt) then return end
  local p, T = S.p, S.targets
  local cnt = wcount(S, w)
  local nT = nearest(S, p.x, p.y, cnt, S.viewR * 0.8)
  if nT == 0 then w.timer = 0.2; return end
  local a0 = atan2(T[1].y - p.y, T[1].x - p.x)
  for k = 1, cnt do
    local a = a0 + (k - (cnt + 1) / 2) * 0.35 + (random() - 0.5) * 0.3
    spawnProj(S, p.x, p.y, cos(a) * w.speed, sin(a) * w.speed, w)
    local pr = lastProj(S)
    pr.src, pr.tgt = w.id, T[((k - 1) % nT) + 1]
  end
end

-- a fan of projectiles toward the nearest enemy (Multi-Shot)
function W.fan(S, w, dt)
  if not ready(S, w, dt) then return end
  local p, T = S.p, S.targets
  local a
  if nearest(S, p.x, p.y, 1, S.viewR * 0.9) > 0 then a = atan2(T[1].y - p.y, T[1].x - p.x) else a = atan2(p.fy, p.fx) end
  local n = wcount(S, w)
  for k = 1, n do
    local b = a + (n > 1 and ((k - 1) / (n - 1) - 0.5) * w.spread or 0)
    spawnProj(S, p.x, p.y, cos(b) * w.speed, sin(b) * w.speed, w)
    lastProj(S).src = w.id
  end
end

-- the densest spot among a few random enemies near you (Blizzard, Rain of Fire, Volley)
local function clusterPoint(S, R)
  local p, q = S.p, S.q
  local n = query(S, p.x, p.y, S.viewR * 0.55, q)
  if n == 0 then return nil end
  local bx, by, bn = nil, nil, -1
  for _ = 1, min(n, 6) do
    local e = q[random(n)]
    local m = query(S, e.x, e.y, R, S.q2)
    if m > bn then bx, by, bn = e.x, e.y, m end
  end
  return bx, by
end

local function addZone(S, w, x, y, R)
  local z = tremove(S.zonePool) or {}
  z.x, z.y, z.r, z.t, z.dur, z.delay, z.acc = x, y, R, w.dur, w.dur, w.delay or 0, 0
  z.w, z.src, z.dead, z.tex = w, w.id, false, nil
  S.nZ = S.nZ + 1
  S.zones[S.nZ] = z
  if z.delay > 0 then S.hooks.fx(S, "zonefall", x, y, z.delay, w) end
end

-- ground areas that tick damage (and slow) for a while
function W.zone(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return end
  local R = w.radius * S.p.area
  local placed = false
  for _ = 1, wcount(S, w) do
    local x, y = clusterPoint(S, R)
    if not x then break end
    placed = true
    addZone(S, w, x + (random() - 0.5) * R * 0.5, y + (random() - 0.5) * R * 0.5, R)
  end
  w.timer = placed and w.cd * S.p.haste or 0.3
end

-- a curse (damage over time) that jumps to nearby enemies when its victim dies (Corruption)
function W.dot(S, w, dt)
  w.timer = w.timer - dt
  if w.timer > 0 then return end
  local p, q = S.p, S.q
  local n = query(S, p.x, p.y, S.viewR * 0.55, q)
  if n == 0 then w.timer = 0.2; return end
  w.timer = w.cd * p.haste
  S.curSrc = w.id
  for _ = 1, wcount(S, w) do
    local e = q[random(n)]
    for _ = 1, 3 do -- prefer enemies not yet cursed
      if e.corr and not e.dead then e = q[random(n)] else break end
    end
    e.corr, e.corrGen = w, 0
    damage(S, e, w.dmg, nil, nil, w.dot, w.dotDur)
    S.hooks.fx(S, "curse", e.x, e.y, 0, w)
  end
end

-- channel on the nearest enemies, healing you per tick (Drain Life)
function W.beam(S, w, dt)
  if not ready(S, w, dt) then return end
  local p, T = S.p, S.targets
  local n = nearest(S, p.x, p.y, wcount(S, w), w.range * p.area)
  if n == 0 then return end
  S.curSrc = w.id
  for k = 1, n do
    local e = T[k]
    S.hooks.fx(S, "drain", p.x, p.y, e.x, e.y, w)
    damage(S, e, w.dmg)
  end
  if p.hp < p.maxhp then p.hp = min(p.maxhp, p.hp + w.heal * n) end
end

-- mines dropped near you; armed after 0.5 s, they explode when an enemy steps close (Explosive Trap)
function W.trap(S, w, dt)
  if not ready(S, w, dt) then return end
  local p, mine = S.p, 0
  for i = 1, S.nTr do if S.traps[i].src == w.id then mine = mine + 1 end end
  if mine >= wcount(S, w) then w.timer = 0.3; return end
  local tr = tremove(S.trapPool) or {}
  local a, d = random() * TAU, 25 + random() * 55
  tr.x, tr.y, tr.arm, tr.life, tr.w, tr.src, tr.dead, tr.tex = p.x + cos(a) * d, p.y + sin(a) * d, 0.5, w.life, w, w.id, false, nil
  S.nTr = S.nTr + 1
  S.traps[S.nTr] = tr
end

-- minions with their own position: ranged ones hover near you and shoot, melee ones chase and bite (Imp, Wolf)
function W.pet(S, w, dt)
  local p = S.p
  local pets = w.pets
  if not pets then pets = {}; w.pets = pets end
  local cnt = wcount(S, w)
  for k = #pets + 1, cnt do
    local a = random() * TAU
    pets[k] = { x = p.x + cos(a) * 40, y = p.y + sin(a) * 40, cd = 0.4, face = 1, moving = false, re = 0 }
  end
  for k = cnt + 1, #pets do pets[k] = nil end
  S.curSrc = w.id
  local melee = w.def.mode == "melee"
  for k = 1, cnt do
    local pet = pets[k]
    pet.cd = pet.cd - dt
    local ddx, ddy = p.x - pet.x, p.y - pet.y
    if ddx * ddx + ddy * ddy > S.viewR * S.viewR then pet.x, pet.y = p.x - p.fx * 30, p.y - p.fy * 30 end -- left behind
    local tx, ty
    if melee then
      local t = pet.tgt
      pet.re = pet.re - dt
      if not t or t.dead or pet.re <= 0 then
        pet.re = 0.4
        local q = S.q
        local n = query(S, p.x, p.y, w.range * p.area, q)
        local bd = math.huge
        t = nil
        for i = 1, n do
          local e = q[i]
          local dx, dy = e.x - pet.x, e.y - pet.y
          local d2 = dx * dx + dy * dy + (e.def.stay and 1e6 or 0) -- braziers and goblins last
          if d2 < bd then t, bd = e, d2 end
        end
        pet.tgt = t
      end
      if t then
        local dx, dy = t.x - pet.x, t.y - pet.y
        local d = sqrt(dx * dx + dy * dy) + 0.01
        if d < t.r + 14 then
          if pet.cd <= 0 then
            pet.cd = w.cd * p.haste
            damage(S, t, w.dmg, dx / d * w.knock, dy / d * w.knock)
            S.hooks.fx(S, "bite", t.x, t.y, 0, w)
          end
          pet.face = dx < 0 and -1 or 1
        else
          tx, ty = t.x, t.y
        end
      else
        tx, ty = p.x + (k % 2 == 0 and 1 or -1) * (36 + k * 6), p.y - 26
      end
    else
      local a = S.t * 0.8 + k * TAU / cnt
      tx, ty = p.x + cos(a) * 55, p.y + sin(a) * 40 + 12
      if pet.cd <= 0 then
        local T = S.targets
        if nearest(S, pet.x, pet.y, 1, w.range) > 0 then
          pet.cd = w.cd * p.haste
          local e = T[1]
          local a2 = atan2(e.y - pet.y, e.x - pet.x)
          spawnProj(S, pet.x, pet.y, cos(a2) * w.speed, sin(a2) * w.speed, w)
          lastProj(S).src = w.id
          pet.face = e.x < pet.x and -1 or 1
        else
          pet.cd = 0.2
        end
      end
    end
    pet.moving = false
    if tx then
      local dx, dy = tx - pet.x, ty - pet.y
      local d = sqrt(dx * dx + dy * dy)
      if d > 3 then
        local st = min(d, w.move * dt)
        pet.x, pet.y = pet.x + dx / d * st, pet.y + dy / d * st
        pet.moving = true
        if abs(dx) > 2 then pet.face = dx < 0 and -1 or 1 end
      end
    end
  end
end

---------------------------------------------------------------------------
-- enemy AI (C.ENEMIES[kind].ai); no ai = plain chase in Sim.Step
---------------------------------------------------------------------------
local AI = {}
local function chaseStep(e, dx, dy, d, dt, mul)
  local sp = e.root > 0 and 0 or e.speed * (e.slow > 0 and 0.45 or 1) * dt * (mul or 1)
  e.x = e.x + dx / d * sp + e.kx * dt
  e.y = e.y + dy / d * sp + e.ky * dt
  e.face = dx < 0 and -1 or 1
end

local function spawnEnemyBolt(S, e, ux, uy)
  local def = e.def
  local b = tremove(S.ebPool) or {}
  b.kind, b.x, b.y = "enemybolt", e.x + ux * e.r, e.y + uy * e.r
  b.vx, b.vy = ux * def.boltSpeed, uy * def.boltSpeed
  b.dmg, b.life, b.dead, b.tex = def.boltDmg * e.dmg / def.dmg * S.ascR.boltDmg, 4, false, nil
  S.nEB = S.nEB + 1
  S.ebolts[S.nEB] = b
end

-- oozes chase; they split on death (see stepDeaths)
function AI.split(S, e, dx, dy, d, dt)
  chaseStep(e, dx, dy, d, dt)
  if d < e.r + S.p.r then hurtPlayer(S, e) end
end

-- skeleton mages keep their distance and fire slow bolts the player can dodge
function AI.ranged(S, e, dx, dy, d, dt)
  local def = e.def
  if e.aiS == 0 then e.aiS, e.aiT = 1, 0.5 + random() * def.fireCd end
  local keep = def.keep
  if d > keep + 30 then chaseStep(e, dx, dy, d, dt)
  elseif d < keep - 50 then chaseStep(e, dx, dy, d, dt, -0.8)
  else
    e.x, e.y = e.x + e.kx * dt, e.y + e.ky * dt
    e.face = dx < 0 and -1 or 1
  end
  e.aiT = e.aiT - dt
  if e.aiT <= 0 and d < keep + 200 and e.root <= 0 then
    e.aiT = def.fireCd * (0.85 + random() * 0.3)
    spawnEnemyBolt(S, e, dx / d, dy / d)
  end
  if d < e.r + S.p.r then hurtPlayer(S, e) end
end

-- worgen stalk, stop and aim (telegraph line, orange tint), then dash in a straight line
function AI.charge(S, e, dx, dy, d, dt)
  local def = e.def
  if e.aiS == 0 then e.aiS, e.aiT = 1, random() * def.dashCd end
  if e.aiS == 1 then
    chaseStep(e, dx, dy, d, dt)
    e.aiT = e.aiT - dt
    if e.aiT <= 0 and d < def.dashRange and e.root <= 0 then
      e.aiS, e.aiT, e.ux, e.uy = 2, def.tele, dx / d, dy / d
      local L = def.dashSpeed * def.dashTime
      S.hooks.fx(S, "telegraph", e.x, e.y, e.x + e.ux * L, e.y + e.uy * L, def.tele)
    end
  elseif e.aiS == 2 then
    e.x, e.y = e.x + e.kx * dt, e.y + e.ky * dt
    e.aiT = e.aiT - dt
    if e.aiT <= 0 then e.aiS, e.aiT = 3, def.dashTime end
  else
    if e.root <= 0 then
      local sp = def.dashSpeed * (e.slow > 0 and 0.45 or 1) * dt
      e.x, e.y = e.x + e.ux * sp, e.y + e.uy * sp
    end
    e.face = e.ux < 0 and -1 or 1
    e.aiT = e.aiT - dt
    if e.aiT <= 0 then e.aiS, e.aiT = 1, def.dashCd end
  end
  if d < e.r + S.p.r then hurtPlayer(S, e) end
end

-- the gold goblin runs away (zig-zagging) and vanishes after its life
function AI.flee(S, e, dx, dy, d, dt)
  if e.aiS == 0 then e.aiS, e.aiT = 1, e.def.life end
  e.aiT = e.aiT - dt
  if e.aiT <= 0 or d > S.viewR * 1.6 then
    e.dead, e.gone = true, true
    S.hooks.fx(S, "goblinGone", e.x, e.y)
    return
  end
  local a = atan2(-dy, -dx) + sin(S.t * 1.7) * 0.7
  if e.root <= 0 then
    local sp = e.speed * (e.slow > 0 and 0.45 or 1) * dt
    e.x, e.y = e.x + cos(a) * sp + e.kx * dt, e.y + sin(a) * sp + e.ky * dt
  end
  e.face = cos(a) < 0 and -1 or 1
end

-- braziers stand still and burn out when far behind
function AI.static(S, e, dx, dy, d, dt)
  if d > S.viewR * 1.5 then e.dead, e.gone = true, true end
end

---------------------------------------------------------------------------
-- pickups (items other than the potion)
---------------------------------------------------------------------------
-- coins, chests and potions are handled in Sim.Step's item loop
local PICKUP = {}
function PICKUP.chicken(S)
  local p = S.p
  local h = min(p.maxhp - p.hp, p.maxhp * C.PICKUPS.chicken.heal * S.ascR.healMul)
  p.hp = p.hp + h
  S.hooks.heal(S, h)
end
function PICKUP.magnet(S)
  for i = 1, S.nG do S.gems[i].pull = true end
  for i = 1, S.nI do local it = S.items[i]; if it.kind == "coin" then it.pull = true end end
  S.hooks.fx(S, "magnet", S.p.x, S.p.y)
end
function PICKUP.bomb(S)
  local p, q = S.p, S.q
  S.curSrc = "bomb"
  local n = query(S, p.x, p.y, S.viewR, q)
  local dmg = C.PICKUPS.bomb.dmg * Sim.HpScale(S.t)
  for k = 1, n do damage(S, q[k], dmg) end
  S.hooks.fx(S, "bomb", p.x, p.y, S.viewR)
end

local function pickWeighted(t)
  local total = 0
  for _, wt in pairs(t) do total = total + wt end
  local r = random() * total
  for k, wt in pairs(t) do
    r = r - wt
    if r <= 0 then return k end
  end
  return next(t)
end

---------------------------------------------------------------------------
-- content step (called once per Sim.Step before compaction)
---------------------------------------------------------------------------
local function stepEvents(S)
  local ev, E, p, t = S.ev, C.EVENTS, S.p, S.t
  if E.rings[ev.ring] and t >= E.rings[ev.ring] then
    ev.ring = ev.ring + 1
    local count = floor(E.ringBase + t / 15)
    local a0, R = random() * TAU, S.viewR + 10
    for i = 1, count do
      local a = a0 + i * TAU / count
      if S.nE < S.cap + 80 then spawnEnemy(S, "skeleton", p.x + cos(a) * R, p.y + sin(a) * R, true) end
    end
    S.hooks.fx(S, "ring")
  end
  if E.goblins[ev.goblin] and t >= E.goblins[ev.goblin] then
    ev.goblin = ev.goblin + 1
    local x, y = ringPos(S, S.viewR * 0.45)
    spawnEnemy(S, "goblin", x, y, true)
    S.hooks.fx(S, "goblin", x, y)
  end
  if t >= ev.brazier then
    ev.brazier = t + E.brazierEvery
    local n = 0
    for i = 1, S.nE do local e = S.enemies[i]; if e.kind == "brazier" and not e.dead then n = n + 1 end end
    if n < E.brazierMax then
      local x, y = ringPos(S, 180 + random() * 200)
      spawnEnemy(S, "brazier", x, y, true)
    end
  end
end

local function stepEnemyBolts(S, dt)
  local p = S.p
  local hitR = p.r + 7
  for i = 1, S.nEB do
    local b = S.ebolts[i]
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    b.life = b.life - dt
    if b.life <= 0 then
      b.dead = true
    else
      local dx, dy = b.x - p.x, b.y - p.y
      if dx * dx + dy * dy < hitR * hitR then
        b.dead = true
        hurtPlayer(S, b) -- iframes and armor apply
      end
    end
  end
  S.nEB = compact(S, S.ebolts, S.nEB, S.ebPool)
end

local function stepZones(S, dt)
  local q = S.q2
  for i = 1, S.nZ do
    local z = S.zones[i]
    if z.delay > 0 then
      z.delay = z.delay - dt
    else
      z.t = z.t - dt
      z.acc = z.acc - dt
      if z.acc <= 0 then
        local w = z.w
        z.acc = w.tick
        S.curSrc = z.src
        local n = query(S, z.x, z.y, z.r, q)
        for k = 1, n do
          local e = q[k]
          if w.slow and e.slow < w.slow * (S.ccMul or 1) then e.slow = w.slow * (S.ccMul or 1) end
          damage(S, e, w.dmg)
        end
        if w.def.rain then S.hooks.fx(S, "rain", z.x, z.y, z.r, w) end
      end
      if z.t <= 0 then z.dead = true end
    end
  end
  S.nZ = compact(S, S.zones, S.nZ, S.zonePool)
end

local function stepTraps(S, dt)
  local q = S.q2
  for i = 1, S.nTr do
    local tr = S.traps[i]
    tr.life = tr.life - dt
    if tr.life <= 0 then
      tr.dead = true
    elseif tr.arm > 0 then
      tr.arm = tr.arm - dt
    elseif query(S, tr.x, tr.y, tr.w.trigger, q) > 0 then
      local w = tr.w
      local R = w.radius * S.p.area
      S.curSrc = tr.src
      local n = query(S, tr.x, tr.y, R, q)
      for k = 1, n do
        local e = q[k]
        local dx, dy = e.x - tr.x, e.y - tr.y
        local d = sqrt(dx * dx + dy * dy) + 0.01
        damage(S, e, w.dmg, dx / d * 120, dy / d * 120)
      end
      S.hooks.fx(S, "impact", tr.x, tr.y, R, w)
      tr.dead = true
    end
  end
  S.nTr = compact(S, S.traps, S.nTr, S.trapPool)
end

-- killed this step (not silently removed): oozes split, braziers drop a pickup, curses spread
local function stepDeaths(S)
  local E, q = S.enemies, S.q
  for i = 1, S.nE do
    local e = E[i]
    if e.dead and not e.gone then
      local d = e.def
      if d.split then
        for _ = 1, d.splitN do
          local a = random() * TAU
          local o = spawnEnemy(S, d.split, e.x + cos(a) * 8, e.y + sin(a) * 8, true)
          if o then o.kx, o.ky = cos(a) * 140, sin(a) * 140 end
        end
      end
      if e.kind == "goblin" then S.hooks.fx(S, "goblinKilled", e.x, e.y) end -- its coins drop in damage()
      if d.ai == "static" then dropItem(S, pickWeighted(C.EVENTS.pickups), e.x, e.y) end
      local w = e.corr
      local gen = e.corrGen or 0
      e.corr, e.corrGen = nil, nil
      -- a curse jumps at most w.jumps times from where it was cast, weaker each jump (no chain across the swarm)
      if w and gen < (w.jumps or 1) then
        S.curSrc = w.id
        local n = query(S, e.x, e.y, w.range, q)
        local c = 0
        for k = 1, n do
          local o = q[k]
          if c >= w.spread then break end
          if not o.corr then
            c = c + 1
            o.corr, o.corrGen = w, gen + 1
            S.hooks.fx(S, "spread", e.x, e.y, o.x, o.y, w)
            local f = 0.75 ^ (gen + 1)
            damage(S, o, w.dmg * f, nil, nil, w.dot * f, w.dotDur)
          end
        end
      end
    end
  end
end

function Sim.StepContent(S, dt)
  stepEvents(S)
  if S.nEB > 0 then stepEnemyBolts(S, dt) end
  if S.nZ > 0 then stepZones(S, dt) end
  if S.nTr > 0 then stepTraps(S, dt) end
  stepDeaths(S)
end

---------------------------------------------------------------------------
-- Endless
---------------------------------------------------------------------------
-- gold per coin past 10:00: +10% per minute
function Sim.EndlessGold(t)
  if t <= C.RUN_SECONDS then return 1 end
  return 1 + C.ENDLESS.goldPerMin * (t - C.RUN_SECONDS) / 60
end

-- the victory panel's two ways on
function Sim.CashOut(S)
  if S.state ~= "victory" then return false end
  S.state = "won"
  S.hooks.over(S, true)
  return true
end

function Sim.KeepGoing(S)
  if S.state ~= "victory" then return false end
  S.endless = true
  S.state = "play"
  return true
end

-- seconds survived past 10:00 (0 when the run did not go on)
function Sim.EndlessTime(S)
  return S.endless and max(0, S.t - C.RUN_SECONDS) or 0
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
function Sim.Step(S, dt, ix, iy)
  if S.state ~= "play" then return end
  if dt > 0.05 then dt = 0.05 end
  S.t = S.t + dt
  local p = S.p

  -- spawning
  S.curSrc = nil
  local cap = S.cap
  if S.t > C.RUN_SECONDS and not S.stress then -- Endless: the horde keeps growing and shrugs off roots and slows
    local d = S.t - C.RUN_SECONDS
    cap = cap + min(C.ENDLESS.capMax, d * C.ENDLESS.capPerSec)
    S.ccMul = 1 / (1 + d / C.ENDLESS.ccRamp)
  end
  local target = min(cap, C.TargetPop(S.t) * S.spawnMul)
  S.spawnAcc = min(S.spawnAcc + dt * (S.stress and 400 or 25 * S.spawnMul), S.stress and 50 or 6)
  while S.spawnAcc >= 1 and S.nE < (S.stress and S.cap or target) do
    S.spawnAcc = S.spawnAcc - 1
    local x, y = ringPos(S, S.viewR + 30)
    spawnEnemy(S, pickKind(S.t, S.zdef and S.zdef.mix), x, y)
  end
  if S.t >= S.nextElite then
    S.nextElite = S.nextElite + (S.eliteEvery or C.ELITE_EVERY)
    local x, y = ringPos(S, S.viewR + 40)
    spawnEnemy(S, "elite", x, y, true)
  end
  if S.t >= S.nextSwarm then
    S.nextSwarm = S.nextSwarm + C.SWARM_EVERY
    local count = floor(20 + S.t / 15)
    local a0 = random() * TAU
    for i = 1, count do
      local a = a0 + i * TAU / count
      if S.nE < S.cap + 80 then
        spawnEnemy(S, "bat", p.x + cos(a) * (S.viewR + 20), p.y + sin(a) * (S.viewR + 20), true)
      end
    end
    S.hooks.fx(S, "swarm")
  end
  -- the Frost Lich: at 8:00 (7:00 on Ascension 3+), then in Endless every 5 minutes, stronger each time
  if S.t >= S.nextBoss and not S.boss then
    local n = S.bossN
    S.bossSpawned = true
    S.bossN = n + 1
    S.nextBoss = n == 0 and C.RUN_SECONDS + C.ENDLESS.bossEvery or S.nextBoss + C.ENDLESS.bossEvery
    local x, y = ringPos(S, S.viewR + 60)
    local e = spawnEnemy(S, "boss", x, y, true)
    if n > 0 then
      e.hp = e.hp * (1 + C.ENDLESS.bossHp * n); e.maxhp = e.hp
      e.dmg = e.dmg * (1 + C.ENDLESS.bossDmg * n)
    end
    S.hooks.fx(S, "boss", n)
  end

  -- player
  ix, iy = ix or 0, iy or 0
  local len = sqrt(ix * ix + iy * iy)
  if len > 0 then
    ix, iy = ix / len, iy / len
    p.fx, p.fy = ix, iy
    p.x, p.y = p.x + ix * p.speed * dt, p.y + iy * p.speed * dt
    p.moving = true
  else
    p.moving = false
  end
  p.hp = min(p.maxhp, p.hp + p.regen * dt)
  if p.iframes > 0 then p.iframes = p.iframes - dt end

  -- enemies
  local E, far = S.enemies, S.viewR * 1.7
  for i = 1, S.nE do
    local e = E[i]
    if not e.dead then
      local dx, dy = p.x - e.x, p.y - e.y
      local d = sqrt(dx * dx + dy * dy)
      if d > far and not e.def.boss and not e.def.elite and not e.def.stay then
        e.x, e.y = ringPos(S, S.viewR + 30) -- left behind: come back from ahead
      elseif d > 0.001 then
        local ai = e.def.ai
        if ai then AI[ai](S, e, dx, dy, d, dt) else -- ranged, charge, split, flee, static
        local sp = e.root > 0 and 0 or e.speed * (e.slow > 0 and 0.45 or 1) * dt
        e.x = e.x + dx / d * sp + e.kx * dt
        e.y = e.y + dy / d * sp + e.ky * dt
        e.face = dx < 0 and -1 or 1
        if d < e.r + p.r then hurtPlayer(S, e) end
        end
      end
      if e.kx ~= 0 then
        local f = max(0, 1 - 10 * dt)
        e.kx, e.ky = e.kx * f, e.ky * f
        if e.kx * e.kx + e.ky * e.ky < 1 then e.kx, e.ky = 0, 0 end
      end
      if e.slow > 0 then e.slow = e.slow - dt end
      if e.root > 0 then e.root = e.root - dt end
      if e.dotT > 0 or e.pT > 0 then -- burns and poison tick twice a second
        local bd, pd = (e.dotT > 0 and e.dot or 0), (e.pT > 0 and e.pdps or 0)
        e.dotT, e.pT = e.dotT - dt, e.pT - dt
        e.dotAcc = e.dotAcc + dt
        if e.dotAcc >= 0.5 then
          local acc = e.dotAcc
          e.dotAcc = 0
          if bd > 0 and pd > 0 and e.dotSrc ~= e.pSrc then -- two sources: two ticks, each credited to its skill
            S.curSrc = e.dotSrc
            damage(S, e, bd * acc, nil, nil, nil, nil, true)
            S.curSrc = e.pSrc
            damage(S, e, pd * acc, nil, nil, nil, nil, true)
          else
            S.curSrc = bd > 0 and e.dotSrc or e.pSrc
            damage(S, e, (bd + pd) * acc, nil, nil, nil, nil, true)
          end
          S.curSrc = nil
        end
      end
      if e.flash > 0 then e.flash = e.flash - dt end
    end
  end
  if S.state ~= "play" then return end

  gridBuild(S)
  separate(S)

  -- weapons
  for i = 1, #S.wlist do
    local w = S.wlist[i]
    S.curSrc = w.id
    W[w.def.type](S, w, dt)
  end
  S.curSrc = nil
  if S.nImp > 0 then stepImpacts(S, dt) end
  S.curSrc = nil

  -- projectiles
  local P, q = S.projs, S.q2
  for i = 1, S.nP do
    local pr = P[i]
    if pr.w.def.homing then steer(S, pr, dt) end
    pr.x, pr.y = pr.x + pr.vx * dt, pr.y + pr.vy * dt
    pr.life = pr.life - dt
    if pr.life <= 0 then
      pr.dead = true
    else
      local n = query(S, pr.x, pr.y, 6, q)
      for k = 1, n do
        local e = q[k]
        if e.lastProj ~= pr.id then
          e.lastProj = pr.id
          S.curSrc = pr.src
          damage(S, e, pr.dmg, pr.vx * 0.25, pr.vy * 0.25)
          local hit = pr.w.def.hit
          if hit then HIT[hit](S, pr, e) end
          pr.pierce = pr.pierce - 1
          if pr.pierce <= 0 then pr.dead = true; break end
        end
      end
    end
  end

  -- gems
  local G = S.gems
  local mag2 = p.magnet * p.magnet
  local lost2 = (S.viewR * 1.5) ^ 2
  local pull = 420 * dt
  for i = 1, S.nG do
    local g = G[i]
    local dx, dy = p.x - g.x, p.y - g.y
    local d2 = dx * dx + dy * dy
    if d2 > lost2 then
      g.dead = true
      S.xpBank = S.xpBank + g.xp
    elseif g.pull or d2 < mag2 then
      g.pull = true
      local d = sqrt(d2)
      if d < p.r + 6 then
        g.dead = true
        addXp(S, g.xp)
        S.hooks.pickup(S, "gem")
      else
        local step = min(d, pull)
        g.x, g.y = g.x + dx / d * step, g.y + dy / d * step
      end
    end
  end

  S.curSrc = nil
  -- items (coins are pulled in like crystals)
  for i = 1, S.nI do
    local it = S.items[i]
    local dx, dy = p.x - it.x, p.y - it.y
    local d2 = dx * dx + dy * dy
    if d2 < (p.r + 16) ^ 2 then
      it.dead = true
      if it.kind == "potion" then p.hp = min(p.maxhp, p.hp + p.maxhp * 0.3 * S.ascR.healMul)
      elseif it.kind == "coin" then S.gold = S.gold + (it.value or 1) * S.goldMul * Sim.EndlessGold(S.t)
      elseif it.kind == "chest" then
        -- Ascension 9: one upgrade fewer (min 1); Luck: 15% per rank for one more
        local n = max(1, (it.value or 1) - S.ascR.chestLess)
        if (S.luck or 0) > 0 and random() < 0.15 * S.luck then n = n + 1 end
        S.chestN = S.chestN + n
      else
        local pk = PICKUP[it.kind] -- magnet, chicken, bomb
        if pk then pk(S, it) end
      end
      S.hooks.pickup(S, it.kind, it)
    elseif it.kind == "coin" and d2 > lost2 then -- left far behind: banked into the next coin, never lost
      it.dead = true
      S.coinBank = S.coinBank + (it.value or 1)
    elseif it.kind == "coin" and (it.pull or d2 < mag2) then
      it.pull = true
      local d = sqrt(d2)
      local step = min(d, pull)
      it.x, it.y = it.x + dx / d * step, it.y + dy / d * step
    end
  end

  Sim.StepContent(S, dt) -- events, enemy projectiles, zones, traps, deaths (splits, drops, spreading curses)
  S.nE = compact(S, E, S.nE, S.enemyPool)
  S.nP = compact(S, P, S.nP, S.projPool)
  S.nG = compact(S, G, S.nG, S.gemPool)
  S.nI = compact(S, S.items, S.nI, nil)
  if S.state ~= "play" then return end -- killed by an enemy projectile

  if S.t >= C.RUN_SECONDS and not S.stress and not S.won10 then
    -- 10:00: the win is recorded now (hooks.victory); then cash out (results) or keep going (Endless)
    S.won10 = true
    S.state = "victory"
    S.hooks.victory(S)
    return
  end
  if S.chestN > 0 then
    S.state = "chest"
    S.hooks.chest(S)
  elseif S.pendingLevels > 0 then
    S.state = "levelup"
    Sim.RollChoices(S)
    S.hooks.levelup(S)
  end
end

---------------------------------------------------------------------------
-- save / load (plain tables only: they go into SavedVariables)
---------------------------------------------------------------------------
-- v2: gold, dmgBy, gotAt, meta, curses, unlocks, rerolls/skips, chests, evolved weapons, item values.
-- v1 saves still load (the new fields start empty).
-- v3 (0.6): Limit Break stacks, Ascension level, Endless (won10, endless, banked gold), boss schedule, elite
-- interval, revives / banishes left and the banished ids. v2 saves load with those at their defaults.
Sim.SAVE_VERSION = 3

function Sim.Serialize(S)
  local p = S.p
  local d = {
    v = Sim.SAVE_VERSION, class = S.class, t = S.t, kills = S.kills, dmgDone = S.dmgDone,
    state = (S.state == "levelup" or S.state == "chest" or S.state == "victory") and S.state or "play",
    spawnAcc = S.spawnAcc, nextElite = S.nextElite, nextSwarm = S.nextSwarm,
    bossSpawned = S.bossSpawned or nil, bossKilled = S.bossKilled or nil,
    pendingLevels = S.pendingLevels, xpBank = S.xpBank, picks = S.picks or 0,
    p = { x = p.x, y = p.y, hp = p.hp, xp = p.xp, level = p.level, fx = p.fx, fy = p.fy },
    weapons = {}, passives = {}, enemies = {}, gems = {}, items = {},
    gold = S.gold, coinBank = S.coinBank, chestN = S.chestN, chests = S.chests,
    rerolls = S.rerolls, skips = S.skips,
    meta = copyFlat(S.meta), curses = copyFlat(S.curses), unlocks = copyFlat(S.unlocks),
    dmgBy = copyFlat(S.dmgBy), gotAt = copyFlat(S.gotAt),
    -- v3
    limit = copyFlat(S.limit), lbPicks = S.lbPicks, lbAmtAt = S.lbAmtAt, asc = S.asc,
    won10 = S.won10 or nil, endless = S.endless or nil, banked = S.banked,
    nextBoss = S.nextBoss, bossN = S.bossN, bossKills = S.bossKills, nextEliteEvery = S.eliteEvery,
    revives = S.revives, revived = S.revived, banishes = S.banishes, banished = copyFlat(S.banished),
  }
  for i, w in ipairs(S.wlist) do d.weapons[i] = { w.id, w.level, w.timer or 0, w.angle or 0 } end
  for i, id in ipairs(S.plist) do d.passives[i] = { id, S.passives[id] } end
  for i = 1, S.nE do
    local e = S.enemies[i]
    if not e.dead then
      d.enemies[#d.enemies + 1] = { e.kind, e.x, e.y, e.hp, e.maxhp, e.speed, e.dmg, e.slow, e.root, e.dot, e.dotT, e.pdps, e.pT, e.face,
        e.enraged and 1 or 0 }
    end
  end
  for i = 1, S.nG do local g = S.gems[i]; if not g.dead then d.gems[#d.gems + 1] = { g.x, g.y, g.xp } end end
  for i = 1, S.nI do local it = S.items[i]; if not it.dead then d.items[#d.items + 1] = { it.kind, it.x, it.y, it.value } end end
  if S.choices then
    d.choices = {}
    for i, c in ipairs(S.choices) do d.choices[i] = { c.kind, c.id, c.level } end
  end
  d.zone, d.ev = S.zone, { S.ev.ring, S.ev.goblin, S.ev.brazier }
  d.runId = S.runId
  return d
end

-- Rebuild a run from Sim.Serialize data. opts as for Sim.New (hooks, viewR). Returns S or nil, why.
function Sim.Deserialize(d, opts)
  if type(d) ~= "table" or type(d.v) ~= "number" or d.v < 1 or d.v > Sim.SAVE_VERSION or not C.CLASSES[d.class] then
    return nil, "unknown save"
  end
  opts = opts or {}
  opts.class = d.class
  -- the run keeps the shop ranks, curses and unlocks it started with
  opts.meta, opts.curses, opts.unlocks = d.meta, d.curses, d.unlocks
  opts.zone = d.zone
  opts.asc = d.asc
  local S = Sim.New(opts)
  -- weapons in their order, levelled up the same way as in play
  S.weapons, S.wlist, S.poison, S.thorns, S.gotAt = {}, {}, nil, nil, {}
  for _, wd in ipairs(d.weapons or {}) do
    local def = C.WEAPONS[wd[1]]
    if def then
      local w = Sim.AddWeapon(S, wd[1])
      for _ = 2, wd[2] do Sim.LevelWeapon(S, wd[1]) end
      w.timer, w.angle = wd[3], wd[4]
      local r = def.evolved and recipeOf(wd[1])
      if r then S.evolved[r.weapon] = wd[1]; S.nEvolved = S.nEvolved + 1 end
    end
  end
  for k, v in pairs(d.gotAt or {}) do S.gotAt[k] = v end
  for k, v in pairs(d.dmgBy or {}) do S.dmgBy[k] = v end
  S.gold, S.coinBank, S.chestN, S.chests = d.gold or 0, d.coinBank or 0, d.chestN or 0, d.chests
  if d.rerolls then S.rerolls = d.rerolls end
  if d.skips then S.skips = d.skips end
  for _, pd in ipairs(d.passives or {}) do
    if C.PASSIVES[pd[1]] then for _ = 1, pd[2] do Sim.AddPassive(S, pd[1]) end end
  end
  -- Limit Break stacks after the passives (as in play); a fixed order keeps the cooldown floor stable
  for _, l in ipairs(C.LIMIT) do
    local n = type(d.limit) == "table" and tonumber(d.limit[l.id]) or 0
    for _ = 1, n do Sim.AddLimit(S, l.id) end
  end
  S.lbPicks, S.lbAmtAt = d.lbPicks or 0, d.lbAmtAt or 0
  S.won10, S.endless, S.banked = d.won10, d.endless, d.banked
  if d.revives then S.revives = d.revives end
  S.revived = d.revived
  if d.banishes then S.banishes = d.banishes end
  if type(d.banished) == "table" then for k, v in pairs(d.banished) do S.banished[k] = v end end
  if d.nextEliteEvery then S.eliteEvery = d.nextEliteEvery end
  local p, dp = S.p, d.p
  p.x, p.y, p.xp, p.level, p.fx, p.fy = dp.x, dp.y, dp.xp, dp.level, dp.fx, dp.fy
  p.hp = math.min(dp.hp, p.maxhp)
  p.xpNext = C.XpForLevel(p.level)
  S.t, S.kills, S.dmgDone = d.t, d.kills, d.dmgDone
  S.spawnAcc, S.nextElite, S.nextSwarm = d.spawnAcc, d.nextElite, d.nextSwarm
  S.bossSpawned, S.bossKilled = d.bossSpawned, d.bossKilled
  if d.nextBoss then
    S.nextBoss, S.bossN, S.bossKills = d.nextBoss, d.bossN or 0, d.bossKills
  elseif d.bossSpawned then -- a v1/v2 save after 8:00: the boss came once
    S.nextBoss, S.bossN = C.RUN_SECONDS + C.ENDLESS.bossEvery, 1
  end
  S.pendingLevels, S.xpBank, S.picks = d.pendingLevels, d.xpBank or 0, d.picks
  for _, ed in ipairs(d.enemies or {}) do
    if C.ENEMIES[ed[1]] then
      local e = spawnEnemy(S, ed[1], ed[2], ed[3], true)
      e.hp, e.maxhp, e.speed, e.dmg = ed[4], ed[5], ed[6], ed[7]
      e.slow, e.root, e.dot, e.dotT, e.pdps, e.pT, e.face = ed[8], ed[9], ed[10], ed[11], ed[12], ed[13], ed[14]
      e.enraged = ed[15] == 1 or nil
    end
  end
  for _, gd in ipairs(d.gems or {}) do
    local g = tremove(S.gemPool) or {}
    g.x, g.y, g.xp, g.pull, g.dead, g.tex = gd[1], gd[2], gd[3], false, false, nil
    S.nG = S.nG + 1
    S.gems[S.nG] = g
  end
  for _, id in ipairs(d.items or {}) do
    local it = { kind = id[1], x = id[2], y = id[3], dead = false, value = id[4] }
    S.nI = S.nI + 1
    S.items[S.nI] = it
  end
  Sim.RestoreEvents(S, d.ev)
  if d.state == "victory" and S.won10 then
    S.state = "victory"
  elseif d.state == "chest" and S.chestN > 0 then
    S.state = "chest"
  elseif d.state == "levelup" and d.choices then
    S.state = "levelup"
    S.choices = {}
    for i, c in ipairs(d.choices) do S.choices[i] = { kind = c[1], id = c[2], level = c[3] } end
  end
  S.runId = d.runId
  return S
end
