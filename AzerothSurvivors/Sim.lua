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
local NOHOOKS = { release = noop, number = noop, fx = noop, levelup = noop, hurt = noop, kill = noop, over = noop, pickup = noop, heal = noop }

function Sim.HpScale(t) return 1 + t / 300 + (t / 550) ^ 2 end

---------------------------------------------------------------------------
-- setup
---------------------------------------------------------------------------
function Sim.New(opts)
  opts = opts or {}
  local P = C.PLAYER
  local cls = C.CLASSES[opts.class or "paladin"] and (opts.class or "paladin") or "paladin"
  local cd = C.CLASSES[cls]
  local S = {
    class = cls, cdef = cd, impacts = {}, nImp = 0, xpBank = 0,
    t = 0, kills = 0, state = "play", dmgDone = 0,
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
    spawnAcc = 0, nextElite = C.ELITE_EVERY, nextSwarm = C.SWARM_EVERY,
    pendingLevels = 0, choices = nil,
    grid = {}, gridUsed = {}, nUsed = 0, nBuckets = 0, q = {}, q2 = {}, targets = {},
    nextId = 0, castId = 0,
  }
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
  if def.type == "poison" then S.poison = w end
  if def.reflect or w.reflect then S.thorns = w end
  return w
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

-- Three weighted picks without replacement; upgrades of owned things weigh double.
function Sim.RollChoices(S)
  local pool, wts = {}, {}
  local function add(c, wt) pool[#pool + 1] = c; wts[#wts + 1] = wt end
  for _, id in ipairs(S.cdef.kit) do
    local w = S.weapons[id]
    if w then
      if w.level < C.MAX_WEAPON_LEVEL then add({ kind = "weapon", id = id, level = w.level + 1 }, 2) end
    elseif #S.wlist < C.WEAPON_SLOTS then
      add({ kind = "weapon", id = id, level = 1 }, 1.2)
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
  for _ = 1, 3 do
    local total = 0
    for i = 1, #wts do total = total + wts[i] end
    if total <= 0 then break end
    local r = random() * total
    for i = 1, #wts do
      r = r - wts[i]
      if r <= 0 and wts[i] > 0 then picks[#picks + 1] = pool[i]; wts[i] = 0; break end
    end
  end
  if #picks == 0 then picks[1] = { kind = "heal" } end
  S.choices = picks
  return picks
end

function Sim.ChoiceText(c)
  if c.kind == "heal" then return "Healing Potion", "Restore 40 health.", "Interface\\Icons\\INV_Potion_54" end
  if c.kind == "weapon" then
    local d = C.WEAPONS[c.id]
    local text = c.level == 1 and ("New! " .. d.desc) or (d.levels[c.level].text)
    return d.name .. (c.level > 1 and (" " .. c.level) or ""), text, d.icon
  end
  local d = C.PASSIVES[c.id]
  return d.name .. (c.level > 1 and (" " .. c.level) or ""), (c.level == 1 and "New! " or "") .. d.text, d.icon
end

function Sim.Choose(S, i)
  local c = S.choices and S.choices[i]
  if not c or S.state ~= "levelup" then return false end
  if c.kind == "heal" then S.p.hp = min(S.p.maxhp, S.p.hp + 40)
  elseif c.kind == "weapon" then
    if S.weapons[c.id] then Sim.LevelWeapon(S, c.id) else Sim.AddWeapon(S, c.id) end
  else Sim.AddPassive(S, c.id) end
  S.choices = nil
  S.picks = (S.picks or 0) + 1
  S.pendingLevels = S.pendingLevels - 1
  if S.pendingLevels > 0 then
    Sim.RollChoices(S)
    S.hooks.levelup(S)
  else
    S.state = "play"
  end
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
  local hs = d.boss and 1 or Sim.HpScale(S.t)
  e.kind, e.def, e.x, e.y, e.r = kind, d, x, y, d.r
  e.hp = d.hp * hs; e.maxhp = e.hp
  e.speed = d.speed * (0.9 + random() * 0.2)
  e.dmg = d.dmg * (1 + S.t / 600)
  e.slow, e.flash, e.kx, e.ky, e.orbT, e.lastProj, e.chainId = 0, 0, 0, 0, -1, 0, 0
  e.root, e.dot, e.dotT, e.pdps, e.pT, e.dotAcc = 0, 0, 0, 0, 0, 0
  e.dead, e.face, e.tex = false, 1, nil
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

local function pickKind(t)
  local mix = C.WAVES[1].mix
  for i = #C.WAVES, 1, -1 do
    if t >= C.WAVES[i].t then mix = C.WAVES[i].mix; break end
  end
  local total = 0
  for _, wt in pairs(mix) do total = total + wt end
  local r = random() * total
  for kind, wt in pairs(mix) do
    r = r - wt
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

local function dropItem(S, kind, x, y)
  local it = { kind = kind, x = x, y = y, dead = false }
  S.nI = S.nI + 1
  S.items[S.nI] = it
end

-- dot/dotDur: apply (refresh) a burn; S.poison adds poison to every direct hit. isDot = tick, no crit/knock.
local function damage(S, e, amt, kx, ky, dot, dotDur, isDot)
  if e.dead then return end
  local p = S.p
  amt = amt * p.might
  local crit = false
  if not isDot then
    if random() < p.crit then amt = amt * 2; crit = true end
    if dot and dot * dotDur > e.dot * e.dotT then e.dot, e.dotT = dot, dotDur end
    local pw = S.poison
    if pw then
      if pw.dps > e.pdps or e.pT < pw.dur then e.pdps, e.pT = pw.dps, pw.dur end
    end
  end
  e.hp = e.hp - amt
  e.flash = 0.12
  S.dmgDone = S.dmgDone + amt
  if kx and not e.def.boss then
    local k = e.def.elite and 0.3 or 1
    e.kx, e.ky = e.kx + kx * k, e.ky + ky * k
  end
  S.hooks.number(S, e.x, e.y + e.r, amt, crit, isDot)
  if e.hp <= 0 then
    e.dead = true
    S.kills = S.kills + 1
    dropGem(S, e.x, e.y, e.def.xp)
    if e.def.drop then dropItem(S, e.def.drop, e.x, e.y) end
    if e == S.boss then S.boss = nil; S.bossKilled = true end
    S.hooks.kill(S, e)
  end
end
Sim.Damage = damage

local function addXp(S, xp)
  local p = S.p
  p.xp = p.xp + xp
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
  if S.thorns then damage(S, e, S.thorns.reflect) end
  p.iframes = C.PLAYER.iframes
  S.hooks.hurt(S, dmg)
  if p.hp <= 0 then
    if S.invuln then p.hp = p.maxhp
    else p.hp = 0; S.state = "dead"; S.hooks.over(S, false) end
  end
end

local function spawnProj(S, x, y, vx, vy, w)
  local pr = tremove(S.projPool) or {}
  S.nextId = S.nextId + 1
  pr.id, pr.x, pr.y, pr.vx, pr.vy = S.nextId, x, y, vx, vy
  pr.dmg, pr.pierce, pr.life, pr.dead, pr.tex, pr.w = w.dmg, w.pierce, w.life, false, nil, w
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
  local nT = nearest(S, p.x, p.y, w.count, S.viewR * 0.9)
  for k = 1, w.count do
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
  for k = 1, w.count do
    local a = a0 + k * TAU / w.count
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
  for k = 1, w.count do
    local a = w.angle + (k - 1) * TAU / w.count
    local ox, oy = p.x + cos(a) * R, p.y + sin(a) * R
    w.orbs[2 * k - 1], w.orbs[2 * k] = ox, oy
    local n = query(S, ox, oy, hitR, q)
    for i = 1, n do
      local e = q[i]
      if S.t - e.orbT >= w.hitcd then
        e.orbT = S.t
        local dx, dy = e.x - p.x, e.y - p.y
        local d = sqrt(dx * dx + dy * dy) + 0.01
        damage(S, e, w.dmg, dx / d * 90, dy / d * 90)
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
      if w.root and not e.def.boss then e.root = w.slow else e.slow = w.slow end
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
  for _ = 1, w.count do
    local e = q[random(n)]
    if w.delay > 0 then
      local imp = { x = e.x, y = e.y, t = w.delay, w = w }
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
-- step
---------------------------------------------------------------------------
function Sim.Step(S, dt, ix, iy)
  if S.state ~= "play" then return end
  if dt > 0.05 then dt = 0.05 end
  S.t = S.t + dt
  local p = S.p

  -- spawning
  local target = min(S.cap, C.TargetPop(S.t))
  S.spawnAcc = min(S.spawnAcc + dt * (S.stress and 400 or 25), S.stress and 50 or 6)
  while S.spawnAcc >= 1 and S.nE < (S.stress and S.cap or target) do
    S.spawnAcc = S.spawnAcc - 1
    local x, y = ringPos(S, S.viewR + 30)
    spawnEnemy(S, pickKind(S.t), x, y)
  end
  if S.t >= S.nextElite then
    S.nextElite = S.nextElite + C.ELITE_EVERY
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
  if not S.bossSpawned and S.t >= C.BOSS_AT then
    S.bossSpawned = true
    local x, y = ringPos(S, S.viewR + 60)
    spawnEnemy(S, "boss", x, y, true)
    S.hooks.fx(S, "boss")
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
      if d > far and not e.def.boss and not e.def.elite then
        e.x, e.y = ringPos(S, S.viewR + 30) -- left behind: come back from ahead
      elseif d > 0.001 then
        local sp = e.root > 0 and 0 or e.speed * (e.slow > 0 and 0.45 or 1) * dt
        e.x = e.x + dx / d * sp + e.kx * dt
        e.y = e.y + dy / d * sp + e.ky * dt
        e.face = dx < 0 and -1 or 1
        if d < e.r + p.r then hurtPlayer(S, e) end
      end
      if e.kx ~= 0 then
        local f = max(0, 1 - 10 * dt)
        e.kx, e.ky = e.kx * f, e.ky * f
        if e.kx * e.kx + e.ky * e.ky < 1 then e.kx, e.ky = 0, 0 end
      end
      if e.slow > 0 then e.slow = e.slow - dt end
      if e.root > 0 then e.root = e.root - dt end
      if e.dotT > 0 or e.pT > 0 then -- burns and poison tick twice a second
        local dps = (e.dotT > 0 and e.dot or 0) + (e.pT > 0 and e.pdps or 0)
        e.dotT, e.pT = e.dotT - dt, e.pT - dt
        e.dotAcc = e.dotAcc + dt
        if e.dotAcc >= 0.5 then
          damage(S, e, dps * e.dotAcc, nil, nil, nil, nil, true)
          e.dotAcc = 0
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
    W[w.def.type](S, w, dt)
  end
  if S.nImp > 0 then stepImpacts(S, dt)
  end

  -- projectiles
  local P, q = S.projs, S.q2
  for i = 1, S.nP do
    local pr = P[i]
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
          damage(S, e, pr.dmg, pr.vx * 0.25, pr.vy * 0.25)
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

  -- items
  for i = 1, S.nI do
    local it = S.items[i]
    local dx, dy = p.x - it.x, p.y - it.y
    if dx * dx + dy * dy < (p.r + 16) ^ 2 then
      it.dead = true
      if it.kind == "potion" then p.hp = min(p.maxhp, p.hp + p.maxhp * 0.3) end
      S.hooks.pickup(S, it.kind)
    end
  end

  S.nE = compact(S, E, S.nE, S.enemyPool)
  S.nP = compact(S, P, S.nP, S.projPool)
  S.nG = compact(S, G, S.nG, S.gemPool)
  S.nI = compact(S, S.items, S.nI, nil)

  if S.t >= C.RUN_SECONDS and not S.stress then
    S.state = "won"
    S.hooks.over(S, true)
    return
  end
  if S.pendingLevels > 0 then
    S.state = "levelup"
    Sim.RollChoices(S)
    S.hooks.levelup(S)
  end
end
