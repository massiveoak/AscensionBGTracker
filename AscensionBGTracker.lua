local ADDON_NAME = ...

local DEFAULTS = {
  fontSize = 12,
  backgroundOpacity = 0.72,
  showEmptyBrackets = true,
  scanInterval = 60,
  staleTimeout = 1200,
  width = 330,
  height = 220,
  point = "CENTER",
  relativePoint = "CENTER",
  x = 0,
  y = 0,
  visible = true,
}

local BRACKETS = {
  { min = 10, max = 19, label = "10-19" },
  { min = 20, max = 29, label = "20-29" },
  { min = 30, max = 39, label = "30-39" },
  { min = 40, max = 49, label = "40-49" },
  { min = 50, max = 59, label = "50-59" },
}

local BATTLEGROUND_ZONES = {
  ["alterac valley"] = "Alterac Valley",
  ["arathi basin"] = "Arathi Basin",
  ["arathi highlands"] = "Arathi Basin",
  ["battle for gilneas"] = "Battle for Gilneas",
  ["deepwind gorge"] = "Deepwind Gorge",
  ["eye of the storm"] = "Eye of the Storm",
  ["isle of conquest"] = "Isle of Conquest",
  ["seething shore"] = "Seething Shore",
  ["silvershard mines"] = "Silvershard Mines",
  ["strand of the ancients"] = "Strand of the Ancients",
  ["temple of kotmogu"] = "Temple of Kotmogu",
  ["the battle for gilneas"] = "Battle for Gilneas",
  ["the temple of kotmogu"] = "Temple of Kotmogu",
  ["twin peaks"] = "Twin Peaks",
  ["warsong gulch"] = "Warsong Gulch",
}

local Tracker = CreateFrame("Frame")
local observations = {}
local rows = {}
local elapsedSinceScan = 0
local lastRosterRequest = -10
local mainFrame
local settingsPanel
local controlIndex = 0

