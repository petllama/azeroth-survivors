-- Azeroth Survivors: HUD and panels (title, level-up, pause, game over).
local _, ns = ...
local C, Sim = ns.Content, ns.Sim
local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local floor = math.floor
local hud, xpBar, levelText, timerText, killText, goldText, bossBar, bossText, debugText, banner, slots
local panels = {}
local choiceButtons = {}
local subs, subOpen = {}, nil
local toast
local WEAPON_SLOTS_MAX = C.WEAPON_SLOTS + 1 -- the 6th slot is an achievement unlock
-- results screen rows for damage that no skill did (S.dmgBy keys that are not weapon ids)
local SOURCES = {
  bomb  = { name = "Goblin Bomb", icon = "Interface\\Icons\\INV_Misc_Bomb_05", color = { 1, 0.55, 0.2 } },
  other = { name = "Other", icon = "Interface\\Icons\\INV_Misc_QuestionMark", color = { 0.7, 0.7, 0.7 } },
}
UI.SOURCES = SOURCES
UI.panels, UI.subs = panels, subs

local function font(parent, size, flags, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(STANDARD_TEXT_FONT, size, flags or "OUTLINE")
  return fs
end

local function bar(parent, r, g, b)
  local s = CreateFrame("StatusBar", nil, parent)
  s:SetStatusBarTexture(WHITE)
  s:SetStatusBarColor(r, g, b)
  local bg = s:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)
  return s
end

local function fmtTime(t)
  t = floor(t)
  return string.format("%02d:%02d", floor(t / 60), t % 60)
end
UI.FmtTime = fmtTime

