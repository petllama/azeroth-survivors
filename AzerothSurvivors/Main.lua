-- Azeroth Survivors: window, input, game loop and slash commands.
local addonName, ns = ...
local C, Sim, R, UI = ns.Content, ns.Sim, ns.Render, ns.UI

local DEFAULTS = { anim = true, numbers = true, debug = false, scale = 1, runs = 0, class = "paladin", flightOffer = true }
local frame, S
local mode = "title" -- title | play | levelup | pause | over
local stressCap
local fpsAcc, fpsN, fps, simMs, drawMs = 0, 0, 0, 0, 0
local debugLine = ""

local function clampScale(s)
  local maxS = math.min(UIParent:GetWidth() / (frame:GetWidth() + 6), UIParent:GetHeight() / (frame:GetHeight() + 30))
  return math.max(0.5, math.min(maxS, s))
end

local MOVE = { W = "up", UP = "up", S = "down", DOWN = "down", A = "left", LEFT = "left", D = "right", RIGHT = "right" }

function ns.State() return S, mode end

function ns.PlaySound(id)
  pcall(PlaySound, id, "SFX")
end

local function viewR()
  local w, h = frame:GetSize()
  return math.sqrt(w * w + h * h) / 2
end

local hooks = {
  release = R.Release,
  number = R.Number,
  fx = R.Fx,
  hurt = function() R.Hurt() end,
  heal = R.Heal,
  kill = R.Kill,
  levelup = function(s)
    mode = "levelup"
    UI.LevelUp(s)
    ns.PlaySound(888) -- level up
  end,
  over = function(s, won)
    mode = "over"
    local db = ns.db
    db.runs = (db.runs or 0) + 1
    db.bestByClass = db.bestByClass or {}
    local b = db.bestByClass[s.class]
    local newBest = not s.stress and (not b or (won and not b.won) or (won == (b.won or false) and s.t > b.t))
    if newBest then db.bestByClass[s.class] = { t = s.t, level = s.p.level, kills = s.kills, won = won } end
    UI.Over(s, won, newBest)
    ns.PlaySound(won and 888 or 8959)
  end,
}

-- Zone theme (C.ZONES key) for the player's map: exact uiMapID, else name keywords on the map and its parents
-- (zone -> continent). nil = the default ground and waves.
function ns.DetectZone()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
  local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok then return nil end
  for _ = 1, 8 do
    if not id or id == 0 then return nil end
    if C.ZONE_MAPS[id] then return C.ZONE_MAPS[id] end
    local ok2, info = pcall(C_Map.GetMapInfo, id)
    if not ok2 or type(info) ~= "table" then return nil end
    local key = C.ZoneForName(info.name)
    if key then return key end
    id = info.parentMapID
  end
  return nil
end

local function startRun()
  if S then R.ReleaseAll(S) end
  local cls = C.CLASSES[ns.db.class] and ns.db.class or "paladin"
  local zone = ns.DetectZone()
  S = Sim.New({ class = cls, zone = zone, viewR = viewR(), hooks = hooks, stress = stressCap and true or nil, cap = stressCap })
  R.SetClass(C.CLASSES[cls])
  R.SetZone(S.zone)
  UI.HideBoss()
  UI.Show(nil)
  mode = "play"
  if stressCap then UI.Banner("Stress test: " .. stressCap .. " enemies, invulnerable", 0.6, 1, 0.6)
  elseif S.zdef then UI.Banner(S.zdef.name, 0.85, 0.8, 0.6) end
end

local function pause(reason)
  if mode == "play" then mode = "pause"; UI.Pause(reason, ns.db.save) end
end

local function resume()
  if mode == "pause" then mode = "play"; UI.Show(nil) end
end

---------------------------------------------------------------------------
-- quick save / load (one slot, in SavedVariables: survives /reload and logout)
---------------------------------------------------------------------------
local function runActive()
  return S and not S.stress and (S.state == "play" or S.state == "levelup")
    and (mode == "play" or mode == "pause" or mode == "levelup")
