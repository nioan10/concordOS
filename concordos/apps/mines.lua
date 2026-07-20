-- A small touch-friendly Minesweeper for ConcordOS.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end

local difficulties = {
  { title = "Лёгкая", short = "Лёгк.", rows = 9, cols = 9, mines = 10 },
  { title = "Средняя", short = "Сред.", rows = 12, cols = 12, mines = 24 },
  { title = "Сложная", short = "Слож.", rows = 16, cols = 16, mines = 48 },
}
local difficulty = 1
local board = {}
local initialized, lost, won = false, false, false
local cursorRow, cursorCol = 1, 1

local numberColors = {
  [1] = colors.blue, [2] = colors.green, [3] = colors.red,
  [4] = colors.purple, [5] = colors.maroon, [6] = colors.cyan,
  [7] = colors.black, [8] = colors.gray,
}

local function settings()
  return difficulties[difficulty]
end

local function cell(row, col)
  return board[row] and board[row][col]
end

local function reset()
  local level = settings()
  board, initialized, lost, won = {}, false, false, false
  cursorRow, cursorCol = 1, 1
  for row = 1, level.rows do
    board[row] = {}
    for col = 1, level.cols do
      board[row][col] = { mine = false, open = false, flag = false, nearby = 0 }
    end
  end
end

