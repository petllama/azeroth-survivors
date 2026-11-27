-- Azeroth Survivors: window, input, game loop and slash commands.
local addonName, ns = ...
local C, Sim, R, UI = ns.Content, ns.Sim, ns.Render, ns.UI

local DEFAULTS = { anim = true, numbers = true, debug = false, scale = 1, runs = 0, class = "paladin", flightOffer = true, sound = true, gold = 0 }
-- db.meta = shop ranks, db.curses = active curses, db.ach = earned, db.guild = board,
-- db.asc[class] = highest Ascension unlocked, db.ascSel[class] = the level chosen for the next run
local TABLES = { "meta", "curses", "ach", "guild", "asc", "ascSel" }
local frame, S
local mode = "title" -- title | play | levelup | pause | over | chest | victory
local banishMode = false -- B on the level-up screen: the next card picked is banished instead
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

---------------------------------------------------------------------------
-- sound: WoW's built-in SOUNDKIT entries (no files shipped), throttled per name
---------------------------------------------------------------------------
local SFX = {
  levelup  = { "UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP", 46893 },
  chest    = { "UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK_GOLD_SUCCESS", 44332 },
  evolve   = { "UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT", 54125 },
  coin     = { "LOOT_WINDOW_COIN_SOUND", 120, max = 1, window = 0.12 },
  hit      = { "IG_CREATURE_AGGRO_SELECT", 873, max = 1, window = 0.35 },
  boss     = { "RAID_WARNING", 8959 },
  death    = { "UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER", 43503 },
  victory  = { "LFG_REWARDS", 17316 },
  ach      = { "UI_EPICLOOT_TOAST", 31578 },
  revive   = { "UI_70_ARTIFACT_FORGE_TRAIT_GOLD_TRAIT", 54125 },
  buy      = { "UI_GARRISON_ARCHITECT_TABLE_UPGRADE", 44302 },
  click    = { "IG_MAINMENU_OPTION_CHECKBOX_ON", 856 },
  -- map events and pickups
  goblin   = { "UI_BONUS_LOOT_ROLL_START", 31579 },
  goblinKilled = { "TRADING_POST_UI_COLLECTING_COINS", 218228 },
  ring     = { "UI_GARRISON_TOAST_INVASION_ALERT", 44292 },
  bomb     = { "UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_MEDIUM", 97597, max = 1, window = 0.5 },
  chicken  = { "UI_ADVENTURES_HEAL_FOLLOWER", 169288, max = 1, window = 0.5 },
  magnet   = { "UI_POWER_AURA_GENERIC", 23287, max = 1, window = 0.5 },
  brazier  = { "PUT_DOWN_SMALL_CHAIN", 1212, max = 1, window = 0.3 },
  ebolt    = { "UI_73_ARTIFACT_OVERLOADED_ORB_IMPACT_LOW", 97598, max = 1, window = 0.35 },
}
-- Sim fx / pickup kinds that make a sound (same name in SFX)
local FX_SOUND = { goblin = true, goblinKilled = true, ring = true }
local PICKUP_SOUND = { coin = true, bomb = true, chicken = true, magnet = true }
ns.SFX = SFX
local sfxT, sfxN = {}, {}
-- at most `max` (default 2) plays per `window` (default 0.1 s) per name
function ns.Sfx(name)
  local d = SFX[name]
  if not d or not ns.db or not ns.db.sound then return false end
  local now = GetTime()
  if not sfxT[name] or now - sfxT[name] >= (d.window or 0.1) then sfxT[name], sfxN[name] = now, 0 end
  if sfxN[name] >= (d.max or 2) then return false end
  sfxN[name] = sfxN[name] + 1
  local id = (SOUNDKIT and SOUNDKIT[d[1]]) or d[2]
  pcall(PlaySound, id)
  return true
end

local function viewR()
  local w, h = frame:GetSize()
  return math.sqrt(w * w + h * h) / 2
end

