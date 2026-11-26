-- Azeroth Survivors: HUD and panels (title, level-up, pause, game over).
local _, ns = ...
local C, Sim = ns.Content, ns.Sim
local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local floor = math.floor
local hud, xpBar, levelText, timerText, killText, bossBar, bossText, debugText, banner, slots
local panels = {}
local choiceButtons = {}

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

  bossBar = bar(hud, 0.4, 0.7, 1)
  bossBar:SetSize(420, 14)
  bossBar:SetPoint("TOP", 0, -52)
  bossText = font(bossBar, 11)
  bossText:SetPoint("CENTER")
  bossBar:Hide()

  slots = {}
  for i = 1, C.WEAPON_SLOTS + C.PASSIVE_SLOTS do
    local f = CreateFrame("Frame", nil, hud)
    f:SetSize(24, 24)
    local row = i <= C.WEAPON_SLOTS and 0 or 1
    local col = i <= C.WEAPON_SLOTS and i - 1 or i - C.WEAPON_SLOTS - 1
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
  title:SetPoint("CENTER", 0, 120)
  title:SetText("Azeroth Survivors")
  title:SetTextColor(1, 0.82, 0)
  local sub = font(t, 14)
  sub:SetPoint("TOP", title, "BOTTOM", 0, -18)
  sub:SetWidth(560)
  sub:SetText("Survive the Scourge for 10 minutes.\n\nMove with |cffffd100WASD|r or the |cffffd100arrow keys|r. Your spells cast themselves.\nCollect crystals to level up and choose upgrades.\n|cffffd100ESC|r pauses. Combat with real mobs pauses the game.")
  t.best = font(t, 13)
  t.best:SetPoint("TOP", sub, "BOTTOM", 0, -24)
  t.best:SetTextColor(0.8, 0.8, 0.8)
  local go = font(t, 18)
  go:SetPoint("TOP", t.best, "BOTTOM", 0, -26)
  go:SetText("Press |cff00ff00SPACE|r to start")

  -- level up
  local l = panel("levelup", frame)
  local lt = font(l, 30)
  lt:SetPoint("CENTER", 0, 170)
  lt:SetText("Level Up!")
  lt:SetTextColor(1, 0.82, 0)
  for i = 1, 3 do
    local b = CreateFrame("Button", nil, l)
    b:SetSize(460, 76)
    b:SetPoint("CENTER", 0, 100 - i * 86)
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

  -- game over
  local o = panel("over", frame)
  o.title = font(o, 40)
  o.title:SetPoint("CENTER", 0, 90)
  o.stats = font(o, 15)
  o.stats:SetPoint("TOP", o.title, "BOTTOM", 0, -20)
  o.stats:SetWidth(520)
  local again = font(o, 16)
  again:SetPoint("TOP", o.stats, "BOTTOM", 0, -28)
  again:SetText("|cff00ff00SPACE|r new run     |cffffd100ESC|r close")
end

function UI.Show(name)
  for n, p in pairs(panels) do
    if n == name then p:Show() else p:Hide() end
  end
end

function UI.Showing(name) return panels[name] and panels[name]:IsShown() end

function UI.TitleBest(db)
  local b = db.best
  if b then
    panels.title.best:SetText(string.format("Best run: %s, level %d, %d kills%s", fmtTime(b.t), b.level, b.kills, b.won and "  |cff00ff00(victory)|r" or ""))
  else
    panels.title.best:SetText("")
  end
end

function UI.LevelUp(S)
  for i = 1, 3 do
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
  panels.pause.sub:SetText(reason or "|cffffd100ESC|r resume     |cffffd100Q|r end run")
  UI.Show("pause")
end

function UI.Over(S, won, newBest)
  local o = panels.over
  o.title:SetText(won and "Victory!" or "You have fallen")
  o.title:SetTextColor(won and 0.3 or 1, won and 1 or 0.25, won and 0.3 or 0.25)
  local w = {}
  for _, x in ipairs(S.wlist) do w[#w + 1] = C.WEAPONS[x.id].name .. " " .. x.level end
  o.stats:SetText(string.format("Survived %s   Level %d   Kills %d\nDamage dealt %d\n\n%s%s",
    fmtTime(S.t), S.p.level, S.kills, floor(S.dmgDone), table.concat(w, ", "),
    newBest and "\n\n|cffffd100New best run!|r" or ""))
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
  for k = i + 1, C.WEAPON_SLOTS do slots[k]:Hide() end
  i = C.WEAPON_SLOTS
  for _, id in ipairs(S.plist) do
    i = i + 1
    slots[i].icon:SetTexture(C.PASSIVES[id].icon); slots[i].lv:SetText(S.passives[id]); slots[i]:Show()
  end
  for k = i + 1, #slots do slots[k]:Hide() end
end

function UI.HideBoss() bossBar:Hide(); banner:Hide(); banner.t = 0; hud.lv, hud.sec, hud.k, hud.sig = nil, nil, nil, nil end