local function neighbours(row, col)
  local result = {}
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local neighbour = cell(row + dy, col + dx)
        if neighbour then result[#result + 1] = { row = row + dy, col = col + dx, cell = neighbour } end
      end
    end
  end
  return result
end

local function plantMines(safeRow, safeCol)
  local level = settings()
  local candidates = {}
  for row = 1, level.rows do
    for col = 1, level.cols do
      if row ~= safeRow or col ~= safeCol then candidates[#candidates + 1] = { row = row, col = col } end
    end
  end
  for index = #candidates, 2, -1 do
    local other = math.random(index)
    candidates[index], candidates[other] = candidates[other], candidates[index]
  end
  for index = 1, level.mines do
    local target = candidates[index]
    cell(target.row, target.col).mine = true
  end
  for row = 1, level.rows do
    for col = 1, level.cols do
      local count = 0
      for _, neighbour in ipairs(neighbours(row, col)) do if neighbour.cell.mine then count = count + 1 end end
      cell(row, col).nearby = count
    end
  end
  initialized = true
end

local function openEmpty(startRow, startCol)
  local queue, head = { { row = startRow, col = startCol } }, 1
  while queue[head] do
    local point = queue[head]
    head = head + 1
    local current = cell(point.row, point.col)
    if current and not current.open and not current.flag and not current.mine then
      current.open = true
      if current.nearby == 0 then
        for _, neighbour in ipairs(neighbours(point.row, point.col)) do
          if not neighbour.cell.open and not neighbour.cell.flag and not neighbour.cell.mine then
            queue[#queue + 1] = { row = neighbour.row, col = neighbour.col }
          end
        end
      end
    end
  end
end

local function checkWin()
  local level = settings()
  local opened = 0
  for row = 1, level.rows do
    for col = 1, level.cols do
      local current = cell(row, col)
      if current.open and not current.mine then opened = opened + 1 end
    end
  end
  won = opened == level.rows * level.cols - level.mines
end

local function openCell(row, col)
  if lost or won then return end
  local current = cell(row, col)
  if not current or current.flag then return end
  if not initialized then plantMines(row, col) end
  if current.mine then
    current.open, lost = true, true
    return
  end
  openEmpty(row, col)
  checkWin()
end

local function toggleFlag(row, col)
  if lost or won then return end
  local current = cell(row, col)
  if current and not current.open then current.flag = not current.flag end
end

local function flagCount()
  local level = settings()
  local result = 0
  for row = 1, level.rows do
    for col = 1, level.cols do if cell(row, col).flag then result = result + 1 end end
  end
  return result
end

local function geometry(target)
  local level = settings()
  local width, height = target.getSize()
  local left = math.max(1, math.floor((width - level.cols * 2) / 2) + 1)
  local top = 3
  return width, height, left, top
end

local function drawTarget(target)
  local level = settings()
  local width, height, left, top = geometry(target)
  ui.clear(target, colors.gray)
  local state = lost and "Мина!" or (won and "Победа!" or "Мин: " .. tostring(level.mines - flagCount()))
  ui.line(target, 1, 1, width, "ConcordOS | Сапёр | " .. level.title .. " | " .. state, lost and colors.red or (won and colors.lime or colors.white), colors.blue)
  local firstWidth = math.floor(width / 3)
  local secondWidth = math.floor(width / 3)
  ui.button(target, 1, 2, firstWidth, 1, difficulties[1].short, colors.white, colors.green, difficulty == 1)
  ui.button(target, firstWidth + 1, 2, secondWidth, 1, difficulties[2].short, colors.white, colors.orange, difficulty == 2)
  ui.button(target, firstWidth + secondWidth + 1, 2, width - firstWidth - secondWidth, 1, difficulties[3].short, colors.white, colors.red, difficulty == 3)
  if width < math.max(20, level.cols * 2) or height < level.rows + 3 then
    ui.text(target, 2, 4, "Для этой сложности нужен экран", colors.white, colors.gray)
    ui.text(target, 2, 5, "не меньше " .. tostring(level.cols * 2) .. "x" .. tostring(level.rows + 3) .. ".", colors.white, colors.gray)
    ui.text(target, 2, 7, "Выбери сложность 1/2/3. Esc — выход", colors.lightGray, colors.gray)
    return
  end

  for row = 1, level.rows do
    for col = 1, level.cols do
      local current = cell(row, col)
      local x, y = left + (col - 1) * 2, top + row - 1
      local foreground, background, mark = colors.white, colors.lightGray, "[]"
      if current.open or (lost and current.mine) then
        background = current.mine and colors.red or colors.gray
        if current.mine then
          mark = "* "
        elseif current.nearby > 0 then
          mark, foreground = tostring(current.nearby) .. " ", numberColors[current.nearby] or colors.white
        else
          mark = "  "
        end
      elseif current.flag then
        mark, foreground, background = "! ", colors.white, colors.orange
      end
      if row == cursorRow and col == cursorCol and not current.open and not lost and not won then background = colors.lightBlue end
      ui.text(target, x, y, mark, foreground, background, 2)
    end
  end

  local footer = "1/2/3: сложность  ЛКМ: открыть  ПКМ/F: флаг  R: заново  Esc: выход"
  ui.line(target, 1, height, width, footer, colors.black, colors.lightGray)
end

local function draw()
  for _, target in ipairs(outputs) do drawTarget(target) end
end

local function boardPoint(target, x, y)
  local level = settings()
  local _, _, left, top = geometry(target)
  local col, row = math.floor((x - left) / 2) + 1, y - top + 1
  if row >= 1 and row <= level.rows and col >= 1 and col <= level.cols then return row, col end
end

local function chooseDifficulty(target, x, y)
  if y ~= 2 then return false end
  local width = target.getSize()
  local firstWidth, secondWidth = math.floor(width / 3), math.floor(width / 3)
  local selected = x <= firstWidth and 1 or (x <= firstWidth + secondWidth and 2 or 3)
  if selected ~= difficulty then difficulty = selected end
  reset()
  return true
end

local seed = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
math.randomseed(seed)
reset()
draw()

while true do
  local event, a, b, c = os.pullEventRaw()
  if event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    draw()
  elseif event == "mouse_click" then
    if chooseDifficulty(computer, b, c) then
      draw()
    else
      local row, col = boardPoint(computer, b, c)
      if row then
        cursorRow, cursorCol = row, col
        if a == 1 then openCell(row, col) elseif a == 2 then toggleFlag(row, col) end
        draw()
      end
    end
  elseif event == "monitor_touch" and a == monitorName then
    if chooseDifficulty(monitor, b, c) then
      draw()
    else
      local row, col = boardPoint(monitor, b, c)
      if row then
        cursorRow, cursorCol = row, col
        openCell(row, col)
        draw()
      end
    end
  elseif event == "key" then
    if a == keys.escape then return end
    if a == keys.one then
      difficulty = 1
      reset()
    elseif a == keys.two then
      difficulty = 2
      reset()
    elseif a == keys.three then
      difficulty = 3
      reset()
    elseif a == keys.r then reset()
    elseif a == keys.left then cursorCol = math.max(1, cursorCol - 1)
    elseif a == keys.right then cursorCol = math.min(settings().cols, cursorCol + 1)
    elseif a == keys.up then cursorRow = math.max(1, cursorRow - 1)
    elseif a == keys.down then cursorRow = math.min(settings().rows, cursorRow + 1)
    elseif a == keys.f then toggleFlag(cursorRow, cursorCol)
    elseif a == keys.enter or a == keys.space then openCell(cursorRow, cursorCol)
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
