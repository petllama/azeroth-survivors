-- Azeroth Survivors: window, input, game loop and slash commands.
local addonName, ns = ...
local C, Sim, R, UI = ns.Content, ns.Sim, ns.Render, ns.UI

local DEFAULTS = { numbers = true, debug = false, scale = 1, runs = 0 }
local frame, S
local mode = "title" -- title | play | levelup | pause | over
local keys = {}
local stressCap
local fpsAcc, fpsN, fps, simMs, drawMs = 0, 0, 0, 0, 0

local MOVE = { W = "up", UP = "up", S = "down", DOWN = "down", A = "left", LEFT = "left", D = "right", RIGHT = "right" }

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
  levelup = function(s)
    mode = "levelup"
    UI.LevelUp(s)
    ns.PlaySound(888) -- level up
  end,
  over = function(s, won)
    mode = "over"
    local db = ns.db
    db.runs = (db.runs or 0) + 1
    local b = db.best
    local newBest = not s.stress and (not b or (won and not b.won) or (won == (b.won or false) and s.t > b.t))
    if newBest then db.best = { t = s.t, level = s.p.level, kills = s.kills, won = won } end
    UI.Over(s, won, newBest)
    ns.PlaySound(won and 8960 or 8959)
  end,
}

local function startRun()
  if S then R.ReleaseAll(S) end
  wipe(keys)
  S = Sim.New({ viewR = viewR(), hooks = hooks, stress = stressCap and true or nil, cap = stressCap })
  UI.HideBoss()
  UI.Show(nil)
  mode = "play"
  if stressCap then UI.Banner("Stress test: " .. stressCap .. " enemies, invulnerable", 0.6, 1, 0.6) end
end

local function pause(reason)
  if mode == "play" then mode = "pause"; wipe(keys); UI.Pause(reason) end
end

local function resume()
  if mode == "pause" then mode = "play"; UI.Show(nil) end
end

function ns.Choose(i)
  if mode ~= "levelup" or not S then return end
  if Sim.Choose(S, i) and S.state == "play" then
    mode = "play"
    UI.Show(nil)
  end
end

local function close()
  frame:Hide()
end

-- returns true when the key is ours (not passed on to the game's bindings)
local function onKey(key, down)
  local dir = MOVE[key]
  if dir then
    keys[dir] = down or nil
    return true
  end
  if not down then return key == "ESCAPE" or key == "SPACE" end
  if key == "ESCAPE" then
    if mode == "play" then pause()
    elseif mode == "pause" then resume()
    elseif mode == "title" or mode == "over" then close() end
    return true
  elseif key == "SPACE" then
    if mode == "title" or mode == "over" then startRun() end
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

local function onUpdate(_, elapsed)
  if not S then return end
  fpsAcc, fpsN = fpsAcc + elapsed, fpsN + 1
  if fpsAcc >= 0.5 then fps, fpsAcc, fpsN = fpsN / fpsAcc, 0, 0 end
  local t0 = debugprofilestop()
  if mode == "play" then
    local ix = (keys.right and 1 or 0) - (keys.left and 1 or 0)
    local iy = (keys.up and 1 or 0) - (keys.down and 1 or 0)
    Sim.Step(S, elapsed, ix, iy)
  end
  local t1 = debugprofilestop()
  if mode == "play" or mode == "levelup" or S.state == "play" then
    R.Draw(S, mode == "play" and elapsed or 0)
  end
  local t2 = debugprofilestop()
  simMs = simMs * 0.9 + (t1 - t0) * 0.1
  drawMs = drawMs * 0.9 + (t2 - t1) * 0.1
  local dbg
  if ns.db.debug then
    dbg = string.format("%.0f fps   sim %.2f ms   draw %.2f ms   enemies %d   missiles %d   crystals %d   mem %.0f KB",
      fps, simMs, drawMs, S.nE, S.nP, S.nG, collectgarbage("count"))
  end
  UI.Update(S, elapsed, dbg)
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
  frame:SetScale(ns.db.scale or 1)
  frame:Hide()

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

  R.Init(frame, w, h)
  UI.Init(frame)

  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(not onKey(key, true))
  end)
  frame:SetScript("OnKeyUp", function(self, key)
    if InCombatLockdown() then return end
    self:SetPropagateKeyboardInput(not onKey(key, false))
  end)
  frame:SetScript("OnUpdate", onUpdate)
  frame:SetScript("OnShow", function(self)
    if not InCombatLockdown() then self:EnableKeyboard(true) end
    if mode == "title" then UI.TitleBest(ns.db); UI.Show("title") end
  end)
  frame:SetScript("OnHide", function()
    wipe(keys)
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
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    AzerothSurvivorsDB = AzerothSurvivorsDB or {}
    ns.db = AzerothSurvivorsDB
    for k, v in pairs(DEFAULTS) do if ns.db[k] == nil then ns.db[k] = v end end
    build()
  elseif event == "PLAYER_REGEN_DISABLED" and frame then
    -- still allowed in this handler; afterwards keyboard propagation is locked
    wipe(keys)
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
    toggle()
  elseif cmd == "debug" then
    ns.db.debug = not ns.db.debug
    P("debug overlay " .. (ns.db.debug and "on" or "off"))
  elseif cmd == "numbers" then
    ns.db.numbers = not ns.db.numbers
    P("damage numbers " .. (ns.db.numbers and "on" or "off"))
  elseif cmd == "scale" and tonumber(arg) then
    ns.db.scale = math.max(0.5, math.min(1.5, tonumber(arg)))
    frame:SetScale(ns.db.scale)
    P("scale " .. ns.db.scale)
  elseif cmd == "stress" then
    if InCombatLockdown() then return P("not in combat") end
    stressCap = tonumber(arg) or 500
    ns.db.debug = true
    frame:Show()
    startRun()
  elseif cmd == "reset" then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    P("window position reset")
  else
    P("/azs  open/close   /azs stress N  stress test with N enemies   /azs debug  fps overlay   /azs numbers  damage numbers   /azs scale 0.8   /azs reset")
  end
end

function AzerothSurvivors_OnAddonCompartmentClick() toggle() end
