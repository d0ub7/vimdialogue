local source = debug.getinfo(1, "S").source:gsub("^@", "")
if source:sub(1, 1) ~= "/" then
  local pwd = assert(io.popen("pwd")):read("*l")
  source = pwd .. "/" .. source
end
local root = source:match("^(.*)/tests/run%.lua$")
if not root then
  error("could not find the repo root from " .. source)
end

local passed, failed = 0, 0

local function check(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    passed = passed + 1
    io.write(".")
  else
    failed = failed + 1
    io.write("\nFAIL ", name, "\n", err, "\n")
  end
end

local function eq(actual, expected, what)
  if actual ~= expected then
    error((what or "value") .. "\n  actual:   " .. tostring(actual) .. "\n  expected: " .. tostring(expected), 2)
  end
end

local function loadChunk(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error(err)
  end
  return chunk("VimDialogue")
end

loadChunk(root .. "/VimDialogue/Logic.lua")
assert(loadfile(root .. "/VimDialogue/Core.lua"), "Core.lua did not compile")

local Logic = VimDialogue.Logic

check("movement keys", function()
  eq(Logic.Action("j"), "next")
  eq(Logic.Action("L"), "next")
  eq(Logic.Action("down"), "next")
  eq(Logic.Action("RIGHT"), "next")
  eq(Logic.Action("k"), "prev")
  eq(Logic.Action("H"), "prev")
  eq(Logic.Action("up"), "prev")
  eq(Logic.Action("left"), "prev")
end)

check("confirm and back", function()
  eq(Logic.Action("SPACE"), "confirm")
  eq(Logic.Action("enter"), "confirm")
  eq(Logic.Action("NUMPADENTER"), "confirm")
  eq(Logic.Action("ESCAPE"), "back")
  eq(Logic.Action("F"), nil)
  eq(Logic.Action("SHIFT-J"), nil)
  eq(Logic.Action(nil), nil)
end)

check("every bound key has an action", function()
  for i = 1, #Logic.BIND_KEYS do
    local key = Logic.BIND_KEYS[i]
    if Logic.Action(key) == nil then
      error("unmapped bind key " .. key)
    end
    if key == "ESCAPE" then
      error("escape stays with the game menu")
    end
  end
  eq(Logic.Action("ESCAPE"), "back")
end)

check("one option is already selected", function()
  eq(Logic.Move(1, 1, "next"), 1)
  eq(Logic.Move(1, 1, "prev"), 1)
end)

check("j and k wrap the list", function()
  eq(Logic.Move(1, 3, "next"), 2)
  eq(Logic.Move(3, 3, "next"), 1)
  eq(Logic.Move(1, 3, "prev"), 3)
  eq(Logic.Move(2, 3, "prev"), 1)
end)

check("empty list stays put", function()
  eq(Logic.Move(4, 0, "next"), 1)
end)

check("same rows keep the cursor", function()
  local state = { mode = "gossip", keys = { "5:1", "4:2" }, index = 2 }
  eq(Logic.KeepIndex(state, "gossip", { "5:1", "4:2" }), 2)
end)

check("space keeps the reward the click picked", function()
  eq(Logic.RewardRow(1, 4, 3, nil), 3)
  eq(Logic.RewardRow(1, 4, 0, 3), 3)
  eq(Logic.RewardRow(2, 4, nil, nil), 2)
  eq(Logic.RewardRow(9, 4, 0, nil), 1)
  eq(Logic.RewardRow(1, 0, 1, 1), nil)
end)

check("a reward redraw keeps the row", function()
  local state = { mode = "reward", keys = { "choice:1", "choice:2", "choice:3" }, index = 3 }
  eq(Logic.HeldIndex(state, "quest", {}), 3)
  eq(Logic.HeldIndex(state, "reward", {}), 3)
  eq(Logic.HeldIndex(state, "reward", { "choice:1" }), 3)
  eq(Logic.HeldIndex(state, "reward", { "choice:1", "choice:2", "choice:3" }), nil)
  eq(Logic.HeldIndex(state, "gossip", {}), nil)
  eq(Logic.HeldIndex(state, "reward", { "choice:9" }), nil)
end)

check("a new list starts at the top", function()
  local state = { mode = "gossip", keys = { "5:1" }, index = 1 }
  eq(Logic.KeepIndex(state, "gossip", { "5:9", "3:4" }), 1)
  eq(Logic.KeepIndex(state, "detail", { "5:1" }), 1)
  eq(Logic.KeepIndex(state, "gossip", {}), 1)
  eq(Logic.KeepIndex(nil, "gossip", { "5:1" }), 1)
end)

check("bindings follow the window", function()
  eq(Logic.ShouldBind(true, true, false, false), true)
  eq(Logic.ShouldBind(true, false, false, false), false)
  eq(Logic.ShouldBind(false, true, false, false), false)
  eq(Logic.ShouldBind(true, true, true, false), false)
  eq(Logic.ShouldBind(true, true, false, true), false)
end)

local function joinedKeys(rows)
  local found = {}
  for i = 1, #rows do
    for k = 1, #rows[i].keys do
      found[rows[i].keys[k]] = rows[i].action
    end
  end
  return found
end

check("the legend lists every key", function()
  local rows = Logic.Legend("gossip")
  eq(#rows, 4)
  eq(rows[1].label, "next")
  eq(rows[1].keys[1], "j")
  eq(rows[1].keys[2], "l")
  eq(rows[2].label, "previous")
  eq(rows[2].keys[1], "k")
  eq(rows[2].keys[2], "h")
  eq(rows[3].label, "select")
  eq(rows[3].keys[1], "space")
  eq(rows[3].keys[2], "enter")
  eq(rows[3].keys[3], "num enter")
  eq(rows[4].label, "goodbye")
  eq(rows[4].keys[1], "esc")
  local found = joinedKeys(rows)
  for i = 1, #Logic.BIND_KEYS do
    local key = Logic.BIND_KEYS[i]
    local shown = Logic.KEY_LABEL[key]
    if found[shown] ~= Logic.Action(key) then
      error(key .. " is missing from the legend")
    end
  end
  eq(found[Logic.KEY_LABEL.ESCAPE], "back")
end)

check("legend words follow the window", function()
  local offer = Logic.Legend("detail")
  eq(offer[3].label, "accept")
  eq(offer[4].label, "decline")
  local turnin = Logic.Legend("reward")
  eq(turnin[3].label, "complete")
  eq(turnin[4].label, "cancel")
  local progress = Logic.Legend("progress")
  eq(progress[3].label, "continue")
  eq(progress[4].label, "cancel")
  local book = Logic.Legend("book")
  eq(book[1].label, "next page")
  eq(book[2].label, "prev page")
  eq(book[3].label, "next page")
  eq(book[4].label, "close")
end)

check("slash words", function()
  eq(Logic.Command(""), "toggle")
  eq(Logic.Command("  Toggle "), "toggle")
  eq(Logic.Command("on"), "on")
  eq(Logic.Command("enable"), "on")
  eq(Logic.Command("off"), "off")
  eq(Logic.Command("disable"), "off")
  eq(Logic.Command("help"), "help")
  eq(Logic.Command("nope"), "help")
end)

io.write("\n", passed, " passed, ", failed, " failed\n")
if failed > 0 then
  os.exit(1)
end
