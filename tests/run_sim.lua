-- Headless simulation run (no WoW). Usage:
--   lua5.1 tests/run_sim.lua [seed] [mode]      mode = play (kiting bot) | stress (cap N, invulnerable)
-- Prints survival, level, kills, and per-step timing so balance and speed can be checked offline.
local ROOT = (arg[0]:match("^(.*)/tests/") or ".") .. "/AzerothSurvivors/"
local ns = {}
for _, f in ipairs({ "Content.lua", "Sim.lua" }) do assert(loadfile(ROOT .. f))("AzerothSurvivors", ns) end
local Sim, C = ns.Sim, ns.Content

local seed = tonumber(arg[1]) or 1
local mode = arg[2] or "play"
local cap = tonumber(arg[3]) or 500
local class = os.getenv("CLASS") or "paladin"
if os.getenv("VACUUM") then C.PLAYER.magnet = 3000 end
math.randomseed(seed)

local KEEP = (class == "paladin" or class == "rogue") and 75 or 130 -- melee classes fight up close
-- META=max buys every shop rank; META=might:3,armor:1 picks ranks. CURSES=horde,brutal turns curses on.
local meta, curses = {}, {}
local mv = os.getenv("META")
if mv == "max" then for _, s in ipairs(C.SHOP) do meta[s.id] = s.max end
elseif mv then for k, v in mv:gmatch("(%w+):(%d+)") do meta[k] = tonumber(v) end end
for c in (os.getenv("CURSES") or ""):gmatch("%w+") do curses[c] = true end
local S = Sim.New({ class = class, zone = os.getenv("ZONE"), viewR = 560, stress = mode == "stress", cap = mode == "stress" and cap or nil, meta = meta, curses = curses })
local dt = 1 / 60
local clock = os.clock
local worst, total, steps = 0, 0, 0
local maxE = 0
local marks, nextMark = {}, 60
local function bot()
  -- kite: move away from the weighted centre of nearby enemies, with a slow circular drift
  local p = S.p
  local ax, ay = 0, 0
  for i = 1, S.nE do
    local e = S.enemies[i]
    local dx, dy = p.x - e.x, p.y - e.y
    local d2 = dx * dx + dy * dy + 1
    if d2 < KEEP * KEEP then ax, ay = ax + dx / d2, ay + dy / d2 end
  end
  -- sidestep enemy bolts heading this way (move off their line)
  for i = 1, (S.nEB or 0) do
    local b = S.ebolts[i]
    local dx, dy = p.x - b.x, p.y - b.y
    local d2 = dx * dx + dy * dy + 1
    if d2 < 100 * 100 and dx * b.vx + dy * b.vy > 0 then
      local nx, ny = -b.vy, b.vx
      local side = (dx * nx + dy * ny) >= 0 and 1 or -1
      local l = math.sqrt(nx * nx + ny * ny) + 0.01
      ax, ay = ax + side * nx / l / math.sqrt(d2) * 0.6, ay + side * ny / l / math.sqrt(d2) * 0.6
    end
  end
  -- walk toward the nearest gem (players vacuum XP)
  local gx, gy, gd = 0, 0, math.huge
  for i = 1, S.nG do
    local g = S.gems[i]
    local dx, dy = g.x - p.x, g.y - p.y
    local d2 = dx * dx + dy * dy
    if d2 < gd then gx, gy, gd = dx, dy, d2 end
  end
  -- chests and coins too (a player walks to a chest)
  for i = 1, S.nI do
    local it = S.items[i]
    if it.kind ~= "potion" then
      local dx, dy = it.x - p.x, it.y - p.y
      local r2 = dx * dx + dy * dy
      local d2 = r2 * (it.kind == "chest" and 0.1 or 1)
      if r2 < 400 * 400 and d2 < gd then gx, gy, gd = dx, dy, d2 end -- only what is on screen
    end
  end
  if gd < math.huge then local d = math.sqrt(gx * gx + gy * gy) + 1; gx, gy = gx / d * 1.0, gy / d * 1.0 end
  local t = S.t * 0.25
  return ax * 2500 + gx + math.cos(t) * 0.2, ay * 900 + gy + math.sin(t) * 0.2
end

local limit = mode == "stress" and 60 or C.RUN_SECONDS + 5
while S.t < limit and S.state ~= "dead" and S.state ~= "won" do
  if S.state == "chest" then
    Sim.OpenChest(S)
    Sim.CloseChest(S)
  elseif S.state == "levelup" then
    Sim.Choose(S, math.random(#S.choices))
  else
    local ix, iy = bot()
    local t0 = clock()
    Sim.Step(S, dt, ix, iy)
    local el = (clock() - t0) * 1000
    total, steps = total + el, steps + 1
    if S.t > 2 and el > worst then worst = el end
    if S.nE > maxE then maxE = S.nE end
    if S.t >= nextMark then marks[#marks + 1] = string.format("%d:%d", nextMark / 60, S.p.level); nextMark = nextMark + 60 end
  end
end

local weapons = {}
for _, w in ipairs(S.wlist) do weapons[#weapons + 1] = w.id .. w.level end
local passives = {}
for _, id in ipairs(S.plist) do passives[#passives + 1] = id .. S.passives[id] end
print(string.format(class .. " %s seed=%d result=%s t=%.0fs level=%d kills=%d hp=%.0f/%.0f maxEnemies=%d gems=%d",
  mode, seed, S.state, S.t, S.p.level, S.kills, S.p.hp, S.p.maxhp, maxE, S.nG))
local killer = S.lastHit and S.lastHit.kind or "-"
print("  level by minute: " .. table.concat(marks, " "))
print("  last hit by: " .. killer .. "   boss " .. (S.bossKilled and ("killed at " .. math.floor(S.bossKilledAt or 0)) or (S.bossSpawned and "alive" or "not spawned")))
local dmg = {}
for k, v in pairs(S.dmgBy) do dmg[#dmg + 1] = { k, v } end
table.sort(dmg, function(a, b) return a[2] > b[2] end)
local dl = {}
for i, e in ipairs(dmg) do dl[i] = string.format("%s %.0f%%", e[1], e[2] * 100 / math.max(1, S.dmgDone)) end
print(string.format("  gold %d  chests %d  evolved %d  damage: %s", S.gold, S.chests or 0, S.nEvolved, table.concat(dl, " ")))
print(string.format("  zone %s", tostring(S.zone)))
print("  weapons: " .. table.concat(weapons, " ") .. "   passives: " .. table.concat(passives, " "))
print(string.format("  step ms: avg %.3f worst %.3f  (%s, lua mem %.0f KB)", total / steps, worst, _VERSION, collectgarbage("count")))
