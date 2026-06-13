local ADDON_NAME = ...

local DEFAULTS = {
  fontSize = 12,
  bracketColor = { r = 1, g = 193 / 255, b = 105 / 255 },
  battlegroundColor = { r = 1, g = 1, b = 1 },
  playerColor = { r = 0.72, g = 0.72, b = 0.72 },
  backgroundOpacity = 0.72,
  showEmptyBrackets = true,
  showPlayerNames = true,
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
local colorControls = {}
local settingsControlRefreshers = {}

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

local function ColorToHex(r, g, b)
  return string.format(
    "#%02X%02X%02X",
    Round(Clamp(r, 0, 1) * 255),
    Round(Clamp(g, 0, 1) * 255),
    Round(Clamp(b, 0, 1) * 255)
  )
end

local function HexToColor(value)
  if type(value) ~= "string" then
    return nil
  end

  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  value = string.gsub(value, "^#", "")
  if string.len(value) ~= 6 or string.find(value, "[^%x]") then
    return nil
  end

  return
    tonumber(string.sub(value, 1, 2), 16) / 255,
    tonumber(string.sub(value, 3, 4), 16) / 255,
    tonumber(string.sub(value, 5, 6), 16) / 255
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

  local left = mainFrame:GetLeft()
  local top = mainFrame:GetTop()
  local parentTop = UIParent:GetTop()
  if left and top and parentTop then
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, top - parentTop)
    AscensionBGTrackerDB.point = "TOPLEFT"
    AscensionBGTrackerDB.relativePoint = "TOPLEFT"
    AscensionBGTrackerDB.x = Round(left)
    AscensionBGTrackerDB.y = Round(top - parentTop)
  end
  AscensionBGTrackerDB.width = Round(mainFrame:GetWidth())
  AscensionBGTrackerDB.height = Round(mainFrame:GetHeight())
end

local function SetBackdropOpacity()
  if mainFrame then
    mainFrame:SetBackdropColor(0.035, 0.035, 0.045, AscensionBGTrackerDB.backgroundOpacity)
  end
end

local function ApplyTextColors()
  local bracketColor = AscensionBGTrackerDB.bracketColor
  local battlegroundColor = AscensionBGTrackerDB.battlegroundColor
  local playerColor = AscensionBGTrackerDB.playerColor
  if mainFrame then
    mainFrame.title:SetTextColor(bracketColor.r, bracketColor.g, bracketColor.b)
    mainFrame.status:SetTextColor(playerColor.r, playerColor.g, playerColor.b)
  end

  for _, row in ipairs(rows) do
    row.bracket:SetTextColor(bracketColor.r, bracketColor.g, bracketColor.b)
    row.battleground:SetTextColor(battlegroundColor.r, battlegroundColor.g, battlegroundColor.b)
    row.players:SetTextColor(playerColor.r, playerColor.g, playerColor.b)
  end

  for key, control in pairs(colorControls) do
    local color = AscensionBGTrackerDB[key]
    control.swatchColor:SetVertexColor(color.r, color.g, color.b)
    if not control.hex:HasFocus() then
      control.hex:SetText(ColorToHex(color.r, color.g, color.b))
    end
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
  end
end

local function GetTextHeight(fontString, fallback)
  local height = fontString:GetStringHeight()
  if not height or height <= 0 then
    return fallback
  end
  return height
end