local function CopyDefaults(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil then
      target[key] = value
    end
  end
end

local function Clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then
    return minimum
  elseif value > maximum then
    return maximum
  end
  return value
end

local function Round(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function GetBracket(level)
  level = tonumber(level)
  if not level or level < 10 or level >= 60 then
    return nil
  end

  local minimum = math.floor(level / 10) * 10
  return minimum .. "-" .. (minimum + 9)
end

local function NormalizeZone(zone)
  if type(zone) ~= "string" then
    return nil
  end

  local normalized = string.lower(zone)
  normalized = string.gsub(normalized, "^%s+", "")
  normalized = string.gsub(normalized, "%s+$", "")
  return BATTLEGROUND_ZONES[normalized]
end

local function SavePosition()
  if not mainFrame then
    return
  end

  local point, _, relativePoint, x, y = mainFrame:GetPoint(1)
  AscensionBGTrackerDB.point = point or "CENTER"
  AscensionBGTrackerDB.relativePoint = relativePoint or "CENTER"
  AscensionBGTrackerDB.x = Round(x)
  AscensionBGTrackerDB.y = Round(y)
  AscensionBGTrackerDB.width = Round(mainFrame:GetWidth())
  AscensionBGTrackerDB.height = Round(mainFrame:GetHeight())
end

local function SetBackdropOpacity()
  if mainFrame then
    mainFrame:SetBackdropColor(0.035, 0.035, 0.045, AscensionBGTrackerDB.backgroundOpacity)
  end
end

local function ApplyFontSize()
  if not mainFrame then
    return
  end

  local size = AscensionBGTrackerDB.fontSize
  mainFrame.title:SetFont(STANDARD_TEXT_FONT, size + 2, "OUTLINE")
  mainFrame.status:SetFont(STANDARD_TEXT_FONT, math.max(9, size - 2))

  for _, row in ipairs(rows) do
    row.bracket:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    row.battleground:SetFont(STANDARD_TEXT_FONT, size)
    row.players:SetFont(STANDARD_TEXT_FONT, math.max(9, size - 1))
    row:SetHeight(size + 12)
  end
end

local function BuildDisplayData()
  local now = time()
  local grouped = {}

  for name, observation in pairs(observations) do
    if now - observation.lastSeen > AscensionBGTrackerDB.staleTimeout then
      observations[name] = nil
    else
      local bracketData = grouped[observation.bracket]
      if not bracketData then
        bracketData = {}
        grouped[observation.bracket] = bracketData
      end

      local battlegroundData = bracketData[observation.battleground]
      if not battlegroundData then
        battlegroundData = {}
        bracketData[observation.battleground] = battlegroundData
      end
      table.insert(battlegroundData, name)
    end
  end

  return grouped
end

local function AcquireRow(index)
  local row = rows[index]
  if row then
    return row
  end

  row = CreateFrame("Frame", nil, mainFrame.content)
  row.bracket = row:CreateFontString(nil, "OVERLAY")
  row.bracket:SetPoint("TOPLEFT", 0, 0)
  row.bracket:SetWidth(50)
  row.bracket:SetJustifyH("LEFT")

  row.battleground = row:CreateFontString(nil, "OVERLAY")
  row.battleground:SetPoint("TOPLEFT", row.bracket, "TOPRIGHT", 6, 0)
  row.battleground:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.battleground:SetJustifyH("LEFT")

  row.players = row:CreateFontString(nil, "OVERLAY")
  row.players:SetPoint("TOPLEFT", row.battleground, "BOTTOMLEFT", 0, -2)
  row.players:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.players:SetJustifyH("LEFT")
  row.players:SetTextColor(0.72, 0.72, 0.72)

  rows[index] = row
  return row
end

local function RefreshDisplay()
  if not mainFrame then
    return
  end

  local grouped = BuildDisplayData()
  local rowIndex = 0
  local activeCount = 0
  local previousRow

  for _, bracket in ipairs(BRACKETS) do
    local bracketData = grouped[bracket.label]
    local battlegroundNames = {}

    if bracketData then
      for battleground in pairs(bracketData) do
        table.insert(battlegroundNames, battleground)
      end
      table.sort(battlegroundNames)
    end

    if #battlegroundNames == 0 and AscensionBGTrackerDB.showEmptyBrackets then
      rowIndex = rowIndex + 1
      local row = AcquireRow(rowIndex)
      row:ClearAllPoints()
      if previousRow then
        row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -4)
      else
        row:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 0, 0)
      end
      row:SetPoint("RIGHT", mainFrame.content, "RIGHT", 0, 0)
      row.bracket:SetText(bracket.label)
      row.battleground:SetText("|cff777777None detected|r")
      row.players:SetText("")
      row:Show()
      previousRow = row
    else
      for battlegroundIndex, battleground in ipairs(battlegroundNames) do
        rowIndex = rowIndex + 1
        local row = AcquireRow(rowIndex)
        local playerNames = bracketData[battleground]
        table.sort(playerNames)
        activeCount = activeCount + #playerNames

        row:ClearAllPoints()
        if previousRow then
          row:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -4)
        else
          row:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 0, 0)
        end
        row:SetPoint("RIGHT", mainFrame.content, "RIGHT", 0, 0)
        row.bracket:SetText(battlegroundIndex == 1 and bracket.label or "")
        row.battleground:SetText(battleground)
        row.players:SetText(table.concat(playerNames, ", "))
        row:Show()
        previousRow = row
      end
    end
  end

  for index = rowIndex + 1, #rows do
    rows[index]:Hide()
  end

  if not IsInGuild() then
    mainFrame.status:SetText("Join a guild to begin tracking.")
  elseif activeCount == 0 then
    mainFrame.status:SetText("No leveling battlegrounds detected.")
  else
    mainFrame.status:SetText(activeCount .. " guild member" .. (activeCount == 1 and "" or "s") .. " detected")
  end

  ApplyFontSize()
end

local function ProcessGuildRoster()
  if not IsInGuild() then
    wipe(observations)
    RefreshDisplay()
    return
  end

  local now = time()
  local seenOnline = {}
  local memberCount = GetNumGuildMembers(true) or 0

  for index = 1, memberCount do
    local name, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(index)
    if name and online then
      seenOnline[name] = true
      local bracket = GetBracket(level)
      local battleground = NormalizeZone(zone)

      if bracket and battleground then
        observations[name] = {
          bracket = bracket,
          battleground = battleground,
          lastSeen = now,
        }
      else
        observations[name] = nil
      end
    end
  end

  for name in pairs(observations) do
    if not seenOnline[name] then
      observations[name] = nil
    end
  end

  RefreshDisplay()