end

local function saveRun()
  if not runActive() then return false end
  local d = Sim.Serialize(S)
  d.savedAt = time and time() or 0
  ns.db.save = d
  return true
end
ns.SaveRun = saveRun

local function loadRun()
  local d = ns.db.save
  if not d then return false end
  local S2 = Sim.Deserialize(d, { viewR = viewR(), hooks = hooks })
  if not S2 then ns.db.save = nil; return false end
  if S then R.ReleaseAll(S) end
  S = S2
  stressCap = nil
  R.SetClass(C.CLASSES[S.class])
  R.SetZone(S.zone)
  UI.HideBoss()
  if S.state == "levelup" then
    mode = "levelup"
    UI.LevelUp(S)
  else
    mode = "play"
    pause("|cff00ff00Saved run loaded.|r  |cffffd100P|r or |cffffd100ESC|r to play.")
  end
  R.Draw(S, 0)
  return true
end

function ns.QuickSave()
  if saveRun() then UI.Banner("Game saved", 0.6, 1, 0.6) end
end

function ns.QuickLoad()
  if not loadRun() then UI.Banner("No saved game", 1, 0.5, 0.5) end
end

function ns.SaveInfo()
  local d = ns.db.save
  if not d then return nil end
  return C.CLASSES[d.class].name, d.t, d.p.level
end

function ns.StartClass(id)
  if mode ~= "title" and mode ~= "over" then return end
  ns.db.class = id
  startRun()
end

local function showTitle()
  mode = "title"
  UI.TitleBest(ns.db, ns.db.class)
  UI.Show("title")
end

function ns.Choose(i)
  if mode ~= "levelup" or not S then return end
  if Sim.Choose(S, i) and S.state == "play" then
    mode = "play"
    UI.Show(nil)
    if InCombatLockdown() then pause("|cffff4040You are in combat!|r  The game resumes control after combat.") end
  end
end

local function close()
  frame:Hide()
end

---------------------------------------------------------------------------
-- for Flight.lua and other addons (same shape as FreedoomArcadeAPI: Open, Close(saveAndPause), IsOpen)
---------------------------------------------------------------------------
function ns.IsOpen() return frame and frame:IsShown() and true or false end

function ns.Open()
  if not frame then return false end
  if InCombatLockdown() then print("|cffffd100Azeroth Survivors|r: opens after the fight.") return false end
  frame:Show()
  return true
end

-- save, pause and close: closed, saved
function ns.PutAway()
  if not ns.IsOpen() then return false, false end
  pause()
  local saved = saveRun()
  close()
  return true, saved
end

AzerothSurvivorsAPI = {
  version = 1,
  Open = function() return ns.Open() end,
  Close = function(saveAndPause)
    if saveAndPause then local _, saved = ns.PutAway(); return saved end
    if ns.IsOpen() then close() end
    return false
  end,
  IsOpen = function() return ns.IsOpen() end,
}