local function UpdateAutomaticHeight(rowCount)
  local size = AscensionBGTrackerDB.fontSize
  local totalRowHeight = 0

  for index = 1, rowCount do
    local row = rows[index]
    local bracketHeight = GetTextHeight(row.bracket, size)
    local battlegroundHeight = GetTextHeight(row.battleground, size)
    local rowHeight = math.max(bracketHeight, battlegroundHeight)

    if AscensionBGTrackerDB.showPlayerNames and row.players:IsShown() and row.players:GetText() ~= "" then
      local playerHeight = GetTextHeight(row.players, math.max(9, size - 1))
      rowHeight = battlegroundHeight + 2 + playerHeight
    end

    row:SetHeight(math.ceil(rowHeight))
    totalRowHeight = totalRowHeight + math.ceil(rowHeight)
  end

  if rowCount > 1 then
    totalRowHeight = totalRowHeight + ((rowCount - 1) * 4)
  end

  local headerHeight = 36
  local footerHeight = math.max(31, GetTextHeight(mainFrame.status, math.max(9, size - 2)) + 20)
  local automaticHeight = math.max(92, math.ceil(headerHeight + totalRowHeight + footerHeight))
  mainFrame:SetHeight(automaticHeight)
  AscensionBGTrackerDB.height = automaticHeight
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
  row.bracket = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.bracket:SetFont(STANDARD_TEXT_FONT, AscensionBGTrackerDB.fontSize, "OUTLINE")
  row.bracket:SetPoint("TOPLEFT", 0, 0)
  row.bracket:SetWidth(50)
  row.bracket:SetJustifyH("LEFT")

  row.battleground = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.battleground:SetFont(STANDARD_TEXT_FONT, AscensionBGTrackerDB.fontSize)
  row.battleground:SetPoint("TOPLEFT", row.bracket, "TOPRIGHT", 6, 0)
  row.battleground:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.battleground:SetJustifyH("LEFT")

  row.players = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.players:SetFont(STANDARD_TEXT_FONT, math.max(9, AscensionBGTrackerDB.fontSize - 1))
  row.players:SetPoint("TOPLEFT", row.battleground, "BOTTOMLEFT", 0, -2)
  row.players:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.players:SetJustifyH("LEFT")
  local bracketColor = AscensionBGTrackerDB.bracketColor
  local battlegroundColor = AscensionBGTrackerDB.battlegroundColor
  local playerColor = AscensionBGTrackerDB.playerColor
  row.bracket:SetTextColor(bracketColor.r, bracketColor.g, bracketColor.b)
  row.battleground:SetTextColor(battlegroundColor.r, battlegroundColor.g, battlegroundColor.b)
  row.players:SetTextColor(playerColor.r, playerColor.g, playerColor.b)

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
      row.battleground:SetText("None detected")
      row.players:SetText("")
      row.players:Hide()
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
        if AscensionBGTrackerDB.showPlayerNames then
          row.players:Show()
        else
          row.players:Hide()
        end
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
  ApplyTextColors()
  UpdateAutomaticHeight(rowIndex)
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
  mainFrame:SetFrameStrata("BACKGROUND")
  mainFrame:SetClampedToScreen(true)
  mainFrame:SetMovable(true)
  mainFrame:SetResizable(true)
  mainFrame:SetMinResize(260, 92)
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
  SavePosition()
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

  mainFrame.close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
  mainFrame.close:SetFrameLevel(mainFrame:GetFrameLevel() + 5)
  mainFrame.close:SetPoint("TOPRIGHT", -3, -3)
  mainFrame.close:SetHitRectInsets(0, 0, 0, 0)
  mainFrame.close:SetScript("OnClick", function()
    AscensionBGTrackerDB.visible = false
    mainFrame:Hide()
  end)

  mainFrame.settings = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
  mainFrame.settings:SetFrameLevel(mainFrame:GetFrameLevel() + 5)
  mainFrame.settings:SetWidth(76)
  mainFrame.settings:SetHeight(24)
  mainFrame.settings:SetPoint("TOPRIGHT", mainFrame.close, "TOPLEFT", -2, -2)
  mainFrame.settings:SetHitRectInsets(0, 0, 0, 0)
  mainFrame.settings:SetText("Settings")
  mainFrame.settings:SetScript("OnClick", function()
    InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    InterfaceOptionsFrame_OpenToCategory(settingsPanel)
  end)

  mainFrame.header = CreateFrame("Frame", nil, mainFrame)
  mainFrame.header:SetFrameLevel(mainFrame:GetFrameLevel() + 1)
  mainFrame.header:SetPoint("TOPLEFT", 8, -7)
  mainFrame.header:SetPoint("TOPRIGHT", mainFrame.settings, "TOPLEFT", -4, -2)
  mainFrame.header:SetHeight(24)
  mainFrame.header:EnableMouse(true)
  mainFrame.header:RegisterForDrag("LeftButton")
  mainFrame.header:SetScript("OnDragStart", function()
    mainFrame:StartMoving()
  end)
  mainFrame.header:SetScript("OnDragStop", function()
    mainFrame:StopMovingOrSizing()
    SavePosition()
  end)

  mainFrame.title = mainFrame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  mainFrame.title:SetFont(STANDARD_TEXT_FONT, AscensionBGTrackerDB.fontSize + 2, "OUTLINE")
  mainFrame.title:SetPoint("LEFT", 4, 0)
  mainFrame.title:SetText("Guild Battlegrounds")

  mainFrame.content = CreateFrame("Frame", nil, mainFrame)
  mainFrame.content:SetPoint("TOPLEFT", 12, -36)
  mainFrame.content:SetPoint("BOTTOMRIGHT", -12, 31)

  mainFrame.status = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mainFrame.status:SetFont(STANDARD_TEXT_FONT, math.max(9, AscensionBGTrackerDB.fontSize - 2))
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
      mainFrame:StartSizing("RIGHT")
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
  slider:SetHeight(18)

  local lowText = getglobal(slider:GetName() .. "Low")
  local highText = getglobal(slider:GetName() .. "High")
  local labelText = getglobal(slider:GetName() .. "Text")
  if lowText then
    lowText:SetFontObject(GameFontHighlightSmall)
    lowText:SetText(tostring(minimum))
  end
  if highText then
    highText:SetFontObject(GameFontHighlightSmall)
    highText:SetText(tostring(maximum))
  end
  if labelText then
    labelText:SetFontObject(GameFontNormal)
    labelText:SetText(label)
  end

  local input = CreateFrame("EditBox", nil, parent)
  input:SetWidth(64)
  input:SetHeight(24)
  input:SetPoint("TOP", slider, "BOTTOM", 0, -20)
  input:SetFontObject(ChatFontNormal)
  input:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  input:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
  input:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
  input:SetAutoFocus(false)
  input:SetJustifyH("CENTER")
  input:SetTextColor(1, 1, 1, 0)
  input:SetTextInsets(6, 6, 0, 0)
  input:SetMaxLetters(6)

  local displayedValue = input:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  displayedValue:SetPoint("CENTER", input, "CENTER", 0, 0)

  local valueLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  valueLabel:SetPoint("RIGHT", input, "LEFT", -8, 0)
  valueLabel:SetText("Value:")

  local function SetDisplayedValue(value)
    local text = format(value)
    input:SetText(text)
    displayedValue:SetText(text)
  end

  local updating = false
  local function Apply(value)
    value = Clamp(value, minimum, maximum)
    if step >= 1 then
      value = Round(value)
    end
    setter(value)
    SetDisplayedValue(value)
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
  input:SetScript("OnEditFocusGained", function(self)
    displayedValue:Hide()
    self:SetTextColor(1, 1, 1, 1)
    self:SetText(format(getter()))
    self:HighlightText()
  end)
  input:SetScript("OnEditFocusLost", function(self)
    self:SetTextColor(1, 1, 1, 0)
    SetDisplayedValue(getter())
    displayedValue:Show()
  end)
  input:SetScript("OnEscapePressed", function(self)
    SetDisplayedValue(getter())
    self:ClearFocus()
  end)

  local function RefreshControl()
    local value = getter()
    updating = true
    slider:SetValue(value)
    SetDisplayedValue(value)
    if not input:HasFocus() then
      displayedValue:Show()
    end
    updating = false
  end

  table.insert(settingsControlRefreshers, RefreshControl)
  RefreshControl()
  return slider, input
