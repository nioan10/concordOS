-- A small touch-friendly Minesweeper for ConcordOS.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end

local ROWS, COLS, MINES = 9, 9, 10
local board = {}
local initialized, lost, won = false, false, false
local cursorRow, cursorCol = 1, 1

local numberColors = {
  [1] = colors.blue, [2] = colors.green, [3] = colors.red,
  [4] = colors.purple, [5] = colors.maroon, [6] = colors.cyan,
  [7] = colors.black, [8] = colors.gray,
}

local function cell(row, col)
  return board[row] and board[row][col]
end

local function reset()
  board, initialized, lost, won = {}, false, false, false
  for row = 1, ROWS do
    board[row] = {}
    for col = 1, COLS do
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
  local candidates = {}
  for row = 1, ROWS do
    for col = 1, COLS do
      if row ~= safeRow or col ~= safeCol then candidates[#candidates + 1] = { row = row, col = col } end
    end
  end
  for index = #candidates, 2, -1 do
    local other = math.random(index)
    candidates[index], candidates[other] = candidates[other], candidates[index]
  end
  for index = 1, MINES do
    local target = candidates[index]
    cell(target.row, target.col).mine = true
  end
  for row = 1, ROWS do
    for col = 1, COLS do
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
  local opened = 0
  for row = 1, ROWS do
    for col = 1, COLS do
      local current = cell(row, col)
      if current.open and not current.mine then opened = opened + 1 end
    end
  end
  won = opened == ROWS * COLS - MINES
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
  local result = 0
  for row = 1, ROWS do
    for col = 1, COLS do if cell(row, col).flag then result = result + 1 end end
  end
  return result
end

local function geometry(target)
  local width, height = target.getSize()
  local left = math.max(1, math.floor((width - COLS * 2) / 2) + 1)
  local top = height >= 18 and 4 or 3
  return width, height, left, top
end

local function drawTarget(target)
  local width, height, left, top = geometry(target)
  ui.clear(target, colors.gray)
  if width < 20 or height < 14 then
    ui.line(target, 1, 1, width, "Сапёр", colors.white, colors.blue)
    ui.text(target, 2, 3, "Нужен экран не меньше 20x14.", colors.white, colors.gray)
    ui.text(target, 2, 5, "Esc — выход", colors.lightGray, colors.gray)
    return
  end

  ui.line(target, 1, 1, width, "ConcordOS | Сапёр", colors.white, colors.blue)
  local state = lost and "Мина!" or (won and "Победа!" or "Мин: " .. tostring(MINES - flagCount()))
  ui.line(target, 1, 2, width, state .. "   R — заново", lost and colors.red or (won and colors.lime or colors.white), colors.gray)

  for row = 1, ROWS do
    for col = 1, COLS do
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

  local footer = "ЛКМ: открыть  ПКМ/F: флаг  R: заново  Esc: выход"
  ui.line(target, 1, height, width, footer, colors.black, colors.lightGray)
end

local function draw()
  for _, target in ipairs(outputs) do drawTarget(target) end
end

local function boardPoint(target, x, y)
  local _, _, left, top = geometry(target)
  local col, row = math.floor((x - left) / 2) + 1, y - top + 1
  if row >= 1 and row <= ROWS and col >= 1 and col <= COLS then return row, col end
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
    local row, col = boardPoint(computer, b, c)
    if row then
      cursorRow, cursorCol = row, col
      if a == 1 then openCell(row, col) elseif a == 2 then toggleFlag(row, col) end
      draw()
    end
  elseif event == "monitor_touch" and a == monitorName then
    local row, col = boardPoint(monitor, b, c)
    if row then
      cursorRow, cursorCol = row, col
      openCell(row, col)
      draw()
    end
  elseif event == "key" then
    if a == keys.escape then return end
    if a == keys.r then reset()
    elseif a == keys.left then cursorCol = math.max(1, cursorCol - 1)
    elseif a == keys.right then cursorCol = math.min(COLS, cursorCol + 1)
    elseif a == keys.up then cursorRow = math.max(1, cursorRow - 1)
    elseif a == keys.down then cursorRow = math.min(ROWS, cursorRow + 1)
    elseif a == keys.f then toggleFlag(cursorRow, cursorCol)
    elseif a == keys.enter or a == keys.space then openCell(cursorRow, cursorCol)
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
