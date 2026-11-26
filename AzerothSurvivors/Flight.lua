-- Azeroth Survivors on flights, the way Polestar offers Freedoom Arcade.
--
-- On a flight with SecondsLeft() at MIN_LEFT seconds or more, out of combat and outside instances, with
-- the game's window closed: once per flight a small card asks "Do you want to play Azeroth Survivors
-- while waiting?" (Play, Not now, Don't ask again: the setting off); after it, a "Play Azeroth Survivors"
-- row while the conditions hold. LANDING seconds before arrival with the window open: a raid-warning
-- banner says so and the run is saved, paused and closed so the keys are the character's again. The
-- landing itself (a loading screen ends a flight too) and a fight on the way do the same with the game
-- still open; a chat line says how to go on. Opening the game on a flight by any means starts the
-- landing guard. The card sits under Polestar's flight timer (or its Doom card) when those are shown.
--
-- Flight time: this account's own recording of that exact from -> to flight when there is one
-- (db.flightTimes, learned on every landing), else an estimate from the taxi map: straight-line
-- distance x PATH at gryphon speed. No estimate possible: the time is unknown and, as in Polestar, no
-- card is offered on that flight; the landing guard still runs for a game opened by hand.
--
-- Cost: nothing ticks on the ground. A driver frame ticks twice a second from picking a destination
-- (or boarding) until landing; the card is built on the first offer.
local _, ns = ...
local F = {}
ns.Flight = F

local MIN_LEFT = 60   -- seconds of flight left to offer the game
local LANDING = 10    -- seconds before arrival: the game is put away
local TICK = 0.5
local SPEED, STOP, PATH = 30, 2, 1.3 -- yd/s, take-off and landing seconds, path length vs straight line
local BOARD_WINDOW = 10
local MIN_FLIGHT, MAX_FLIGHT = 5, 3600
local CARD_W, PAD, BTN_H = 320, 12, 22
local TITLE = "Azeroth Survivors"
local ICON = "Interface\\Icons\\Spell_Shadow_RaiseDead"

local flight   -- { from, to, start, total, source, boarded }
local pending  -- picked at a flight master, not on the taxi yet
local trip     -- this flight's offer state { asked, warned, closedByUs }
local driver, acc = nil, 0
local card

local function P(s) print("|cffffd100Azeroth Survivors|r: " .. s) end
local function onTaxi() return UnitOnTaxi and UnitOnTaxi("player") and true or false end
local function now() return GetTime() end
local function inInstance()
  if not IsInInstance then return false end
  local inside = IsInInstance()
  return inside and true or false
end

---------------------------------------------------------------------------
-- Flight timing
---------------------------------------------------------------------------
local function routeKey(from, to) return (from or "?") .. " -> " .. (to or "?") end

-- seconds left (nil when unknown), source ("learned" | "estimate")
function F.SecondsLeft()
  if not flight or not flight.total then return nil end
  return flight.total - (now() - flight.start), flight.source
end
function F.InFlight() return flight ~= nil end

-- the taxi map's size in yards, for the straight-line estimate (nil when the client can't say)
local function taxiMapYards()
  local id = type(GetTaxiMapID) == "function" and GetTaxiMapID() or nil
  if not id or not (C_Map and C_Map.GetMapWorldSize) then return nil end
  local ok, w, h = pcall(C_Map.GetMapWorldSize, id)
  if ok and w and h and w > 0 and h > 0 then return w, h end
  return nil
end

local function onTake(slot)
  if type(NumTaxiNodes) ~= "function" or type(TaxiNodeName) ~= "function" then return end
  local to = TaxiNodeName(slot)
  local from, fi
  for i = 1, NumTaxiNodes() or 0 do
    if TaxiNodeGetType and TaxiNodeGetType(i) == "CURRENT" then from, fi = TaxiNodeName(i), i end
  end
  local est
  if fi and type(TaxiNodePosition) == "function" then
    local w, h = taxiMapYards()
    local x1, y1 = TaxiNodePosition(fi)
    local x2, y2 = TaxiNodePosition(slot)
    if w and x1 and x2 then
      local dx, dy = (x2 - x1) * w, (y2 - y1) * h
      est = math.sqrt(dx * dx + dy * dy) * PATH / SPEED + STOP
    end
  end
  pending = { from = from, to = to, est = est, at = now() }
  F.Wake()
