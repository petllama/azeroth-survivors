-- Save/load round trip: play a while, serialize, rebuild, compare, and check the save is plain data.
-- Usage: lua5.1 tests/test_save.lua
local ROOT = (arg[0]:match("^(.*)/tests/") or ".") .. "/AzerothSurvivors/"
local ns = {}
for _, f in ipairs({ "Content.lua", "Sim.lua" }) do assert(loadfile(ROOT .. f))("AzerothSurvivors", ns) end
local Sim, C = ns.Sim, ns.Content

local function plain(v, seen, path)
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return end
  assert(t == "table", "non-plain value at " .. path .. ": " .. t)
  assert(not seen[v], "shared/cyclic table at " .. path)
  seen[v] = true
  for k, x in pairs(v) do
    assert(type(k) == "number" or type(k) == "string", "bad key at " .. path)
    plain(x, seen, path .. "." .. tostring(k))
  end
end

local checks = 0
for _, cls in ipairs(C.CLASS_ORDER) do
  math.randomseed(3)
  local S = Sim.New({ class = cls, viewR = 600, invuln = true })
  local dt = 1 / 60
  while S.t < 150 and S.state ~= "dead" do
    if S.state == "levelup" then
      if S.t > 100 and cls ~= "druid" then break end -- save some runs mid level-up
      Sim.Choose(S, 1)
    else
      local a = S.t * 0.3
      Sim.Step(S, dt, math.cos(a), math.sin(a))
    end
  end
  local d = Sim.Serialize(S)
  plain(d, {}, "save")
  local S2 = assert(Sim.Deserialize(d, { viewR = 600 }))
  local function same(a, b, what) assert(math.abs(a - b) < 1e-6, cls .. " " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b)); checks = checks + 1 end
  same(S2.t, S.t, "t"); same(S2.kills, S.kills, "kills"); same(S2.p.level, S.p.level, "level")
  same(S2.p.hp, S.p.hp, "hp"); same(S2.p.maxhp, S.p.maxhp, "maxhp"); same(S2.p.xp, S.p.xp, "xp")
  same(S2.p.might, S.p.might, "might"); same(S2.p.speed, S.p.speed, "speed"); same(S2.p.crit, S.p.crit, "crit")
  same(S2.nG, S.nG, "gems")
  local live = 0
  for i = 1, S.nE do if not S.enemies[i].dead then live = live + 1 end end
  same(S2.nE, live, "enemies")
  assert(#S2.wlist == #S.wlist, cls .. " weapon count")
  for i, w in ipairs(S.wlist) do
    local w2 = S2.wlist[i]
    assert(w2.id == w.id and w2.level == w.level, cls .. " weapon " .. w.id)
    for k, v in pairs(w) do
      if type(v) == "number" and k ~= "npts" then same(w2[k], v, "weapon " .. w.id .. "." .. k) end
    end
  end
  assert(S2.state == (S.state == "levelup" and "levelup" or "play"), "state")
  if S.state == "levelup" then assert(#S2.choices == #S.choices, "choices") end
  assert((S2.boss ~= nil) == (S.boss ~= nil), "boss")
  -- the rebuilt run keeps playing
  if S2.state == "levelup" then Sim.Choose(S2, 1) end
  for _ = 1, 600 do Sim.Step(S2, dt, 1, 0) end
  print(string.format("%s ok: t=%.1f level=%d weapons=%d passives=%d enemies=%d gems=%d state=%s -> continued to t=%.1f",
    cls, S.t, S.p.level, #S.wlist, #S.plist, live, S.nG, S.state, S2.t))
end
print("checks " .. checks)
