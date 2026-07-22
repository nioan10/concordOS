-- 2048: a small monitor-friendly break inside ConcordOS.
local ROOT = "/concordos"
local SCORE_PATH = ROOT .. "/data/2048.db"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end

local board, score, highScore, won = {}, 0, 0, false

local tileColors = {
  [0] = colors.gray, [2] = colors.lightGray, [4] = colors.white, [8] = colors.orange,
  [16] = colors.red, [32] = colors.pink, [64] = colors.magenta, [128] = colors.yellow,
  [256] = colors.lime, [512] = colors.green, [1024] = colors.cyan, [2048] = colors.lightBlue,
}

local function loadHighScore()
  if not fs.exists(SCORE_PATH) then return 0 end
  local file = fs.open(SCORE_PATH, "r")
  if not file then return 0 end
  local value = tonumber(file.readAll()) or 0
  file.close()
  return math.max(0, math.floor(value))
end

local function saveHighScore()
  if score <= highScore then return end
  highScore = score
  local directory = fs.getDir(SCORE_PATH)
  if not fs.exists(directory) then fs.makeDir(directory) end
  local file = fs.open(SCORE_PATH, "w")
  if file then file.write(tostring(highScore)) file.close() end
end

local function newTile()
  local empty = {}
  for row = 1, 4 do
    for col = 1, 4 do
      if board[row][col] == 0 then empty[#empty + 1] = { row = row, col = col } end
    end
  end
  if #empty == 0 then return false end
  local target = empty[math.random(#empty)]
  board[target.row][target.col] = math.random(10) == 1 and 4 or 2
  return true
end

local function reset()
  board, score, won = {}, 0, false
  for row = 1, 4 do board[row] = { 0, 0, 0, 0 } end
  newTile()
  newTile()
end

local function lineMoved(line)
  local values, result = {}, { 0, 0, 0, 0 }
  for _, value in ipairs(line) do if value ~= 0 then values[#values + 1] = value end end
  local target, index = 1, 1
  while index <= #values do
    local value = values[index]
    if values[index + 1] == value then
      value = value * 2
      score = score + value
      if value >= 2048 then won = true end
      index = index + 1
    end
    result[target] = value
    target, index = target + 1, index + 1
  end
  local changed = false
  for index = 1, 4 do if result[index] ~= line[index] then changed = true break end end
  return result, changed
end

local function move(direction)
  local changed = false
  for index = 1, 4 do
    local line = {}
    for offset = 1, 4 do
      local row, col
      if direction == "left" or direction == "right" then
        row, col = index, direction == "left" and offset or 5 - offset
      else
        row, col = direction == "up" and offset or 5 - offset, index
      end
      line[offset] = board[row][col]
    end
    local result, lineChanged = lineMoved(line)
    if lineChanged then changed = true end
    for offset = 1, 4 do
      local row, col
      if direction == "left" or direction == "right" then
        row, col = index, direction == "left" and offset or 5 - offset
      else
        row, col = direction == "up" and offset or 5 - offset, index
      end
      board[row][col] = result[offset]
    end
  end
  if changed then newTile() saveHighScore() end
  return changed
end

local function canMove()
  for row = 1, 4 do
    for col = 1, 4 do
      local value = board[row][col]
      if value == 0 then return true end
      if board[row + 1] and board[row + 1][col] == value then return true end
      if board[row][col + 1] == value then return true end
    end
  end
  return false
end

local function geometry(target)
  local width = target.getSize()
  local cellWidth, left, top = 5, math.max(2, math.floor((width - 20) / 2) + 1), 3
  return left, top, cellWidth
end

local function homeButton(target)
  local width = target.getSize()
  local size = width >= 40 and 11 or 3
  return width - size + 1, size, size == 3 and "<" or "< Главная"
end

local function drawTarget(target)
  local width, height = target.getSize()
  local left, top, cellWidth = geometry(target)
  ui.clear(target, colors.gray)
  ui.line(target, 1, 1, width, "ConcordOS | 2048 | Очки: " .. tostring(score) .. " | Рекорд: " .. tostring(math.max(highScore, score)), colors.white, colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(target)
  ui.button(target, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(target, homeX, 1, homeLabel, colors.white, colors.lightBlue)
  if width < 24 or height < 13 then
    ui.text(target, 2, 4, "Нужен экран не меньше 24x13.", colors.white, colors.gray)
    return
  end
  for row = 1, 4 do
    for col = 1, 4 do
      local value = board[row][col]
      local x, y = left + (col - 1) * cellWidth, top + row - 1
      local background = tileColors[value] or colors.lightBlue
      local text = value == 0 and "" or tostring(value)
      ui.line(target, x, y, cellWidth - 1, string.rep(" ", cellWidth - 1), colors.black, background)
      local textX = x + math.max(0, math.floor((cellWidth - 1 - #text) / 2))
      ui.text(target, textX, y, text, value >= 8 and colors.white or colors.black, background)
    end
  end
  local buttonY = top + 5
  ui.button(target, left + 7, buttonY, 3, 1, "^", colors.white, colors.blue, false)
  ui.button(target, left + 3, buttonY + 1, 3, 1, "<", colors.white, colors.blue, false)
  ui.button(target, left + 7, buttonY + 1, 3, 1, "v", colors.white, colors.blue, false)
  ui.button(target, left + 11, buttonY + 1, 3, 1, ">", colors.white, colors.blue, false)
  local state = won and "2048 собрана! Можно продолжать." or (canMove() and "Сдвигай одинаковые плитки." or "Ходов больше нет. Нажми R.")
  ui.text(target, 2, math.min(height - 2, buttonY + 3), state, won and colors.lime or colors.lightGray, colors.gray)
  ui.line(target, 1, height, width, "Стрелки/WASD или кнопки  R: новая игра  < Главная: выход", colors.black, colors.lightGray)
end

local function draw()
  for _, target in ipairs(outputs) do drawTarget(target) end
end

local function directionAt(target, x, y)
  local left, top = geometry(target)
  local buttonY = top + 5
  if y == buttonY and x >= left + 7 and x < left + 10 then return "up" end
  if y == buttonY + 1 then
    if x >= left + 3 and x < left + 6 then return "left" end
    if x >= left + 7 and x < left + 10 then return "down" end
    if x >= left + 11 and x < left + 14 then return "right" end
  end
end

local function clickedHome(target, x, y)
  local homeX, homeWidth = homeButton(target)
  return y == 1 and x >= homeX and x < homeX + homeWidth
end

math.randomseed(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000))
highScore = loadHighScore()
reset()
draw()

while true do
  local event, a, b, c = os.pullEventRaw()
  if event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    draw()
  elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
    local target, x, y = event == "monitor_touch" and monitor or computer, b, c
    if clickedHome(target, x, y) then return end
    local direction = directionAt(target, x, y)
    if direction then move(direction) draw() end
  elseif event == "key" then
    if a == keys.escape or a == keys.q then return end
    if a == keys.r then reset()
    elseif a == keys.left or a == keys.a then move("left")
    elseif a == keys.right or a == keys.d then move("right")
    elseif a == keys.up or a == keys.w then move("up")
    elseif a == keys.down or a == keys.s then move("down")
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