end

local function RequestRosterScan()
  elapsedSinceScan = 0

  if not IsInGuild() then
    RefreshDisplay()
    return
  end

  local now = GetTime()
  if now - lastRosterRequest < 10 then
    return
  end

  lastRosterRequest = now
  GuildRoster()
end

local function CreateMainFrame()
  mainFrame = CreateFrame("Frame", "AscensionBGTrackerFrame", UIParent)
  mainFrame:SetFrameStrata("MEDIUM")
  mainFrame:SetClampedToScreen(true)
  mainFrame:SetMovable(true)
  mainFrame:SetResizable(true)
  mainFrame:SetMinResize(260, 150)
  mainFrame:SetMaxResize(700, 700)
  mainFrame:SetWidth(AscensionBGTrackerDB.width)
  mainFrame:SetHeight(AscensionBGTrackerDB.height)
  mainFrame:SetPoint(
    AscensionBGTrackerDB.point,
    UIParent,
    AscensionBGTrackerDB.relativePoint,
    AscensionBGTrackerDB.x,
    AscensionBGTrackerDB.y
  )
  mainFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  mainFrame:SetBackdropBorderColor(0.35, 0.35, 0.42, 0.9)
  SetBackdropOpacity()

  mainFrame.header = CreateFrame("Frame", nil, mainFrame)
  mainFrame.header:SetPoint("TOPLEFT", 8, -7)
  mainFrame.header:SetPoint("TOPRIGHT", -8, -7)
  mainFrame.header:SetHeight(22)
  mainFrame.header:EnableMouse(true)
  mainFrame.header:RegisterForDrag("LeftButton")
  mainFrame.header:SetScript("OnDragStart", function()
    mainFrame:StartMoving()
  end)
  mainFrame.header:SetScript("OnDragStop", function()
    mainFrame:StopMovingOrSizing()
    SavePosition()
  end)

  mainFrame.title = mainFrame.header:CreateFontString(nil, "OVERLAY")
  mainFrame.title:SetPoint("LEFT", 4, 0)
  mainFrame.title:SetText("Guild Battlegrounds")

  mainFrame.close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
  mainFrame.close:SetPoint("TOPRIGHT", 3, 3)
  mainFrame.close:SetScript("OnClick", function()
    AscensionBGTrackerDB.visible = false
    mainFrame:Hide()
  end)

  mainFrame.settings = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
  mainFrame.settings:SetWidth(60)
  mainFrame.settings:SetHeight(20)
  mainFrame.settings:SetPoint("RIGHT", mainFrame.close, "LEFT", -2, 0)
  mainFrame.settings:SetText("Settings")
  mainFrame.settings:SetScript("OnClick", function()
    InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    InterfaceOptionsFrame_OpenToCategory(settingsPanel)
  end)

  mainFrame.content = CreateFrame("Frame", nil, mainFrame)
  mainFrame.content:SetPoint("TOPLEFT", 12, -36)
  mainFrame.content:SetPoint("BOTTOMRIGHT", -12, 31)

  mainFrame.status = mainFrame:CreateFontString(nil, "OVERLAY")
  mainFrame.status:SetPoint("BOTTOMLEFT", 12, 11)
  mainFrame.status:SetPoint("BOTTOMRIGHT", -25, 11)
  mainFrame.status:SetJustifyH("LEFT")
  mainFrame.status:SetTextColor(0.62, 0.62, 0.68)

  mainFrame.resize = CreateFrame("Button", nil, mainFrame)
  mainFrame.resize:SetWidth(18)
  mainFrame.resize:SetHeight(18)
  mainFrame.resize:SetPoint("BOTTOMRIGHT", -3, 3)
  mainFrame.resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  mainFrame.resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  mainFrame.resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  mainFrame.resize:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
      mainFrame:StartSizing("BOTTOMRIGHT")
    end
  end)
  mainFrame.resize:SetScript("OnMouseUp", function()
    mainFrame:StopMovingOrSizing()
    SavePosition()
    RefreshDisplay()
  end)

  if AscensionBGTrackerDB.visible then
    mainFrame:Show()
  else
    mainFrame:Hide()
  end
