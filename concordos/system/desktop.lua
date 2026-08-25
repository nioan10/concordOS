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

local SIDEBAR_WIDTH = 14

local function usesDashboard(output)
  local width, height = output.getSize()
  return width >= 40 and height >= 15
end

local function appGeometry(output)
  local width, height = output.getSize()
  local dashboard = usesDashboard(output)
  local ultraCompact = height < 9
  local compact = height < 14 or width < 32
  if dashboard then
    local contentWidth = width - SIDEBAR_WIDTH - 2
    local tileWidth = math.floor((contentWidth - 1) / 2)
    local featured = section == 'main' and visible[1] and visible[1].featured
    local firstY = featured and 10 or 5
    local rows = featured and 3 or 4
    local capacity = featured and (1 + rows * 2) or rows * 2
    return width, height, tileWidth, rows, capacity, firstY, 3, 2, false, false, 2
  end

  local columns = (ultraCompact or width < 32) and 1 or 2
  local tileWidth = columns == 1 and width - 2 or math.floor((width - 3) / 2)
  local firstY = ultraCompact and 2 or (compact and 3 or 4)
  local tileHeight = (ultraCompact or compact) and 1 or 2
  local step = (ultraCompact or compact) and 1 or 3
  local lastContentY = math.max(firstY, height - 1)
  local rows = math.max(1, math.floor((lastContentY - firstY + 1) / step))
  local featured = not ultraCompact and section == 'main' and visible[1] and visible[1].featured
  local capacity = featured and (1 + math.max(0, rows - 1) * columns) or rows * columns
  return width, height, tileWidth, rows, capacity, firstY, step, tileHeight, compact, ultraCompact, columns
end

local function appPosition(output, slot)
  local width, _, tileWidth, _, _, firstY, step, tileHeight, _, ultraCompact, columns = appGeometry(output)
  local dashboard = usesDashboard(output)
  local featured = section == 'main' and visible[1] and visible[1].featured
  if dashboard then
    local contentX, contentWidth = SIDEBAR_WIDTH + 2, width - SIDEBAR_WIDTH - 2
    if featured and slot == 0 then return contentX, 5, contentWidth, 3 end
    local relative = featured and slot - 1 or slot
    return contentX + (relative % 2) * (tileWidth + 1), firstY + math.floor(relative / 2) * step, tileWidth, tileHeight
  end
  if featured and not ultraCompact and slot == 0 then return 2, firstY, width - 2, tileHeight end

  local relative = featured and slot - 1 or slot
  local column = relative % columns
  local row = math.floor(relative / columns)
  return 2 + column * (tileWidth + 1), firstY + row * step, tileWidth, tileHeight
end

local function drawAppCard(output, x, y, width, height, app, active, shortcut)
  local background = active and colors.blue or colors.black
  local accent = active and colors.lightBlue or (app.color == colors.black and colors.lightGray or app.color)
  ui.fill(output, x, y, width, height, background)
  ui.fill(output, x, y, 1, height, accent)
  ui.text(output, x + 2, y, ru.fit(app.title, width - 7), colors.white, background)
  if shortcut then ui.text(output, x + width - 3, y, '[' .. tostring(shortcut) .. ']', colors.lightGray, background) end
  if height > 1 then
    ui.text(output, x + 2, y + 1, ru.fit(app.subtitle, width - 3), colors.lightGray, background)
  end
  if height > 2 then ui.line(output, x + 2, y + 2, width - 3, 'Enter или клик — открыть', accent, background) end
end

local function backButton(output)
  local width = output.getSize()
  local buttonWidth = width >= 28 and 11 or 3
  return width - buttonWidth + 1, 1, buttonWidth, buttonWidth == 3 and '<' or '< Главная'
end

local function pageCapacity()
  local capacity = nil
  for _, output in ipairs(outputs) do
    local _, _, _, _, count = appGeometry(output)
    capacity = capacity and math.min(capacity, count) or count
  end
  return capacity or 1
end

local function sectionTitle()
  return section == 'tools' and 'Инструменты' or (section == 'games' and 'Игры' or 'Главный пульт')
end

local function sidebarSectionAt(x, y)
  if x > SIDEBAR_WIDTH then return nil end
  if y == 5 then return 'main' end
  if y == 7 then return 'tools' end
  if y == 9 then return 'games' end
end

local function systemSnapshot()
  local snapshot = { ticker = peripheral.find('Create_StockTicker') ~= nil, activeGroups = 0, partialGroups = 0, standaloneActive = 0 }
  local ok, api = pcall(dofile, ROOT .. '/system/lib/orders.lua')
  if ok and api and api.overview then
    local overviewOk, overview = pcall(api.overview)
    if overviewOk and type(overview) == 'table' then
      snapshot.activeGroups = tonumber(overview.activeGroups) or 0
      snapshot.partialGroups = tonumber(overview.partialGroups) or 0
      snapshot.standaloneActive = tonumber(overview.standaloneActive) or 0
    end
  end
  return snapshot
