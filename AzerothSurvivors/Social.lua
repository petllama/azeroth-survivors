-- Azeroth Survivors: guild leaderboard over addon messages.
-- On a run end (in a guild) one message goes to GUILD: "R1:<class>:<seconds>:<kills>:<level>:<won 0|1>".
-- 0.6: a run with Endless time or an Ascension level also sends the same line with two fields appended,
-- ":<endless seconds>:<ascension>". Clients before 0.6 match the 6-field line exactly (anchored pattern), so
-- they read the plain line and ignore the long one; 0.6 reads both and merges the extra fields into the record.
-- <seconds> is the whole run (10:00 + Endless time).
-- Received results (and our own) keep the best per player per class in db.guild[name][class].
local _, ns = ...
local C = ns.Content
local Social = {}
ns.Social = Social

local PREFIX = "AzSurv"
Social.PREFIX = PREFIX
local MIN_GAP = 10 -- seconds between two sends, on top of one send per run end
local lastSend

local function P(s) print("|cffffd100Azeroth Survivors|r: " .. s) end

-- "R1:rogue:412:3021:31:0" or "R1:rogue:754:9021:71:1:154:3" -> record, or nil when malformed
function Social.Parse(msg)
  if type(msg) ~= "string" or #msg > 64 then return nil end
  local cls, t, kills, level, won, rest = msg:match("^R1:(%l+):(%d+):(%d+):(%d+):([01])(.*)$")
  if not cls or #cls > 16 then return nil end
  local endless, asc
  if rest ~= "" then
    endless, asc = rest:match("^:(%d+):(%d+)$")
    if not endless then endless = rest:match("^:(%d+)$") end
    if not endless then return nil end
    endless, asc = tonumber(endless), tonumber(asc or 0)
    if endless > 86400 or asc > C.ASC_MAX then return nil end
  end
  t, kills, level = tonumber(t), tonumber(kills), tonumber(level)
  if t > 86400 or kills > 10000000 or level < 1 or level > 9999 then return nil end
  return { class = cls, t = t, kills = kills, level = level, won = won == "1",
    endless = endless and endless > 0 and endless or nil, asc = asc and asc > 0 and asc or nil }
end

-- the plain line every version reads; with endless/asc (0.6) the long line instead (see the top)
function Social.Format(cls, t, kills, level, won, endless, asc)
  local s = string.format("R1:%s:%d:%d:%d:%d", cls, math.floor(t), kills, level, won and 1 or 0)
  if (endless or 0) > 0 or (asc or 0) > 0 then s = s .. string.format(":%d:%d", math.floor(endless or 0), asc or 0) end
  return s
end

-- a beats b: a win, then longer survival, then more kills
local function better(a, b)
  if not b then return true end
  if a.won ~= b.won then return a.won end
  if a.t ~= b.t then return a.t > b.t end
  return a.kills > b.kills
end
Social.Better = better

function Social.Record(name, rec)
  if not name or name == "" or not rec then return false end
  local db = ns.db
  db.guild = db.guild or {}
  local mine = db.guild[name]
  if type(mine) ~= "table" then mine = {}; db.guild[name] = mine end
  local old = mine[rec.class]
  if better(rec, old) then
    mine[rec.class] = { class = rec.class, t = rec.t, kills = rec.kills, level = rec.level, won = rec.won,
      endless = rec.endless, asc = rec.asc, at = time and time() or 0 }
    return true
  end
  -- the same run again as the long line: keep its Endless time and Ascension level
  if type(old) == "table" and old.t == rec.t and old.kills == rec.kills and old.won == rec.won and (rec.endless or rec.asc) then
    old.endless, old.asc = rec.endless or old.endless, rec.asc or old.asc
    return true
  end
  return false
end

local function playerName()
  return UnitName and UnitName("player") or "me"
end

-- once at 10:00 (the win) and once more when an Endless run ends
function Social.OnRunEnd(S, won)
  if not S or S.stress then return false end
  local stage = S.endless and "endless" or "end"
  if S.sentBoard == stage or S.sentBoard == "endless" then return false end
  S.sentBoard = stage
  local endless = S.endless and math.floor(math.max(0, S.t - C.RUN_SECONDS)) or 0
  local rec = { class = S.class, t = math.floor(S.t), kills = S.kills, level = S.p.level, won = won and true or false,
    endless = endless > 0 and endless or nil, asc = (S.asc or 0) > 0 and S.asc or nil }
  Social.Record(playerName(), rec)
  if not (IsInGuild and IsInGuild()) or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  local now = GetTime()
  if lastSend and now - lastSend < MIN_GAP then return false end
  lastSend = now
  local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, Social.Format(rec.class, rec.t, rec.kills, rec.level, rec.won), "GUILD")
  if rec.endless or rec.asc then -- the long line for 0.6+ (older clients ignore it)
    ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, Social.Format(rec.class, rec.t, rec.kills, rec.level, rec.won, rec.endless, rec.asc), "GUILD") and ok
  end
  return ok
end

-- CHAT_MSG_ADDON: prefix, text, channel, sender, ...
function Social.OnMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or type(sender) ~= "string" then return false end
  local rec = Social.Parse(text)
  if not rec then return false end
  local name = Ambiguate and Ambiguate(sender, "none") or sender
  return Social.Record(name, rec)
end

-- every player's best per class, best first
function Social.Board(limit)
  local list = {}
  for name, byClass in pairs(ns.db.guild or {}) do
    if type(byClass) == "table" then
      for _, r in pairs(byClass) do
        if type(r) == "table" and r.t then
          list[#list + 1] = { name = name, class = r.class, t = r.t, kills = r.kills or 0, level = r.level or 0, won = r.won,
            endless = r.endless, asc = r.asc }
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if better(a, b) and not better(b, a) then return true end
    if better(b, a) and not better(a, b) then return false end
    return a.name < b.name
  end)
  if limit then for i = #list, limit + 1, -1 do list[i] = nil end end
  return list
end

local function className(cls)
  local cd = C.CLASSES[cls]
  return cd and cd.name or (cls:sub(1, 1):upper() .. cls:sub(2))
end
Social.ClassName = className

function Social.PrintBoard()
  local list = Social.Board(10)
  if #list == 0 then P("no guild results yet. Runs by guild members with the addon show up here.") return end
  P("guild leaderboard")
  for i, r in ipairs(list) do
    print(string.format("  %d. %s (%s%s)  %s  level %d  %d kills%s%s", i, r.name, className(r.class),
      (r.asc or 0) > 0 and (" A" .. r.asc) or "", ns.UI.FmtTime(r.t), r.level, r.kills, r.won and "  |cff00ff00victory|r" or "",
      (r.endless or 0) > 0 and string.format("  |cffff8040endless +%d:%02d|r", math.floor(r.endless / 60), r.endless % 60) or ""))
  end
end

function Social.Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
    Social.OnMessage(prefix, text, channel, sender)
  end)
end
