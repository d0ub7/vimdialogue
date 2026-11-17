-- Key map and selection math. No game frames here, so the tests can load it.

VimDialogue = VimDialogue or {}

local Logic = {}
VimDialogue.Logic = Logic

-- Bound only while a dialogue window is open. Esc is not bound. These windows
-- are already on the game's panel stack, so Esc closes them. Binding it too
-- would also open the game menu.
-- The legend rows are the full key list. Bindings are every row except Esc.
Logic.LEGEND_ROWS = {
  { action = "next", keys = { "J", "L", "DOWN", "RIGHT" } },
  { action = "prev", keys = { "K", "H", "UP", "LEFT" } },
  { action = "confirm", keys = { "SPACE", "ENTER", "NUMPADENTER" } },
  { action = "back", keys = { "ESCAPE" } },
}

Logic.KEY_LABEL = {
  J = "j",
  L = "l",
  DOWN = "down",
  RIGHT = "right",
  K = "k",
  H = "h",
  UP = "up",
  LEFT = "left",
  SPACE = "space",
  ENTER = "enter",
  NUMPADENTER = "num enter",
  ESCAPE = "esc",
}

local bindKeys = {}
for i = 1, #Logic.LEGEND_ROWS do
  local row = Logic.LEGEND_ROWS[i]
  for k = 1, #row.keys do
    if row.keys[k] ~= "ESCAPE" then
      bindKeys[#bindKeys + 1] = row.keys[k]
    end
  end
end
Logic.BIND_KEYS = bindKeys

local ACTION = {
  J = "next",
  L = "next",
  DOWN = "next",
  RIGHT = "next",
  K = "prev",
  H = "prev",
  UP = "prev",
  LEFT = "prev",
  SPACE = "confirm",
  ENTER = "confirm",
  NUMPADENTER = "confirm",
  ESCAPE = "back",
}

function Logic.Action(key)
  if type(key) ~= "string" then
    return nil
  end
  return ACTION[key:upper()]
end

local ROW_WORD = {
  next = { default = "next", book = "next page" },
  prev = { default = "previous", book = "prev page" },
  confirm = {
    default = "select",
    detail = "accept",
    progress = "continue",
    reward = "complete",
    book = "next page",
  },
  back = {
    default = "goodbye",
    detail = "decline",
    progress = "cancel",
    reward = "cancel",
    book = "close",
  },
}

-- Rows for the legend on the open window. Words follow the window.
function Logic.Legend(mode)
  local rows = {}
  for i = 1, #Logic.LEGEND_ROWS do
    local spec = Logic.LEGEND_ROWS[i]
    local words = ROW_WORD[spec.action]
    local keys = {}
    for k = 1, #spec.keys do
      keys[k] = Logic.KEY_LABEL[spec.keys[k]] or spec.keys[k]
    end
    rows[i] = {
      action = spec.action,
      label = words[mode] or words.default,
      keys = keys,
    }
  end
  return rows
end

function Logic.ShouldBind(enabled, dialogueOpen, typing, inCombat)
  if enabled ~= true then
    return false
  end
  if dialogueOpen ~= true or typing == true or inCombat == true then
    return false
  end
  return true
end

-- Wrap so a one-option list is already on that option, and j from the last
-- row comes back to the first.
function Logic.Move(index, count, direction)
  count = tonumber(count) or 0
  if count < 1 then
    return 1
  end
  index = tonumber(index) or 1
  if index < 1 or index > count then
    index = 1
  end
  if direction == "next" then
    index = index + 1
    if index > count then
      index = 1
    end
  elseif direction == "prev" then
    index = index - 1
    if index < 1 then
      index = count
    end
  end
  return index
end

-- Keep the cursor when the same rows are redrawn. A new list starts at the top.
function Logic.KeepIndex(state, mode, keys)
  if type(keys) ~= "table" or #keys == 0 then
    return 1
  end
  if type(state) ~= "table" or state.mode ~= mode or type(state.keys) ~= "table" then
    return 1
  end
  if #state.keys ~= #keys then
    return 1
  end
  for i = 1, #keys do
    if state.keys[i] ~= keys[i] then
      return 1
    end
  end
  local index = tonumber(state.index) or 1
  if index < 1 or index > #keys then
    return 1
  end
  return index
end

function Logic.Command(text)
  if type(text) ~= "string" then
    text = ""
  end
  text = text:lower():match("^%s*(.-)%s*$") or ""
  if text == "" or text == "toggle" then
    return "toggle"
  end
  if text == "on" or text == "enable" then
    return "on"
  end
  if text == "off" or text == "disable" then
    return "off"
  end
  return "help"
end

return Logic
