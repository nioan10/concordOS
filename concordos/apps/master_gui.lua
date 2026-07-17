-- Touch/mouse friendly graphical front-end for ConcordOS industrial orders.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local ru = ui.ru
local orders = dofile(ROOT .. "/system/lib/orders.lua")
local output = term.current()

local page = "order"
local activeField = "address"
local fields = { address = "", item = "", amount = "", search = "" }
local stockResults = {}
local confirmation = false
local statusText, statusColor = "Готово к работе", colors.lightGray
local refreshTimer = nil

local tabs = {
  { id = "order", label = "Заказать" },
  { id = "orders", label = "Заявки" },
  { id = "stock", label = "Склад" },
  { id = "network", label = "Сеть" },
}

local function setStatus(text, color)
  statusText, statusColor = tostring(text or ""), color or colors.lightGray
end

local function parseQuantity(value)
  local text = ru.lower(tostring(value or ""):match("^%s*(.-)%s*$"))
  local stacks = text:match("^(%d+)%s*[сc]")
  if stacks then return tonumber(stacks) * 64 end
  local count = tonumber(text)
  return count and math.floor(count) or nil
end

local function formatQuantity(count)
  count = tonumber(count) or 0
  local stacks, remainder = math.floor(count / 64), count % 64
  if stacks > 0 and remainder == 0 then return tostring(count) .. " (" .. tostring(stacks) .. " ст.)" end
  if stacks > 0 then return tostring(count) .. " (" .. tostring(stacks) .. "+" .. tostring(remainder) .. ")" end
  return tostring(count)
end

local function itemName(item)
  if type(item) ~= "table" then return nil end
  return item.name or item.id or (type(item.item) == "table" and item.item.name)
end

local function itemCount(item)
  if type(item) ~= "table" then return 0 end
  return tonumber(item.count or item.amount or item.quantity or item.total) or 0
end

local function getTicker()
  return peripheral.find("Create_StockTicker")
end

local function availableCount(name)
  local ticker = getTicker()
  if not ticker then return nil end
  local ok, stock = pcall(ticker.stock, false)
  if not ok or type(stock) ~= "table" then return nil end
  local total = 0
  for _, item in ipairs(stock) do
    if itemName(item) == name then total = total + itemCount(item) end
  end
  return total
end

local function inputBox(x, y, width, label, value, selected)
  ui.text(output, x, y, label, colors.lightGray, colors.gray)
  local background = selected and colors.blue or colors.black
  local suffix = selected and "|" or ""
  ui.line(output, x, y + 1, width, ru.fit(value .. suffix, width, ""), colors.white, background)
end

