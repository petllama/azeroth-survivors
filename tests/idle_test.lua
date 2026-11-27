-- Stand still and take a given skill whenever offered: how long do you live, and how much of the damage is that skill?
-- Also: START_LV=n owns PREFER at level n from the start; IDLE_AT=s kites (vacuum) until s, then stands still.
-- Usage: CLASS=paladin PREFER=hammers lua5.1 tests/idle_test.lua [seeds]
local ROOT = (arg[0]:match("^(.*)/tests/") or ".") .. "/AzerothSurvivors/"
local ns = {}
for _, f in ipairs({ "Content.lua", "ContentDK.lua", "Sim.lua" }) do assert(loadfile(ROOT .. f))("AzerothSurvivors", ns) end
local Sim = ns.Sim
local class, prefer = os.getenv("CLASS") or "paladin", os.getenv("PREFER") or "hammers"
local seeds = tonumber(arg[1]) or 4
local idleAt = tonumber(os.getenv("IDLE_AT") or "0") -- kite in a circle until then (vacuum pickup), then stand still
if idleAt > 0 then ns.Content.PLAYER.magnet = 3000 end
for seed = 1, seeds do
  math.randomseed(seed)
  local S = Sim.New({ class = class, viewR = 560 })
  local startLv = tonumber(os.getenv("START_LV") or "0") -- own PREFER at this level from the start
  if startLv > 0 then
    if not S.weapons[prefer] then Sim.AddWeapon(S, prefer) end
    while S.weapons[prefer].level < startLv do Sim.LevelWeapon(S, prefer) end
  end
  while S.t < 600 and S.state ~= "dead" and S.state ~= "won" do
    if S.state == "levelup" then
      local pick = 1
      for i, c in ipairs(S.choices) do if c.id == prefer then pick = i end end
      Sim.Choose(S, pick)
    elseif S.state == "chest" then while Sim.OpenChest(S) do end; Sim.CloseChest(S)
    elseif S.state ~= "play" then break
    else
      local a = S.t * 0.35
      if S.t < idleAt then Sim.Step(S, 1 / 30, math.cos(a), math.sin(a)) else Sim.Step(S, 1 / 30, 0, 0) end
    end
  end
  local tot, mine = 0, 0
  for k, v in pairs(S.dmgBy or {}) do tot = tot + v; if k:find(prefer, 1, true) then mine = mine + v end end
  local lvl = 0
  for _, w in ipairs(S.wlist) do if w.id:find(prefer, 1, true) then lvl = w.level end end
  print(string.format("seed %d: %s t=%.0f (idle %.0fs) level=%d %s lv%d share=%.0f%% kills=%d", seed, S.state, S.t, math.max(0, S.t - idleAt), S.p.level, prefer, lvl, tot > 0 and mine / tot * 100 or 0, S.kills))
end
