-- Vim keys for the gossip window, the quest window, and books.
--
-- Bindings exist only while one of those windows is open, so h j k l and
-- space keep their normal jobs the rest of the time. The game refuses to
-- change bindings during combat, so a window that closes in combat keeps the
-- keys until combat ends. The click handler then does nothing.

local Logic = VimDialogue and VimDialogue.Logic
if not Logic then
  return
end

local ADDON = ...
if type(ADDON) ~= "string" or ADDON == "" then
  ADDON = "VimDialogue"
end

VimDialogue = VimDialogue or {}
VimDialogue.version = "1.1.0"

local index = 1
local lastMode = nil
local lastKeys = nil
local bindingsOn = false
local bindPending = false
local quietUntil = 0
local applying = false
local lastLocked = nil
local hooked = false

local owner
local cursor
local legend
local watcher

local TYPE_OPTION = 3
local TYPE_ACTIVE = 4
local TYPE_AVAILABLE = 5

local HELP = {
  "j and l move down. k and h move up. Arrows do the same.",
  "Space and Enter confirm the highlighted row.",
  "Esc says goodbye, declines, or cancels.",
  "On a book, h and l turn the page. Space turns the page, then closes it.",
  "Commands: /vimdialogue on, off, toggle, help. /vd is the same.",
}

local function Print(text)
  local line = "|cffe0a030Vim Dialogue:|r " .. tostring(text or "")
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(line)
  end
end

local function DB()
  if type(VimDialogueDB) ~= "table" then
    VimDialogueDB = {}
  end
  if VimDialogueDB.enabled == nil then
    VimDialogueDB.enabled = true
  end
  return VimDialogueDB
end

local function Enabled()
  return DB().enabled == true
end

local function Shown(frame)
  return frame and frame.IsShown and frame:IsShown() and true or false
end

local function InCombat()
  return InCombatLockdown and InCombatLockdown() and true or false
end

local function Typing()
  local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  if not focus then
    return false
  end
  if focus.IsShown and not focus:IsShown() then
    return false
  end
  return true
end

local function Modified()
  if IsShiftKeyDown and IsShiftKeyDown() then
    return true
  end
  if IsControlKeyDown and IsControlKeyDown() then
    return true
  end
  if IsAltKeyDown and IsAltKeyDown() then
    return true
  end
  return false
end

local function CanClick(button)
  if not button or type(button.Click) ~= "function" then
    return false
  end
  if button.IsShown and not button:IsShown() then
    return false
  end
  if button.IsEnabled and not button:IsEnabled() then
    return false
  end
  return true
end

local function Click(button)
  if not CanClick(button) then
    return false
  end
  button:Click()
  return true
end

local function HidePanel(frame)
  if not Shown(frame) then
    return false
  end
  if HideUIPanel then
    HideUIPanel(frame)
  elseif frame.Hide then
    frame:Hide()
  end
  return true
end

local function Now()
  if GetTime then
    return GetTime()
  end
  return 0
end

local function GossipTypes()
  return _G.GOSSIP_BUTTON_TYPE_OPTION or TYPE_OPTION,
    _G.GOSSIP_BUTTON_TYPE_ACTIVE_QUEST or TYPE_ACTIVE,
    _G.GOSSIP_BUTTON_TYPE_AVAILABLE_QUEST or TYPE_AVAILABLE
end

local function Mode()
  if Shown(QuestFrame) then
    if Shown(QuestFrameGreetingPanel) then
      return "greeting"
    end
    if Shown(QuestFrameRewardPanel) then
      return "reward"
    end
    if Shown(QuestFrameDetailPanel) then
      return "detail"
    end
    if Shown(QuestFrameProgressPanel) then
      return "progress"
    end
    return "quest"
  end
  if Shown(GossipFrame) then
    return "gossip"
  end
  if Shown(ItemTextFrame) then
    return "book"
  end
  return nil
end

local function DialogueOpen()
  return Mode() ~= nil
end

local function HostFrame(mode)
  if mode == "book" then
    return ItemTextFrame
  end
  if mode == "gossip" then
    return GossipFrame
  end
  if mode == "greeting" or mode == "detail" or mode == "progress" or mode == "reward" or mode == "quest" then
    return QuestFrame
  end
  return nil
end

local function ShownPopup()
  local found
  for i = 1, 4 do
    local dialog = _G["StaticPopup" .. i]
    if Shown(dialog) then
      found = dialog
    end
  end
  return found