end

local function CreateLabeledSlider(parent, label, minimum, maximum, step, top, getter, setter, format)
  controlIndex = controlIndex + 1
  local sliderName = "AscensionBGTrackerSlider" .. controlIndex
  local slider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", 20, top)
  slider:SetWidth(240)
  slider:SetMinMaxValues(minimum, maximum)
  slider:SetValueStep(step)
  slider:SetValue(getter())
  getglobal(slider:GetName() .. "Low"):SetText(tostring(minimum))
  getglobal(slider:GetName() .. "High"):SetText(tostring(maximum))
  getglobal(slider:GetName() .. "Text"):SetText(label)

  local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  input:SetWidth(55)
  input:SetHeight(20)
  input:SetPoint("TOP", slider, "BOTTOM", 0, -2)
  input:SetAutoFocus(false)
  input:SetJustifyH("CENTER")

  local updating = false
  local function Apply(value)
    value = Clamp(value, minimum, maximum)
    if step >= 1 then
      value = Round(value)
    end
    setter(value)
    input:SetText(format(value))
  end

  slider:SetScript("OnValueChanged", function(_, value)
    if updating then
      return
    end
    updating = true
    Apply(value)
    updating = false
  end)

  input:SetScript("OnEnterPressed", function(self)
    updating = true
    local value = Clamp(self:GetText(), minimum, maximum)
    if step >= 1 then
      value = Round(value)
    end
    slider:SetValue(value)
    Apply(value)
    updating = false
    self:ClearFocus()
  end)
  input:SetScript("OnEscapePressed", function(self)
    self:SetText(format(getter()))
    self:ClearFocus()
  end)

  input:SetText(format(getter()))
  return slider, input
end

local function CreateSettingsPanel()
  settingsPanel = CreateFrame("Frame", "AscensionBGTrackerSettings")
  settingsPanel.name = "Ascension BG Tracker"

  local title = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Ascension BG Tracker")

  local description = settingsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  description:SetWidth(560)
  description:SetJustifyH("LEFT")
  description:SetText("Tracks battleground zones reported for online guild members from levels 10 through 59.")

  CreateLabeledSlider(
    settingsPanel,
    "Font size",
    8,
    24,
    1,
    -95,
    function() return AscensionBGTrackerDB.fontSize end,
    function(value)
      AscensionBGTrackerDB.fontSize = value
      ApplyFontSize()
      RefreshDisplay()
    end,
    function(value) return tostring(Round(value)) end
  )

  CreateLabeledSlider(
    settingsPanel,
    "Background opacity",
    10,
    100,
    5,
    -175,
    function() return AscensionBGTrackerDB.backgroundOpacity * 100 end,
    function(value)
      AscensionBGTrackerDB.backgroundOpacity = value / 100
      SetBackdropOpacity()
    end,
    function(value) return tostring(Round(value)) end
  )

  local showEmpty = CreateFrame(
    "CheckButton",
    "AscensionBGTrackerShowEmptyBrackets",
    settingsPanel,
    "InterfaceOptionsCheckButtonTemplate"
  )
  showEmpty:SetPoint("TOPLEFT", 16, -250)
  showEmpty:SetChecked(AscensionBGTrackerDB.showEmptyBrackets)
  getglobal(showEmpty:GetName() .. "Text"):SetText("Show empty leveling brackets")
  showEmpty:SetScript("OnClick", function(self)
    AscensionBGTrackerDB.showEmptyBrackets = self:GetChecked() and true or false
    RefreshDisplay()
  end)

  CreateLabeledSlider(
    settingsPanel,
    "Guild scan interval (seconds)",
    30,
    300,
    10,
    -310,
    function() return AscensionBGTrackerDB.scanInterval end,
    function(value)
      AscensionBGTrackerDB.scanInterval = value
      elapsedSinceScan = math.min(elapsedSinceScan, value)
    end,
    function(value) return tostring(Round(value)) end
  )

  CreateLabeledSlider(
    settingsPanel,
    "Stale observation timeout (minutes)",
    5,
    30,
    1,
    -390,
    function() return AscensionBGTrackerDB.staleTimeout / 60 end,
    function(value)
      AscensionBGTrackerDB.staleTimeout = value * 60
      RefreshDisplay()
    end,
    function(value) return tostring(Round(value)) end
  )

  local reset = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
  reset:SetWidth(130)
  reset:SetHeight(22)
  reset:SetPoint("TOPLEFT", 16, -470)
  reset:SetText("Reset window")
  reset:SetScript("OnClick", function()
    AscensionBGTrackerDB.width = DEFAULTS.width
    AscensionBGTrackerDB.height = DEFAULTS.height
    AscensionBGTrackerDB.point = DEFAULTS.point
    AscensionBGTrackerDB.relativePoint = DEFAULTS.relativePoint
    AscensionBGTrackerDB.x = DEFAULTS.x
    AscensionBGTrackerDB.y = DEFAULTS.y
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetWidth(DEFAULTS.width)
    mainFrame:SetHeight(DEFAULTS.height)
    SavePosition()
  end)

  InterfaceOptions_AddCategory(settingsPanel)