end

local function CreateColorControl(parent, labelText, colorKey, top)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("TOPLEFT", 20, top)
  label:SetWidth(150)
  label:SetJustifyH("LEFT")
  label:SetText(labelText)

  local swatch = CreateFrame("Button", nil, parent)
  swatch:SetWidth(24)
  swatch:SetHeight(24)
  swatch:SetPoint("LEFT", label, "RIGHT", 10, 0)
  swatch:SetHitRectInsets(0, 0, 0, 0)

  local border = swatch:CreateTexture(nil, "BACKGROUND")
  border:SetTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")
  border:SetAllPoints(swatch)

  local swatchColor = swatch:CreateTexture(nil, "ARTWORK")
  swatchColor:SetTexture(1, 1, 1)
  swatchColor:SetPoint("TOPLEFT", 4, -4)
  swatchColor:SetPoint("BOTTOMRIGHT", -4, 4)

  local hex = CreateFrame("EditBox", nil, parent)
  hex:SetWidth(88)
  hex:SetHeight(24)
  hex:SetPoint("LEFT", swatch, "RIGHT", 12, 0)
  hex:SetFontObject(ChatFontNormal)
  hex:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  hex:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
  hex:SetBackdropBorderColor(0.45, 0.45, 0.5, 1)
  hex:SetAutoFocus(false)
  hex:SetJustifyH("CENTER")
  hex:SetTextInsets(5, 5, 0, 0)
  hex:SetMaxLetters(7)

  local hexLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hexLabel:SetPoint("BOTTOM", hex, "TOP", 0, 3)
  hexLabel:SetText("Hex")

  colorControls[colorKey] = {
    swatchColor = swatchColor,
    hex = hex,
  }

  local function SetColor(r, g, b)
    local color = AscensionBGTrackerDB[colorKey]
    color.r = Clamp(r, 0, 1)
    color.g = Clamp(g, 0, 1)
    color.b = Clamp(b, 0, 1)
    hex:SetText(ColorToHex(color.r, color.g, color.b))
    ApplyTextColors()
  end

  swatch:SetScript("OnClick", function()
    local current = AscensionBGTrackerDB[colorKey]
    local previous = { r = current.r, g = current.g, b = current.b }

    if ColorPickerFrame:IsShown() then
      ColorPickerFrame:Hide()
    end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = previous
    ColorPickerFrame.func = function()
      SetColor(ColorPickerFrame:GetColorRGB())
    end
    ColorPickerFrame.cancelFunc = function()
      SetColor(previous.r, previous.g, previous.b)
    end
    ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)
    ShowUIPanel(ColorPickerFrame)
    ColorPickerFrame:SetFrameStrata("TOOLTIP")
    ColorPickerFrame:Raise()
  end)

  hex:SetScript("OnEnterPressed", function(self)
    local r, g, b = HexToColor(self:GetText())
    if r then
      SetColor(r, g, b)
    else
      local current = AscensionBGTrackerDB[colorKey]
      self:SetText(ColorToHex(current.r, current.g, current.b))
    end
    self:ClearFocus()
  end)
  hex:SetScript("OnEscapePressed", function(self)
    local current = AscensionBGTrackerDB[colorKey]
    self:SetText(ColorToHex(current.r, current.g, current.b))
    self:ClearFocus()
  end)

  ApplyTextColors()