end

local function PopupButton(dialog, buttonIndex)
  if not dialog then
    return nil
  end
  local button = dialog["button" .. buttonIndex] or dialog["Button" .. buttonIndex]
  if not button and dialog.ButtonContainer then
    local container = dialog.ButtonContainer
    button = container["Button" .. buttonIndex] or container["button" .. buttonIndex]
  end
  if not button and dialog.GetButton then
    local ok, got = pcall(dialog.GetButton, dialog, buttonIndex)
    if ok then
      button = got
    end
  end
  if not button and dialog.GetName then
    local name = dialog:GetName()
    if name then
      button = _G[name .. "Button" .. buttonIndex]
    end
  end
  return button
end

local function CopyKeys(entries)
  local keys = {}
  for i = 1, #entries do
    keys[i] = entries[i].key
  end
  return keys
end

local function EachElement(provider, visitor)
  if not provider then
    return
  end
  if provider.ForEach then
    provider:ForEach(visitor)
    return
  end
  if provider.Enumerate then
    for _, data in provider:Enumerate() do
      visitor(data)
    end
  end
end

local function GossipKey(elementData)
  local info = elementData.info or {}
  local id = info.questID or info.gossipOptionID or info.orderIndex or info.name or "?"
  return tostring(elementData.buttonType) .. ":" .. tostring(id)
end

local function GossipEntries()
  local panel = GossipFrame and GossipFrame.GreetingPanel
  local box = panel and panel.ScrollBox
  if not box or not box.GetDataProvider then
    return {}
  end
  local optionType, activeType, availableType = GossipTypes()
  local entries = {}
  EachElement(box:GetDataProvider(), function(first, second)
    local elementData = first
    if type(elementData) ~= "table" then
      elementData = second
    end
    if type(elementData) ~= "table" then
      return
    end
    local buttonType = elementData.buttonType
    if buttonType == optionType or buttonType == activeType or buttonType == availableType then
      entries[#entries + 1] = {
        kind = "gossip",
        elementData = elementData,
        key = GossipKey(elementData),
      }
    end
  end)
  return entries
end

local function GreetingEntries()
  local panel = QuestFrameGreetingPanel
  if not panel or not panel.titleButtonPool or not panel.titleButtonPool.EnumerateActive then
    return {}
  end
  local entries = {}
  for button in panel.titleButtonPool:EnumerateActive() do
    if Shown(button) then
      local top = button.GetTop and button:GetTop() or nil
      if top == 0 then
        top = nil
      end
      entries[#entries + 1] = {
        kind = "button",
        button = button,
        top = top,
        order = #entries + 1,
        key = tostring(button.isActive) .. ":" .. tostring(button:GetID()),
      }
    end
  end
  local ready = true
  for i = 1, #entries do
    if not entries[i].top then
      ready = false
      break
    end
  end
  if ready and #entries > 1 then
    table.sort(entries, function(a, b)
      if a.top == b.top then
        return a.order < b.order
      end
      return a.top > b.top
    end)
  end
  return entries
end

local function RewardButtons()
  local frame = QuestInfoFrame and QuestInfoFrame.rewardsFrame or _G.QuestInfoRewardsFrame
  if frame and type(frame.RewardButtons) == "table" then
    return frame.RewardButtons
  end
  return nil
end

local function RewardEntries()
  local buttons = RewardButtons()
  if not buttons then
    return {}
  end
  local entries = {}
  for i = 1, #buttons do
    local button = buttons[i]
    if Shown(button) and button.type == "choice" then
      entries[#entries + 1] = {
        kind = "reward",
        button = button,
        key = "choice:" .. tostring(button:GetID()),
      }
    end
  end
  return entries
end

local function Entries(mode)
  if mode == "gossip" then
    return GossipEntries()
  end
  if mode == "greeting" then
    return GreetingEntries()
  end
  if mode == "reward" then
    return RewardEntries()
  end
  return {}
end

local function ForwardButton(mode)
  if mode == "detail" then
    return QuestFrameAcceptButton
  end
  if mode == "progress" then
    return QuestFrameCompleteButton
  end
  if mode == "reward" then
    return QuestFrameCompleteQuestButton
  end
  return nil
end