local function drawHeader(width)
  ui.line(output, 1, 1, width, "ConcordOS | Мастер промзоны", colors.white, colors.blue)
  local tabWidth = math.max(10, math.floor(width / #tabs))
  for index, tab in ipairs(tabs) do
    local x = 1 + (index - 1) * tabWidth
    ui.button(output, x, 3, tabWidth, 1, tab.label, colors.white, colors.gray, page == tab.id)
  end
end

local function drawOrder(width)
  ui.text(output, 2, 5, "Постоянная заявка: сеть сама дозаказывает остаток.", colors.lightGray, colors.gray)
  inputBox(2, 6, width - 3, "Адрес доставки", fields.address, activeField == "address")
  inputBox(2, 9, width - 3, "ID предмета", fields.item, activeField == "item")
  inputBox(2, 12, width - 3, "Количество: 448 или 7с", fields.amount, activeField == "amount")
  ui.button(output, 2, 15, math.floor((width - 3) / 2), 2, "Найти предмет", colors.white, colors.purple, false)
  ui.button(output, 3 + math.floor((width - 3) / 2), 15, width - 3 - math.floor((width - 3) / 2), 2, "Создать заявку", colors.white, colors.red, false)
end

local function searchStock()
  local query = ru.lower(fields.search)
  if query == "" then setStatus("Введи часть ID или названия", colors.orange) return end
  local ticker = getTicker()
  if not ticker then setStatus("Stock Ticker не найден", colors.red) return end
  local ok, stock = pcall(ticker.stock, true)
  if not ok or type(stock) ~= "table" then setStatus("Не удалось прочитать склад", colors.red) return end
  stockResults = {}
  for _, item in ipairs(stock) do
    local id, title = tostring(itemName(item) or ""), tostring(item.displayName or "")
    if ru.lower(id):find(query, 1, true) or ru.lower(title):find(query, 1, true) then
      stockResults[#stockResults + 1] = item
      if #stockResults >= 7 then break end
    end
  end
  setStatus(#stockResults == 0 and "Ничего не найдено" or ("Найдено: " .. tostring(#stockResults)), colors.lightGray)
end

local function drawStock(width)
  inputBox(2, 5, width - 3, "Поиск ID или названия", fields.search, activeField == "search")
  ui.button(output, 2, 8, width - 3, 1, "Искать", colors.white, colors.purple, false)
  if #stockResults == 0 then
    ui.text(output, 2, 10, "Выбери результат — ID подставится в заявку.", colors.lightGray, colors.gray)
    return
  end
  for index, item in ipairs(stockResults) do
    local y = 9 + index
    local label = tostring(item.displayName or itemName(item) or "?") .. " x" .. tostring(itemCount(item))
    ui.line(output, 2, y, width - 3, ru.fit(tostring(index) .. ". " .. label, width - 3, ""), colors.white, index % 2 == 0 and colors.gray or colors.black)
  end
end

local function orderBar(order)
  local requested = math.max(1, tonumber(order.requested) or 1)
  local accepted = tonumber(order.accepted) or 0
  local filled = math.min(8, math.floor(accepted * 8 / requested))
  return "[" .. string.rep("#", filled) .. string.rep("-", 8 - filled) .. "] " .. formatQuantity(accepted) .. "/" .. formatQuantity(requested)
end

local function drawOrders(width)
  local data = orders.load()
  if #data.orders == 0 then
    ui.text(output, 2, 6, "Заявок пока нет.", colors.lightGray, colors.gray)
    return
  end
  local first = math.max(1, #data.orders - 3)
  local row = 5
  for index = first, #data.orders do
    local order = data.orders[index]
    local state = order.state == "active" and "авто" or order.state
    ui.line(output, 2, row, width - 3, "№" .. tostring(order.id) .. " [" .. state .. "] " .. ru.fit(order.item, width - 15, ""), colors.white, colors.gray)
    ui.line(output, 2, row + 1, width - 11, orderBar(order), colors.lightGray, colors.black)
    ui.button(output, width - 8, row + 1, 3, 1, "R", colors.white, colors.blue, false)
    ui.button(output, width - 4, row + 1, 3, 1, "X", colors.white, colors.red, false)
    ui.line(output, 2, row + 2, width - 3, ru.fit(tostring(order.lastResult or ""), width - 3, ""), colors.lightGray, colors.gray)
    row = row + 4
  end
end

local function drawNetwork(width)
  local function count(kind)
    local result = 0
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.hasType and peripheral.hasType(name, kind) then result = result + 1 end
    end
    return result
  end
  ui.text(output, 2, 6, "Stock Ticker: " .. tostring(count("Create_StockTicker")), colors.white, colors.gray)
  ui.text(output, 2, 8, "Redstone Requester: " .. tostring(count("Create_RedstoneRequester")), colors.white, colors.gray)
  ui.text(output, 2, 10, "Material Checklist: " .. tostring(count("create:clipboard")), colors.white, colors.gray)
  ui.text(output, 2, 13, "Автозаказы работают, пока ConcordOS запущен.", colors.lightGray, colors.gray)
end

local function drawConfirmation(width)
  ui.fill(output, 2, 5, width - 3, 12, colors.black)
  ui.text(output, 3, 6, "Подтверждение заявки", colors.white, colors.red)
  ui.text(output, 3, 8, ru.fit(fields.item, width - 5, ""), colors.white, colors.black)
  ui.text(output, 3, 10, formatQuantity(parseQuantity(fields.amount) or 0) .. " -> " .. ru.fit(fields.address, width - 8, ""), colors.lightGray, colors.black)
  local available = availableCount(fields.item)
  ui.text(output, 3, 12, "В сети сейчас: " .. tostring(available or "?"), colors.lightGray, colors.black)
  ui.button(output, 3, 14, math.floor((width - 7) / 2), 2, "Отмена", colors.white, colors.gray, false)
  ui.button(output, 4 + math.floor((width - 7) / 2), 14, math.ceil((width - 7) / 2), 2, "ОТПРАВИТЬ", colors.white, colors.red, false)
end

local function draw()
  local width, height = output.getSize()
  ui.clear(output, colors.gray)
  drawHeader(width)
  if confirmation then drawConfirmation(width)
  elseif page == "order" then drawOrder(width)
  elseif page == "stock" then drawStock(width)
  elseif page == "orders" then drawOrders(width)
  elseif page == "network" then drawNetwork(width)
  end
  ui.line(output, 1, height, width, ru.fit(statusText, width, ""), statusColor, colors.black)
end

local function submitOrder()
  local amount = parseQuantity(fields.amount)
  if fields.address == "" or fields.item == "" or not amount or amount < 1 then
    setStatus("Заполни адрес, ID и количество", colors.red)
    confirmation = false
    return
  end
  local order = orders.create(fields.address, fields.item, amount)
  local ok, err = pcall(orders.tick, order.id)
  if ok then
    setStatus("Заявка №" .. tostring(order.id) .. " создана", colors.lime)
    fields.item, fields.amount = "", ""
    activeField = "item"
  else
    setStatus("Заявка сохранена: " .. tostring(err), colors.orange)
  end
  confirmation = false
end

local function fieldAt(x, y, width)
  if page == "order" and x >= 2 and x < width - 1 then
    if y == 7 then return "address" end
    if y == 10 then return "item" end
    if y == 13 then return "amount" end
  elseif page == "stock" and x >= 2 and x < width - 1 and y == 6 then
    return "search"
  end
end

local function appendText(text)
  if activeField and fields[activeField] then fields[activeField] = fields[activeField] .. text end
end

local function backspace()
  if activeField and fields[activeField] then
    local length = ru.len(fields[activeField])
    fields[activeField] = ru.sub(fields[activeField], 1, length - 1)
  end
end

local function activateTab(index)
  local tab = tabs[index]
  if tab then
    page, confirmation = tab.id, false
    activeField = page == "stock" and "search" or "address"
  end
end

draw()
refreshTimer = os.startTimer(2)
while true do
  local event, a, b, c = os.pullEventRaw()
  local width, height = output.getSize()
  if event == "timer" and a == refreshTimer then
    refreshTimer = os.startTimer(2)
    draw()
  elseif event == "term_resize" then
    draw()
  elseif event == "char" or event == "paste" then
    if not confirmation then appendText(a) draw() end
  elseif event == "key" then
    if a == keys.escape then return end
    if a == keys.tab and not confirmation then
      if page == "order" then
        activeField = activeField == "address" and "item" or (activeField == "item" and "amount" or "address")
      end
    elseif a == keys.backspace and not confirmation then backspace()
    elseif a == keys.enter then
      if confirmation then submitOrder()
      elseif page == "order" then confirmation = true
      elseif page == "stock" then searchStock()
      end
    elseif a >= keys.one and a <= keys.four then activateTab(a - keys.one + 1)
    elseif a == keys.f5 then draw()
    end
    draw()
  elseif event == "mouse_click" then
    local x, y = b, c
    if confirmation then
      if y >= 14 and y <= 15 then
        local split = 3 + math.floor((width - 7) / 2)
        if x < split then confirmation = false else submitOrder() end
      end
    elseif y == 3 then
      local tabWidth = math.max(10, math.floor(width / #tabs))
      activateTab(math.floor((x - 1) / tabWidth) + 1)
    else
      local field = fieldAt(x, y, width)
      if field then activeField = field
      elseif page == "order" and y >= 15 and y <= 16 then
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then page, activeField = "stock", "search" else confirmation = true end
      elseif page == "stock" and y == 8 then
        searchStock()
      elseif page == "stock" and y >= 10 and y <= 16 then
        local index = y - 9
        local item = stockResults[index]
        if item then
          fields.item = itemName(item) or ""
          page, activeField = "order", "amount"
          setStatus("ID предмета выбран", colors.lime)
        end
      elseif page == "orders" then
        local first = math.max(1, #orders.load().orders - 3)
        for index = first, #orders.load().orders do
          local row = 5 + (index - first) * 4
          local order = orders.load().orders[index]
          if y == row + 1 and x >= width - 8 and x <= width - 6 then
            if orders.retry(order.id) then pcall(orders.tick, order.id) setStatus("Повтор отправлен", colors.lime) end
          elseif y == row + 1 and x >= width - 4 then
            if orders.cancel(order.id) then setStatus("Заявка отменена", colors.orange) end
          end
        end
      end
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
