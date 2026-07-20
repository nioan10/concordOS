-- ConcordOS Create and ComputerCraft peripheral inspector.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end

local page = "devices"
local selected = 1
local devicePage, methodPage = 0, 0
local devices = {}

local tabs = {
  { id = "devices", label = "Устройства" },
  { id = "methods", label = "Методы" },
  { id = "guide", label = "Интеграция" },
}

local function typesOf(name)
  if peripheral.getTypes then
    local types = peripheral.getTypes(name)
    if type(types) == "table" then return types end
  end
  local kind = peripheral.getType(name)
  return kind and { kind } or {}
end

local function hasType(types, predicate)
  for _, kind in ipairs(types) do if predicate(kind) then return true end end
  return false
end

local function classify(types)
  if hasType(types, function(kind) return kind == "create_source" or kind == "create_target" or kind == "redrouter" end) then
    return "CC:C Bridge", colors.orange
  end
  if hasType(types, function(kind) return kind:find("^Create_") or kind:find("^create:") end) then
    return "Create", colors.red
  end
  if hasType(types, function(kind) return kind == "monitor" or kind == "modem" or kind == "inventory" end) then
    return "ComputerCraft", colors.blue
  end
  return "Прочее", colors.gray
end

local function scan()
  devices = {}
  for _, name in ipairs(peripheral.getNames()) do
    local types = typesOf(name)
    local methods = peripheral.getMethods(name) or {}
    table.sort(methods)
    local group, color = classify(types)
    devices[#devices + 1] = { name = name, types = types, methods = methods, group = group, color = color }
  end
  table.sort(devices, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    return a.name < b.name
  end)
  selected = math.max(1, math.min(selected, #devices))
  devicePage, methodPage = 0, 0
end

local function homeButton(target)
  local width = target.getSize()
  local buttonWidth = width >= 40 and 11 or 3
  return width - buttonWidth + 1, buttonWidth, buttonWidth == 3 and "<" or "< Главная"
end

local function tabGeometry(target)
  local width = target.getSize()
  local first = math.floor(width / 3)
  local second = math.floor(width / 3)
  return {
    { x = 1, width = first },
    { x = first + 1, width = second },
    { x = first + second + 1, width = width - first - second },
  }
end

local function rowsPerPage(target, firstRow)
  local _, height = target.getSize()
  return math.max(1, height - firstRow - 1)
end

local function drawHeader(target)
  local width = target.getSize()
  ui.line(target, 1, 1, width, "ConcordOS | Инспектор Create", colors.white, colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(target)
  ui.button(target, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(target, homeX, 1, homeLabel, colors.white, colors.lightBlue)
  local geometry = tabGeometry(target)
  for index, tab in ipairs(tabs) do
    ui.button(target, geometry[index].x, 3, geometry[index].width, 1, tab.label, colors.white, colors.gray, page == tab.id)
  end
end

local function drawDevices(target)
  local width = target.getSize()
  ui.line(target, 1, 5, width, "Найдено: " .. tostring(#devices) .. "   Клик — открыть методы   F5 — обновить", colors.lightGray, colors.gray)
  if #devices == 0 then
    ui.text(target, 2, 7, "Периферий пока нет. Подключи блок, кабель или modem.", colors.white, colors.gray)
    return
  end
  local firstRow, perPage = 6, rowsPerPage(target, 6)
  local totalPages = math.max(1, math.ceil(#devices / perPage))
  if devicePage >= totalPages then devicePage = totalPages - 1 end
  local first = devicePage * perPage + 1
  for offset = 0, perPage - 1 do
    local index = first + offset
    local item = devices[index]
    if item then
      local active = index == selected
      local label = "[" .. item.group .. "] " .. item.name .. "  ·  " .. table.concat(item.types, ", ")
      ui.line(target, 2, firstRow + offset, width - 3, label, active and colors.white or colors.lightGray, active and colors.lightBlue or (offset % 2 == 0 and colors.gray or colors.black))
    end
  end
  local _, height = target.getSize()
  ui.line(target, 1, height, width, "Стр. " .. tostring(devicePage + 1) .. "/" .. tostring(totalPages) .. "  Колесо: страницы", colors.black, colors.lightGray)
end

local function drawMethods(target)
  local width = target.getSize()
  local current = devices[selected]
  if not current then
    ui.text(target, 2, 6, "Выбери устройство во вкладке «Устройства».", colors.white, colors.gray)
    return
  end
  ui.line(target, 1, 5, width, current.name, colors.white, current.color)
  ui.line(target, 1, 6, width, "Типы: " .. table.concat(current.types, ", ") .. "  |  Методов: " .. tostring(#current.methods), colors.lightGray, colors.gray)
  local firstRow, perPage = 8, rowsPerPage(target, 8)
  local totalPages = math.max(1, math.ceil(#current.methods / perPage))
  if methodPage >= totalPages then methodPage = totalPages - 1 end
  if #current.methods == 0 then
    ui.text(target, 2, firstRow, "У этой периферии нет доступных методов.", colors.white, colors.gray)
  else
    local first = methodPage * perPage + 1
    for offset = 0, perPage - 1 do
      local method = current.methods[first + offset]
      if method then ui.line(target, 2, firstRow + offset, width - 3, method .. "()", colors.white, offset % 2 == 0 and colors.gray or colors.black) end
    end
  end
  local _, height = target.getSize()
  ui.line(target, 1, height, width, "Стр. " .. tostring(methodPage + 1) .. "/" .. tostring(totalPages) .. "  Колесо: страницы  ←: список", colors.black, colors.lightGray)
end

local guide = {
  { "Create + CC:Tweaked", colors.lightBlue },
  { "Инспектор ничего не меняет: он только читает", colors.lightGray },
  { "подключённые периферии и их реальные методы.", colors.lightGray },
  { "", colors.gray },
  { "Stock Ticker  [Create_StockTicker]", colors.red },
  { "stock() читает склад; requestFiltered() отправляет", colors.white },
  { "предмет на адрес квакопорта. Используется заявками ОС.", colors.white },
  { "", colors.gray },
  { "Redstone Requester  [Create_RedstoneRequester]", colors.orange },
  { "setAddress(), setRequest(), request(); для крафта", colors.white },
  { "есть setCraftingRequest().", colors.white },
  { "", colors.gray },
  { "Material Checklist  [create:clipboard]", colors.purple },
  { "getMissingItems() — список материалов из блокнота.", colors.white },
  { "Из него ОС создаёт «Заказ стройки».", colors.white },
  { "", colors.gray },
  { "CC:C Bridge (после установки аддона)", colors.orange },
  { "create_source — вывод на Create Display Target;", colors.white },
  { "create_target — чтение Display Source; redrouter", colors.white },
  { "— управление красным сигналом. Методы смотри здесь.", colors.white },
}

local function drawGuide(target)
  local width = target.getSize()
  local firstRow, perPage = 5, rowsPerPage(target, 5)
  local maxPage = math.max(1, math.ceil(#guide / perPage))
  if methodPage >= maxPage then methodPage = maxPage - 1 end
  local first = methodPage * perPage + 1
  for offset = 0, perPage - 1 do
    local line = guide[first + offset]
    if line then ui.line(target, 2, firstRow + offset, width - 3, line[1], line[2], offset % 2 == 0 and colors.gray or colors.black) end
  end
  local _, height = target.getSize()
  ui.line(target, 1, height, width, "Стр. " .. tostring(methodPage + 1) .. "/" .. tostring(maxPage) .. "  Колесо: страницы", colors.black, colors.lightGray)
end

local function drawTarget(target)
  ui.clear(target, colors.gray)
  drawHeader(target)
  if page == "devices" then drawDevices(target)
  elseif page == "methods" then drawMethods(target)
  else drawGuide(target) end
end

local function draw()
  for _, target in ipairs(outputs) do drawTarget(target) end
end

local function clickedHome(target, x, y)
  local homeX, homeWidth = homeButton(target)
  return y == 1 and x >= homeX and x < homeX + homeWidth
end

local function clickedTab(target, x, y)
  if y ~= 3 then return nil end
  for index, box in ipairs(tabGeometry(target)) do
    if x >= box.x and x < box.x + box.width then return tabs[index].id end
  end
end

local function selectDelta(delta, target)
  if #devices == 0 then return end
  selected = math.max(1, math.min(#devices, selected + delta))
  local perPage = rowsPerPage(target, 6)
  devicePage = math.floor((selected - 1) / perPage)
  methodPage = 0
end

scan()
draw()

while true do
  local event, a, b, c = os.pullEventRaw()
  if event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    draw()
  elseif event == "mouse_scroll" then
    local target = computer
    if page == "devices" then
      local perPage = rowsPerPage(target, 6)
      local maxPage = math.max(0, math.ceil(#devices / perPage) - 1)
      devicePage = math.max(0, math.min(maxPage, devicePage + (a > 0 and 1 or -1)))
    else
      methodPage = math.max(0, methodPage + (a > 0 and 1 or -1))
    end
    draw()
  elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
    local target, x, y = event == "monitor_touch" and monitor or computer, b, c
    if clickedHome(target, x, y) then return end
    local tab = clickedTab(target, x, y)
    if tab then
      page, methodPage = tab, 0
    elseif page == "devices" then
      local perPage = rowsPerPage(target, 6)
      local index = devicePage * perPage + y - 5
      if y >= 6 and devices[index] then
        selected, page, methodPage = index, "methods", 0
      end
    end
    draw()
  elseif event == "key" then
    if a == keys.escape or a == keys.q then return end
    if a == keys.f5 then scan()
    elseif a == keys.one then page, methodPage = "devices", 0
    elseif a == keys.two then page, methodPage = "methods", 0
    elseif a == keys.three then page, methodPage = "guide", 0
    elseif a == keys.left then page, methodPage = "devices", 0
    elseif a == keys.right and page == "devices" then page, methodPage = "methods", 0
    elseif a == keys.up and page == "devices" then selectDelta(-1, computer)
    elseif a == keys.down and page == "devices" then selectDelta(1, computer)
    elseif a == keys.enter and page == "devices" and devices[selected] then page, methodPage = "methods", 0
    elseif a == keys.pageUp then methodPage = math.max(0, methodPage - 1)
    elseif a == keys.pageDown then methodPage = methodPage + 1
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