end

local function begin()
  local p = pending
  pending = nil
  flight = { start = now(), boarded = p ~= nil }
  if p then
    flight.from, flight.to = p.from, p.to
    local learned = ns.db.flightTimes and ns.db.flightTimes[routeKey(p.from, p.to)]
    if learned then flight.total, flight.source = learned, "learned"
    elseif p.est then flight.total, flight.source = p.est, "estimate" end
  end
  if ns.db.flightOffer then F.StartTrip(false) end
end

local function land(byLoadingScreen)
  local f = flight
  flight = nil
  local elapsed = now() - f.start
  if f.boarded and f.to and not byLoadingScreen and elapsed >= MIN_FLIGHT and elapsed <= MAX_FLIGHT then
    ns.db.flightTimes = ns.db.flightTimes or {}
    ns.db.flightTimes[routeKey(f.from, f.to)] = math.floor(elapsed + 0.5)
  end
  F.Landed()
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function anchorCard()
  card:ClearAllPoints()
  local above = _G.PolestarArcadeOffer
  if not (above and above.IsShown and above:IsShown()) then above = _G.PolestarFlightTimer end
  if above and above.IsShown and above:IsShown() then
    card:SetPoint("TOP", above, "BOTTOM", 0, -6)
  else
    card:SetPoint("TOP", UIParent, "TOP", 0, -180)
  end
end

local function build()
  local f = CreateFrame("Frame", "AzerothSurvivorsFlightOffer", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetWidth(CARD_W)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.06, 0.05, 0.08, 0.95)
    f:SetBackdropBorderColor(0.75, 0.6, 0.2, 1)
  end
  f:Hide()

  local q = CreateFrame("Frame", nil, f)
  q:SetAllPoints(f)
  f.Ask = q
  q.Icon = q:CreateTexture(nil, "ARTWORK")
  q.Icon:SetSize(16, 16)
  q.Icon:SetPoint("TOPLEFT", PAD, -PAD)
  q.Icon:SetTexture(ICON)
  q.Title = q:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  q.Title:SetPoint("TOPLEFT", q.Icon, "TOPRIGHT", 8, 1)
  q.Title:SetWidth(CARD_W - 2 * PAD - 24)
  q.Title:SetJustifyH("LEFT")
  q.Title:SetText("Do you want to play Azeroth Survivors while waiting?")
  q.By = q:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  q.By:SetPoint("TOPLEFT", q.Title, "BOTTOMLEFT", 0, -3)
  q.By:SetText("Azeroth Survivors by petllama")
  q.Play = CreateFrame("Button", nil, q, "UIPanelButtonTemplate")
  q.Play:SetSize(70, BTN_H)
  q.Play:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  q.Play:SetText("Play")
  q.Play:SetScript("OnClick", function() F.Play() end)
  q.Later = CreateFrame("Button", nil, q, "UIPanelButtonTemplate")
  q.Later:SetSize(80, BTN_H)
  q.Later:SetPoint("RIGHT", q.Play, "LEFT", -6, 0)
  q.Later:SetText("Not now")
  q.Later:SetScript("OnClick", function() F.NotNow() end)
  q.Never = CreateFrame("CheckButton", nil, q, "UICheckButtonTemplate")
  q.Never:SetSize(22, 22)
  q.Never:SetPoint("BOTTOMLEFT", PAD - 4, PAD)
  q.NeverText = q:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  q.NeverText:SetPoint("LEFT", q.Never, "RIGHT", 2, 0)
  q.NeverText:SetText("Don't ask again")

  local row = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  row:SetPoint("TOPLEFT", 5, -5)
  row:SetPoint("BOTTOMRIGHT", -5, 5)
  row:SetText("Play Azeroth Survivors")
  row:SetScript("OnClick", function() F.Play() end)
  f.Row = row

  function f.Layout(self)
    q:SetShown(self.mode == "ask")
    row:SetShown(self.mode == "row")
    if self.mode == "ask" then
      local h = PAD + (q.Title:GetStringHeight() or 14) + 3 + (q.By:GetStringHeight() or 10) + 12 + BTN_H + PAD
      self:SetHeight(math.ceil(math.max(h, 78)))
    else
      self:SetHeight(BTN_H + 12)
    end
    anchorCard()
  end
  return f