end

SLASH_ASCENSIONBGTRACKER1 = "/bgt"
SLASH_ASCENSIONBGTRACKER2 = "/abgt"
SlashCmdList.ASCENSIONBGTRACKER = function(message)
  message = string.lower(message or "")
  message = string.gsub(message, "^%s+", "")
  message = string.gsub(message, "%s+$", "")

  if message == "settings" or message == "options" then
    InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    InterfaceOptionsFrame_OpenToCategory(settingsPanel)
  elseif message == "scan" then
    RequestRosterScan()
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fbfffAscension BG Tracker:|r guild roster scan requested.")
  elseif message == "reset" then
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetWidth(DEFAULTS.width)
    mainFrame:SetHeight(DEFAULTS.height)
    AscensionBGTrackerDB.visible = true
    mainFrame:Show()
    SavePosition()
  else
    AscensionBGTrackerDB.visible = not mainFrame:IsShown()
    if AscensionBGTrackerDB.visible then
      mainFrame:Show()
      RequestRosterScan()
    else
      mainFrame:Hide()
    end
  end
end

Tracker:RegisterEvent("ADDON_LOADED")
Tracker:RegisterEvent("PLAYER_GUILD_UPDATE")
Tracker:RegisterEvent("GUILD_ROSTER_UPDATE")
Tracker:SetScript("OnEvent", function(_, event, addon)
  if event == "ADDON_LOADED" and addon == ADDON_NAME then
    AscensionBGTrackerDB = AscensionBGTrackerDB or {}
    CopyDefaults(AscensionBGTrackerDB, DEFAULTS)
    AscensionBGTrackerDB.fontSize = Clamp(AscensionBGTrackerDB.fontSize, 8, 24)
    AscensionBGTrackerDB.backgroundOpacity = Clamp(AscensionBGTrackerDB.backgroundOpacity, 0.1, 1)
    AscensionBGTrackerDB.scanInterval = Clamp(AscensionBGTrackerDB.scanInterval, 30, 300)
    AscensionBGTrackerDB.staleTimeout = Clamp(AscensionBGTrackerDB.staleTimeout, 300, 1800)
    CreateMainFrame()
    CreateSettingsPanel()
    RefreshDisplay()
    RequestRosterScan()
  elseif event == "GUILD_ROSTER_UPDATE" and mainFrame then
    ProcessGuildRoster()
  elseif event == "PLAYER_GUILD_UPDATE" and mainFrame then
    RequestRosterScan()
  end
end)

Tracker:SetScript("OnUpdate", function(_, elapsed)
  if not mainFrame then
    return
  end

  elapsedSinceScan = elapsedSinceScan + elapsed
  if elapsedSinceScan >= AscensionBGTrackerDB.scanInterval then
    RequestRosterScan()
  end
end)