-- returns true when the key is ours (not passed on to the game's bindings)
local function onKey(key, down)
  if MOVE[key] then
    return mode == "play" -- movement is polled with IsKeyDown; outside play the character may walk
  end
  if not down then return key == "ESCAPE" or key == "SPACE" end
  if key == "F6" then
    ns.QuickSave()
    return true
  elseif key == "F9" then
    ns.QuickLoad()
    return true
  elseif key == "P" and (mode == "play" or mode == "pause") then
    if mode == "play" then pause() else resume() end
    return true
  elseif key == "ESCAPE" then
    if mode == "play" then pause()
    elseif mode == "pause" then resume()
    else close() end -- title, over, levelup (the level-up waits for reopening)
    return true
  elseif key == "SPACE" then
    if mode == "title" or mode == "over" then startRun() end
    return true
  elseif mode == "title" and C.CLASS_ORDER[tonumber(key) or 0] then
    ns.StartClass(C.CLASS_ORDER[tonumber(key)])
    return true
  elseif mode == "over" and key == "C" then
    showTitle()
    return true
  elseif mode == "levelup" and (key == "1" or key == "2" or key == "3") then
    ns.Choose(tonumber(key))
    return true
  elseif mode == "pause" and key == "Q" then
    S.state = "dead"
    hooks.over(S, false)
    return true
  end
  return false
end

local function held(a, b) return IsKeyDown(a) or IsKeyDown(b) end

local function onUpdate(_, elapsed)
  if not S then return end
  fpsAcc, fpsN = fpsAcc + elapsed, fpsN + 1
  if fpsAcc >= 0.5 then fps, fpsAcc, fpsN = fpsN / fpsAcc, 0, 0 end
  local t0 = debugprofilestop()
  if mode == "play" then
    local ix, iy = 0, 0
    if not GetCurrentKeyBoardFocus() then -- typing in chat must not steer
      ix = (held("D", "RIGHT") and 1 or 0) - (held("A", "LEFT") and 1 or 0)
      iy = (held("W", "UP") and 1 or 0) - (held("S", "DOWN") and 1 or 0)
    end
    Sim.Step(S, elapsed, ix, iy)
  end
  local t1 = debugprofilestop()
  if mode == "play" or mode == "levelup" or S.state == "play" then
    R.Draw(S, mode == "play" and elapsed or 0)
  end
  local t2 = debugprofilestop()
  simMs = simMs * 0.9 + (t1 - t0) * 0.1
  drawMs = drawMs * 0.9 + (t2 - t1) * 0.1
  if ns.db.debug and fpsN == 0 then
    debugLine = string.format("%.0f fps   sim %.2f ms   draw %.2f ms   enemies %d   missiles %d   crystals %d   mem %.0f KB",
      fps, simMs, drawMs, S.nE, S.nP, S.nG, collectgarbage("count"))
  end
  UI.Update(S, elapsed, ns.db.debug and debugLine or nil)
  if mode ~= frame.shownMode then
    frame.shownMode = mode
    local pb = frame.pauseButton
    if mode == "play" then pb:SetText("Pause"); pb:Enable()
    elseif mode == "pause" then pb:SetText("Resume"); pb:Enable()
    else pb:SetText("Pause"); pb:Disable() end
  end
end

local function build()
  local w = math.min(1200, math.floor(UIParent:GetWidth() - 80))
  local h = math.min(760, math.floor(UIParent:GetHeight() - 140))
  frame = CreateFrame("Frame", "AzerothSurvivorsFrame", UIParent)
  frame:SetSize(w, h)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetScale(clampScale(ns.db.scale or 1))
  frame:Hide()
  -- swallow clicks and the wheel so they never reach the 3D world (a right-click could pull a mob)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function() end)

  local border = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  border:SetPoint("TOPLEFT", -3, 3)
  border:SetPoint("BOTTOMRIGHT", 3, -3)
  border:SetColorTexture(0.45, 0.36, 0.15, 1)

  -- drag bar above the arena
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -3, 3)
  bar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 3, 3)
  bar:SetHeight(22)
  local bt = bar:CreateTexture(nil, "BACKGROUND")
  bt:SetAllPoints()
  bt:SetColorTexture(0.1, 0.08, 0.05, 0.95)
  local name = bar:CreateFontString(nil, "OVERLAY")
  name:SetFont(STANDARD_TEXT_FONT, 12, "")
  name:SetPoint("LEFT", 8, 0)
  name:SetText("|cffffd100Azeroth Survivors|r   drag to move")
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() frame:StartMoving() end)
  bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  local x = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
  x:SetPoint("RIGHT", 2, 0)
  x:SetSize(24, 24)
  x:SetScript("OnClick", close)
  local pb = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
  pb:SetSize(64, 18)
  pb:SetPoint("RIGHT", x, "LEFT", -4, 0)
  pb:SetText("Pause")
  pb:SetScript("OnClick", function()
    if mode == "play" then pause() elseif mode == "pause" then resume() end
  end)
  pb:Disable()
  frame.pauseButton = pb

  R.Init(frame, w, h)
  UI.Init(frame)

  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(not onKey(key, true))
  end)
  frame:SetScript("OnKeyUp", function() end)
  frame:SetScript("OnUpdate", onUpdate)
  frame:SetScript("OnShow", function(self)
    if not InCombatLockdown() then self:EnableKeyboard(true) end
    if mode == "title" then showTitle() end
  end)
  frame:SetScript("OnHide", function()
      pause()
  end)