end

local function drawSidebar(output, height, snapshot)
  ui.fill(output, 1, 2, SIDEBAR_WIDTH, height - 2, colors.black)
  ui.line(output, 2, 2, SIDEBAR_WIDTH - 2, 'CONCORDOS', colors.white, colors.black)
  ui.line(output, 2, 3, SIDEBAR_WIDTH - 2, 'НАВИГАЦИЯ', colors.lightGray, colors.black)
  local entries = {
    { id = 'main', label = 'Пульт', y = 5 },
    { id = 'tools', label = 'Сервисы', y = 7 },
    { id = 'games', label = 'Игры', y = 9 },
  }
  for _, entry in ipairs(entries) do
    local active = section == entry.id
    local background = active and colors.blue or colors.black
    ui.line(output, 2, entry.y, SIDEBAR_WIDTH - 2, (active and '> ' or '  ') .. entry.label, colors.white, background)
  end
  ui.line(output, 2, 11, SIDEBAR_WIDTH - 2, string.rep('-', SIDEBAR_WIDTH - 2), colors.darkGray, colors.black)
  if height >= 18 then
    ui.text(output, 2, 13, snapshot.ticker and 'CREATE: ON' or 'CREATE: ---', snapshot.ticker and colors.lime or colors.red, colors.black)
    local orderText = snapshot.partialGroups > 0 and ('ЧАСТЬ: ' .. tostring(snapshot.partialGroups)) or ('РАБОТА: ' .. tostring(snapshot.activeGroups))
    ui.text(output, 2, 14, orderText, snapshot.partialGroups > 0 and colors.orange or colors.lightGray, colors.black)
  end
  ui.text(output, 2, height - 3, 'Tab: раздел', colors.lightGray, colors.black)
  ui.text(output, 2, height - 2, 'R: reboot', colors.lightGray, colors.black)
  ui.text(output, 2, height - 1, 'v' .. config.version, colors.lightGray, colors.black)
end

