-- Minimal WoW client mock: loads the whole addon in TOC order, opens the window, plays a run
-- with simulated key presses and checks for Lua errors. Usage: lua5.1 tests/run_addon.lua [seconds]
local ROOT = (arg[0]:match("^(.*)/tests/") or ".") .. "/AzerothSurvivors/"
local SECONDS = tonumber(arg[1]) or 120

local calls = {}
local Widget = {}
local function widget(kind, parent)
  local w = { _kind = kind, _parent = parent, _shown = kind ~= "Frame" or true, _scripts = {}, _w = 0, _h = 0, _children = {} }
  if parent then parent._children[#parent._children + 1] = w end
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
function Widget:SetPoint(point, a, b, c, d)
  calls.SetPoint = (calls.SetPoint or 0) + 1
  assert(type(point) == "string", "SetPoint point")
  local rel, relPoint, x, y = self._parent, point, 0, 0 -- the last point, for the layout check
  if type(a) == "number" then x, y = a, b
  elseif type(a) == "table" then rel = a; if type(b) == "string" then relPoint, x, y = b, c, d else x, y = b, c end
  elseif type(a) == "string" then x, y = c, d; relPoint = b or point end
  self._pt = { point, rel, relPoint, x or 0, y or 0 }
end
function Widget:CreateTexture() return widget("Texture", self) end
function Widget:CreateFontString() return widget("FontString", self) end
function Widget:CreateLine() return widget("Line", self) end
function Widget:GetHighlightTexture() return widget("Texture", self) end
function Widget:SetText(t) assert(t ~= nil, "SetText(nil)"); self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFont(path, size) assert(path and size, "SetFont args"); self._fsize = size end
function Widget:SetTexture(path)
  self._tex = path
  if _G.__missingArt and type(path) == "string" and _G.__missingArt[path:match("([^\\]+)$") or ""] then return false end
  return not _G.__noArt
end
function Widget:SetVertexColor(r, g, b) self._vc = { r, g, b } end
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
-- sound: SOUNDKIT names verified against wow-ui-source (Forever 1.60.1 SoundKitConstants.lua)
SOUNDKIT = { UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP = 46893, UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK_GOLD_SUCCESS = 44332,
  UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT = 54125, LOOT_WINDOW_COIN_SOUND = 120, IG_CREATURE_AGGRO_SELECT = 873, RAID_WARNING = 8959,
  UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER = 43503, LFG_REWARDS = 17316, UI_EPICLOOT_TOAST = 31578,
  UI_GARRISON_ARCHITECT_TABLE_UPGRADE = 44302, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
  UI_BONUS_LOOT_ROLL_START = 31579, TRADING_POST_UI_COLLECTING_COINS = 218228, UI_GARRISON_TOAST_INVASION_ALERT = 44292,
  UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_MEDIUM = 97597, UI_ADVENTURES_HEAL_FOLLOWER = 169288, UI_POWER_AURA_GENERIC = 23287,
  PUT_DOWN_SMALL_CHAIN = 1212, UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_LOW = 97598, UI_LEGENDARY_LOOT_TOAST = 63971 }
local played = {}
function PlaySound(id) assert(type(id) == "number", "PlaySound needs a SoundKit id"); played[id] = (played[id] or 0) + 1; return true end
-- guild / addon messages
_G.__inGuild = false
function IsInGuild() return _G.__inGuild end
function UnitName(u) return u == "player" and "Tester" or nil end
function Ambiguate(name, ctx) assert(ctx, "Ambiguate context"); local n, realm = name:match("^([^-]+)-(.+)$"); if n and realm == "HomeRealm" then return n end return name end
local prefixes, sent = {}, {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(prefix) assert(type(prefix) == "string" and #prefix <= 16); prefixes[prefix] = true; return true end,
  SendAddonMessage = function(prefix, msg, chatType, target)
    assert(prefixes[prefix], "prefix not registered: " .. tostring(prefix))
    assert(type(msg) == "string" and #msg <= 255, "bad addon message")
    sent[#sent + 1] = { prefix = prefix, msg = msg, chatType = chatType }
    return 0
  end,
}
-- achievement toast atlases (absent under NOART to exercise the fallback)
if not os.getenv("NOART") then
  C_Texture = { GetAtlasInfo = function(a) if a == "ui-achievement-alert-background" or a == "ui-achievement-iconframe" then return { width = 300, height = 88 } end end }
end
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

-- Title screen layout (1000x700): resolve each direct child's rectangle from its last SetPoint (vertical and
-- horizontal) with estimated text sizes, and check nothing overlaps or leaves the window. Hidden regions (the
-- class card of a class not unlocked yet) are skipped. Run for the 6 base classes and with the 7th unlocked.
local function checkTitleLayout(label)
  local UI = ns.UI
  local t = UI.panels.title
  local W, H = 1000, 700
  local function textSize(r)
    local s = (r._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local size, lines, longest = r._fsize or 12, 0, 0
    for line in (s .. "\n"):gmatch("(.-)\n") do
      local w = #line * size * 0.52
      local n = (r._w > 0 and w > r._w) and math.ceil(w / r._w) or 1
      lines = lines + n
      longest = math.max(longest, r._w > 0 and math.min(w, r._w) or w)
    end
    return (r._w > 0 and r._w or longest), lines * size * 1.2
  end
  local FX = { LEFT = 0, CENTER = 0.5, RIGHT = 1 }
  local function frac(p)
    local fx = p:match("LEFT") and 0 or (p:match("RIGHT") and 1 or 0.5)
    local fy = p:match("TOP") and 1 or (p:match("BOTTOM") and 0 or 0.5)
    return fx, fy
  end
  local rect
  rect = function(r)
    if r == t or r == nil then return 0, 0, W, H end
    local w, h = r._w, r._h
    if r._kind == "FontString" then w, h = textSize(r) end
    local pt = r._pt
    assert(pt, "layout: region without a point")
    local rx, ry, rw, rh = rect(pt[2] ~= t._parent and pt[2] or t)
    local ax, ay = frac(pt[3])
    local px, py = frac(pt[1])
    local x = rx + rw * ax + pt[4] - w * px
    local y = ry + rh * ay + pt[5] - h * py
    return x, y, w, h
  end
  local skip = {}
  for _, s in pairs(UI.subs) do skip[s] = true end
  local boxes = {}
  for _, r in ipairs(t._children) do
    if r._pt and r._shown and not skip[r] and r._pt[2] ~= nil and (r._kind ~= "FontString" or (r._text or r == t.champion or r == t.info)) then
      if r == t.champion and not r._text then r._text = "Champion of Azeroth" end
      if r == t.info and not r._text then r._text = "|cffffd10099999 gold|r banked     Curses: Horde, Brutal, Haste, Frail" end
      local x, y, w, h = rect(r)
      boxes[#boxes + 1] = { r = r, x = x, y = y, w = w, h = h, name = r._text or r._kind }
      assert(x >= 0 and y >= 0 and x + w <= W + 0.5 and y + h <= H + 0.5,
        string.format("title layout: %s leaves the window (%.0f,%.0f %.0fx%.0f)", tostring(r._text or r._kind):sub(1, 30), x, y, w, h))
    end
  end
  for i = 1, #boxes do
    for j = i + 1, #boxes do
      local a, b = boxes[i], boxes[j]
      local ov = a.x < b.x + b.w - 1 and b.x < a.x + a.w - 1 and a.y < b.y + b.h - 1 and b.y < a.y + a.h - 1
      assert(not ov, string.format("title layout overlap: %s (%.0f,%.0f %.0fx%.0f) and %s (%.0f,%.0f %.0fx%.0f)",
        tostring(a.name):sub(1, 30), a.x, a.y, a.w, a.h, tostring(b.name):sub(1, 30), b.x, b.y, b.w, b.h))
    end
  end
  print(string.format("title layout ok (%s): %d regions inside 1000x700, no overlaps", label, #boxes))
  return #boxes
end
do
  local UI, C = ns.UI, ns.Content
  local t = UI.panels.title
  t.cont:Show(); t.cont:SetText("Continue saved Death Knight run (09:59, level 63)   F9")
  assert(not ns.db.unlockedDK and #C.VisibleClasses(ns.db) == 6, "the hidden class starts hidden")
  assert(not t.cards.deathknight._shown, "hidden class card shown before the unlock")
  local n6 = checkTitleLayout("6 classes")
  ns.db.unlockedDK = true
  UI.LayoutClasses(C.VisibleClasses(ns.db))
  assert(t.cards.deathknight._shown and t.cards.deathknight.key._text == 7, "7th card with key 7 after the unlock")
  local n7 = checkTitleLayout("7 classes, centred third row")
  assert(n7 == n6 + 1, "one more card")
  ns.db.unlockedDK = false
  UI.LayoutClasses(C.VisibleClasses(ns.db))
  assert(not t.cards.deathknight._shown, "relayout hides the card again")
end

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
for i, cls in ipairs(ns.Content.VisibleClasses(ns.db)) do
  local S0, m0 = ns.State()
  if m0 == "levelup" then key("1", true) end
  if m0 == "chest" then key("SPACE", true); key("SPACE", true); key("SPACE", true) end
  if select(2, ns.State()) == "levelup" then key("1", true) end
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
    if select(2, ns.State()) == "chest" then key("SPACE", true); key("SPACE", true) end
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
  for _ = 1, 600 do tick(dt); if select(2, ns.State()) == "levelup" then key("1", true) end; if select(2, ns.State()) == "chest" then key("SPACE", true); key("SPACE", true) end end
  if select(2, ns.State()) == "over" then key("SPACE", true); for _ = 1, 120 do tick(dt) end end
  if select(2, ns.State()) == "levelup" then key("1", true) end
  local S1 = ns.State()
  key("F6", true)
  assert(ns.db.save and math.abs(ns.db.save.t - S1.t) < 0.01, "F6 did not save")
  local savedT, savedLevel = S1.t, S1.p.level
  for _ = 1, 300 do tick(dt); if select(2, ns.State()) == "levelup" then key("1", true) end; if select(2, ns.State()) == "chest" then key("SPACE", true); key("SPACE", true) end end
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
  -- a run that ends takes its quick save with it; a save of another run stays
  local function quit()
    if select(2, ns.State()) == "levelup" then key("1", true) end
    if select(2, ns.State()) == "play" then key("P", true) end
    assert(select(2, ns.State()) == "pause", "should be paused to quit")
    key("Q", true)
    assert(select(2, ns.State()) == "over", "Q should end the run")
  end
  key("F6", true)
  assert(ns.db.save and ns.db.save.runId == ns.State().runId, "save should carry the run id")
  quit()
  assert(ns.db.save == nil, "the ended run's save should be removed")
  key("SPACE", true)
  for _ = 1, 60 do tick(dt) end
  key("F6", true)
  ns.db.save.runId = "another-run"
  quit()
  assert(ns.db.save and ns.db.save.runId == "another-run", "another run's save should stay")
  ns.db.save.runId = nil -- an old save without an id goes with the next run that ends
  key("SPACE", true)
  quit()
  assert(ns.db.save == nil, "an old save without id should be removed when a run ends")
  key("SPACE", true)
  print("save cleanup ok: death/quit removes the run's save, other run's save stays")
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
-- 0.5 systems: chests, evolution, achievements + toast, gold + shop, curses, results, guild board, reroll/skip, sound
do
  local UI, Sim, C = ns.UI, ns.Sim, ns.Content
  local function settle() -- reach the game-over screen from wherever we are
    if not frame._shown then try(SlashCmdList.AZEROTHSURVIVORS, "") end
    for _ = 1, 20 do
      local _, m = ns.State()
      if m == "over" then return end
      if m == "levelup" then key("1", true)
      elseif m == "chest" then key("SPACE", true)
      elseif m == "play" then key("ESCAPE", true)
      elseif m == "pause" then key("Q", true)
      elseif m == "title" then key("SPACE", true) end
    end
    assert(select(2, ns.State()) == "over", "could not reach game over: " .. tostring(select(2, ns.State())))
  end
  local function playUntilFree(n)
    for _ = 1, n do
      tick(dt)
      local _, m = ns.State()
      if m == "levelup" then key("1", true) elseif m == "chest" then key("SPACE", true); key("SPACE", true) end
    end
  end
  settle()
  key("C", true)
  assert(select(2, ns.State()) == "title", "C should open the class screen")
  ns.db.gold, ns.db.meta, ns.db.curses = 0, {}, {}
  ns.db.ach.evolve = nil
  key("1", true)
  local S = ns.State()
  assert(S.class == "paladin" and S.rerolls == 0 and S.skips == 0, "fresh run without meta")
  playUntilFree(240)
  -- chest -> chest screen -> upgrade applied
  local picks0, lv0 = S.picks or 0, S.weapons.crusader and S.weapons.crusader.level
  Sim.DropItem(S, "chest", S.p.x, S.p.y, 1)
  tick(dt)
  assert(select(2, ns.State()) == "chest" and UI.panels.chest._shown, "picking up a chest should open the chest screen")
  key("SPACE", true)
  assert(S.chestN == 0 and (S.picks or 0) == picks0 + 1 and S.chestRewards and #S.chestRewards == 1, "chest should apply 1 upgrade")
  assert(UI.panels.chest.cards[1]._shown, "chest reward card shown")
  key("SPACE", true)
  assert(select(2, ns.State()) ~= "chest", "SPACE should close the chest screen")
  playUntilFree(5)
  -- evolution: maxed Crusader Strike + Might -> Templar's Verdict through a chest
  if not S.weapons.crusader then Sim.AddWeapon(S, "crusader") end
  while S.weapons.crusader.level < C.MAX_WEAPON_LEVEL do Sim.LevelWeapon(S, "crusader") end
  if not S.passives.might then Sim.AddPassive(S, "might") end
  local slot
  for i, w in ipairs(S.wlist) do if w.id == "crusader" then slot = i end end
  Sim.DropItem(S, "chest", S.p.x, S.p.y, 1)
  tick(dt)
  key("SPACE", true)
  assert(S.weapons.crusader_evo and not S.weapons.crusader and S.wlist[slot].id == "crusader_evo", "crusader should evolve in its slot")
  assert(S.wlist[slot].def.evolved and S.evolved.crusader == "crusader_evo", "evolved flag")
  assert(S.chestRewards[1].kind == "evolve", "chest reward should be the evolution")
  assert(played[SOUNDKIT.UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT] and played[SOUNDKIT.UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK_GOLD_SUCCESS], "evolve/chest sounds")
  key("SPACE", true)
  for _ = 1, 3 do Sim.RollChoices(S); for _, c in ipairs(S.choices) do assert(c.id ~= "crusader" and c.id ~= "crusader_evo", "evolved weapon offered on level-up") end end
  S.choices = nil
  -- the evolve achievement is awarded live, with a toast
  playUntilFree(70)
  assert(ns.db.ach.evolve, "evolve achievement not awarded")
  assert(UI.toast._shown and UI.toast.shownId, "achievement toast should show")
  assert(played[SOUNDKIT.UI_EPICLOOT_TOAST], "achievement sound")
  -- coins: picked up into S.gold
  local g0 = S.gold
  Sim.DropItem(S, "coin", S.p.x, S.p.y, 10)
  tick(dt)
  assert(math.abs(S.gold - g0 - 10 * S.goldMul) < 1e-6, "coin should add gold: " .. S.gold - g0)
  for _ = 1, 20 do if (S.dmgBy.crusader_evo or 0) > 0 then break end; playUntilFree(60) end
  assert((S.dmgBy.crusader_evo or 0) > 0, "damage should be credited to the evolved weapon")
  for k in pairs(S.dmgBy) do assert(C.WEAPONS[k] or (UI.SOURCES[k] and k ~= "other"), "unknown dmgBy key " .. tostring(k)) end
  -- run end: gold banked, results screen with damage bars, guild message sent once
  S.gold = 1500.4
  _G.__inGuild = true
  local nSent = #sent
  settle()
  assert(ns.db.gold == 1500, "gold should be banked, got " .. tostring(ns.db.gold))
  assert(UI.panels.over._shown and UI.panels.over.rows[1]._shown, "results screen with damage rows")
  assert(UI.panels.over.rows[1].val._text:match("dps"), "results row should show DPS")
  assert(#sent == nSent + 1 and sent[#sent].chatType == "GUILD" and sent[#sent].prefix == "AzSurv", "one guild message per run end")
  assert(sent[#sent].msg:match("^R1:paladin:%d+:%d+:%d+:[01]$"), "guild message format: " .. sent[#sent].msg)
  assert(ns.db.guild.Tester and ns.db.guild.Tester.paladin, "own result stored")
  -- received guild results: stored best per player per class; malformed ignored
  fireAll("CHAT_MSG_ADDON", "AzSurv", "R1:rogue:400:3000:30:0", "GUILD", "Bob-HomeRealm", "", 0, 0, "", 0)
  fireAll("CHAT_MSG_ADDON", "AzSurv", "R1:rogue:300:9000:50:0", "GUILD", "Bob-HomeRealm", "", 0, 0, "", 0) -- worse: shorter
  fireAll("CHAT_MSG_ADDON", "AzSurv", "R1:druid:600:5000:44:1", "GUILD", "Ann-FarRealm", "", 0, 0, "", 0)
  fireAll("CHAT_MSG_ADDON", "AzSurv", "R1:rogue:abc:1:1:0", "GUILD", "Eve-HomeRealm", "", 0, 0, "", 0)
  fireAll("CHAT_MSG_ADDON", "AzSurv", "R1:rogue:100:1:1:0; drop", "GUILD", "Eve-HomeRealm", "", 0, 0, "", 0)
  fireAll("CHAT_MSG_ADDON", "Other", "R1:rogue:100:1:1:0", "GUILD", "Eve-HomeRealm", "", 0, 0, "", 0)
  assert(ns.db.guild.Bob and ns.db.guild.Bob.rogue.t == 400 and ns.db.guild.Bob.rogue.kills == 3000, "Bob's best should be stored")
  assert(ns.db.guild["Ann-FarRealm"].druid.won == true, "other-realm name keeps the realm")
  assert(not ns.db.guild.Eve and not ns.db.guild["Eve-HomeRealm"], "malformed messages must be ignored")
  assert(ns.Social.Board()[1].name == "Ann-FarRealm", "board sorts wins first")
  try(SlashCmdList.AZEROTHSURVIVORS, "board")
  -- shop: buy Might, Reroll and Skip on the class screen
  key("C", true)
  UI.panels.title.tabs.shop:Click()
  assert(UI.SubOpen() == "shop" and UI.subs.shop._shown, "Shop panel should open")
  local rows = {}
  for _, r in ipairs(UI.subs.shop.rows) do rows[r.id] = r end
  local cost = C.ShopCost("might", 0)
  rows.might.buy:Click()
  assert(ns.db.meta.might == 1 and ns.db.gold == 1500 - cost, "Might should be bought")
  rows.reroll.buy:Click(); rows.skip.buy:Click()
  assert(ns.db.meta.reroll == 1 and ns.db.meta.skip == 1, "Reroll and Skip should be bought")
  UI.panels.title.tabs.guild:Click()
  assert(UI.SubOpen() == "guild" and UI.subs.guild.lines[1]._text:match("Ann"), "Guild tab lists the board")
  UI.panels.title.tabs.ach:Click()
  assert(UI.SubOpen() == "ach", "Achievements panel")
  -- curses: Frail on
  UI.panels.title.tabs.curses:Click()
  for _, r in ipairs(UI.subs.curses.rows) do if r.id == "frail" then r.check:Click() end end
  assert(ns.db.curses.frail, "Frail should be on")
  assert(UI.subs.curses.mult._text:match("x1.25"), "curse multiplier shown")
  key("ESCAPE", true)
  assert(not UI.SubOpen() and frame._shown and select(2, ns.State()) == "title", "ESC closes the sub panel only")
  -- next run: shop ranks and curse applied
  key("1", true)
  S = ns.State()
  assert(math.abs(S.p.might - 1.05) < 1e-9, "Might rank should apply: " .. S.p.might)
  assert(S.p.maxhp == math.floor(120 * 0.7 + 0.5) and S.p.hp == S.p.maxhp, "Frail should cut max HP: " .. S.p.maxhp)
  assert(math.abs(S.xpMul - 1.25) < 1e-9 and math.abs(S.goldMul - 1.5) < 1e-9, "curse XP/gold multipliers")
  assert(S.rerolls == 1 and S.skips == 1, "rerolls/skips from the shop")
  assert(S.wslots == C.WEAPON_SLOTS + 1, "evolve achievement unlocks a 6th slot")
  -- save v2 keeps meta/curses/gold
  S.gold = 12
  key("F6", true)
  local sv = ns.db.save
  assert(sv and sv.v == 2 and sv.meta.might == 1 and sv.curses.frail and sv.gold == 12 and sv.dmgBy, "save v2 fields")
  -- reroll (R) and skip (S) on the level-up screen
  S.pendingLevels = 2
  tick(dt)
  assert(select(2, ns.State()) == "levelup", "level-up expected")
  local before = S.choices
  key("R", true)
  assert(frame._prop == false and S.rerolls == 0 and S.choices ~= before and S.state == "levelup", "R should reroll")
  key("R", true)
  assert(S.rerolls == 0, "no rerolls left")
  key("S", true)
  assert(frame._prop == false and S.skips == 0 and S.pendingLevels == 1 and select(2, ns.State()) == "levelup", "S should skip one level")
  key("4", true) -- only 3 cards without Insight: ignored
  assert(select(2, ns.State()) == "levelup", "4 without a 4th card does nothing")
  key("1", true)
  assert(select(2, ns.State()) == "play", "pick returns to play")
  -- sound toggle
  local n0 = played[SOUNDKIT.LOOT_WINDOW_COIN_SOUND] or 0
  try(SlashCmdList.AZEROTHSURVIVORS, "sound")
  assert(ns.db.sound == false, "/azs sound toggles")
  Sim.DropItem(S, "coin", S.p.x, S.p.y, 1); tick(dt)
  assert((played[SOUNDKIT.LOOT_WINDOW_COIN_SOUND] or 0) == n0, "no sound when off")
  try(SlashCmdList.AZEROTHSURVIVORS, "sound")
  for _ = 1, 10 do Sim.DropItem(S, "coin", S.p.x, S.p.y, 1) end; tick(dt)
  assert((played[SOUNDKIT.LOOT_WINDOW_COIN_SOUND] or 0) - n0 == 1, "coin sound throttled")
  ns.db.curses = {}
  _G.__inGuild = false
  settle()
  print(string.format("systems ok: chest, evolution, achievement toast, coins, results with DPS, gold %d, shop, curses, guild board %d, reroll/skip, sound",
    ns.db.gold, #ns.Social.Board()))
end
-- merged 0.5: new-class evolutions through chests, pets after evolving, sounds of map events, every class's
-- damage attributed to a named source on the results screen
do
  local UI, Sim, C = ns.UI, ns.Sim, ns.Content
  local function settle()
    if not frame._shown then try(SlashCmdList.AZEROTHSURVIVORS, "") end
    for _ = 1, 20 do
      local _, m = ns.State()
      if m == "over" then return end
      if m == "levelup" then key("1", true)
      elseif m == "chest" then key("SPACE", true)
      elseif m == "play" then key("ESCAPE", true)
      elseif m == "pause" then key("Q", true)
      elseif m == "title" then key("SPACE", true) end
    end
    assert(select(2, ns.State()) == "over", "could not reach game over")
  end
  local function play(n)
    for _ = 1, n do
      tick(dt)
      local _, m = ns.State()
      if m == "levelup" then key("1", true) elseif m == "chest" then key("SPACE", true); key("SPACE", true) end
    end
  end
  local function startClass(cls)
    settle()
    key("C", true)
    for i, id in ipairs(C.VisibleClasses(ns.db)) do if id == cls then key(tostring(i), true) end end
    local S = ns.State()
    assert(S.class == cls and select(2, ns.State()) == "play", "start " .. cls)
    S.invuln = true
    return S
  end
  local function evolveByChest(S, wid)
    local r
    for _, x in ipairs(C.EVOLUTIONS) do if x.weapon == wid then r = x end end
    assert(r and C.WEAPONS[r.into], "recipe for " .. wid)
    if not S.weapons[wid] then
      if #S.wlist >= S.wslots then table.remove(S.wlist) end
      Sim.AddWeapon(S, wid)
    end
    while S.weapons[wid].level < C.MAX_WEAPON_LEVEL do Sim.LevelWeapon(S, wid) end
    if not S.passives[r.passive] then Sim.AddPassive(S, r.passive) end
    local slot
    for i, w in ipairs(S.wlist) do if w.id == wid then slot = i end end
    Sim.DropItem(S, "chest", S.p.x, S.p.y, 1)
    tick(dt)
    assert(select(2, ns.State()) == "chest", "chest screen for " .. wid)
    key("SPACE", true)
    assert(S.weapons[r.into] and not S.weapons[wid] and S.wlist[slot].id == r.into, wid .. " should evolve into " .. r.into)
    assert(S.chestRewards[1].kind == "evolve", "chest reward is the evolution")
    key("SPACE", true)
    return S.weapons[r.into]
  end
  -- Mage: Frostbolt -> Frostfire Bolt
  local S = startClass("mage")
  play(120)
  local w = evolveByChest(S, "frostbolt")
  play(600)
  assert((S.dmgBy.frostbolt_evo or 0) > 0, "Frostfire Bolt should deal damage")
  -- Hunter: Call Wolf -> The Beast Within; Warlock: Summon Imp -> Demonic Legion; pets keep fighting
  for _, pc in ipairs({ { "hunter", "wolf" }, { "warlock", "imp" } }) do
    S = startClass(pc[1])
    play(120)
    if not S.weapons[pc[2]] then Sim.AddWeapon(S, pc[2]) end
    play(60)
    assert(S.weapons[pc[2]].pets and #S.weapons[pc[2]].pets >= 1, pc[2] .. " pets before evolving")
    w = evolveByChest(S, pc[2])
    play(900)
    assert(w.pets and #w.pets == w.count, pc[2] .. " evolved pets: " .. tostring(w.pets and #w.pets))
    assert((S.dmgBy[w.id] or 0) > 0, w.id .. " pets should deal damage")
    for _, p in ipairs(w.pets) do assert(p.x == p.x and math.abs(p.x - S.p.x) < 2000, "pet position") end
    if not _G.__noArt then -- the pre-evolution pet textures are hidden: exactly one shown texture per pet
      local n = 0
      local function walk(r)
        for _, c in ipairs(r._children) do
          if c._kind == "Texture" and c._shown and type(c._tex) == "string" and c._tex:match("\\" .. pc[2] .. "$") then n = n + 1 end
          walk(c)
        end
      end
      walk(frame)
      assert(n == w.count, pc[2] .. ": " .. n .. " pet textures shown for " .. w.count .. " pets")
    end
  end
  -- Blessed Hammers -> Hammer of the Righteous: the old orbit textures are hidden
  S = startClass("paladin")
  play(60)
  w = evolveByChest(S, "hammers")
  play(30)
  if not _G.__noArt then
    local n = 0
    local function walk(r)
      for _, c in ipairs(r._children) do
        if c._kind == "Texture" and c._shown and type(c._tex) == "string" and c._tex:match("\\hammer$") then n = n + 1 end
        walk(c)
      end
    end
    walk(frame)
    assert(n == w.count, "hammers: " .. n .. " orbit textures shown for " .. w.count)
  end
  -- every class, 60 s each: all damage goes to a named skill or source (no "Other" row)
  for _, cls in ipairs(C.VisibleClasses(ns.db)) do
    S = startClass(cls)
    play(3600)
    assert(not S.dmgBy.other, cls .. ": damage credited to 'other': " .. tostring(S.dmgBy.other))
    for k in pairs(S.dmgBy) do assert(C.WEAPONS[k] or UI.SOURCES[k], cls .. ": unknown damage source " .. k) end
    settle()
    for _, r in ipairs(UI.panels.over.rows) do
      if r._shown then assert(r.name._text ~= "Other", cls .. ": results screen shows Other") end
    end
  end
  -- a bomb pickup is credited to the Goblin Bomb row
  S = startClass("paladin")
  play(300)
  Sim.DropItem(S, "bomb", S.p.x, S.p.y)
  play(2)
  assert((S.dmgBy.bomb or 0) > 0, "bomb damage")
  assert(played[SOUNDKIT.UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_MEDIUM], "bomb sound")
  S.hooks.fx(S, "ring"); S.hooks.fx(S, "goblin", S.p.x, S.p.y); S.hooks.fx(S, "goblinKilled", S.p.x, S.p.y)
  assert(played[SOUNDKIT.UI_GARRISON_TOAST_INVASION_ALERT] and played[SOUNDKIT.UI_BONUS_LOOT_ROLL_START]
    and played[SOUNDKIT.TRADING_POST_UI_COLLECTING_COINS], "event sounds")
  Sim.DropItem(S, "chicken", S.p.x, S.p.y); Sim.DropItem(S, "magnet", S.p.x, S.p.y)
  play(2)
  assert(played[SOUNDKIT.UI_ADVENTURES_HEAL_FOLLOWER] and played[SOUNDKIT.UI_POWER_AURA_GENERIC], "pickup sounds")
  local br = Sim.SpawnEnemy(S, "brazier", S.p.x + 30, S.p.y, true)
  Sim.Damage(S, br, 1e6)
  assert(played[SOUNDKIT.PUT_DOWN_SMALL_CHAIN], "brazier sound")
  S.lastHit = nil
  settle()
  local found
  for _, r in ipairs(UI.panels.over.rows) do if r._shown and r.name._text == "Goblin Bomb" then found = true end end
  assert(found, "results screen should label bomb damage Goblin Bomb")
  print("merge ok: frostbolt/wolf/imp evolve via chest, evolved pets fight, no 'other' damage for 6 classes, Goblin Bomb row")
end
-- the hidden class: invisible until The Frost Lich dies in a run with 2+ curses; then key 7, its kit, ghouls,
-- Death Coil heals, five evolutions, its achievements, the unlock toast and sound on the results screen
do
  local UI, Sim, C = ns.UI, ns.Sim, ns.Content
  local function settle()
    if not frame._shown then try(SlashCmdList.AZEROTHSURVIVORS, "") end
    for _ = 1, 20 do
      local _, m = ns.State()
      if m == "over" then return end
      if m == "levelup" then key("1", true)
      elseif m == "chest" then key("SPACE", true)
      elseif m == "play" then key("ESCAPE", true)
      elseif m == "pause" then key("Q", true)
      elseif m == "title" then key("SPACE", true) end
    end
    assert(select(2, ns.State()) == "over", "could not reach game over")
  end
  local function play(n)
    for _ = 1, n do
      tick(dt)
      local _, m = ns.State()
      if m == "levelup" then key("1", true) elseif m == "chest" then key("SPACE", true); key("SPACE", true) end
    end
  end
  local t = UI.panels.title
  ns.db.unlockedDK = false
  ns.db.ach.unlock_dk, ns.db.ach.win_deathknight = nil, nil
  -- hidden: no card, key 7 and StartClass do nothing, no achievement rows, no 6th-slot offers
  settle()
  key("C", true)
  assert(select(2, ns.State()) == "title" and not t.cards.deathknight._shown, "hidden class card on the class screen")
  assert(t.go._text:match("%-|cffffd1006|r"), "keys 1-6 before the unlock: " .. t.go._text)
  key("7", true)
  assert(select(2, ns.State()) == "title" and frame._prop == true, "key 7 must do nothing before the unlock")
  ns.StartClass("deathknight")
  assert(select(2, ns.State()) == "title", "StartClass must refuse the hidden class")
  t.tabs.ach:Click()
  for _, r in ipairs(UI.subs.ach.rows) do
    if r.id == "unlock_dk" or r.id == "win_deathknight" then assert(not r._shown, "hidden achievement row shown: " .. r.id) end
  end
  local visRows = 0
  for _, r in ipairs(UI.subs.ach.rows) do if r._shown then visRows = visRows + 1 end end
  assert(UI.subs.ach.head._text == string.format("0 / %d earned", visRows) or UI.subs.ach.head._text:match("/ " .. visRows .. " earned"), "achievement count without hidden rows")
  key("ESCAPE", true)
  local dkSkill = {}
  for _, id in ipairs(C.CLASSES.deathknight.kit) do dkSkill[id] = true end
  local function offersDK(unlocks)
    local S = Sim.New({ class = "paladin", viewR = 600, unlocks = unlocks })
    for _ = 1, 400 do
      for _, c in ipairs(Sim.RollChoices(S)) do if c.kind == "weapon" and dkSkill[c.id] then return true end end
    end
    return false
  end
  assert(not offersDK({ slot = 1 }), "6th-slot offers must not include the hidden class's skills before the unlock")
  assert(offersDK({ slot = 1, unlockedDK = true }), "6th-slot offers include the hidden class's skills after the unlock")
  -- a boss kill with one curse: no unlock
  local function bossRun(curses)
    ns.db.curses = curses
    key("1", true)
    local S = ns.State()
    assert(S.class == "paladin", "paladin run for the boss kill")
    S.invuln = true
    local boss = Sim.SpawnEnemy(S, "boss", S.p.x + 200, S.p.y, true)
    Sim.Damage(S, boss, 1e9)
    assert(S.bossKilled, "boss should be killed")
    play(150) -- live achievement checks run: the unlock waits for the results screen
    assert(not ns.db.unlockedDK, "the class must not unlock during play")
    settle()
    return S
  end
  bossRun({ horde = true })
  assert(not ns.db.unlockedDK, "one curse must not unlock the class")
  key("C", true)
  -- two curses: unlocked on the results screen, with the unlock toast and its own sound
  local n0 = played[SOUNDKIT.UI_LEGENDARY_LOOT_TOAST] or 0
  bossRun({ horde = true, brutal = true })
  assert(ns.db.unlockedDK == true and ns.db.ach.unlock_dk, "Frost Lich + 2 curses should unlock the class")
  assert(UI.panels.over._shown and UI.toast._shown and UI.toast.shownId == "unlock_dk", "unlock toast on the results screen")
  assert(UI.toast.head._text == "A new class has risen from the grave" and UI.toast.name._text == "Death Knight", "unlock toast text")
  assert((played[SOUNDKIT.UI_LEGENDARY_LOOT_TOAST] or 0) == n0 + 1, "unlock sound")
  assert(UI.panels.over.ach._text:match("Death Knight"), "results list the unlock")
  ns.db.curses = {}
  -- visible: 7 cards, key 7 plays the class
  key("C", true)
  assert(t.cards.deathknight._shown and t.go._text:match("%-|cffffd1007|r"), "7 cards after the unlock")
  checkTitleLayout("class screen after the unlock")
  t.tabs.ach:Click()
  for _, r in ipairs(UI.subs.ach.rows) do
    if r.id == "unlock_dk" or r.id == "win_deathknight" then assert(r._shown, "achievement row should show after the unlock: " .. r.id) end
  end
  key("ESCAPE", true)
  -- the new art may not be installed yet: every key falls back (hero -> class icon, ghoul -> tinted ghoul.tga)
  _G.__missingArt = { hero_dk = true, dk_ghoul = true, deathcoil = true, dnd = true, howlingblast = true }
  key("7", true)
  local S = ns.State()
  assert(S.class == "deathknight" and select(2, ns.State()) == "play" and S.wlist[1].id == "obliterate", "key 7 starts the Death Knight")
  assert(S.p.maxhp == 125 and S.p.armor >= 1, "Death Knight stats")
  S.invuln = true
  for _, id in ipairs(C.CLASSES.deathknight.kit) do if not S.weapons[id] then Sim.AddWeapon(S, id) end end
  for _, k in ipairs({ "caster", "charger", "ooze", "skeleton", "brute" }) do
    for j = 1, 3 do Sim.SpawnEnemy(S, k, S.p.x + math.cos(j * 2) * 200, S.p.y + math.sin(j * 2) * 200, true) end
  end
  play(60 * 20)
  for _, id in ipairs(C.CLASSES.deathknight.kit) do
    assert((S.dmgBy[id] or 0) > 0, "Death Knight skill dealt no damage: " .. id)
  end
  assert(S.weapons.raisedead.pets and #S.weapons.raisedead.pets == 1, "ghoul pet")
  do
    local hero, ghoul = false, 0
    local function walk(r)
      for _, c in ipairs(r._children) do
        if c._kind == "Texture" and c._shown and type(c._tex) == "string" then
          if c._tex == C.CLASSES.deathknight.icon then hero = true end
          local tint = C.WEAPONS.raisedead.petTint
          if c._tex:match("\\ghoul$") and c._vc and c._vc[1] == tint[1] and c._vc[2] == tint[2] then ghoul = ghoul + 1 end
        end
        walk(c)
      end
    end
    walk(frame)
    assert(hero, "without hero_dk the hero is drawn with the class icon")
    if not _G.__noArt then assert(ghoul >= 1, "without dk_ghoul the pet uses the ghoul art") end
  end
  _G.__missingArt = nil
  -- Death Coil heals per hit (straight on the sim, no regen)
  do
    local S2 = Sim.New({ class = "deathknight", viewR = 600, weapon = "deathcoil", cap = 0 })
    S2.p.hp, S2.p.regen = 50, 0
    for j = 1, 4 do local e = Sim.SpawnEnemy(S2, "brute", 140 + j * 20, j * 10, true); e.root = 1e9 end
    for _ = 1, 60 * 4 do Sim.Step(S2, 1 / 60, 0, 0) end
    assert((S2.dmgBy.deathcoil or 0) > 0 and S2.p.hp > 50, "Death Coil should heal: hp " .. S2.p.hp)
    -- the ghoul claws a held brute
    local S3 = Sim.New({ class = "deathknight", viewR = 600, weapon = "raisedead", cap = 0 })
    local e = Sim.SpawnEnemy(S3, "brute", 150, 0, true); e.root = 1e9
    local hp0 = e.hp
    for _ = 1, 240 do Sim.Step(S3, 1 / 60, 0, 0) end
    assert(e.hp < hp0 or e.dead, "the ghoul dealt no damage")
    print(string.format("death coil ok: hp 50 -> %.1f; ghoul ok: brute %d -> %d hp", S2.p.hp, hp0, math.max(0, e.hp)))
  end
  -- five evolutions through chests
  local evolved = {}
  for _, wid in ipairs(C.CLASSES.deathknight.kit) do
    local r
    for _, x in ipairs(C.EVOLUTIONS) do if x.weapon == wid then r = x end end
    assert(r and C.WEAPONS[r.into], "recipe for " .. wid)
    while S.weapons[wid].level < C.MAX_WEAPON_LEVEL do Sim.LevelWeapon(S, wid) end
    if not S.passives[r.passive] then
      if #S.plist >= C.PASSIVE_SLOTS then table.remove(S.plist) end
      Sim.AddPassive(S, r.passive)
    end
    local slot
    for i, w in ipairs(S.wlist) do if w.id == wid then slot = i end end
    if select(2, ns.State()) ~= "play" then play(1) end
    Sim.DropItem(S, "chest", S.p.x, S.p.y, 1)
    tick(dt)
    assert(select(2, ns.State()) == "chest", "chest screen for " .. wid)
    key("SPACE", true)
    assert(S.weapons[r.into] and not S.weapons[wid] and S.wlist[slot].id == r.into, wid .. " should evolve into " .. r.into)
    key("SPACE", true)
    evolved[#evolved + 1] = C.WEAPONS[r.into].name
  end
  for j = 1, 8 do -- a held pack in melee reach (ranged coils and ghouls otherwise kill everything first)
    local e = Sim.SpawnEnemy(S, "elite", S.p.x + math.cos(j) * 70, S.p.y + math.sin(j) * 70, true); e.root = 1e9
  end
  play(60 * 20)
  for _, w in ipairs(S.wlist) do
    if w.def.evolved then assert((S.dmgBy[w.id] or 0) > 0, w.id .. " should deal damage; " .. (function() local o = {} for k, v in pairs(S.dmgBy) do o[#o + 1] = k .. "=" .. math.floor(v) end return table.concat(o, " ") .. " t=" .. S.t .. " nE=" .. S.nE .. " mode=" .. tostring(select(2, ns.State())) end)()) end
  end
  local army = S.weapons.raisedead_evo
  assert(army and #army.pets == 4, "Army of the Dead: 4 ghouls")
  if not _G.__noArt then -- one shown ghoul texture per pet (the pre-evolution ghoul is hidden)
    local n = 0
    local function walk(r)
      for _, c in ipairs(r._children) do
        if c._kind == "Texture" and c._shown and type(c._tex) == "string" and c._tex:match("\\dk_ghoul$") then n = n + 1 end
        walk(c)
      end
    end
    walk(frame)
    assert(n == 4, n .. " ghoul textures shown for 4 ghouls")
  end
  assert(not S.dmgBy.other, "Death Knight: damage credited to 'other'")
  for k in pairs(S.dmgBy) do assert(C.WEAPONS[k] or UI.SOURCES[k], "unknown damage source " .. k) end
  -- Champion of Azeroth stays at the six base classes
  local have = {}
  for _, c in ipairs(C.CLASS_ORDER) do if c ~= "deathknight" then have["win_" .. c] = true end end
  for _, a in ipairs(C.ACHIEVEMENTS) do
    if a.id == "allclasses" then assert(a.check({ have = have }), "Champion of Azeroth needs only the six base classes") end
  end
  settle()
  print("hidden class ok: hidden before, 1 curse no unlock, 2 curses unlock + toast + sound, 7 cards, key 7, kit, ghoul, Death Coil heal, evolved: " .. table.concat(evolved, ", "))
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