local function BackButton(mode)
  if mode == "gossip" then
    local panel = GossipFrame and GossipFrame.GreetingPanel
    return panel and panel.GoodbyeButton
  end
  if mode == "greeting" then
    return QuestFrameGreetingGoodbyeButton
  end
  if mode == "detail" then
    return QuestFrameDeclineButton
  end
  if mode == "progress" then
    return QuestFrameGoodbyeButton
  end
  return nil
end

local function ClearHighlight()
  if lastLocked and lastLocked.UnlockHighlight then
    pcall(lastLocked.UnlockHighlight, lastLocked)
  end
  lastLocked = nil
  if cursor then
    cursor:Hide()
    cursor:SetParent(UIParent)
    cursor:ClearAllPoints()
  end
end

local function ShowCursor(button, lock)
  if not cursor or not button then
    ClearHighlight()
    return
  end
  cursor:SetParent(button)
  cursor:ClearAllPoints()
  cursor:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
  cursor:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
  local level = button.GetFrameLevel and button:GetFrameLevel() or 0
  cursor:SetFrameLevel(level + 8)
  cursor:Show()
  if lastLocked and lastLocked ~= button and lastLocked.UnlockHighlight then
    pcall(lastLocked.UnlockHighlight, lastLocked)
    lastLocked = nil
  end
  -- Reward rows use the quest reward highlight. Locking those buttons paints
  -- the icon as pressed, which fights that highlight.
  if lock and button.LockHighlight and lastLocked ~= button then
    pcall(button.LockHighlight, button)
    lastLocked = button
  end
end

local function FrameForData(box, elementData)
  if not box or not elementData then
    return nil
  end
  if box.FindFrame then
    local ok, frame = pcall(box.FindFrame, box, elementData)
    if ok and Shown(frame) then
      return frame
    end
  end
  local found
  if box.ForEachFrame then
    box:ForEachFrame(function(frame)
      if found or not frame then
        return
      end
      local data = frame.elementData
      if not data and frame.GetElementData then
        data = frame:GetElementData()
      end
      if data == elementData then
        found = frame
      end
    end)
  end
  return found
end

local function GossipButton(elementData, scroll)
  local panel = GossipFrame and GossipFrame.GreetingPanel
  local box = panel and panel.ScrollBox
  local frame = FrameForData(box, elementData)
  if frame or not scroll or not box or not box.ScrollToElementData then
    return frame
  end
  pcall(box.ScrollToElementData, box, elementData)
  return FrameForData(box, elementData)
end

local function ActivateGossip(elementData)
  local frame = GossipButton(elementData, true)
  if Click(frame) then
    return true
  end
  local info = elementData.info or {}
  local optionType, activeType, availableType = GossipTypes()
  local buttonType = elementData.buttonType
  if not C_GossipInfo then
    return false
  end
  if buttonType == availableType and C_GossipInfo.SelectAvailableQuest then
    C_GossipInfo.SelectAvailableQuest(info.questID)
    return true
  end
  if buttonType == activeType and C_GossipInfo.SelectActiveQuest then
    C_GossipInfo.SelectActiveQuest(info.questID)
    return true
  end
  if buttonType == optionType and info.orderIndex and C_GossipInfo.SelectOptionByIndex then
    C_GossipInfo.SelectOptionByIndex(info.orderIndex)
    return true
  end
  if buttonType == optionType and info.gossipOptionID and C_GossipInfo.SelectOption then
    C_GossipInfo.SelectOption(info.gossipOptionID)
    return true
  end
  return false
end

local function SelectReward(button)
  if not button then
    return false
  end
  if QuestInfoItem_OnClick then
    return pcall(QuestInfoItem_OnClick, button)
  end
  return Click(button)
end

local function EntryButton(entry, scroll)
  if not entry then
    return nil
  end
  if entry.kind == "gossip" then
    return GossipButton(entry.elementData, scroll)
  end
  return entry.button
end

local function Highlight(entry, scroll, chooseReward)
  if applying then
    return
  end
  applying = true
  local button = EntryButton(entry, scroll)
  -- Selecting a reward from a passive refresh would commit that choice for a
  -- mouse click on Complete. Only the keys do that.
  if chooseReward and entry and entry.kind == "reward" and button then
    local chosen = QuestInfoFrame and QuestInfoFrame.itemChoice
    if chosen ~= button:GetID() then
      SelectReward(button)
    end
  end
  ShowCursor(button, entry and entry.kind ~= "reward")
  applying = false
end