end

local function show(mode)
  if not card then card = build() end
  card.mode = mode
  if mode == "ask" then card.Ask.Never:SetChecked(false) end
  card:Layout()
  card:Show()
end

local function hide()
  if card then card:Hide() end
end

function F.Card() return card end

---------------------------------------------------------------------------
-- The trip: offer, landing guard
---------------------------------------------------------------------------
local function offerable(left)
  if not (left and left >= MIN_LEFT and ns.db.flightOffer) then return false end
  if InCombatLockdown() or inInstance() then return false end
  return not ns.IsOpen()
end

function F.StartTrip(asked)
  trip = { asked = asked or false, warned = false, closedByUs = false }
  F.Wake()
end

local function stopTrip()
  trip = nil
  hide()
end

local function warn(title, text)
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, title, ChatTypeInfo["RAID_WARNING"])
    if text then pcall(RaidNotice_AddMessage, RaidWarningFrame, text, ChatTypeInfo["SYSTEM"] or ChatTypeInfo["RAID_WARNING"]) end
  end
end

local function tripTick()
  if not trip then return end
  -- off, with nothing of ours to put away: the flight is none of our business
  if not ns.db.flightOffer and not trip.closedByUs and not ns.IsOpen() then stopTrip() return end
  local left = F.SecondsLeft()
  if left and left <= LANDING then
    hide()
    if not trip.warned then
      trip.warned = true
      if ns.IsOpen() then
        local closed, saved = ns.PutAway()
        trip.closedByUs = closed
        warn("Landing in 10 seconds", closed and (saved and "Azeroth Survivors is saved and paused." or "Azeroth Survivors is paused.")
          or "Close Azeroth Survivors to get your keys back.")
      end
    end
    return
  end
  if not offerable(left) then hide() return end
  if not trip.asked then
    trip.asked = true
    show("ask")
  elseif not (card and card:IsShown() and card.mode == "ask") then
    show("row")
  end
end
F.Tick = tripTick

function F.Play()
  hide()
  if card and card.mode == "ask" and card.Ask.Never:GetChecked() then ns.db.flightOffer = false end
  F.Open()
end

function F.NotNow()
  if card and card.Ask.Never:GetChecked() then
    ns.db.flightOffer = false
    hide()
    return
  end
  show("row")
end

-- Open the game; on a flight (whatever opened it) the landing guard runs for it.
function F.Open()
  local ok = ns.Open()
  if ok and flight and not trip then F.StartTrip(true) end
  return ok
end

-- A fight on the way: saved, paused and closed.
function F.OnFight()
  if not trip then return end
  hide()
  if ns.IsOpen() then
    local closed = ns.PutAway()
    if closed then P("saved and paused for the fight: type /azs to continue.") end
  end
end

-- Landed (or a loading screen ended the flight): a game still open is put away.
function F.Landed()
  if not trip then return end
  local closedByUs = trip.closedByUs
  if ns.IsOpen() then closedByUs = ns.PutAway() or closedByUs end
  stopTrip()
  if closedByUs then P("Landed. Azeroth Survivors is saved and paused: type /azs to continue.") end
end

---------------------------------------------------------------------------
-- Driver and events
---------------------------------------------------------------------------
local function tick()
  local airborne = onTaxi()
  if flight then
    if not airborne then land(false) end
  elseif airborne then
    begin()
  elseif pending and now() - pending.at > BOARD_WINDOW then
    pending = nil
  end
  tripTick()
  if not (flight or pending or trip) then driver:Hide() end
end

function F.Wake()
  if not driver then
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
      acc = acc + dt
      if acc < TICK then return end
      acc = 0
      tick()
    end)
  end
  acc = TICK
  driver:Show()
end

function F.Init()
  if TakeTaxiNode and hooksecurefunc then hooksecurefunc("TakeTaxiNode", onTake) end
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED" }) do
    ev:RegisterEvent(e)
  end
  ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_REGEN_DISABLED" then F.OnFight() return end
    if e == "PLAYER_ENTERING_WORLD" and flight and not onTaxi() then land(true) end
    if onTaxi() or flight or pending then F.Wake() end
  end)
  if onTaxi() then F.Wake() end -- a /reload mid-flight: the time is unknown, the guard still runs
end

-- for tests
function F.State() return flight, trip, pending end
