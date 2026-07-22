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
local section = "main"

local function sectionApps()
  if section == "tools" then return config.tools end
  if section == "games" then return config.games end
  return config.mainApps
end

local function parentSection()
  return section == "games" and "tools" or "main"
end

local function hasAvailableApp(apps)
  for _, app in ipairs(apps or {}) do
    if app.path == "shell" or (app.path and fs.exists(app.path)) then return true end
  end
  return false
end

local function appList()
  visible = {}
  local source = sectionApps()
  for _, app in ipairs(source or {}) do
    local available = app.kind == "folder" and hasAvailableApp(config[app.section or app.id])
      or app.path == "shell" or (app.path and fs.exists(app.path))
    if available then visible[#visible + 1] = app end
  end
  if selected > #visible then selected = math.max(1, #visible) end
end

local function appGeometry(output)
  local width, height = output.getSize()
  local tileWidth = math.max(16, math.floor((width - 3) / 2))
  local ultraCompact = height < 12
  local compact = height < 16
  local columns = ultraCompact and 1 or 2
  local firstY = ultraCompact and 2 or (compact and 3 or 5)
  local step = ultraCompact and 1 or (compact and 3 or 4)
  local tileHeight = ultraCompact and 1 or (compact and 2 or 3)
  local rows = math.max(1, math.floor((height - firstY) / step))
  local featured = not ultraCompact and section == "main" and visible[1] and visible[1].featured
  local capacity = featured and (1 + math.max(0, rows - 1) * 2) or rows * columns
  return width, height, tileWidth, rows, capacity, firstY, step, tileHeight, compact, ultraCompact, columns
end

local function appPosition(output, slot)
  local width, _, tileWidth, _, _, firstY, step, tileHeight, _, ultraCompact, columns = appGeometry(output)
  local featured = not ultraCompact and section == "main" and visible[1] and visible[1].featured
  if featured and slot == 0 then return 2, firstY, width - 2, tileHeight end

  local relative = featured and slot - 1 or slot
  local column = relative % columns
  local row = math.floor(relative / columns)
  local y = featured and firstY + step + row * step or firstY + row * step
  local buttonWidth = columns == 1 and width - 2 or tileWidth
  return 2 + column * (tileWidth + 1), y, buttonWidth, tileHeight
end

local function backButton(output)
  local width = output.getSize()
  local buttonWidth = width >= 28 and 11 or 3
  return width - buttonWidth + 1, 1, buttonWidth, buttonWidth == 3 and "<" or "< Главная"
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
  local width, height, tileWidth, rows, _, _, _, _, compact, ultraCompact = appGeometry(output)
  local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)
  local sectionTitle = section == "tools" and "Инструменты и тесты" or (section == "games" and "Игры" or "Главный пульт")
  local sectionSubtitle = section == "tools" and "Служебные программы и диагностика"
    or (section == "games" and "Небольшие игры для отдыха" or "Заказы, производство и управление сетью")

  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width,
    ultraCompact and (config.name .. " | " .. sectionTitle) or (config.name .. " | " .. config.country),
    colors.white, colors.blue)
  if section ~= "main" then
    local x, y, buttonWidth, label = backButton(output)
    ui.button(output, x, y, buttonWidth, 1, "", colors.white, colors.blue, true)
    ui.text(output, x, y, label, colors.white, colors.lightBlue)
  end
  if not ultraCompact then
    ui.line(output, 1, 2, width, sectionTitle .. " | " .. config.version, colors.lightGray, colors.blue)
  end
  if not compact and not ultraCompact then
    ui.text(output, 2, 3, ru.fit(sectionSubtitle, width - 2), colors.lightGray, colors.gray)
  end

  if #visible == 0 then
    ui.text(output, 2, compact and 3 or 6, "Приложения пока не найдены.", colors.white, colors.gray)
  end

  local start = page * perPage + 1
  for slot = 0, perPage - 1 do
    local index = start + slot
    local app = visible[index]
    if app then
      local x, y, buttonWidth, buttonHeight = appPosition(output, slot)
      local active = index == selected
      ui.button(output, x, y, buttonWidth, buttonHeight, "", colors.white, app.color, active)
      ui.text(output, x + 1, y, ru.fit(app.title, buttonWidth - 2), colors.white, active and colors.lightBlue or app.color)
      if buttonHeight > 1 then
        ui.text(output, x + 1, y + 1, ru.fit(app.subtitle, buttonWidth - 2), colors.lightGray, active and colors.lightBlue or app.color)
      end
    end
  end

  local controls
  if section ~= "main" then
    controls = isMonitor and "Коснись: открыть  Q: назад" or "Колесо: страницы  Enter: открыть  Q: назад"
  else
    controls = isMonitor and "Коснись плитки  Enter: открыть  Q: терминал" or "Колесо: страницы  Enter: открыть  Q: терминал"
  end
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
  if app.kind == "folder" then
    section = app.section or app.id
    selected = 1
    page = 0
    return
  end
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
    local backX, backY, backWidth = backButton(target)
    if section ~= "main" and ui.inside(mouseX, mouseY, backX, backY, backWidth, 1) then
      section = parentSection()
      selected = 1
      page = 0
      draw()
    else
      for slot = 0, perPage - 1 do
        local x, y, buttonWidth, buttonHeight = appPosition(target, slot)
        local index = page * perPage + slot + 1
        if visible[index] and ui.inside(mouseX, mouseY, x, y, buttonWidth, buttonHeight) then
          selected = index
          launch(index)
          draw()
          break
        end
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
      if section ~= "main" then
        section = parentSection()
        selected = 1
        page = 0
      else
        for index, app in ipairs(visible) do
          if app.id == "terminal" then launch(index) break end
        end
      end
      draw()
    elseif a == keys.r then os.reboot()
    end
  elseif event == "terminate" then
    break
  end
end