local function Remember(mode, entries)
  index = Logic.KeepIndex({ mode = lastMode, keys = lastKeys, index = index }, mode, CopyKeys(entries))
  lastMode = mode
  lastKeys = CopyKeys(entries)
  return index
end

local function Confirm(mode, entries)
  local popup = ShownPopup()
  if popup then
    return Click(PopupButton(popup, 1))
  end
  if mode == "book" then
    if Click(_G.ItemTextNextPageButton) then
      return true
    end
    return HidePanel(ItemTextFrame)
  end
  if #entries > 0 then
    local entry = entries[index] or entries[1]
    if entry.kind == "gossip" then
      return ActivateGossip(entry.elementData)
    end
    if entry.kind == "reward" then
      local selected = SelectReward(entry.button)
      local completed = Click(ForwardButton("reward"))
      return selected or completed
    end
    return Click(entry.button)
  end
  return Click(ForwardButton(mode))
end

local function Back(mode)
  local popup = ShownPopup()
  if popup then
    if Click(PopupButton(popup, 2)) then
      return true
    end
    if popup.Hide then
      popup:Hide()
      return true
    end
    return false
  end
  if mode == "book" then
    return HidePanel(ItemTextFrame)
  end
  if Click(BackButton(mode)) then
    return true
  end
  if mode == "gossip" then
    return HidePanel(GossipFrame)
  end
  if mode == "greeting" or mode == "detail" or mode == "progress" or mode == "reward" or mode == "quest" then
    return HidePanel(QuestFrame)
  end
  return false
end

local function Move(direction)
  local mode = Mode()
  if mode == "book" then
    if direction == "next" then
      return Click(_G.ItemTextNextPageButton)
    end
    return Click(_G.ItemTextPrevPageButton)
  end
  local entries = Entries(mode)
  if #entries == 0 then
    return false
  end
  Remember(mode, entries)
  index = Logic.Move(index, #entries, direction)
  Highlight(entries[index], true, true)
  return true
end

local function Run(action)
  if not Enabled() or not DialogueOpen() or Typing() then
    return false
  end
  if action == "next" or action == "prev" then
    return Move(action)
  end
  local now = Now()
  if now < quietUntil then
    return false
  end
  local mode = Mode()
  local acted
  if action == "confirm" then
    acted = Confirm(mode, Entries(mode))
  elseif action == "back" then
    acted = Back(mode)
  end
  if acted then
    -- One press can be delivered twice. A second tap still gets through.
    quietUntil = now + 0.05
  end
  return acted and true or false
end

local function SetFallback(on)
  local frames = { GossipFrame, QuestFrame, ItemTextFrame }
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.EnableKeyboard then
      local enable = on and Shown(frame)
      if enable and not frame.questHotkeysKey then
        frame.questHotkeysKey = true
        local handler = function(self, key)
          if bindingsOn or Modified() then
            if self.SetPropagateKeyboardInput then
              self:SetPropagateKeyboardInput(true)
            end
            return
          end
          local action = Logic.Action(key)
          if not action then
            if self.SetPropagateKeyboardInput then
              self:SetPropagateKeyboardInput(true)
            end
            return
          end
          if self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(false)
          end
          Run(action)
        end
        if frame:GetScript("OnKeyDown") then
          frame:HookScript("OnKeyDown", handler)
        else
          frame:SetScript("OnKeyDown", handler)
        end
      end
      frame:EnableKeyboard(enable and true or false)
    end
  end
end

local function ApplyBindings()
  -- Override bindings are refused in combat. A window opened in combat uses
  -- the frame's own key handler instead. Bindings already in place are left
  -- alone until combat ends, because they cannot be cleared either.
  local open = Logic.ShouldBind(Enabled(), DialogueOpen(), Typing(), false)
  if InCombat() then
    bindPending = true
    if not bindingsOn then
      SetFallback(open)
    end
    return
  end
  bindPending = false
  if not owner then
    return
  end
  ClearOverrideBindings(owner)
  bindingsOn = false
  if not open then
    SetFallback(false)
    return
  end
  local name = owner:GetName()
  local applied = false
  for i = 1, #Logic.BIND_KEYS do
    local key = Logic.BIND_KEYS[i]
    if pcall(SetOverrideBindingClick, owner, true, key, name, key) then
      applied = true
    end
  end
  bindingsOn = applied
  SetFallback(not applied)
end

local LEGEND_PAD = 8
local LEGEND_GAP = 12
local LEGEND_ROW = 15

local function HideLegend()
  if not legend then
    return
  end
  legend:Hide()
  legend:SetParent(UIParent)
end

local function TextWidth(fontString, text)
  fontString:SetText(text)
  local width = fontString.GetStringWidth and fontString:GetStringWidth() or 0
  if not width or width < 1 then
    width = #tostring(text) * 6
  end
  return width
end

local function LayoutLegend(rows)
  local labelWidth, keyWidth = 0, 0
  for i = 1, #rows do
    local row = legend.rows[i]
    local keys = table.concat(rows[i].keys, "   ")
    labelWidth = math.max(labelWidth, TextWidth(row.label, rows[i].label))
    keyWidth = math.max(keyWidth, TextWidth(row.keys, keys))
    row.label:Show()
    row.keys:Show()
  end
  for i = #rows + 1, #legend.rows do
    legend.rows[i].label:Hide()
    legend.rows[i].keys:Hide()
  end
  local width = LEGEND_PAD + labelWidth + LEGEND_GAP + keyWidth + LEGEND_PAD
  local height = LEGEND_PAD + (#rows * LEGEND_ROW) + LEGEND_PAD - 2
  legend:SetSize(math.ceil(width), math.ceil(height))
  for i = 1, #rows do
    local row = legend.rows[i]
    local y = -LEGEND_PAD - ((i - 1) * LEGEND_ROW)
    row.label:ClearAllPoints()
    row.keys:ClearAllPoints()
    row.label:SetPoint("TOPRIGHT", legend, "TOPLEFT", LEGEND_PAD + labelWidth, y)
    row.keys:SetPoint("TOPLEFT", legend, "TOPLEFT", LEGEND_PAD + labelWidth + LEGEND_GAP, y)
  end
end

local function ShowLegend(mode)
  local host = HostFrame(mode)
  if not legend or not host then
    HideLegend()
    return
  end
  LayoutLegend(Logic.Legend(mode))
  -- Parent is the screen, not the dialogue. Some dialogue frames clip their
  -- children, which would hide a list drawn just outside the window.
  legend:SetParent(UIParent)
  legend:ClearAllPoints()
  local bottom = host.GetBottom and host:GetBottom()
  if bottom and bottom < (legend:GetHeight() + 12) then
    legend:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 6, 4)
  else
    legend:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 6, -4)
  end
  legend:SetFrameStrata("DIALOG")
  legend:Show()