local hooks = {
  release = R.Release,
  number = R.Number,
  fx = function(s, kind, ...)
    R.Fx(s, kind, ...)
    if FX_SOUND[kind] then ns.Sfx(kind) end
  end,
  hurt = function(s)
    R.Hurt()
    ns.Sfx(s and s.lastHit and s.lastHit.kind == "enemybolt" and "ebolt" or "hit")
  end,
  heal = R.Heal,
  kill = function(s, e)
    R.Kill(s, e)
    if e.kind == "brazier" then ns.Sfx("brazier") end
  end,
  pickup = function(_, kind) if PICKUP_SOUND[kind] then ns.Sfx(kind) end end,
  levelup = function(s)
    mode = "levelup"
    banishMode = false
    UI.LevelUp(s, banishMode)
    ns.Sfx("levelup")
  end,
  revive = function(s)
    R.Fx(s, "revive")
    UI.Banner(string.format("Revived!  %d left", s.revives or 0), 1, 0.9, 0.5)
    ns.Sfx("revive")
  end,
  -- 10:00: the win counts now (achievements, best, gold so far, guild board, Ascension), then cash out or Endless
  victory = function(s)
    mode = "victory"
    local db = ns.db
    if db.save and (db.save.runId == nil or db.save.runId == s.runId) then db.save = nil end -- this run's old save
    local res = { gold = 0 }
    if not s.stress then
      res.gold = math.floor(s.gold or 0)
      s.banked = res.gold
      db.gold = (db.gold or 0) + res.gold
      ns.RecordBest(s, true)
      ns.CheckAchievements(s, true)
      res.ascUnlocked = ns.AscUnlock(s)
      ns.Social.OnRunEnd(s, true)
    end
    UI.Victory(s, res)
    ns.Sfx("victory")
  end,
  chest = function(s)
    mode = "chest"
    UI.Chest(s)
  end,
  evolve = function(s, w)
    R.Fx(s, "evolve", w)
    UI.Banner(w.def.name .. "!", 1, 0.82, 0)
    ns.Sfx("evolve")
  end,
  over = function(s, won)
    mode = "over"
    banishMode = false
    won = won or s.won10 or false -- a run that reached 10:00 stays a win, also when it falls in Endless
    local db = ns.db
    -- the run is over: its quick save goes too (a save of another run stays; old saves have no id)
    if db.save and (db.save.runId == nil or db.save.runId == s.runId) then db.save = nil end
    local res = { gold = 0 }
    if not s.stress then
      db.runs = (db.runs or 0) + 1
      res.newBest = ns.RecordBest(s, won)
      -- bank the run's gold; what was banked at 10:00 is not banked again
      res.gold = math.floor(s.gold or 0)
      db.gold = (db.gold or 0) + math.max(0, res.gold - (s.banked or 0))
      s.banked = res.gold
      res.ach = ns.CheckAchievements(s, won)
      if not s.won10 or s.endless then ns.Social.OnRunEnd(s, won) end -- a cash-out was sent at 10:00
    end
    UI.Over(s, won, res)
    ns.Sfx(won and "victory" or "death")
  end,
}

-- best run per class: a win beats a loss, then the longer time (Endless counts); returns true when new
function ns.RecordBest(s, won)
  local db = ns.db
  db.bestByClass = db.bestByClass or {}
  local b = db.bestByClass[s.class]
  local newBest = not b or (won and not b.won) or (won == (b.won or false) and s.t > b.t)
  if newBest then
    db.bestByClass[s.class] = { t = s.t, level = s.p.level, kills = s.kills, won = won and true or false,
      asc = (s.asc or 0) > 0 and s.asc or nil, endless = s.endless and math.floor(Sim.EndlessTime(s)) or nil }
  end
  return newBest
end

-- Ascension: a win with all four curses unlocks A1 for the class; a win at the class's top level the next one.
-- Returns the newly unlocked level or nil.
function ns.AscUnlock(s)
  local db = ns.db
  local top, lv = db.asc[s.class] or 0, s.asc or 0
  local _, _, nc = C.CurseMult(s.curses)
  local new
  if lv == 0 and top == 0 and nc >= #C.CURSES then new = 1
  elseif lv > 0 and lv == top and top < C.ASC_MAX then new = top + 1 end
  if not new then return nil end
  db.asc[s.class] = new
  UI.Toast({ id = "asc", icon = "Interface\\Icons\\Spell_Holy_DivineIntervention", name = "Ascension " .. new,
    desc = "Unlocked for " .. C.CLASSES[s.class].name .. ": pick it on the class screen." })
  return new
end

