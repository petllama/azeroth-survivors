-- Minimal WoW client mock: loads the whole addon in TOC order, opens the window, plays a run
-- with simulated key presses and checks for Lua errors. Usage: lua5.1 tests/run_addon.lua [seconds]
local ROOT = (arg[0]:match("^(.*)/tests/") or ".") .. "/AzerothSurvivors/"
local SECONDS = tonumber(arg[1]) or 120

local calls = {}
local Widget = {}
local function widget(kind, parent)
  local w = { _kind = kind, _parent = parent, _shown = kind ~= "Frame" or true, _scripts = {}, _w = 0, _h = 0, _children = {} }
  return setmetatable(w, Widget)
end
Widget.__index = function(self, k)
  local m = rawget(Widget, k)
  if m then return m end
  if type(k) == "string" and k:match("^[A-Z]") then
    calls[k] = (calls[k] or 0) + 1
    return function() end -- unknown widget API: accept silently (counted)
  end
  return nil
end
function Widget:SetScript(n, f) self._scripts[n] = f end
function Widget:GetScript(n) return self._scripts[n] end
function Widget:HookScript(n, f) self._scripts[n] = f end
function Widget:Show() local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function Widget:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible() return self._shown end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:GetSize() return self._w, self._h end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
function Widget:GetFrameLevel() return 1 end
function Widget:SetChecked(v) self._checked = v end
function Widget:GetChecked() return self._checked end
function Widget:GetStringHeight() return 14 end
function Widget:Click() local f = self._scripts.OnClick; if f then f(self) end end
function Widget:SetPoint(...) calls.SetPoint = (calls.SetPoint or 0) + 1; assert(select("#", ...) >= 1) end
function Widget:CreateTexture() return widget("Texture", self) end
function Widget:CreateFontString() return widget("FontString", self) end
function Widget:CreateLine() return widget("Line", self) end
function Widget:GetHighlightTexture() return widget("Texture", self) end
function Widget:SetText(t) assert(t ~= nil, "SetText(nil)"); self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFont(path, size) assert(path and size, "SetFont args") end
function Widget:SetTexture(path) self._tex = path; return not _G.__noArt end
function Widget:SetPropagateKeyboardInput(v) assert(not _G.__inCombat, "SetPropagateKeyboardInput in combat"); self._prop = v end

_G.UIParent = widget("Frame"); UIParent._w, UIParent._h = 1920, 1080
function CreateFrame(kind, name, parent)
  local f = widget(kind, parent)
  if name then _G[name] = f end
  return f
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local down = {}
-- clock, taxi and flight-master mocks (Flight.lua)
local clock = 1000
function GetTime() return clock end
function time() return 1700000000 + math.floor(clock) end
_G.__onTaxi = false
function UnitOnTaxi() return _G.__onTaxi end
function IsInInstance() return false end
local hooks_ = {}
function hooksecurefunc(name, f) hooks_[name] = f end
local TAXI = { { "Stormwind, Elwynn", "CURRENT", 0.50, 0.60 }, { "Ironforge, Dun Morogh", "REACHABLE", 0.55, 0.30 } }
function NumTaxiNodes() return #TAXI end
function TaxiNodeName(i) return TAXI[i][1] end
function TaxiNodeGetType(i) return TAXI[i][2] end
function TaxiNodePosition(i) return TAXI[i][3], TAXI[i][4] end
function GetTaxiMapID() return 1415 end
-- maps: a subzone with no keyword under Tirisfal Glades (parent walk), an unknown cave, an isle on a continent
local MAPS = {
  [9001] = { mapID = 9001, name = "Scarlet Watch Post", mapType = 5, parentMapID = 9002 },
  [9002] = { mapID = 9002, name = "Tirisfal Glades", mapType = 3, parentMapID = 1415 },
  [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
  [947]  = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 },
  [9100] = { mapID = 9100, name = "Nowhere Cave", mapType = 4, parentMapID = 0 },
  [9200] = { mapID = 9200, name = "Some Isle", mapType = 3, parentMapID = 1415 },
}
_G.__mapID = 9001
C_Map = {
  GetMapWorldSize = function() return 30000, 20000 end,
  GetBestMapForUnit = function(unit) assert(unit == "player"); return _G.__mapID end,
  GetMapInfo = function(id) return MAPS[id] end,
}
function TakeTaxiNode(i) if hooks_.TakeTaxiNode then hooks_.TakeTaxiNode(i) end end
RaidWarningFrame = {}
ChatTypeInfo = { RAID_WARNING = {}, SYSTEM = {} }
local raidMsgs = {}
function RaidNotice_AddMessage(_, msg) raidMsgs[#raidMsgs + 1] = msg end
BackdropTemplateMixin = {}
function IsKeyDown(k) return down[k] or false end
function GetCurrentKeyBoardFocus() return nil end
function InCombatLockdown() return _G.__inCombat or false end
local profT = 0
function debugprofilestop() return os.clock() * 1000 end
function PlaySound() end
function SetPortraitTexture() end
function print(...) io.write(table.concat({ ... }, " "), "\n") end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}