end

local function Refresh()
  local mode = Mode()
  if not mode or not Enabled() then
    index = 1
    lastMode = nil
    lastKeys = nil
    ClearHighlight()
    HideLegend()
    ApplyBindings()
    if watcher then
      watcher:Hide()
    end
    return
  end
  if watcher then
    watcher:Show()
  end
  local entries = Entries(mode)
  Remember(mode, entries)
  if entries[index] then
    Highlight(entries[index], false)
  else
    ClearHighlight()
  end
  ShowLegend(mode)
  ApplyBindings()
end

local refreshQueued = false
local function QueueRefresh()
  Refresh()
  if refreshQueued or not C_Timer or not C_Timer.After then
    return
  end
  refreshQueued = true
  C_Timer.After(0, function()
    refreshQueued = false
    Refresh()
  end)
end

local function WatchScroll(box)
  if not box or box.questHotkeysWatch or type(box.Update) ~= "function" or not hooksecurefunc then
    return
  end
  box.questHotkeysWatch = true
  hooksecurefunc(box, "Update", function()
    if applying or not Enabled() or Mode() ~= "gossip" then
      return
    end
    local entries = GossipEntries()
    if entries[index] then
      Highlight(entries[index], false)
    end
  end)
end

local function EnsureHooks()
  if GossipFrame and GossipFrame.GreetingPanel then
    WatchScroll(GossipFrame.GreetingPanel.ScrollBox)
  end
  if hooked then
    return
  end
  local frames = { GossipFrame, QuestFrame, ItemTextFrame }
  local any = false
  for i = 1, #frames do
    local frame = frames[i]
    if frame and frame.HookScript then
      any = true
      frame:HookScript("OnShow", QueueRefresh)
      frame:HookScript("OnHide", QueueRefresh)
    end
  end
  local panels = {
    QuestFrameGreetingPanel,
    QuestFrameDetailPanel,
    QuestFrameProgressPanel,
    QuestFrameRewardPanel,
  }
  for i = 1, #panels do
    local panel = panels[i]
    if panel and panel.HookScript then
      panel:HookScript("OnShow", QueueRefresh)
    end
  end
  if any then
    hooked = true
  end