local function panel(name, parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  p:SetFrameLevel(parent:GetFrameLevel() + 20)
  local dim = p:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints()
  dim:SetColorTexture(0, 0, 0, 0.62)
  p:EnableMouse(true)
  p:Hide()
  panels[name] = p
  return p
end

function UI.Init(frame)
  hud = CreateFrame("Frame", nil, frame)
  hud:SetAllPoints()
  hud:SetFrameLevel(frame:GetFrameLevel() + 10)

  xpBar = bar(hud, 0.25, 0.7, 1)
  xpBar:SetPoint("TOPLEFT", 0, 0)
  xpBar:SetPoint("TOPRIGHT", 0, 0)
  xpBar:SetHeight(12)
  levelText = font(xpBar, 11)
  levelText:SetPoint("CENTER")

  timerText = font(hud, 26)
  timerText:SetPoint("TOP", 0, -18)
  killText = font(hud, 13)
  killText:SetPoint("TOPRIGHT", -10, -18)
  killText:SetTextColor(0.9, 0.9, 0.9)
  goldText = font(hud, 12)
  goldText:SetPoint("TOPRIGHT", killText, "BOTTOMRIGHT", 0, -4)
  goldText:SetTextColor(1, 0.82, 0)

  bossBar = bar(hud, 0.4, 0.7, 1)
  bossBar:SetSize(420, 14)
  bossBar:SetPoint("TOP", 0, -52)
  bossText = font(bossBar, 11)
  bossText:SetPoint("CENTER")
  bossBar:Hide()

  slots = {}
  for i = 1, WEAPON_SLOTS_MAX + C.PASSIVE_SLOTS do
    local f = CreateFrame("Frame", nil, hud)
    f:SetSize(24, 24)
    local row = i <= WEAPON_SLOTS_MAX and 0 or 1
    local col = i <= WEAPON_SLOTS_MAX and i - 1 or i - WEAPON_SLOTS_MAX - 1
    f:SetPoint("TOPLEFT", 8 + col * 27, -18 - row * 27)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.lv = font(f, 10)
    f.lv:SetPoint("BOTTOMRIGHT", 2, -1)
    f:Hide()
    slots[i] = f
  end

  debugText = font(hud, 10)
  debugText:SetPoint("BOTTOMLEFT", 6, 6)
  debugText:SetJustifyH("LEFT")
  debugText:SetTextColor(0.7, 1, 0.7)

  banner = font(hud, 22)
  banner:SetPoint("CENTER", 0, 120)
  banner:Hide()
  banner.t = 0

  -- title
  local t = panel("title", frame)
  local title = font(t, 40)
  title:SetPoint("TOP", 0, -26)
  title:SetText("Azeroth Survivors")
  title:SetTextColor(1, 0.82, 0)
  local sub = font(t, 14)
  sub:SetPoint("TOP", title, "BOTTOM", 0, -12)
  sub:SetWidth(900)
  sub:SetText("Survive the Scourge for 10 minutes. Move with |cffffd100WASD|r or the |cffffd100arrow keys|r; your skills cast themselves.\nCollect crystals to level up and choose upgrades. |cffffd100ESC|r pauses. Combat with real mobs pauses the game.")
  t.cards, t.sub = {}, sub
  -- rows of three cards (placed by UI.LayoutClasses: hidden classes get no card until unlocked)
  local CW, CH = 300, 150
  for i, id in ipairs(C.CLASS_ORDER) do
    local cd = C.CLASSES[id]
    local b = CreateFrame("Button", nil, t)
    b:SetSize(CW, CH)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.09, 0.13, 0.95)
    b.edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.edge:SetPoint("TOPLEFT", -2, 2)
    b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    b.edge:SetColorTexture(0.4, 0.35, 0.25, 0.9)
    b:SetHighlightTexture(WHITE)
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOPLEFT", 10, -10)
    icon:SetTexture(cd.icon)
    local name = font(b, 17)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    name:SetText(cd.name)
    name:SetTextColor(cd.color[1], cd.color[2], cd.color[3])
    local desc = font(b, 10, "")
    desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(CW - 78)
    desc:SetJustifyH("LEFT")
    local trait = cd.trait or (cd.crit > 0.1 and "high crit" or (cd.armor > 0 and "armored" or (cd.regen > 0 and "regenerates" or nil)))
    desc:SetText(cd.desc .. string.format("\n|cffaaaaaa%d health, speed %d%s|r", cd.hp, cd.speed, trait and (", " .. trait) or ""))
    for k, wid in ipairs(cd.kit) do
      local sk = b:CreateTexture(nil, "ARTWORK")
      sk:SetSize(26, 26)
      sk:SetPoint("BOTTOMLEFT", 10 + (k - 1) * 31, 24)
      sk:SetTexture(C.WEAPONS[wid].icon)
      sk:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local startName = font(b, 10, "")
    startName:SetPoint("BOTTOMLEFT", 10, 7)
    startName:SetText("Starts with |cffffd100" .. C.WEAPONS[cd.start].name .. "|r")
    b.best = font(b, 10, "")
    b.best:SetPoint("BOTTOMRIGHT", -8, 28)
    b.best:SetJustifyH("RIGHT")
    b.best:SetWidth(CW - 172)
    b.best:SetTextColor(0.7, 0.7, 0.7)
    b.key = font(b, 14)
    b.key:SetPoint("TOPLEFT", 4, -3)
    b.key:SetText(i)
    b:SetScript("OnClick", function() ns.StartClass(id) end)
    t.cards[id] = b
  end
  t.cont = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
  t.cont:SetSize(360, 26)
  t.cont:SetScript("OnClick", function() ns.QuickLoad() end)
  t.go = font(t, 16)
  UI.LayoutClasses(C.VisibleClasses(ns.db))
  t.champion = font(t, 13)
  t.champion:SetPoint("TOP", 0, -8)
  t.champion:SetTextColor(1, 0.5, 0.15)
  t.info = font(t, 13)
  t.info:SetPoint("BOTTOM", 0, 52)
  t.info:SetWidth(900)
  local tabs = { { "shop", "Shop" }, { "curses", "Curses" }, { "ach", "Achievements" }, { "guild", "Guild" } }
  t.tabs = {}
  for i, tb in ipairs(tabs) do
    local b = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
    b:SetSize(140, 26)
    b:SetPoint("BOTTOM", (i - 2.5) * 152, 16)
    b:SetText(tb[2])
    b:SetScript("OnClick", function() UI.ShowSub(subOpen ~= tb[1] and tb[1] or nil) end)
    t.tabs[tb[1]] = b
  end
  UI.InitSubs(t)

  -- level up
  local l = panel("levelup", frame)
  local lt = font(l, 30)
  lt:SetPoint("CENTER", 0, 215)
  lt:SetText("Level Up!")
  lt:SetTextColor(1, 0.82, 0)
  l.reroll = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
  l.reroll:SetSize(170, 26)
  l.reroll:SetPoint("CENTER", -95, -262)
  l.reroll:SetScript("OnClick", function() ns.Reroll() end)
  l.skip = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
  l.skip:SetSize(170, 26)
  l.skip:SetPoint("CENTER", 95, -262)
  l.skip:SetScript("OnClick", function() ns.Skip() end)
  for i = 1, 4 do
    local b = CreateFrame("Button", nil, l)
    b:SetSize(460, 76)
    b:SetPoint("CENTER", 0, 150 - i * 84)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.1, 0.16, 0.95)
    local edge = b:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", 2, -2)
    edge:SetColorTexture(0.75, 0.6, 0.2, 0.9)
    edge:SetDrawLayer("BACKGROUND", -1)
    b:SetHighlightTexture(WHITE)
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(56, 56)
    b.icon:SetPoint("LEFT", 10, 0)
    b.name = font(b, 16)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 12, -4)
    b.name:SetTextColor(1, 0.82, 0)
    b.desc = font(b, 13, "")
    b.desc:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -8)
    b.desc:SetWidth(360)
    b.desc:SetJustifyH("LEFT")
    b.key = font(b, 14)
    b.key:SetPoint("TOPRIGHT", -8, -6)
    b.key:SetText(i)
    b:SetScript("OnClick", function() ns.Choose(i) end)
    choiceButtons[i] = b
  end

  -- pause
  local pz = panel("pause", frame)
  pz.title = font(pz, 34)
  pz.title:SetPoint("CENTER", 0, 40)
  pz.title:SetText("Paused")
  pz.sub = font(pz, 14)
  pz.sub:SetPoint("TOP", pz.title, "BOTTOM", 0, -16)

  -- results (game over)
  local o = panel("over", frame)
  o.title = font(o, 34)
  o.title:SetPoint("TOP", 0, -30)
  o.stats = font(o, 15)
  o.stats:SetPoint("TOP", 0, -122)
  o.stats:SetWidth(760)
  o.dmgHead = font(o, 13)
  o.dmgHead:SetPoint("TOP", 0, -196)
  o.dmgHead:SetText("Damage by skill")
  o.dmgHead:SetTextColor(1, 0.82, 0)
  o.rows = {}
  for i = 1, 9 do
    local r = CreateFrame("Frame", nil, o)
    r:SetSize(620, 22)
    r:SetPoint("TOP", 0, -216 - (i - 1) * 26)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = font(r, 12, "")
    r.name:SetPoint("LEFT", 26, 0)
    r.name:SetWidth(170)
    r.name:SetJustifyH("LEFT")
    r.bar = bar(r, 1, 0.7, 0.2)
    r.bar:SetPoint("LEFT", 200, 0)
    r.bar:SetSize(250, 14)
    r.val = font(r, 12, "")
    r.val:SetPoint("LEFT", 458, 0)
    r.val:SetWidth(162)
    r.val:SetJustifyH("LEFT")
    r:Hide()
    o.rows[i] = r
  end
  o.ach = font(o, 13)
  o.ach:SetPoint("TOP", 0, -456)
  o.ach:SetWidth(760)
  local again = font(o, 16)
  again:SetPoint("BOTTOM", 0, 30)
  again:SetText("|cff00ff00SPACE|r play again     |cffffd100C|r change class     |cffffd100ESC|r close")

  -- chest
  local ch = panel("chest", frame)
  ch.title = font(ch, 30)
  ch.title:SetPoint("CENTER", 0, 215)
  ch.title:SetText("Treasure Chest!")
  ch.title:SetTextColor(1, 0.82, 0)
  ch.icon = ch:CreateTexture(nil, "ARTWORK")
  ch.icon:SetSize(96, 96)
  ch.icon:SetPoint("CENTER", 0, 120)
  ch.open = CreateFrame("Button", nil, ch, "UIPanelButtonTemplate")
  ch.open:SetSize(200, 28)
  ch.open:SetPoint("CENTER", 0, -262)
  ch.open:SetScript("OnClick", function() ns.ChestAction() end)
  ch.cards = {}
  for i = 1, 3 do
    local b = CreateFrame("Frame", nil, ch)
    b:SetSize(460, 70)
    b:SetPoint("CENTER", 0, 30 - (i - 1) * 80)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.1, 0.16, 0.95)
    b.edge = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.edge:SetPoint("TOPLEFT", -2, 2)
    b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(50, 50)
    b.icon:SetPoint("LEFT", 10, 0)
    b.name = font(b, 15)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 12, -2)
    b.name:SetTextColor(1, 0.82, 0)
    b.desc = font(b, 12, "")
    b.desc:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -6)
    b.desc:SetWidth(370)
    b.desc:SetJustifyH("LEFT")
    b:Hide()
    ch.cards[i] = b
  end
  ch:SetScript("OnUpdate", function(self, elapsed) UI.ChestTick(elapsed) end)

  -- achievement toast (above every panel)
  toast = CreateFrame("Frame", nil, frame)
  toast:SetSize(320, 84)
  toast:SetPoint("TOPRIGHT", -14, -34) -- clear of the results screen's title and stats lines
  toast:SetFrameLevel(frame:GetFrameLevel() + 40)
  local tbg = toast:CreateTexture(nil, "BACKGROUND")
  tbg:SetAllPoints()
  local atlasOk = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ui-achievement-alert-background")
  if atlasOk and tbg.SetAtlas then
    tbg:SetAtlas("ui-achievement-alert-background")
  else -- fallback: dark plate with a gold edge
    tbg:SetColorTexture(0.08, 0.07, 0.05, 0.95)
    local edge = toast:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -2, 2)
    edge:SetPoint("BOTTOMRIGHT", 2, -2)
    edge:SetColorTexture(0.85, 0.65, 0.2, 1)
  end
  toast.icon = toast:CreateTexture(nil, "ARTWORK")
  toast.icon:SetSize(44, 44)
  toast.icon:SetPoint("LEFT", 18, 0)
  toast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local iconFrame = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("ui-achievement-iconframe")
  if iconFrame then
    local ov = toast:CreateTexture(nil, "OVERLAY")
    ov:SetSize(62, 62)
    ov:SetPoint("CENTER", toast.icon, "CENTER", -1, 2)
    ov:SetAtlas("ui-achievement-iconframe")
  end
  toast.head = font(toast, 11)
  toast.head:SetPoint("TOP", 26, -12)
  toast.head:SetText("Achievement Earned")
  toast.head:SetTextColor(1, 0.82, 0)
  toast.name = font(toast, 15)
  toast.name:SetPoint("TOP", toast.head, "BOTTOM", 0, -5)
  toast.name:SetWidth(230)
  toast.sub = font(toast, 10, "")
  toast.sub:SetPoint("TOP", toast.name, "BOTTOM", 0, -4)
  toast.sub:SetWidth(230)
  toast.queue, toast.t = {}, 0
  toast:Hide()
  toast:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t - elapsed
    self:SetAlpha(math.min(1, self.t / 0.5))
    if self.t <= 0 then
      self:Hide()
      UI.NextToast()
    end
  end)
  UI.toast = toast
