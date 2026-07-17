local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local ru = ui.ru
local config = dofile(ROOT .. "/system/config.lua")

local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end
local selected = 1
local page = 0
local visible = {}

local function appList()
  visible = {}
  for _, app in ipairs(config.apps) do
    if app.path == "shell" or fs.exists(app.path) then visible[#visible + 1] = app end
  end
  if selected > #visible then selected = math.max(1, #visible) end
end

local function appGeometry(output)
  local width, height = output.getSize()
  local tileWidth = math.max(16, math.floor((width - 3) / 2))
  local rows = math.max(1, math.floor((height - 5) / 4))
  return width, height, tileWidth, rows, rows * 2
end

local function pageCapacity()
  local capacity = nil
  for _, output in ipairs(outputs) do
    local _, _, _, _, count = appGeometry(output)
    capacity = capacity and math.min(capacity, count) or count
  end
  return capacity or 1
end

local function drawOutput(output, isMonitor, perPage)
  local width, height, tileWidth, rows = appGeometry(output)
  local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)

  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width, config.name .. "  " .. config.country, colors.white, colors.blue)
  ui.line(output, 1, 2, width, "Промышленная сеть | " .. config.version .. " | F5: обновить", colors.lightGray, colors.blue)

  if #visible == 0 then
    ui.text(output, 2, 5, "Приложения пока не найдены.", colors.white, colors.gray)
  end

  local start = page * perPage + 1
  for slot = 0, perPage - 1 do
    local index = start + slot
    local app = visible[index]
    if app then
      local column = slot % 2
      local row = math.floor(slot / 2)
      local x = 2 + column * (tileWidth + 1)
      local y = 4 + row * 4
      local active = index == selected
      ui.button(output, x, y, tileWidth, 3, "", colors.white, app.color, active)
      ui.text(output, x + 1, y, ru.fit(app.title, tileWidth - 2), colors.white, active and colors.lightBlue or app.color)
      ui.text(output, x + 1, y + 1, ru.fit(app.subtitle, tileWidth - 2), colors.lightGray, active and colors.lightBlue or app.color)
    end
  end

  local controls = isMonitor and "Коснись плитки  Enter: открыть  Q: терминал" or "Колесо: страницы  Enter: открыть  Q: терминал"
  local footer = "Стр. " .. tostring(page + 1) .. "/" .. tostring(maxPage + 1) .. "  " .. controls
  ui.line(output, 1, height, width, footer, colors.black, colors.lightGray)
end

local function draw()
  appList()
  local perPage = pageCapacity()
  local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)
  if page > maxPage then page = maxPage end
  for _, output in ipairs(outputs) do
    drawOutput(output, output == monitor, perPage)
  end
end

local function launch(index)
  local app = visible[index]
  if not app then return end
  computer.setCursorBlink(false)
  ui.clear(computer, colors.black)
  ui.text(computer, 1, 1, "Запуск: " .. app.title, colors.white, colors.black)
  sleep(0.15)
  local ok, err = pcall(function()
    if app.path == "shell" then
      shell.run("shell")
    else
      shell.run(app.path)
    end
  end)
  if not ok then
    ui.clear(computer, colors.black)
    ui.text(computer, 1, 1, "Ошибка запуска: " .. tostring(err), colors.red, colors.black)
    sleep(1.5)
  end
end

local function selectDelta(delta)
  if #visible == 0 then return end
  selected = math.max(1, math.min(#visible, selected + delta))
  local perPage = pageCapacity()
  page = math.floor((selected - 1) / perPage)
end

draw()
while true do
  local event, a, b, c = os.pullEventRaw()
  if event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    draw()
  elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
    local target = event == "monitor_touch" and monitor or computer
    local _, _, tileWidth, rows = appGeometry(target)
    local perPage = pageCapacity()
    local mouseX, mouseY = b, c
    for slot = 0, perPage - 1 do
      local column = slot % 2
      local row = math.floor(slot / 2)
      local x, y = 2 + column * (tileWidth + 1), 4 + row * 4
      local index = page * perPage + slot + 1
      if visible[index] and ui.inside(mouseX, mouseY, x, y, tileWidth, 3) then
        selected = index
        launch(index)
        draw()
        break
      end
    end
  elseif event == "mouse_scroll" then
    local perPage = pageCapacity()
    local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)
    page = math.max(0, math.min(maxPage, page + (a > 0 and 1 or -1)))
    selected = math.min(#visible, page * perPage + 1)
    draw()
  elseif event == "key" then
    if a == keys.enter then
      launch(selected)
      draw()
    elseif a == keys.left then selectDelta(-1) draw()
    elseif a == keys.right then selectDelta(1) draw()
    elseif a == keys.up then selectDelta(-2) draw()
    elseif a == keys.down then selectDelta(2) draw()
    elseif a == keys.f5 then draw()
    elseif a == keys.q then
      launch(1)
      draw()
    elseif a == keys.r then os.reboot()
    end
  elseif event == "terminate" then
    break
  end
end