-- the class screen's Ascension - / +
function ns.AscStep(d)
  local db = ns.db
  local cls = db.class
  local top = db.asc[cls] or 0
  db.ascSel[cls] = math.max(0, math.min(top, (db.ascSel[cls] or 0) + d))
  ns.Sfx("click")
  UI.TitleBest(db, cls)
  return db.ascSel[cls]
end

---------------------------------------------------------------------------
-- achievements (data and pure checks in Content: C.ACHIEVEMENTS)
---------------------------------------------------------------------------
local function countCurses(curses) local _, _, n = C.CurseMult(curses) return n end

function ns.RunSummary(s, won)
  local have = {}
  for k in pairs(ns.db.ach) do have[k] = true end
  return { class = s.class, t = s.t, won = won and true or false, kills = s.kills, level = s.p.level,
    bossKilled = s.bossKilled and true or false, evolved = s.nEvolved or 0, curses = countCurses(s.curses),
    gold = s.gold or 0, have = have, asc = s.asc or 0, endless = Sim.EndlessTime(s) }
end

-- award every achievement whose check passes; returns the new ones
function ns.CheckAchievements(s, won)
  if not s or s.stress then return {} end
  local sum = ns.RunSummary(s, won)
  local new = {}
  for _, a in ipairs(C.ACHIEVEMENTS) do
    if not ns.db.ach[a.id] then
      local ok, got = pcall(a.check, sum)
      if ok and got then
        ns.db.ach[a.id] = time and time() or true
        sum.have[a.id] = true
        new[#new + 1] = a
        UI.Toast(a)
      end
    end
  end
  if #new > 0 then ns.Sfx("ach") end
  return new
end

---------------------------------------------------------------------------
-- shop and curses (class screen)
---------------------------------------------------------------------------
function ns.Buy(id)
  local db = ns.db
  local rank = db.meta[id] or 0
  local cost = C.ShopCost(id, rank) -- prestige ranks (6-10) only once ranks 1-5 are owned
  if not cost or (db.gold or 0) < cost then return false end
  db.gold = db.gold - cost
  db.meta[id] = rank + 1
  ns.Sfx("buy")
  return true
end

function ns.ToggleCurse(id)
  ns.db.curses[id] = not ns.db.curses[id] or nil
  ns.Sfx("click")
  return ns.db.curses[id] and true or false
end

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
  local stress = stressCap and true or nil
  local zone = ns.DetectZone()
  local asc = not stress and math.min(ns.db.asc[cls] or 0, ns.db.ascSel[cls] or 0) or 0
  S = Sim.New({ class = cls, zone = zone, viewR = viewR(), hooks = hooks, stress = stress, cap = stressCap,
    meta = not stress and ns.db.meta or nil, curses = not stress and ns.db.curses or nil,
    unlocks = not stress and C.UnlockBonus(ns.db.ach) or nil, asc = asc })
  S.achT = 0
  S.runId = string.format("%d-%d", time and time() or 0, math.random(1, 999999))
  R.SetClass(C.CLASSES[cls])
  R.SetZone(S.zone)
  UI.HideBoss()
  UI.Show(nil)
  mode = "play"
  if stressCap then UI.Banner("Stress test: " .. stressCap .. " enemies, invulnerable", 0.6, 1, 0.6)
  elseif S.zdef then UI.Banner(S.zdef.name, 0.85, 0.8, 0.6) end
end

local function pause(reason)
  if mode == "play" then mode = "pause"; UI.Pause(reason, S) end
end

local function resume()
  if mode == "pause" then mode = "play"; UI.Show(nil) end
end

---------------------------------------------------------------------------
-- quick save / load (one slot, in SavedVariables: survives /reload and logout)
---------------------------------------------------------------------------
local function runActive()
  return S and not S.stress and (S.state == "play" or S.state == "levelup" or S.state == "chest" or S.state == "victory")
    and (mode == "play" or mode == "pause" or mode == "levelup" or mode == "chest" or mode == "victory")
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
  S.achT = 0
  banishMode = false
  if S.state == "victory" then -- saved on the victory panel: already banked and recorded
    mode = "victory"
    UI.Victory(S, { gold = S.banked or 0 })
  elseif S.state == "levelup" then
    mode = "levelup"
    UI.LevelUp(S, banishMode)
  elseif S.state == "chest" then
    mode = "chest"
    UI.Chest(S)
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
ns.ShowTitle = showTitle

-- after a level-up pick / skip / chest: back to play (unless another level-up opened)
local function resumePlay()
  if S.state == "play" then
    mode = "play"
    UI.Show(nil)
    if InCombatLockdown() then pause("|cffff4040You are in combat!|r  The game resumes control after combat.") end
  end
end

function ns.Choose(i)
  if mode ~= "levelup" or not S then return end
  if banishMode then
    if Sim.Banish(S, i) then banishMode = false; UI.LevelUp(S, banishMode); ns.Sfx("click") end
    return
  end
  if Sim.Choose(S, i) then resumePlay() end
end

-- B on the level-up screen: the next card picked is banished (toggles)
function ns.BanishMode()
  if mode ~= "levelup" or not S or (S.banishes or 0) <= 0 then return false end
  banishMode = not banishMode
  UI.LevelUp(S, banishMode)
  return banishMode
end

-- the victory panel
function ns.CashOut()
  if mode ~= "victory" or not S then return false end
  return Sim.CashOut(S)
end

function ns.KeepGoing()
  if mode ~= "victory" or not S then return false end
  if not Sim.KeepGoing(S) then return false end
  UI.Banner("Endless! The Scourge grows stronger.", 1, 0.5, 0.25)
  resumePlay()
  if S.pendingLevels > 0 or S.chestN > 0 then mode = "play" end -- the next step opens them
  return true
end

function ns.Reroll()
  if mode ~= "levelup" or not S then return false end
  return Sim.Reroll(S)
end

function ns.Skip()
  if mode ~= "levelup" or not S then return false end
  if Sim.Skip(S) then resumePlay() return true end
  return false
end

-- chest screen: first press opens (upgrades applied, revealed one by one), the next closes
function ns.ChestAction()
  if mode ~= "chest" or not S then return end
  if S.chestN > 0 then
    local list = Sim.OpenChest(S)
    UI.ChestOpened(S, list)
    ns.Sfx("chest")
  elseif not UI.ChestRevealAll() then
    Sim.CloseChest(S)
    resumePlay()
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
  if down and mode == "levelup" and key == "S" then ns.Skip() return true end
  if down and mode == "levelup" and key == "B" then ns.BanishMode() return true end
  if down and mode == "victory" and (key == "C" or key == "E") then
    if key == "C" then ns.CashOut() else ns.KeepGoing() end
    return true
  end
  if down and mode == "title" and key == "ESCAPE" and UI.SubOpen() then UI.ShowSub(nil) return true end
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
  elseif key == "SPACE" or (mode == "chest" and (key == "ENTER" or key == "1")) then
    if mode == "title" or mode == "over" then startRun()
    elseif mode == "chest" then ns.ChestAction() end
    return true
  elseif mode == "title" and C.CLASS_ORDER[tonumber(key) or 0] then
    ns.StartClass(C.CLASS_ORDER[tonumber(key)])
    return true
  elseif mode == "over" and key == "C" then
    showTitle()
    return true
  elseif mode == "levelup" and (key == "1" or key == "2" or key == "3" or key == "4") then
    ns.Choose(tonumber(key))
    return true
  elseif mode == "levelup" and key == "R" then
    ns.Reroll()
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
    -- live achievements (survive 5 min, 1000 kills...) once a second
    S.achT = (S.achT or 0) + elapsed
    if S.achT >= 1 and S.state == "play" then S.achT = 0; ns.CheckAchievements(S, false) end
  end
  local t1 = debugprofilestop()
  if mode == "play" or mode == "levelup" or mode == "chest" or mode == "victory" or S.state == "play" then
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
    for _, k in ipairs(TABLES) do if type(ns.db[k]) ~= "table" then ns.db[k] = {} end end
    build()
    ns.Flight.Init()
    ns.Social.Init()
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
  elseif cmd == "sound" then
    ns.db.sound = not ns.db.sound
    P("sound " .. (ns.db.sound and "on" or "off"))
  elseif cmd == "board" then
    ns.Social.PrintBoard()
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
    P("/azs  open/close   /azs stress N  stress test with N enemies   /azs debug  fps overlay   /azs anim  animations on/off   /azs numbers  damage numbers   /azs sound  sound on/off   /azs board  guild leaderboard   /azs flight  offer to play on flights   /azs save | load  quick save / load   /azs scale 0.8   /azs reset")
  end
end

function AzerothSurvivors_OnAddonCompartmentClick() toggle() end