local function drawDashboard(output, isMonitor, perPage, snapshot)
  local width, height = output.getSize()
  local contentX, contentWidth = SIDEBAR_WIDTH + 2, width - SIDEBAR_WIDTH - 2
  local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)
  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width, config.name .. '  /  ' .. config.country, colors.white, colors.blue)
  drawSidebar(output, height, snapshot)

  if section == 'main' then
    ui.text(output, contentX, 2, 'Центр управления', colors.white, colors.gray)
    ui.text(output, contentX, 3, 'Конкордат Фессалоник · промышленная сеть', colors.lightGray, colors.gray)
    local network = snapshot.ticker and 'Create подключён' or 'Create не найден'
    local ordersText = snapshot.partialGroups > 0 and ('частичных: ' .. tostring(snapshot.partialGroups)) or ('в работе: ' .. tostring(snapshot.activeGroups))
    ui.line(output, contentX, 4, contentWidth, network .. '  ·  стройзаказов ' .. ordersText .. '  ·  обычных: ' .. tostring(snapshot.standaloneActive), snapshot.partialGroups > 0 and colors.orange or (snapshot.ticker and colors.lime or colors.red), colors.gray)
    ui.line(output, contentX, 9, contentWidth, 'ОСНОВНЫЕ СИСТЕМЫ', colors.lightGray, colors.gray)
  else
    ui.text(output, contentX, 2, sectionTitle(), colors.white, colors.gray)
    ui.line(output, contentX, 3, contentWidth, ru.fit('Программ: ' .. tostring(#visible) .. '  ·  Tab: раздел  ·  Home: пульт', contentWidth, ''), colors.lightGray, colors.gray)
    ui.line(output, contentX, 4, contentWidth, snapshot.ticker and 'Create: подключён' or 'Create: нет Stock Ticker', snapshot.ticker and colors.lime or colors.red, colors.gray)
  end
  if #visible == 0 then ui.text(output, contentX, 5, 'Приложения пока не найдены.', colors.white, colors.gray) end

  local start = page * perPage + 1
  for slot = 0, perPage - 1 do
    local index = start + slot
    local app = visible[index]
    if app then
      local x, y, cardWidth, cardHeight = appPosition(output, slot)
      drawAppCard(output, x, y, cardWidth, cardHeight, app, index == selected, slot + 1)
    end
  end

  local controls
  if section == 'main' then
    controls = isMonitor and 'Клик: открыть  1–9: быстрый запуск' or '1–9: запуск  Колесо: листать  Enter: открыть  Q: терминал'
  else
    controls = isMonitor and 'Клик: открыть  Q: назад' or '1–9: запуск  Колесо: листать  Enter: открыть  Q: назад'
  end
  ui.line(output, 1, height, width, 'Стр. ' .. tostring(page + 1) .. '/' .. tostring(maxPage + 1) .. '  ' .. controls, colors.black, colors.lightGray)
end

local function drawOutput(output, isMonitor, perPage, snapshot)
  if usesDashboard(output) then
    drawDashboard(output, isMonitor, perPage, snapshot)
    return
  end

  local width, height, _, _, _, firstY, _, _, compact, ultraCompact = appGeometry(output)
  local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)
  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width, config.name .. ' / ' .. sectionTitle(), colors.white, colors.blue)
  if section ~= 'main' then
    local x, y, buttonWidth, label = backButton(output)
    ui.fill(output, x, y, buttonWidth, 1, colors.blue)
    ui.text(output, x, y, label, colors.white, colors.blue)
  end
  if not ultraCompact then ui.line(output, 1, 2, width, sectionTitle() .. '  |  v' .. config.version, colors.lightGray, colors.black) end
  if not compact and not ultraCompact then ui.line(output, 1, 3, width, 'Компактный режим', colors.lightGray, colors.gray) end
  if #visible == 0 then ui.text(output, 2, firstY, 'Приложения пока не найдены.', colors.white, colors.gray) end

  local start = page * perPage + 1
  for slot = 0, perPage - 1 do
    local index = start + slot
    local app = visible[index]
    if app then
      local x, y, cardWidth, cardHeight = appPosition(output, slot)
      drawAppCard(output, x, y, cardWidth, cardHeight, app, index == selected, slot + 1)
    end
  end
  local controls = isMonitor and 'Клик: открыть  Q: назад' or 'Колесо: листать  Enter: открыть  Q: назад'
  ui.line(output, 1, height, width, 'Стр. ' .. tostring(page + 1) .. '/' .. tostring(maxPage + 1) .. '  ' .. controls, colors.black, colors.lightGray)
end
local function draw()
  appList()
  local perPage = pageCapacity()
  local maxPage = math.max(0, math.ceil(#visible / perPage) - 1)
  if page > maxPage then page = maxPage end
  local snapshot = systemSnapshot()
  for _, output in ipairs(outputs) do
    drawOutput(output, output == monitor, perPage, snapshot)
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

local function selectVertical(delta)
  local columns = select(11, appGeometry(computer))
  selectDelta(delta * columns)
end

local function quickSlot(keyCode)
  local keysBySlot = { keys.one, keys.two, keys.three, keys.four, keys.five, keys.six, keys.seven, keys.eight, keys.nine }
  for index, code in ipairs(keysBySlot) do if keyCode == code then return index end end
end

draw()
-- A rendered desktop means the boot itself succeeded. Clear this marker here,
-- before an intentional os.reboot() can terminate all Lua programs at once.
local bootMarker = ROOT .. "/.booting"
if fs.exists(bootMarker) then fs.delete(bootMarker) end
while true do
  local event, a, b, c = os.pullEventRaw()
  if event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    draw()
  elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
    local target = event == "monitor_touch" and monitor or computer
    local perPage = pageCapacity()
    local mouseX, mouseY = b, c
    local backX, backY, backWidth = backButton(target)
    local dashboard = usesDashboard(target)
    local nextSection = dashboard and sidebarSectionAt(mouseX, mouseY) or nil
    if nextSection then
      section = nextSection
      selected = 1
      page = 0
      draw()
    elseif not dashboard and section ~= "main" and ui.inside(mouseX, mouseY, backX, backY, backWidth, 1) then
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
    local slot = quickSlot(a)
    if slot and slot <= pageCapacity() then
      local index = page * pageCapacity() + slot
      if visible[index] then
        selected = index
        launch(index)
        draw()
      end
    elseif a == keys.enter then
      launch(selected)
      draw()
    elseif a == keys.left then selectDelta(-1) draw()
    elseif a == keys.right then selectDelta(1) draw()
    elseif a == keys.up then selectVertical(-1) draw()
    elseif a == keys.down then selectVertical(1) draw()
    elseif a == keys.f5 then draw()
    elseif a == keys.tab then
      local sections = { 'main', 'tools', 'games' }
      local current = 1
      for index, id in ipairs(sections) do if section == id then current = index break end end
      section = sections[current % #sections + 1]
      selected, page = 1, 0
      draw()
    elseif a == keys.home then
      section, selected, page = 'main', 1, 0
      draw()
    elseif a == keys.backspace and section ~= 'main' then
      section, selected, page = parentSection(), 1, 0
      draw()
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