end

-- Class cards for the visible classes (keys 1..n): rows of three; up to six keep the 300x150 cards, a
-- seventh (the unlocked hidden class) makes three rows of shorter cards with the last row centred.
local CARD_W, CARD_GAP = 300, 14
function UI.LayoutClasses(list)
  local t = panels.title
  local n = #list
  local rows = math.max(1, math.ceil(n / 3))
  local CH, gap = rows > 2 and 130 or 150, rows > 2 and 8 or 10
  local shown = {}
  for i, id in ipairs(list) do
    local b = t.cards[id]
    if b then
      shown[id] = true
      local col, row = (i - 1) % 3, floor((i - 1) / 3)
      local inRow = math.min(3, n - row * 3)
      b:SetSize(CARD_W, CH)
      b:ClearAllPoints()
      b:SetPoint("TOP", t.sub, "BOTTOM", (col - (inRow - 1) / 2) * (CARD_W + CARD_GAP), -16 - row * (CH + gap))
      b.key:SetText(i)
      b:Show()
    end
  end
  for id, b in pairs(t.cards) do if not shown[id] then b:Hide() end end
  local below = -16 - rows * (CH + gap)
  t.cont:ClearAllPoints()
  t.cont:SetPoint("TOP", t.sub, "BOTTOM", 0, below - 34)
  t.go:ClearAllPoints()
  t.go:SetPoint("TOP", t.sub, "BOTTOM", 0, below - 6)
  t.go:SetText("Press |cffffd1001|r-|cffffd100" .. n .. "|r or click a class.  |cff00ff00SPACE|r plays the highlighted one.")
  t.classList = list
