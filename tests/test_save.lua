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
  local meta = { might = 2, armor = 1, maxhp = 3, recovery = 1, swift = 1, greed = 2, growth = 1, reroll = 2, skip = 1 }
  local S = Sim.New({ class = cls, viewR = 600, invuln = true, meta = meta, curses = { frail = true, brutal = true }, unlocks = { slot = 1 } })
  local dt = 1 / 60
  while S.t < 150 and S.state ~= "dead" do
    if S.state == "levelup" then
      if S.t > 100 and cls ~= "druid" then break end -- save some runs mid level-up
      Sim.Choose(S, 1)
    elseif S.state == "chest" then
      Sim.OpenChest(S); Sim.CloseChest(S)
    else
      local a = S.t * 0.3
      Sim.Step(S, dt, math.cos(a), math.sin(a))
    end
  end
  -- an evolved weapon, gold and a pending chest must survive the round trip
  local kitw = C.CLASSES[cls].start
  local r
  for _, x in ipairs(C.EVOLUTIONS) do if x.weapon == kitw then r = x end end
  if S.state ~= "levelup" then
    while S.weapons[kitw].level < C.MAX_WEAPON_LEVEL do Sim.LevelWeapon(S, kitw) end
    if not S.passives[r.passive] then Sim.AddPassive(S, r.passive) end
    assert(Sim.Evolve(S, r), cls .. " evolve")
    S.rerolls = 1
    Sim.DropItem(S, "chest", S.p.x + 300, S.p.y, 3)
    Sim.DropItem(S, "coin", S.p.x + 200, S.p.y, 7)
  end
  local d = Sim.Serialize(S)
  assert(d.v == 2, "save version 2")
  plain(d, {}, "save")
  local S2 = assert(Sim.Deserialize(d, { viewR = 600 }))
  local function same(a, b, what) assert(math.abs(a - b) < 1e-6, cls .. " " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b)); checks = checks + 1 end
  same(S2.t, S.t, "t"); same(S2.kills, S.kills, "kills"); same(S2.p.level, S.p.level, "level")
  same(S2.p.hp, S.p.hp, "hp"); same(S2.p.maxhp, S.p.maxhp, "maxhp"); same(S2.p.xp, S.p.xp, "xp")
  same(S2.p.might, S.p.might, "might"); same(S2.p.speed, S.p.speed, "speed"); same(S2.p.crit, S.p.crit, "crit")
  same(S2.nG, S.nG, "gems")
  same(S2.gold, S.gold, "gold"); same(S2.rerolls, S.rerolls, "rerolls"); same(S2.skips, S.skips, "skips")
  same(S2.p.armor, S.p.armor, "armor"); same(S2.p.regen, S.p.regen, "regen"); same(S2.p.magnet, S.p.magnet, "magnet")
  same(S2.xpMul, S.xpMul, "xpMul"); same(S2.goldMul, S.goldMul, "goldMul"); same(S2.eHpMul, S.eHpMul, "eHpMul")
  same(S2.wslots, S.wslots, "wslots"); same(S2.nEvolved, S.nEvolved, "nEvolved"); same(S2.nI, S.nI, "items")
  for k, v in pairs(S.dmgBy) do same(S2.dmgBy[k], v, "dmgBy." .. k) end
  for k, v in pairs(S.evolved) do assert(S2.evolved[k] == v, cls .. " evolved " .. k) end
  for i = 1, S.nI do assert(S2.items[i].kind == S.items[i].kind and S2.items[i].value == S.items[i].value, cls .. " item " .. i) end
  assert(next(S.dmgBy), cls .. " no damage recorded")
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
-- a version 1 save (0.4.x) still loads with empty new fields
do
  local S = Sim.New({ class = "paladin", viewR = 600 })
  for _ = 1, 120 do Sim.Step(S, 1 / 60, 1, 0) end
  local d = Sim.Serialize(S)
  d.v, d.gold, d.dmgBy, d.meta, d.curses, d.unlocks, d.gotAt, d.rerolls, d.skips, d.chestN = 1, nil, nil, nil, nil, nil, nil, nil, nil, nil
  local S2 = assert(Sim.Deserialize(d, { viewR = 600 }), "v1 save should load")
  assert(S2.gold == 0 and S2.rerolls == 0 and next(S2.meta) == nil, "v1 defaults")
  for _ = 1, 60 do Sim.Step(S2, 1 / 60, 1, 0) end
  assert(not Sim.Deserialize({ v = 3, class = "paladin" }), "future versions are refused")
  print("v1 save ok")
  -- saved on the chest screen: reopens on the chest screen with the same upgrades pending
  Sim.DropItem(S2, "chest", S2.p.x, S2.p.y, 3)
  Sim.Step(S2, 1 / 60, 0, 0)
  assert(S2.state == "chest" and S2.chestN == 3, "chest state")
  local S3 = assert(Sim.Deserialize(Sim.Serialize(S2), { viewR = 600 }))
  assert(S3.state == "chest" and S3.chestN == 3, "chest state should survive a save")
  assert(#Sim.OpenChest(S3) == 3 and Sim.CloseChest(S3), "chest opens after load")
  print("chest save ok")
end
print("checks " .. checks)