end

local function HandleClick(_, mouseButton)
  local action = Logic.Action(mouseButton)
  if not action or not Enabled() then
    return
  end
  -- Bindings can outlive the window if it closes during combat.
  if not DialogueOpen() then
    return
  end
  Run(action)
end

local function CreateOwner()
  owner = CreateFrame("Button", "VimDialogueBind", UIParent)
  owner:SetSize(1, 1)
  owner:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
  owner:EnableMouse(false)
  owner:SetAlpha(0)
  owner:RegisterForClicks("AnyDown")
  owner:SetScript("OnClick", HandleClick)
  owner:Show()
end

local function Paint(texture, r, g, b, a)
  if texture.SetColorTexture then
    texture:SetColorTexture(r, g, b, a)
    return
  end
  texture:SetTexture("Interface\\Buttons\\WHITE8x8")
  texture:SetVertexColor(r, g, b, a or 1)
end

local function CreateCursor()
  cursor = CreateFrame("Frame", nil, UIParent)
  cursor:Hide()
  cursor:EnableMouse(false)
  local fill = cursor:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  Paint(fill, 0.95, 0.76, 0.25, 0.16)
  local bar = cursor:CreateTexture(nil, "OVERLAY")
  Paint(bar, 0.95, 0.78, 0.28, 0.95)
  bar:SetPoint("TOPLEFT", cursor, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", cursor, "BOTTOMLEFT", 0, 0)
  bar:SetWidth(3)
end

local function CreateLegend()
  local template = BackdropTemplateMixin and "BackdropTemplate" or nil
  legend = CreateFrame("Frame", "VimDialogueLegend", UIParent, template)
  legend:Hide()
  legend:EnableMouse(false)
  if legend.SetBackdrop then
    legend:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    legend:SetBackdropColor(0.07, 0.06, 0.05, 0.94)
    legend:SetBackdropBorderColor(0.55, 0.40, 0.14, 1)
  else
    local bg = legend:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Paint(bg, 0.07, 0.06, 0.05, 0.94)
  end
  legend.rows = {}
  for i = 1, #Logic.LEGEND_ROWS do
    local label = legend:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local keys = legend:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetJustifyH("RIGHT")
    keys:SetJustifyH("LEFT")
    label:SetTextColor(0.80, 0.74, 0.62)
    keys:SetTextColor(1, 0.84, 0.40)
    legend.rows[i] = { label = label, keys = keys }
  end
end

local function CreateWatcher()
  watcher = CreateFrame("Frame")
  watcher:Hide()
  local wasTyping = false
  watcher:SetScript("OnUpdate", function()
    if not DialogueOpen() then
      wasTyping = false
      watcher:Hide()
      ApplyBindings()
      return
    end
    local typing = Typing()
    if typing ~= wasTyping then
      wasTyping = typing
      ApplyBindings()
    end
  end)
end

local function SetEnabled(on, announce)
  DB().enabled = on and true or false
  QueueRefresh()
  if announce then
    if DB().enabled then
      Print("On. " .. HELP[1])
    else
      Print("Off.")
    end
  end
end

local function Slash(text)
  local command = Logic.Command(text)
  if command == "toggle" then
    SetEnabled(not Enabled(), true)
    return
  end
  if command == "on" then
    SetEnabled(true, true)
    return
  end
  if command == "off" then
    SetEnabled(false, true)
    return
  end
  Print(HELP[1])
  Print(HELP[2])
  Print(HELP[3])
  Print(HELP[4])
  Print(HELP[5])
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("GOSSIP_CLOSED")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_FINISHED")
events:RegisterEvent("QUEST_ITEM_UPDATE")
events:RegisterEvent("ITEM_TEXT_READY")
events:RegisterEvent("ITEM_TEXT_CLOSED")

events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name ~= ADDON and name ~= "VimDialogue" then
      return
    end
    DB()
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if bindPending or not DialogueOpen() then
      ApplyBindings()
    end
    return
  end
  EnsureHooks()
  QueueRefresh()
end)

CreateOwner()
CreateCursor()
CreateLegend()
CreateWatcher()

SLASH_VIMDIALOGUE1 = "/vimdialogue"
SLASH_VIMDIALOGUE2 = "/vd"
SlashCmdList.VIMDIALOGUE = Slash