end

function UI.Show(name)
  if name ~= "title" and subOpen then UI.ShowSub(nil) end
  for n, p in pairs(panels) do
    if n == name then p:Show() else p:Hide() end
  end
end

function UI.Showing(name) return panels[name] and panels[name]:IsShown() end

local function hex(c) return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

function UI.TitleBest(db, selected)
  local t = panels.title
  UI.LayoutClasses(C.VisibleClasses(db))
  local xpM, goldM, n = C.CurseMult(db.curses)
  t.info:SetText(string.format("|cffffd100%d gold|r banked     Curses: %s", db.gold or 0,
    n > 0 and string.format("|cffff6060%d active|r  (XP x%.2f, gold x%.2f)", n, xpM, goldM) or "none"))
  if C.UnlockBonus(db.ach).title then t.champion:SetText(C.TITLE); t.champion:Show() else t.champion:Hide() end
  if subOpen then UI.RefreshSub() end
  local name, t, level = ns.SaveInfo()
  if name then
    panels.title.cont:SetText(string.format("Continue saved %s run (%s, level %d)   F9", name, fmtTime(t), level))
    panels.title.cont:Show()
  else
    panels.title.cont:Hide()
  end
  for id, card in pairs(panels.title.cards) do
    local b = db.bestByClass and db.bestByClass[id]
    card.best:SetText(b and string.format("Best %s, lv %d%s", fmtTime(b.t), b.level, b.won and "\n|cff00ff00victory|r" or "") or "")
    if id == selected then card.edge:SetColorTexture(1, 0.82, 0, 1) else card.edge:SetColorTexture(0.4, 0.35, 0.25, 0.9) end
  end
