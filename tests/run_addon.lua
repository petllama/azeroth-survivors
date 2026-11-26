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
function Widget:SetPoint(...) calls.SetPoint = (calls.SetPoint or 0) + 1; assert(select("#", ...) >= 1) end
function Widget:CreateTexture() return widget("Texture", self) end
function Widget:CreateFontString() return widget("FontString", self) end
function Widget:CreateLine() return widget("Line", self) end
function Widget:GetHighlightTexture() return widget("Texture", self) end
function Widget:SetText(t) assert(t ~= nil, "SetText(nil)"); self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFont(path, size) assert(path and size, "SetFont args") end
function Widget:SetTexture(path) self._tex = path end
function Widget:SetPropagateKeyboardInput(v) assert(not _G.__inCombat, "SetPropagateKeyboardInput in combat"); self._prop = v end

_G.UIParent = widget("Frame"); UIParent._w, UIParent._h = 1920, 1080
function CreateFrame(kind, name, parent)
  local f = widget(kind, parent)
  if name then _G[name] = f end
  return f
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
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

local function key(k, down)
  local h = frame._scripts[down and "OnKeyDown" or "OnKeyUp"]
  try(h, frame, k)
end
local function tick(dt) try(frame._scripts.OnUpdate, frame, dt) end

try(SlashCmdList.AZEROTHSURVIVORS, "")
assert(frame._shown, "window did not open")
key("SPACE", true); key("SPACE", false)
assert(frame._prop == false, "SPACE should be consumed")
key("J", true)
assert(frame._prop == true, "J should propagate")
ns.db.debug = true

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
key("ESCAPE", true); tick(dt)
key("ESCAPE", true); tick(dt)
fireAll("PLAYER_REGEN_DISABLED"); _G.__inCombat = true
tick(dt); key("W", true) -- ignored while in combat
_G.__inCombat = false; fireAll("PLAYER_REGEN_ENABLED")
key("Q", true); tick(dt)
key("SPACE", true); for _ = 1, 120 do tick(dt) end
try(SlashCmdList.AZEROTHSURVIVORS, "stress 600")
for _ = 1, 600 do tick(dt) end
try(SlashCmdList.AZEROTHSURVIVORS, "")
key("ESCAPE", true)

local b = ns.db.best or {}
print(string.format("runs=%d best: t=%.0f level=%s kills=%s", ns.db.runs, b.t or 0, tostring(b.level), tostring(b.kills)))
print(string.format("errors=%d  SetPoint calls=%d  unknown-API calls: %s", errors, calls.SetPoint or 0,
  (function() local t = {} for k, v in pairs(calls) do if k ~= "SetPoint" then t[#t + 1] = k end end table.sort(t) return table.concat(t, " ") end)()))
os.exit(errors == 0 and 0 or 1)