local ns = {}
for line in io.lines(ROOT .. "AzerothSurvivors.toc") do
  if line:match("%.lua$") then
    assert(loadfile(ROOT .. line:gsub("\\", "/")))("AzerothSurvivors", ns)
  end
end

-- events
local evFrames = {}
local realCreate = CreateFrame
local function fire(ev, ...)
  for k, v in pairs(_G) do end
end
-- the event frame is the only frame with an OnEvent script; find it via the registry trick
local function allFrames() return nil end

local errors = 0
local function try(f, ...)
  local args, n = { ... }, select("#", ...)
  local ok, err = xpcall(function() return f(unpack(args, 1, n)) end, debug.traceback) -- 5.1 xpcall drops args
  if not ok then errors = errors + 1; print("ERROR: " .. err) end
  return ok
end

-- find event frame: scan upvalue-free approach - recreate by firing through the frame stored by Main.lua
-- Main.lua creates its event frame first via CreateFrame("Frame"); capture it by wrapping before load would be
-- cleaner, so reload with a capturing CreateFrame.
ns = {}
local created = {}
CreateFrame = function(kind, name, parent)
  local f = realCreate(kind, name, parent)
  created[#created + 1] = f
  return f
end
for line in io.lines(ROOT .. "AzerothSurvivors.toc") do
  if line:match("%.lua$") then
    assert(loadfile(ROOT .. line:gsub("\\", "/")))("AzerothSurvivors", ns)
  end
end
local function fireAll(ev, ...)
  for _, f in ipairs(created) do
    local h = f._scripts.OnEvent
    if h then try(h, f, ev, ...) end
  end
end

fireAll("ADDON_LOADED", "AzerothSurvivors")
assert(ns.db, "db not set")
local frame = _G.AzerothSurvivorsFrame
assert(frame, "no main frame")
frame._w, frame._h = 1200, 760

local function key(k, isDown)
  down[k] = isDown or nil
  local h = frame._scripts[isDown and "OnKeyDown" or "OnKeyUp"]
  try(h, frame, k)
end
local function tick(dt)
  clock = clock + dt
  for _, f in ipairs(created) do
    local h = f._scripts.OnUpdate
    if h and f._shown then try(h, f, dt) end
  end
end

try(SlashCmdList.AZEROTHSURVIVORS, "")
assert(frame._shown, "window did not open")
key("SPACE", true)
assert(frame._prop == false, "SPACE should be consumed")
key("J", true)
assert(frame._prop == true, "J should propagate")
ns.db.debug = true
do -- movement keys steer the hero and are consumed only during play
  local S = ns.State()
  local x0 = S.p.x
  key("D", true); assert(frame._prop == false, "D should be consumed in play")
  for _ = 1, 30 do tick(1 / 60) end
  key("D", false)
  assert(S.p.x > x0 + 50, "hero did not move right: " .. S.p.x - x0)
end
_G.__noArt = os.getenv("NOART") and true or nil

local dt, t, levelups = 1 / 60, 0, 0
local dirs = { "W", "D", "S", "A" }
local held
while t < SECONDS and errors == 0 do
  local want = dirs[math.floor(t / 3) % 4 + 1]
  if want ~= held then
    if held then key(held, false) end
    key(want, true)
    held = want
  end
  tick(dt)
  t = t + dt
  -- level-up panel open? press 1-3
  local S = nil
  for i = 1, 3 do end
  if math.floor(t * 60) % 30 == 0 then key(tostring(math.random(3)), true) end
end
-- pause / resume / combat / quit paths
local S, m = ns.State()
if m == "play" or m == "levelup" then
  if m == "levelup" then key("1", true) end
  key("ESCAPE", true); tick(dt); assert(select(2, ns.State()) == "pause", "ESC should pause")
  key("W", true); assert(frame._prop == true, "W should walk the character while paused")
  key("ESCAPE", true); tick(dt); assert(select(2, ns.State()) == "play", "ESC should resume")
end
fireAll("PLAYER_REGEN_DISABLED"); _G.__inCombat = true
tick(dt); key("W", true) -- ignored while in combat
_G.__inCombat = false; fireAll("PLAYER_REGEN_ENABLED")
key("Q", true); tick(dt)
key("SPACE", true); for _ = 1, 120 do tick(dt) end
-- every class: game over -> C -> class key, then play a while with level-ups
for i, cls in ipairs(ns.Content.CLASS_ORDER) do
  local S0, m0 = ns.State()
  if m0 == "levelup" then key("1", true) end
  if m0 ~= "over" then key("ESCAPE", true); tick(dt); key("Q", true); tick(dt) end
  assert(select(2, ns.State()) == "over", "expected game over before class switch, got " .. tostring(select(2, ns.State())))
  key("C", true)
  assert(select(2, ns.State()) == "title", "C should open class select")
  key(tostring(i), true)
  local S1 = ns.State()
  assert(S1.class == cls, "class " .. cls .. " not started: " .. tostring(S1.class))
  local held2
  for f = 1, 60 * 90 do
    local want = dirs[math.floor(f / 150) % 4 + 1]
    if want ~= held2 then if held2 then key(held2, false) end; key(want, true); held2 = want end
    tick(dt)
    if select(2, ns.State()) == "levelup" then key(tostring(math.random(3)), true) end
    if select(2, ns.State()) == "over" then break end
  end
  if held2 then key(held2, false) end
  local S2 = ns.State()
  local ws = {}
  for _, w in ipairs(S2.wlist) do ws[#ws + 1] = w.id .. w.level end
  print(string.format("%s: t=%.0f level=%d kills=%d state=%s  %s", cls, S2.t, S2.p.level, S2.kills, S2.state, table.concat(ws, " ")))
end
-- zone themes from the mocked map
do
  local S = ns.State()
  assert(S.zone == "tirisfal" and ns.Render.zone == "tirisfal", "zone theme from the map's parent: " .. tostring(S.zone))
  _G.__mapID = 9100; assert(ns.DetectZone() == nil, "unknown zone should have no theme")
  _G.__mapID = 9200; assert(ns.DetectZone() == "elwynn", "continent fallback")
  _G.__mapID = 1452; assert(ns.DetectZone() == "snow", "exact uiMapID (Winterspring)")
  _G.__mapID = nil; assert(ns.DetectZone() == nil, "no map")
  _G.__mapID = 9001
  print("zones ok: parent walk -> tirisfal, unknown -> none, continent -> elwynn, map id -> snow")
end

-- content: pets, enemy AI, enemy projectiles, splits, map events and pickups, straight on the sim
do
  local Sim, C = ns.Sim, ns.Content
  local function fresh(cls, weapon)
    local S = Sim.New({ class = cls, viewR = 600, weapon = weapon, cap = 0 })
    return S
  end
  local function hold(e) e.root = 1e9 end
  -- pets: the imp shoots, the wolf bites
  for _, pw in ipairs({ { "warlock", "imp" }, { "hunter", "wolf" } }) do
    local S = fresh(pw[1], pw[2])
    local e = Sim.SpawnEnemy(S, "brute", 150, 0, true); hold(e)
    local hp0 = e.hp
    for _ = 1, 240 do Sim.Step(S, 1 / 60, 0, 0) end
    local w = S.weapons[pw[2]]
    assert(w.pets and #w.pets == 1, pw[2] .. ": no pet")
    assert(e.hp < hp0 or e.dead, pw[2] .. ": the pet dealt no damage")
    print(string.format("%s ok: pet at %.0f,%.0f, brute %d -> %d hp", pw[2], w.pets[1].x, w.pets[1].y, hp0, math.max(0, e.hp)))
  end
  -- caster: keeps its distance, its bolt hits the player through the normal hit path (armor, iframes)
  do
    local S = fresh("mage"); S.wlist = {}; S.weapons = {}
    local e = Sim.SpawnEnemy(S, "caster", 400, 0, true)
    local hp0, t = S.p.hp, 0
    while S.p.hp >= hp0 and t < 10 do Sim.Step(S, 1 / 60, 0, 0); t = t + 1 / 60 end
    assert(S.p.hp < hp0 and S.lastHit and S.lastHit.kind == "enemybolt", "enemy bolt did not hit the player")
    assert(S.p.iframes > 0, "a bolt hit gives iframes")
    local dx = e.x - S.p.x
    assert(dx > 120 and dx < 300, "caster should keep about 220 px away, at " .. dx)
    print(string.format("caster ok: bolt hit for %.1f at %.1fs, caster keeps %.0f px", hp0 - S.p.hp, t, dx))
  end
  -- charger: telegraphs (stands, line), then dashes
  do
    local S = fresh("mage"); S.wlist = {}; S.weapons = {}; S.invuln = true
    local tele = 0
    S.hooks.fx = function(_, kind) if kind == "telegraph" then tele = tele + 1 end end
    local e = Sim.SpawnEnemy(S, "charger", 250, 0, true)
    local seen, maxSp, lx = {}, 0, e.x
    for _ = 1, 60 * 6 do
      Sim.Step(S, 1 / 60, 0, 0)
      seen[e.aiS] = true
      maxSp = math.max(maxSp, math.abs(e.x - lx) * 60)
      if e.x < -50 then e.x = 250 end
      lx = e.x
    end
    assert(tele > 0 and seen[2] and seen[3], "charger never telegraphed and dashed")
    assert(maxSp > 250, "dash too slow: " .. maxSp)
    print(string.format("charger ok: %d telegraphs, dash speed %.0f", tele, maxSp))
  end
  -- ooze splits into two oozelets
  do
    local S = fresh("mage"); S.wlist = {}; S.weapons = {}
    local e = Sim.SpawnEnemy(S, "ooze", 300, 0, true)
    Sim.Damage(S, e, 1e6)
    Sim.Step(S, 1 / 60, 0, 0)
    local n = 0
    for i = 1, S.nE do if S.enemies[i].kind == "oozelet" then n = n + 1 end end
    assert(n == 2, "ooze should split into 2 oozelets, got " .. n)
    print("ooze ok: split into " .. n)
  end
  -- brazier drops a pickup; magnet, chicken, bomb, coin work
  do
    local S = fresh("mage"); S.wlist = {}; S.weapons = {}
    local b = Sim.SpawnEnemy(S, "brazier", 200, 0, true)
    Sim.Damage(S, b, 1e6)
    Sim.Step(S, 1 / 60, 0, 0)
    local kind
    for i = 1, S.nI do local it = S.items[i]; if C.PICKUPS[it.kind] and it.kind ~= "coin" then kind = it.kind end end
    assert(kind, "brazier dropped no pickup")
    S.items, S.nI = {}, 0
    -- chicken
    S.p.hp = 10
    Sim.DropItem(S, "chicken", S.p.x, S.p.y)
    Sim.Step(S, 1 / 60, 0, 0)
    assert(math.abs(S.p.hp - (10 + S.p.maxhp * 0.3)) < 1, "chicken should heal 30%: " .. S.p.hp)
    -- magnet: a far crystal flies in
    local g = { x = S.p.x + 400, y = S.p.y, xp = 3, pull = false, dead = false }
    S.nG = S.nG + 1; S.gems[S.nG] = g
    Sim.DropItem(S, "magnet", S.p.x, S.p.y)
    Sim.Step(S, 1 / 60, 0, 0)
    assert(g.pull, "magnet should pull every crystal")
    local xp0, lv0 = S.p.xp, S.p.level
    for _ = 1, 90 do Sim.Step(S, 1 / 60, 0, 0) end
    assert(S.p.xp > xp0 or S.p.level > lv0 or S.state == "levelup", "pulled crystal not collected")
    S.state = "play"; S.pendingLevels = 0
    -- bomb: everything on screen takes damage
    local e1, e2 = Sim.SpawnEnemy(S, "brute", S.p.x + 300, S.p.y, true), Sim.SpawnEnemy(S, "elite", S.p.x - 250, S.p.y + 100, true)
    hold(e1); hold(e2)
    local h1, h2 = e1.hp, e2.hp
    Sim.Step(S, 1 / 60, 0, 0)
    Sim.DropItem(S, "bomb", S.p.x, S.p.y)
    Sim.Step(S, 1 / 60, 0, 0)
    assert((e1.dead or e1.hp < h1) and e2.hp < h2, "bomb should damage everything on screen")
    -- coin
    local g0 = S.gold
    Sim.DropItem(S, "coin", S.p.x, S.p.y, 7)
    Sim.Step(S, 1 / 60, 0, 0)
    assert(S.gold == g0 + 7, "coin value not counted")
    print("pickups ok: brazier dropped " .. kind .. ", chicken, magnet, bomb, coin")
  end
  -- gold goblin flees, spills coins when killed, escapes after its life otherwise
  do
    local S = fresh("mage"); S.wlist = {}; S.weapons = {}
    local gob = Sim.SpawnEnemy(S, "goblin", 150, 0, true)
    for _ = 1, 30 do Sim.Step(S, 1 / 60, 0, 0) end
    assert(gob.x > 150, "goblin should flee")
    Sim.Damage(S, gob, 1e6)
    Sim.Step(S, 1 / 60, 0, 0)
    local coins = 0
    for i = 1, S.nI do if S.items[i].kind == "coin" and S.items[i].value then coins = coins + 1 end end
    assert(coins == C.ENEMIES.goblin.coins, "goblin coins: " .. coins)
    local gob2 = Sim.SpawnEnemy(S, "goblin", 150, 0, true)
    for _ = 1, 60 * 16 do Sim.Step(S, 1 / 60, 0, 0) end
    local alive = false
    for i = 1, S.nE do if S.enemies[i] == gob2 and not gob2.dead then alive = true end end
    assert(not alive and S.kills == 1, "goblin should vanish after its life without a kill")
    print("goblin ok: fled, " .. coins .. " coins, escaped later")
  end
  -- corruption spreads on death
  do
    local S = fresh("warlock", "corruption")
    local a = Sim.SpawnEnemy(S, "brute", 100, 0, true); hold(a)
    local b = Sim.SpawnEnemy(S, "brute", 140, 0, true); hold(b)
    for _ = 1, 60 do Sim.Step(S, 1 / 60, 0, 0) end
    local victim = a.corr and a or b
    local other = victim == a and b or a
    other.corr = nil; other.dot, other.dotT = 0, 0
    assert(victim.corr, "corruption applied to nobody")
    Sim.Damage(S, victim, 1e6)
    Sim.Step(S, 1 / 60, 0, 0)
    assert(other.corr and other.dotT > 0, "corruption should spread on death")
    print("corruption ok: spread on death")
  end
  -- every new weapon and evolved form runs together, with all new enemies around (invulnerable)
  do
    local S = Sim.New({ class = "mage", viewR = 600, invuln = true })
    for _, cls in ipairs({ "mage", "warlock", "hunter" }) do
      for _, id in ipairs(C.CLASSES[cls].kit) do
        if not S.weapons[id] then Sim.AddWeapon(S, id) end
        if C.WEAPONS[id .. "_evo"] then Sim.AddWeapon(S, id .. "_evo") end
      end
    end
    for _, k in ipairs({ "caster", "charger", "ooze", "goblin", "brazier", "skeleton" }) do
      for j = 1, 3 do Sim.SpawnEnemy(S, k, math.cos(j) * 250, math.sin(j) * 250, true) end
    end
    for f = 1, 60 * 40 do
      if S.state == "levelup" then Sim.Choose(S, 1) end
      Sim.Step(S, 1 / 60, math.cos(f / 90), math.sin(f / 90))
    end
    assert(S.kills > 50, "all-weapons run killed too little: " .. S.kills)
    print(string.format("all new weapons ok: %d weapons, t=%.0f kills=%d zones=%d traps=%d bolts=%d", #S.wlist, S.t, S.kills, S.nZ, S.nTr, S.nEB))
  end
end

-- the same through the addon: draw every new class kit, enemy and pickup (render paths)
for ci, cls in ipairs({ "mage", "warlock", "hunter" }) do
  local _, m0 = ns.State()
  if m0 == "levelup" then key("1", true) end
  if select(2, ns.State()) ~= "over" then key("ESCAPE", true); tick(dt); key("Q", true); tick(dt) end
  key("C", true); key(tostring(3 + ci), true)
  local S = ns.State()
  assert(S.class == cls, cls .. " run")
  S.invuln = true
  for _, id in ipairs(ns.Content.CLASSES[cls].kit) do if not S.weapons[id] then ns.Sim.AddWeapon(S, id) end end
  for _, k in ipairs({ "caster", "charger", "ooze", "goblin", "brazier", "skeleton" }) do
    for j = 1, 2 do ns.Sim.SpawnEnemy(S, k, S.p.x + math.cos(j * 2 + ci) * 200, S.p.y + math.sin(j * 2 + ci) * 200, true) end
  end
  for _, it in ipairs({ "magnet", "chicken", "bomb", "coin" }) do ns.Sim.DropItem(S, it, S.p.x + 60, S.p.y + 20, 3) end
  for _ = 1, 60 * 10 do
    tick(dt)
    if select(2, ns.State()) == "levelup" then key("1", true) end
  end
  S.invuln = false
  print(string.format("render ok: %s with its whole kit, t=%.0f kills=%d", cls, S.t, S.kills))
end

-- quick save / load
do
  key("ESCAPE", true) -- close whatever screen
  try(SlashCmdList.AZEROTHSURVIVORS, "")
  if not frame._shown then try(SlashCmdList.AZEROTHSURVIVORS, "") end
  local _, m0 = ns.State()
  if m0 == "over" or m0 == "title" then key("SPACE", true) elseif m0 == "pause" then key("P", true) end
  for _ = 1, 600 do tick(dt); if select(2, ns.State()) == "levelup" then key("1", true) end end
  if select(2, ns.State()) == "over" then key("SPACE", true); for _ = 1, 120 do tick(dt) end end
  if select(2, ns.State()) == "levelup" then key("1", true) end
  local S1 = ns.State()
  key("F6", true)
  assert(ns.db.save and math.abs(ns.db.save.t - S1.t) < 0.01, "F6 did not save")
  local savedT, savedLevel = S1.t, S1.p.level
  for _ = 1, 300 do tick(dt); if select(2, ns.State()) == "levelup" then key("1", true) end end
  if select(2, ns.State()) == "over" then key("SPACE", true) end
  key("F9", true)
  local S2, m2 = ns.State()
  assert(S2 ~= S1 and math.abs(S2.t - savedT) < 0.01 and S2.p.level == savedLevel, "F9 did not load")
  assert(m2 == "pause" or m2 == "levelup", "loaded run should wait paused, got " .. m2)
  if m2 == "levelup" then key("1", true) else key("P", true) end
  assert(select(2, ns.State()) == "play", "P should resume")
  key("P", true); assert(select(2, ns.State()) == "pause", "P should pause")
  key("P", true)
  print(string.format("save/load ok: saved at t=%.1f level %d", savedT, savedLevel))
end

-- flight: pick a destination, board, get the card, play, landing guard, land, learned time
do
  if frame._shown then key("ESCAPE", true); key("ESCAPE", true) end
  if frame._shown then try(SlashCmdList.AZEROTHSURVIVORS, "") end
  assert(not frame._shown, "window should be closed before the flight")
  TakeTaxiNode(2)
  _G.__onTaxi = true
  fireAll("PLAYER_CONTROL_LOST")
  for _ = 1, 120 do tick(dt) end
  local F = ns.Flight
  local left, src = F.SecondsLeft()
  assert(left and src == "estimate", "flight time should be estimated, got " .. tostring(left))
  local card = _G.AzerothSurvivorsFlightOffer
  assert(card and card._shown and card.mode == "ask", "card should ask")
  card.Ask.Play:Click()
  assert(frame._shown, "Play should open the game")
  for _ = 1, 60 do tick(dt) end
  local _, mF = ns.State()
  if mF == "title" or mF == "over" then key("2", true) ; if select(2, ns.State()) ~= "play" then key("SPACE", true) end end
  -- an estimate runs out but the flight goes on (UC -> Tarren Mill: estimate a minute short): stays open
  local guard = 0
  while (F.SecondsLeft() or 0) > -60 and guard < 60 * 900 do
    tick(dt); guard = guard + 1
    if select(2, ns.State()) == "levelup" then key("1", true) end
  end
  assert(frame._shown, "an estimate must not close the game before the real landing")
  assert(#raidMsgs == 0, "no landing banner on an estimate")
  ns.db.save = nil
  _G.__onTaxi = false
  fireAll("PLAYER_CONTROL_GAINED")
  for _ = 1, 60 do tick(dt) end
  local fl = F.State()
  assert(not fl, "flight should be over")
  assert(not frame._shown and ns.db.save, "landing puts the game away and saves it")
  local learned = ns.db.flightTimes and ns.db.flightTimes["stormwind, elwynn>ironforge, dun morogh"]
  assert(learned, "flight time should be learned")
  -- second flight: learned time, Not now -> row, Don't ask again turns the offer off
  TakeTaxiNode(2); _G.__onTaxi = true; fireAll("PLAYER_CONTROL_LOST")
  for _ = 1, 60 do tick(dt) end
  assert(select(2, F.SecondsLeft()) == "learned", "second flight should use the learned time")
  assert(card._shown and card.mode == "ask", "second flight asks again")
  card.Ask.Later:Click()
  assert(card._shown and card.mode == "row", "Not now leaves the Play row")
  -- recorded time: put away 10 s before landing
  card.Row:Click()
  assert(frame._shown, "row opens the game")
  local _, mR = ns.State()
  if mR == "pause" then key("P", true) elseif mR == "title" or mR == "over" then key("SPACE", true) end
  local g2 = 0
  while (F.SecondsLeft() or 0) > 9.5 and g2 < 60 * 900 do
    tick(dt); g2 = g2 + 1
    if select(2, ns.State()) == "levelup" then key("1", true) end
  end
  for _ = 1, 40 do tick(dt) end
  assert(not frame._shown, "a recorded time puts the game away 10 s before landing")
  assert(raidMsgs[1] == "Landing in 10 seconds", "landing banner missing: " .. tostring(raidMsgs[1]))
  _G.__onTaxi = false; fireAll("PLAYER_CONTROL_GAINED")
  for _ = 1, 60 do tick(dt) end
  -- Polestar's recording is used when we have none (node IDs from C_TaxiMap)
  C_TaxiMap = { GetAllTaxiNodes = function() return { { slotIndex = 1, nodeID = 11, name = "Undercity, Tirisfal" }, { slotIndex = 2, nodeID = 13, name = "Tarren Mill, Hillsbrad" } } end }
  PolestarCharDB = { flightTimes = { ["11>13"] = 141 } }
  TakeTaxiNode(2); _G.__onTaxi = true; fireAll("PLAYER_CONTROL_LOST")
  for _ = 1, 60 do tick(dt) end
  local leftP, srcP = F.SecondsLeft()
  assert(srcP == "polestar" and math.abs(leftP - 140) < 2, "Polestar's 141 s should be used, got " .. tostring(srcP) .. " " .. tostring(leftP))
  card.Ask.Later:Click()
  _G.__onTaxi = false; fireAll("PLAYER_CONTROL_GAINED")
  for _ = 1, 60 do tick(dt) end
  C_TaxiMap, PolestarCharDB = nil, nil
  TakeTaxiNode(2); _G.__onTaxi = true; fireAll("PLAYER_CONTROL_LOST")
  for _ = 1, 60 do tick(dt) end
  -- a fight on the way with the game open: saved, paused, closed
  card.Row:Click()
  assert(frame._shown, "row opens the game")
  fireAll("PLAYER_REGEN_DISABLED")
  assert(not frame._shown, "fight should put the game away")
  _G.__onTaxi = false; fireAll("PLAYER_CONTROL_GAINED")
  for _ = 1, 60 do tick(dt) end
  TakeTaxiNode(2); _G.__onTaxi = true; fireAll("PLAYER_CONTROL_LOST")
  for _ = 1, 60 do tick(dt) end
  card.Ask.Never:SetChecked(true)
  card.Ask.Later:Click()
  assert(not card._shown and ns.db.flightOffer == false, "Don't ask again should turn the offer off")
  _G.__onTaxi = false; fireAll("PLAYER_CONTROL_GAINED")
  for _ = 1, 60 do tick(dt) end
  ns.db.flightOffer = true
  print(string.format("flight ok: estimate stays open to landing, card, play, learned %ds, recorded time closes 10 s early, Polestar's time, not now, fight, don't ask again", learned))
end
try(SlashCmdList.AZEROTHSURVIVORS, "stress 600")
for _ = 1, 600 do tick(dt) end
try(SlashCmdList.AZEROTHSURVIVORS, "")
key("ESCAPE", true)

for c, b in pairs(ns.db.bestByClass or {}) do print(string.format("best %s: t=%.0f level=%d kills=%d", c, b.t, b.level, b.kills)) end
print("runs=" .. ns.db.runs)
print(string.format("errors=%d  SetPoint calls=%d  unknown-API calls: %s", errors, calls.SetPoint or 0,
  (function() local t = {} for k, v in pairs(calls) do if k ~= "SetPoint" then t[#t + 1] = k end end table.sort(t) return table.concat(t, " ") end)()))
os.exit(errors == 0 and 0 or 1)