end

function UI.LevelUp(S)
  local l = panels.levelup
  l.reroll:SetText(string.format("Reroll (R)  %d left", S.rerolls or 0))
  l.skip:SetText(string.format("Skip (S)  %d left", S.skips or 0))
  if (S.rerolls or 0) > 0 then l.reroll:Enable() else l.reroll:Disable() end
  if (S.skips or 0) > 0 then l.skip:Enable() else l.skip:Disable() end
  for i = 1, 4 do
    local b, c = choiceButtons[i], S.choices[i]
    if c then
      local name, text, icon = Sim.ChoiceText(c)
      b.name:SetText(name)
      b.desc:SetText(text)
      b.icon:SetTexture(icon)
      b:Show()
    else
      b:Hide()
    end
  end
  UI.Show("levelup")
end

function UI.Pause(reason)
  panels.pause.sub:SetText((reason and (reason .. "\n\n") or "") ..
    "|cffffd100P|r / |cffffd100ESC|r resume     |cffffd100F6|r quick save     |cffffd100F9|r quick load     |cffffd100Q|r end run")
  UI.Show("pause")
end

-- results: time, level, kills, gold, damage per skill with DPS, new achievements
function UI.Over(S, won, res)
  res = res or {}
  local o = panels.over
  local cd = C.CLASSES[S.class]
  o.title:SetText((won and "Victory!" or "You have fallen") .. "\n|cff" .. hex(cd.color) .. cd.name .. "|r")
  o.title:SetTextColor(won and 0.3 or 1, won and 1 or 0.25, won and 0.3 or 0.25)
  local _, _, nc = C.CurseMult(S.curses)
  o.stats:SetText(string.format("Survived %s   Level %d   Kills %d   Damage %d\n|cffffd100+%d gold|r (%d banked)%s%s",
    fmtTime(S.t), S.p.level, S.kills, floor(S.dmgDone), res.gold or 0, ns.db and ns.db.gold or 0,
    nc > 0 and string.format("   |cffff6060%d curse%s|r", nc, nc > 1 and "s" or "") or "",
    res.newBest and "   |cffffd100New best run!|r" or ""))
  -- damage bars, biggest first
  local list = {}
  for id, amt in pairs(S.dmgBy or {}) do if amt >= 1 then list[#list + 1] = { id = id, amt = amt } end end
  table.sort(list, function(a, b) return a.amt > b.amt end)
  local top = list[1] and list[1].amt or 1
  for i, r in ipairs(o.rows) do
    local e = list[i]
    if e then
      local d = C.WEAPONS[e.id]
      local src = SOURCES[e.id] or SOURCES.other
      r.icon:SetTexture(d and d.icon or src.icon)
      r.name:SetText(d and ((d.evolved and "|cffffd100" or "") .. d.name .. (d.evolved and "|r" or "")) or src.name)
      local col = d and d.color or src.color
      r.bar:SetStatusBarColor(col[1], col[2], col[3])
      r.bar:SetMinMaxValues(0, top)
      r.bar:SetValue(e.amt)
      local since = S.gotAt and S.gotAt[e.id] or 0
      r.val:SetText(string.format("%d  (%.0f dps)", floor(e.amt), e.amt / math.max(1, S.t - since)))
      r:Show()
    else
      r:Hide()
    end
  end
  o.dmgHead:SetShown(#list > 0)
  local names = {}
  for _, a in ipairs(res.ach or {}) do names[#names + 1] = a.name end
  o.ach:SetText(#names > 0 and ("Achievements earned: |cffffd100" .. table.concat(names, ", ") .. "|r") or "")
  UI.Show("over")
end

function UI.Banner(text, r, g, b)
  banner:SetText(text)
  banner:SetTextColor(r or 1, g or 1, b or 1)
  banner.t = 3
  banner:SetAlpha(1)
  banner:Show()
end

function UI.Update(S, elapsed, dbg)
  local p = S.p
  xpBar:SetMinMaxValues(0, p.xpNext)
  xpBar:SetValue(p.xp)
  if p.level ~= hud.lv then hud.lv = p.level; levelText:SetText("Level " .. p.level) end
  local sec = floor(S.t)
  if sec ~= hud.sec then hud.sec = sec; timerText:SetText(fmtTime(sec)) end
  if S.kills ~= hud.k then hud.k = S.kills; killText:SetText(S.kills .. " kills") end
  local g = floor(S.gold or 0)
  if g ~= hud.g then hud.g = g; goldText:SetText(g .. " gold") end
  if S.boss then
    bossBar:SetMinMaxValues(0, S.boss.maxhp)
    bossBar:SetValue(S.boss.hp)
    bossText:SetText(C.ENEMIES.boss.name)
    bossBar:Show()
  else
    bossBar:Hide()
  end
  local sig = S.picks or 0
  if sig ~= hud.sig or S ~= hud.S then
    hud.sig, hud.S = sig, S
    UI.Slots(S)
  end
  if banner.t > 0 then
    banner.t = banner.t - elapsed
    banner:SetAlpha(math.min(1, banner.t))
    if banner.t <= 0 then banner:Hide() end
  end
  if dbg then debugText:SetText(dbg); debugText:Show() else debugText:Hide() end
end

function UI.Slots(S)
  local i = 0
  for _, w in ipairs(S.wlist) do
    i = i + 1
    slots[i].icon:SetTexture(w.def.icon); slots[i].lv:SetText(w.level); slots[i]:Show()
  end
  for k = i + 1, WEAPON_SLOTS_MAX do slots[k]:Hide() end
  i = WEAPON_SLOTS_MAX
  for _, id in ipairs(S.plist) do
    i = i + 1
    slots[i].icon:SetTexture(C.PASSIVES[id].icon); slots[i].lv:SetText(S.passives[id]); slots[i]:Show()
  end
  for k = i + 1, #slots do slots[k]:Hide() end
end

function UI.HideBoss() bossBar:Hide(); banner:Hide(); banner.t = 0; hud.lv, hud.sec, hud.k, hud.sig, hud.g = nil, nil, nil, nil, nil end


---------------------------------------------------------------------------
-- chest screen
---------------------------------------------------------------------------
local REVEAL = 0.45
local chestList, chestShown, chestT = nil, 0, 0

function UI.Chest(S)
  local ch = panels.chest
  if ns.Render.USE_ART and ch.icon:SetTexture("Interface\\AddOns\\AzerothSurvivors\\Art\\chest") then
    ch.icon:SetTexCoord(0, 1, 0, 1)
  else
    ch.icon:SetTexture("Interface\\Icons\\INV_Misc_TreasureChest02b")
    ch.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  ch.title:SetText(S.chestN > 1 and ("Treasure Chest!  " .. S.chestN .. " upgrades") or "Treasure Chest!")
  for _, c in ipairs(ch.cards) do c:Hide() end
  ch.open:SetText("Open (SPACE)")
  chestList, chestShown, chestT = nil, 0, 0
  UI.Show("chest")
end

local function showCard(i)
  local ch, c = panels.chest, chestList[i]
  local b = ch.cards[i]
  if not b or not c then return end
  local name, text, icon = Sim.ChoiceText(c)
  b.name:SetText(name)
  b.desc:SetText(text)
  b.icon:SetTexture(icon)
  if c.kind == "evolve" then b.edge:SetColorTexture(1, 0.5, 0.1, 1) else b.edge:SetColorTexture(0.75, 0.6, 0.2, 0.9) end
  b:Show()
end

function UI.ChestOpened(S, list)
  chestList, chestShown, chestT = list or {}, 0, 0
  if #chestList > 0 then chestShown = 1; showCard(1) end
  panels.chest.open:SetText(chestShown >= #chestList and "Continue (SPACE)" or "Reveal all (SPACE)")
end

function UI.ChestTick(elapsed)
  if not chestList or chestShown >= #chestList then return end
  chestT = chestT + elapsed
  if chestT >= REVEAL then
    chestT = 0
    chestShown = chestShown + 1
    showCard(chestShown)
    if chestShown >= #chestList then panels.chest.open:SetText("Continue (SPACE)") end
  end
end

-- true when cards were still hidden (they are shown now)
function UI.ChestRevealAll()
  if not chestList or chestShown >= #chestList then return false end
  while chestShown < #chestList do chestShown = chestShown + 1; showCard(chestShown) end
  panels.chest.open:SetText("Continue (SPACE)")
  return true
end

---------------------------------------------------------------------------
-- achievement toast
---------------------------------------------------------------------------
function UI.Toast(a)
  if a.toastHead then
    table.insert(toast.queue, 1, a) -- a class unlock goes first and replaces a plain toast on screen
    if toast:IsShown() and toast.shownA and not toast.shownA.toastHead then
      table.insert(toast.queue, 2, toast.shownA)
      toast:Hide()
    end
  else
    toast.queue[#toast.queue + 1] = a
  end
  if not toast:IsShown() then UI.NextToast() end
end

function UI.NextToast()
  local a = table.remove(toast.queue, 1)
  if not a then return end
  toast.icon:SetTexture(a.icon)
  toast.head:SetText(a.toastHead or "Achievement Earned")
  toast.name:SetText(a.name)
  toast.sub:SetText(a.unlockText or a.desc)
  toast.t = a.toastHead and 7 or 4
  toast.shownId, toast.shownA = a.id, a
  if a.toastSound then ns.Sfx(a.toastSound) end
  toast:SetAlpha(1)
  toast:Show()
end

---------------------------------------------------------------------------
-- class screen sub panels: shop, curses, achievements, guild
---------------------------------------------------------------------------
local function subPanel(t, name, title)
  local p = CreateFrame("Frame", nil, t)
  p:SetSize(660, 540)
  p:SetPoint("TOP", 0, -64)
  p:SetFrameLevel(t:GetFrameLevel() + 10)
  p:EnableMouse(true)
  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.05, 0.08, 0.98)
  local edge = p:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetPoint("TOPLEFT", -2, 2)
  edge:SetPoint("BOTTOMRIGHT", 2, -2)
  edge:SetColorTexture(0.75, 0.6, 0.2, 1)
  p.title = font(p, 20)
  p.title:SetPoint("TOP", 0, -12)
  p.title:SetText(title)
  p.title:SetTextColor(1, 0.82, 0)
  p.head = font(p, 12, "")
  p.head:SetPoint("TOP", 0, -40)
  p.head:SetWidth(620)
  local back = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  back:SetSize(110, 22)
  back:SetPoint("BOTTOM", 0, 10)
  back:SetText("Back (ESC)")
  back:SetScript("OnClick", function() UI.ShowSub(nil) end)
  p.rows = {}
  p:Hide()
  subs[name] = p
  return p
end

local function row(p, i, h, top)
  local r = CreateFrame("Frame", nil, p)
  r:SetSize(620, h - 4)
  r:SetPoint("TOP", 0, -(top or 62) - (i - 1) * h)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(h - 10, h - 10)
  r.icon:SetPoint("LEFT", 4, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = font(r, 13)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 0)
  r.name:SetWidth(330)
  r.name:SetJustifyH("LEFT")
  r.desc = font(r, 11, "")
  r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
  r.desc:SetWidth(400)
  r.desc:SetJustifyH("LEFT")
  p.rows[i] = r
  return r
end

function UI.InitSubs(t)
  -- shop
  local sp = subPanel(t, "shop", "Shop")
  for i, item in ipairs(C.SHOP) do
    local r = row(sp, i, 44)
    r.icon:SetTexture(item.icon)
    r.buy = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.buy:SetSize(130, 24)
    r.buy:SetPoint("RIGHT", -4, 0)
    r.buy:SetScript("OnClick", function()
      if ns.Buy(item.id) then UI.TitleBest(ns.db, ns.db.class) end
    end)
    r.id = item.id
  end
  -- curses
  local cp = subPanel(t, "curses", "Curses")
  for i, c in ipairs(C.CURSES) do
    local r = row(cp, i, 60, 80)
    r.icon:SetTexture(c.icon)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(30, 30)
    r.check:SetPoint("RIGHT", -10, 0)
    r.check:SetScript("OnClick", function(self)
      self:SetChecked(ns.ToggleCurse(c.id))
      UI.TitleBest(ns.db, ns.db.class)
    end)
    r.id = c.id
  end
  cp.mult = font(cp, 15)
  cp.mult:SetPoint("TOP", 0, -340)
  -- achievements
  local ap = subPanel(t, "ach", "Achievements")
  for i, a in ipairs(C.ACHIEVEMENTS) do
    local r = row(ap, i, 40)
    r.desc:SetWidth(560)
    r.icon:SetTexture(a.icon)
    r.id = a.id
  end
  -- guild
  local gp = subPanel(t, "guild", "Guild leaderboard")
  gp.lines = {}
  for i = 1, 14 do
    local l = font(gp, 13, "")
    l:SetPoint("TOPLEFT", 40, -66 - (i - 1) * 28)
    l:SetWidth(580)
    l:SetJustifyH("LEFT")
    gp.lines[i] = l
  end
end

function UI.SubOpen() return subOpen end

function UI.ShowSub(name)
  subOpen = subs[name] and name or nil
  for n, p in pairs(subs) do if n == subOpen then p:Show() else p:Hide() end end
  if subOpen then UI.RefreshSub() end
end

function UI.RefreshSub()
  local db = ns.db
  local p = subs[subOpen]
  if not p or not db then return end
  if subOpen == "shop" then
    p.head:SetText(string.format("|cffffd100%d gold|r to spend. Upgrades apply to every run from the next one on.", db.gold or 0))
    for _, r in ipairs(p.rows) do
      local item = C.SHOP_BY_ID[r.id]
      local rank = db.meta[r.id] or 0
      r.name:SetText(string.format("%s  |cffaaaaaa%d / %d|r", item.name, rank, item.max))
      r.desc:SetText(item.text .. " per rank")
      local cost = C.ShopCost(r.id, rank)
      if cost then
        r.buy:SetText(cost .. " gold")
        if (db.gold or 0) >= cost then r.buy:Enable() else r.buy:Disable() end
      else
        r.buy:SetText("Max")
        r.buy:Disable()
      end
    end
  elseif subOpen == "curses" then
    p.head:SetText("Curses make every run harder and stack. Each active curse gives +25% XP and +50% gold.")
    for _, r in ipairs(p.rows) do
      local c
      for _, x in ipairs(C.CURSES) do if x.id == r.id then c = x end end
      r.name:SetText(c.name)
      r.desc:SetText(c.text)
      r.check:SetChecked(db.curses[r.id] and true or false)
    end
    local xpM, goldM, n = C.CurseMult(db.curses)
    p.mult:SetText(string.format("%d active:  XP x%.2f   gold x%.2f", n, xpM, goldM))
  elseif subOpen == "ach" then
    local got, total = 0, 0
    local vis = {}
    for _, r in ipairs(p.rows) do
      local a
      for _, x in ipairs(C.ACHIEVEMENTS) do if x.id == r.id then a = x end end
      if a.hidden and not db[a.hidden] then r:Hide() else r:Show(); vis[#vis + 1] = r end
    end
    local h = math.min(40, floor(446 / math.max(1, #vis))) -- hidden rows leave no gap; rows fit above Back
    for k, r in ipairs(vis) do
      r:ClearAllPoints()
      r:SetPoint("TOP", 0, -62 - (k - 1) * h)
      r:SetHeight(h - 4)
      r.icon:SetSize(h - 10, h - 10)
      r.name:SetFont(STANDARD_TEXT_FONT, h < 34 and 12 or 13, "OUTLINE")
      r.desc:SetFont(STANDARD_TEXT_FONT, h < 34 and 10 or 11, "")
    end
    for _, r in ipairs(vis) do
      local a
      for _, x in ipairs(C.ACHIEVEMENTS) do if x.id == r.id then a = x end end
      total = total + 1
      local have = db.ach[r.id] and true or false
      if have then got = got + 1 end
      r.name:SetText(have and ("|cffffd100" .. a.name .. "|r") or ("|cff888888" .. a.name .. "|r"))
      r.desc:SetText(a.desc .. (a.unlockText and ("  |cff66ccff" .. a.unlockText .. "|r") or ""))
      r.icon:SetDesaturated(not have)
      r.icon:SetAlpha(have and 1 or 0.5)
    end
    p.head:SetText(string.format("%d / %d earned", got, total))
  elseif subOpen == "guild" then
    local list = ns.Social.Board(#p.lines)
    p.head:SetText((IsInGuild and IsInGuild()) and "Best run per player and class, shared with guild members who have the addon. /azs board prints it."
      or "Join a guild to share runs. Your own bests are listed here.")
    for i, l in ipairs(p.lines) do
      local r = list[i]
      if r then
        local cd = C.CLASSES[r.class]
        l:SetText(string.format("%2d.  %s   |cff%s%s|r   %s   level %d   %d kills%s", i, r.name,
          cd and hex(cd.color) or "cccccc", ns.Social.ClassName(r.class), fmtTime(r.t), r.level, r.kills,
          r.won and "   |cff00ff00victory|r" or ""))
      else
        l:SetText(i == 1 and "|cff888888No results yet.|r" or "")
      end
    end
  end
end
