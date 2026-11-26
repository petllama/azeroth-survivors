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

local KEEP = (class == "druid") and 130 or 75 -- melee classes fight up close
local S = Sim.New({ class = class, viewR = 560, stress = mode == "stress", cap = mode == "stress" and cap or nil })
local dt = 1 / 60
local clock = os.clock
local worst, total, steps = 0, 0, 0
local maxE = 0
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
  -- walk toward the nearest gem (players vacuum XP)
  local gx, gy, gd = 0, 0, math.huge
  for i = 1, S.nG do
    local g = S.gems[i]
    local dx, dy = g.x - p.x, g.y - p.y
    local d2 = dx * dx + dy * dy
    if d2 < gd then gx, gy, gd = dx, dy, d2 end
  end
  if gd < math.huge then local d = math.sqrt(gd) + 1; gx, gy = gx / d * 1.0, gy / d * 1.0 end
  local t = S.t * 0.25
  return ax * 2500 + gx + math.cos(t) * 0.2, ay * 900 + gy + math.sin(t) * 0.2
end

local limit = mode == "stress" and 60 or C.RUN_SECONDS + 5
while S.t < limit and S.state ~= "dead" and S.state ~= "won" do
  if S.state == "levelup" then
    Sim.Choose(S, math.random(#S.choices))
  else
    local ix, iy = bot()
    local t0 = clock()
    Sim.Step(S, dt, ix, iy)
    local el = (clock() - t0) * 1000
    total, steps = total + el, steps + 1
    if S.t > 2 and el > worst then worst = el end
    if S.nE > maxE then maxE = S.nE end
  end
end

local weapons = {}
for _, w in ipairs(S.wlist) do weapons[#weapons + 1] = w.id .. w.level end
local passives = {}
for _, id in ipairs(S.plist) do passives[#passives + 1] = id .. S.passives[id] end
print(string.format(class .. " %s seed=%d result=%s t=%.0fs level=%d kills=%d hp=%.0f/%.0f maxEnemies=%d gems=%d",
  mode, seed, S.state, S.t, S.p.level, S.kills, S.p.hp, S.p.maxhp, maxE, S.nG))
local killer = S.lastHit and S.lastHit.kind or "-"
print("  last hit by: " .. killer .. "   boss " .. (S.bossKilled and "killed" or (S.bossSpawned and "alive" or "not spawned")))
print("  weapons: " .. table.concat(weapons, " ") .. "   passives: " .. table.concat(passives, " "))
print(string.format("  step ms: avg %.3f worst %.3f  (%s, lua mem %.0f KB)", total / steps, worst, _VERSION, collectgarbage("count")))