end

local function CreateSettingsPanel()
  settingsPanel = CreateFrame("Frame", "AscensionBGTrackerSettings")
  settingsPanel.name = "Ascension BG Tracker"

  local scrollFrame = CreateFrame(
    "ScrollFrame",
    "AscensionBGTrackerSettingsScrollFrame",
    settingsPanel,
    "UIPanelScrollFrameTemplate"
  )
  scrollFrame:SetPoint("TOPLEFT", 4, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", -30, 8)

  local settingsContent = CreateFrame("Frame", "AscensionBGTrackerSettingsContent", scrollFrame)
  settingsContent:SetWidth(620)
  settingsContent:SetHeight(780)
  scrollFrame:SetScrollChild(settingsContent)
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll()
    local maximum = self:GetVerticalScrollRange()
    local nextValue = Clamp(current - (delta * 40), 0, maximum)
    self:SetVerticalScroll(nextValue)
  end)

  local title = settingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Ascension BG Tracker")

  local description = settingsContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  description:SetWidth(560)
  description:SetJustifyH("LEFT")
  description:SetText("Tracks battleground zones reported for online guild members from levels 10 through 59.")

  CreateLabeledSlider(
    settingsContent,
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
    settingsContent,
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
    settingsContent,
    "InterfaceOptionsCheckButtonTemplate"
  )
  showEmpty:SetPoint("TOPLEFT", 16, -250)
  showEmpty:SetChecked(AscensionBGTrackerDB.showEmptyBrackets)
  getglobal(showEmpty:GetName() .. "Text"):SetText("Show empty leveling brackets")
  showEmpty:SetScript("OnClick", function(self)
    AscensionBGTrackerDB.showEmptyBrackets = self:GetChecked() and true or false
    RefreshDisplay()
  end)

  local showPlayers = CreateFrame(
    "CheckButton",
    "AscensionBGTrackerShowPlayerNames",
    settingsContent,
    "InterfaceOptionsCheckButtonTemplate"
  )
  showPlayers:SetPoint("TOPLEFT", 16, -278)
  showPlayers:SetChecked(AscensionBGTrackerDB.showPlayerNames)
  getglobal(showPlayers:GetName() .. "Text"):SetText("Show guild character names")
  showPlayers:SetScript("OnClick", function(self)
    AscensionBGTrackerDB.showPlayerNames = self:GetChecked() and true or false
    RefreshDisplay()
  end)

  CreateLabeledSlider(
    settingsContent,
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
    settingsContent,
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

  local colorHeading = settingsContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  colorHeading:SetPoint("TOPLEFT", 20, -465)
  colorHeading:SetText("Tracker colors")

  CreateColorControl(settingsContent, "Bracket", "bracketColor", -500)
  CreateColorControl(settingsContent, "Battleground", "battlegroundColor", -535)
  CreateColorControl(settingsContent, "Character names", "playerColor", -570)

  local reset = CreateFrame("Button", nil, settingsContent, "UIPanelButtonTemplate")
  reset:SetWidth(130)
  reset:SetHeight(22)
  reset:SetPoint("TOPLEFT", 16, -620)
  reset:SetText("Reset window")
  reset:SetScript("OnClick", function()
    AscensionBGTrackerDB.width = DEFAULTS.width
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetWidth(DEFAULTS.width)
    SavePosition()
    RefreshDisplay()
  end)

  settingsPanel:SetScript("OnShow", function()
    scrollFrame:SetVerticalScroll(0)
    for _, refreshControl in ipairs(settingsControlRefreshers) do
      refreshControl()
    end
    ApplyTextColors()
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
    AscensionBGTrackerDB.visible = true
    mainFrame:Show()
    SavePosition()
    RefreshDisplay()
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
    local legacyTextColor = AscensionBGTrackerDB.textColor
    local hadBracketColor = type(AscensionBGTrackerDB.bracketColor) == "table"
    local hadBattlegroundColor = type(AscensionBGTrackerDB.battlegroundColor) == "table"
    local hadPlayerColor = type(AscensionBGTrackerDB.playerColor) == "table"
    CopyDefaults(AscensionBGTrackerDB, DEFAULTS)

    if type(legacyTextColor) == "table" then
      if not hadBracketColor then
        AscensionBGTrackerDB.bracketColor = {
          r = legacyTextColor.r,
          g = legacyTextColor.g,
          b = legacyTextColor.b,
        }
      end
      if not hadBattlegroundColor then
        AscensionBGTrackerDB.battlegroundColor = {
          r = legacyTextColor.r,
          g = legacyTextColor.g,
          b = legacyTextColor.b,
        }
      end
      if not hadPlayerColor then
        AscensionBGTrackerDB.playerColor = {
          r = legacyTextColor.r,
          g = legacyTextColor.g,
          b = legacyTextColor.b,
        }
      end
    end

    for _, key in ipairs({ "bracketColor", "battlegroundColor", "playerColor" }) do
      local color = AscensionBGTrackerDB[key]
      color.r = Clamp(color.r, 0, 1)
      color.g = Clamp(color.g, 0, 1)
      color.b = Clamp(color.b, 0, 1)
    end
    AscensionBGTrackerDB.textColor = nil
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
