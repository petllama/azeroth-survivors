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
  local meta = { might = 7, armor = 1, maxhp = 3, recovery = 1, swift = 1, greed = 2, growth = 1, reroll = 2, skip = 1,
    cooldown = 2, area = 3, magnet = 1, luck = 2, banish = 2, revival = 1, amount = 1 }
  local zones = { mage = "tirisfal", warlock = "barrens", hunter = "snow" }
  local asc = ({ paladin = 3, mage = 10, hunter = 1 })[cls] or 0
  local S = Sim.New({ class = cls, zone = zones[cls], viewR = 600, invuln = true, meta = meta,
    curses = { frail = true, brutal = true }, unlocks = { slot = 1 }, asc = asc })
  local dt = 1 / 60
  local until_ = zones[cls] and 230 or 150 -- the new classes play past a goblin and a skeleton ring
  while S.t < until_ and S.state ~= "dead" do
    if S.state == "levelup" then
      if S.t > until_ - 50 and cls ~= "druid" and cls ~= "hunter" then break end -- save some runs mid level-up
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
  -- 0.6 state: Limit Break stacks, a banished card, a revive used, Endless after the win
  for _, id in ipairs({ "might", "maxhp", "haste", "speed", "amount", "crit", "area", "magnet", "might" }) do Sim.AddLimit(S, id) end
  S.lbPicks, S.lbAmtAt = 9, 5
  S.banished.might, S.banishes, S.revives, S.revived = true, 1, 0, 1
  if cls == "rogue" then S.won10, S.endless, S.banked, S.nextBoss, S.bossN = true, true, 77, 900, 1 end

  local d = Sim.Serialize(S)
  assert(d.v == 3, "save version 3")
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
  same(S2.wslots, S.wslots, "wslots"); same(S2.nEvolved, S.nEvolved, "nEvolved")
  -- v3 (0.6)
  same(S2.p.haste, S.p.haste, "haste"); same(S2.p.area, S.p.area, "area"); same(S2.asc, S.asc, "asc")
  same(S2.lbPicks, S.lbPicks, "lbPicks"); same(S2.lbAmtAt, S.lbAmtAt, "lbAmtAt"); same(S2.nChoices, S.nChoices, "nChoices")
  same(S2.revives, S.revives, "revives"); same(S2.banishes, S.banishes, "banishes"); same(S2.amount, S.amount, "amount")
  same(S2.luck, S.luck, "luck"); same(S2.eliteEvery, S.eliteEvery, "eliteEvery"); same(S2.nextBoss, S.nextBoss, "nextBoss")
  same(S2.bossN, S.bossN, "bossN"); same(S2.spawnMul, S.spawnMul, "spawnMul"); same(S2.eSpeedMul, S.eSpeedMul, "eSpeedMul")
  for k, v in pairs(S.limit) do same(S2.limit[k] or 0, v, "limit." .. k) end
  for k in pairs(S.banished) do assert(S2.banished[k], cls .. " banished " .. k) end
  assert(S2.won10 == S.won10 and S2.endless == S.endless and S2.banked == S.banked, cls .. " Endless state")
  for _, w in ipairs(S.wlist) do same(Sim.Count(S2, S2.weapons[w.id]), Sim.Count(S, w), "count " .. w.id) end
  for k, v in pairs(S.dmgBy) do same(S2.dmgBy[k], v, "dmgBy." .. k) end
  for k, v in pairs(S.evolved) do assert(S2.evolved[k] == v, cls .. " evolved " .. k) end
  assert(next(S.dmgBy), cls .. " no damage recorded")
  assert(S2.zone == S.zone, cls .. " zone")
  same(S2.ev.ring, S.ev.ring, "event ring"); same(S2.ev.goblin, S.ev.goblin, "event goblin"); same(S2.ev.brazier, S.ev.brazier, "event brazier")
  local liveItems, value, value2 = 0, 0, 0
  for i = 1, S.nI do local it = S.items[i]; if not it.dead then liveItems = liveItems + 1; value = value + (it.value or 0) end end
  for i = 1, S2.nI do value2 = value2 + (S2.items[i].value or 0) end
  same(S2.nI, liveItems, "items"); same(value2, value, "item values")
  -- transient content is dropped, not carried over half-built
  assert(S2.nEB == 0 and S2.nZ == 0 and S2.nTr == 0, cls .. " transient lists should start empty")
  local k2 = 0
  for i = 1, S.nI do
    local it = S.items[i]
    if not it.dead then k2 = k2 + 1; assert(S2.items[k2].kind == it.kind and S2.items[k2].value == it.value, cls .. " item " .. i) end
  end
  local live = 0
  for i = 1, S.nE do if not S.enemies[i].dead then live = live + 1 end end
  same(S2.nE, live, "enemies")
  assert(#S2.wlist == #S.wlist, cls .. " weapon count")
  for i, w in ipairs(S.wlist) do
    local w2 = S2.wlist[i]
    assert(w2.id == w.id and w2.level == w.level, cls .. " weapon " .. w.id)
    if w.pets then assert(w2.pets == nil, "pets respawn on load") end
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
  print(string.format("%s ok: t=%.1f level=%d weapons=%d passives=%d enemies=%d gems=%d items=%d zone=%s ev=%d/%d state=%s -> continued to t=%.1f",
    cls, S.t, S.p.level, #S.wlist, #S.plist, live, S.nG, liveItems, tostring(S.zone), S.ev.ring, S.ev.goblin, S.state, S2.t))
end
-- an older save without zone/event cursors: events already past at its time do not fire again
do
  local S = Sim.New({ class = "mage", viewR = 600, invuln = true })
  S.t = 300
  local d = Sim.Serialize(S)
  d.ev, d.zone = nil, nil
  local S2 = assert(Sim.Deserialize(d, { viewR = 600 }))
  assert(S2.ev.ring == 2 and S2.ev.goblin == 3 and S2.ev.brazier >= 300, "events from t for old saves")
  checks = checks + 1
end
-- a version 1 save (0.4.x) still loads with empty new fields
do
  local S = Sim.New({ class = "paladin", viewR = 600 })
  for _ = 1, 120 do Sim.Step(S, 1 / 60, 1, 0) end
  local d = Sim.Serialize(S)
  d.v, d.gold, d.dmgBy, d.meta, d.curses, d.unlocks, d.gotAt, d.rerolls, d.skips, d.chestN = 1, nil, nil, nil, nil, nil, nil, nil, nil, nil
  d.zone, d.ev, d.chests, d.coinBank = nil, nil, nil, nil -- 0.4.x saves had no zone or event cursors either
  for _, it in ipairs(d.items) do it[4] = nil end
  local S2 = assert(Sim.Deserialize(d, { viewR = 600 }), "v1 save should load")
  assert(S2.gold == 0 and S2.rerolls == 0 and next(S2.meta) == nil, "v1 defaults")
  for _ = 1, 60 do Sim.Step(S2, 1 / 60, 1, 0) end
  assert(not Sim.Deserialize({ v = 4, class = "paladin" }), "future versions are refused")
  print("v1 save ok")
  -- a version 2 save (0.5.x) loads with the 0.6 state at its defaults
  local d2 = Sim.Serialize(S2)
  d2.v = 2
  for _, k in ipairs({ "limit", "lbPicks", "lbAmtAt", "asc", "won10", "endless", "banked", "nextBoss", "bossN", "bossKills",
    "nextEliteEvery", "revives", "revived", "banishes", "banished" }) do d2[k] = nil end
  for _, e in ipairs(d2.enemies) do e[15] = nil end
  d2.bossSpawned = true
  local S4 = assert(Sim.Deserialize(d2, { viewR = 600 }), "v2 save should load")
  assert(S4.asc == 0 and next(S4.limit) == nil and S4.lbPicks == 0 and not S4.endless and S4.revives == 0, "v2 defaults")
  assert(S4.nextBoss == C.RUN_SECONDS + C.ENDLESS.bossEvery and S4.bossN == 1, "v2 save past 8:00: the boss came once")
  for _ = 1, 60 do Sim.Step(S4, 1 / 60, 1, 0) end
  print("v2 save ok")
  -- saved on the victory panel: reopens there, already banked
  local V = Sim.New({ class = "rogue", viewR = 600, invuln = true })
  V.t = C.RUN_SECONDS - 0.01
  V.hooks.victory = function() end
  Sim.Step(V, 1 / 60, 0, 0)
  assert(V.state == "victory" and V.won10, "victory state")
  V.banked = 12
  local V2 = assert(Sim.Deserialize(Sim.Serialize(V), { viewR = 600 }))
  assert(V2.state == "victory" and V2.won10 and V2.banked == 12, "victory state survives a save")
  assert(Sim.KeepGoing(V2) and V2.endless and V2.state == "play", "keep going after load")
  for _ = 1, 120 do Sim.Step(V2, 1 / 60, 0, 0) end
  assert(V2.t > C.RUN_SECONDS + 1 and V2.state == "play", "Endless plays past 10:00")
  print("victory save ok")
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
