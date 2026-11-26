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
C_Map = { GetMapWorldSize = function() return 30000, 20000 end }
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
for i, cls in ipairs({ "paladin", "rogue", "druid" }) do
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
  -- fly until 10 s before landing
  local guard = 0
  while (F.SecondsLeft() or 0) > 9.5 and guard < 60 * 600 do
    tick(dt); guard = guard + 1
    if select(2, ns.State()) == "levelup" then key("1", true) end
  end
  for _ = 1, 40 do tick(dt) end
  assert(not frame._shown, "game should be put away 10 s before landing")
  assert(raidMsgs[1] == "Landing in 10 seconds", "landing banner missing: " .. tostring(raidMsgs[1]))
  assert(ns.db.save, "landing should save")
  -- land
  for _ = 1, 60 * 12 do tick(dt) end
  _G.__onTaxi = false
  fireAll("PLAYER_CONTROL_GAINED")
  for _ = 1, 60 do tick(dt) end
  local fl = F.State()
  assert(not fl, "flight should be over")
  local learned = ns.db.flightTimes and ns.db.flightTimes["Stormwind, Elwynn -> Ironforge, Dun Morogh"]
  assert(learned, "flight time should be learned")
  -- second flight: learned time, Not now -> row, Don't ask again turns the offer off
  TakeTaxiNode(2); _G.__onTaxi = true; fireAll("PLAYER_CONTROL_LOST")
  for _ = 1, 60 do tick(dt) end
  assert(select(2, F.SecondsLeft()) == "learned", "second flight should use the learned time")
  assert(card._shown and card.mode == "ask", "second flight asks again")
  card.Ask.Later:Click()
  assert(card._shown and card.mode == "row", "Not now leaves the Play row")
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
  print(string.format("flight ok: estimate, card, play, landing guard, learned %ds, not now, fight, don't ask again", learned))
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