end

local function toggle()
  if not frame then return end
  if frame:IsShown() then close() return end
  if InCombatLockdown() then print("|cffffd100Azeroth Survivors|r: not in combat.") return end
  frame:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    AzerothSurvivorsDB = AzerothSurvivorsDB or {}
    ns.db = AzerothSurvivorsDB
    for k, v in pairs(DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
    build()
    ns.Flight.Init()
  elseif event == "PLAYER_LOGOUT" then
    saveRun() -- a run in progress comes back with F9 / Continue
  elseif event == "PLAYER_REGEN_DISABLED" and frame then
    -- still allowed in this handler; afterwards keyboard propagation is locked
      if frame:IsShown() then
      pause("|cffff4040You are in combat!|r  The game resumes control after combat.")
      frame:SetPropagateKeyboardInput(true)
      frame:EnableKeyboard(false)
    end
  elseif event == "PLAYER_REGEN_ENABLED" and frame and frame:IsShown() then
    frame:EnableKeyboard(true)
    if mode == "pause" then UI.Pause() end
  end
end)

SLASH_AZEROTHSURVIVORS1 = "/azs"
SLASH_AZEROTHSURVIVORS2 = "/survivors"
SlashCmdList.AZEROTHSURVIVORS = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  local P = function(s) print("|cffffd100Azeroth Survivors|r: " .. s) end
  if cmd == "" then
    stressCap = nil
    if not ns.IsOpen() and ns.Flight.InFlight() then ns.Flight.Open() return end
    toggle()
  elseif cmd == "debug" then
    ns.db.debug = not ns.db.debug
    P("debug overlay " .. (ns.db.debug and "on" or "off"))
  elseif cmd == "anim" then
    ns.db.anim = not ns.db.anim
    P("animations " .. (ns.db.anim and "on" or "off"))
  elseif cmd == "numbers" then
    ns.db.numbers = not ns.db.numbers
    P("damage numbers " .. (ns.db.numbers and "on" or "off"))
  elseif cmd == "scale" and tonumber(arg) then
    ns.db.scale = clampScale(tonumber(arg))
    frame:SetScale(ns.db.scale)
    P("scale " .. ns.db.scale)
  elseif cmd == "stress" then
    if InCombatLockdown() then return P("not in combat") end
    stressCap = tonumber(arg) or 500
    ns.db.debug = true
    frame:Show()
    startRun()
  elseif cmd == "flight" then
    ns.db.flightOffer = not ns.db.flightOffer
    P("offer to play on flights " .. (ns.db.flightOffer and "on" or "off"))
  elseif cmd == "save" then
    ns.QuickSave()
  elseif cmd == "load" then
    if not ns.IsOpen() and not ns.Open() then return end
    ns.QuickLoad()
  elseif cmd == "reset" then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    P("window position reset")
  else
    P("/azs  open/close   /azs stress N  stress test with N enemies   /azs debug  fps overlay   /azs anim  animations on/off   /azs numbers  damage numbers   /azs flight  offer to play on flights   /azs save | load  quick save / load   /azs scale 0.8   /azs reset")
  end
end

function AzerothSurvivors_OnAddonCompartmentClick() toggle() end
