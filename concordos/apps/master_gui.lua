-- Touch/mouse friendly graphical front-end for ConcordOS industrial orders.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local ru = ui.ru
local orders = dofile(ROOT .. "/system/lib/orders.lua")
local output = term.current()

local page = "order"
local activeField = "address"
local fields = { address = "", item = "", amount = "", search = "" }
local catalogResults = {}
local catalogPage = 0
local CATALOG_PAGE_SIZE = 5
local clipboardResults = {}
local clipboardPage = 0
local CLIPBOARD_PAGE_SIZE = 7
local confirmation = false
local statusText, statusColor = "Готово к работе", colors.lightGray
local refreshTimer = nil

local tabs = {
  { id = "order", label = "Заказать" },
  { id = "orders", label = "Заявки" },
  { id = "stock", label = "Каталог" },
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

local function itemName(item, fallback)
  if type(item) ~= "table" then return nil end
  return item.name or item.id or (type(item.item) == "table" and (item.item.name or item.item.id))
    or (type(fallback) == "string" and fallback:find(":") and fallback)
end

local function itemCount(item)
  if type(item) == "number" then return item end
  if type(item) ~= "table" then return 0 end
  return tonumber(item.count or item.amount or item.quantity or item.total) or 0
end

local function getTicker()
  return peripheral.find("Create_StockTicker")
end

local function getClipboard()
  return peripheral.find("create:clipboard")
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

local function homeButton(width)
  local buttonWidth = width >= 40 and 11 or 3
  return width - buttonWidth + 1, buttonWidth, buttonWidth == 3 and "<" or "< Главная"
end

local function drawHeader(width)
  ui.line(output, 1, 1, width, "ConcordOS | Мастер промзоны", colors.white, colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(width)
  ui.button(output, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(output, homeX, 1, homeLabel, colors.white, colors.lightBlue)
  local tabWidth = math.max(10, math.floor(width / #tabs))
  for index, tab in ipairs(tabs) do
    local x = 1 + (index - 1) * tabWidth
    ui.button(output, x, 3, tabWidth, 1, tab.label, colors.white, colors.gray, page == tab.id)
  end
end

local function drawOrder(width)
  ui.text(output, 2, 5, "Постоянная заявка: сеть сама дозаказывает остаток.", colors.lightGray, colors.gray)
  inputBox(2, 6, width - 13, "Адрес доставки", fields.address, activeField == "address")
  ui.button(output, width - 9, 6, 9, 2, "Адреса", colors.white, colors.blue, false)
  inputBox(2, 9, width - 3, "ID предмета", fields.item, activeField == "item")
  inputBox(2, 12, width - 3, "Количество: 448 или 7с", fields.amount, activeField == "amount")
  ui.button(output, 2, 15, math.floor((width - 3) / 2), 2, "Из блокнота", colors.white, colors.purple, false)
  ui.button(output, 3 + math.floor((width - 3) / 2), 15, width - 3 - math.floor((width - 3) / 2), 2, "Создать заявку", colors.white, colors.red, false)
end

local function drawAddresses(width)
  local addresses = orders.addresses()
  local leftWidth = math.floor((width - 3) / 2)
  ui.text(output, 2, 5, "Адресная книга: клик подставит адрес в заявку.", colors.lightGray, colors.gray)
  ui.button(output, 2, 6, leftWidth, 1, "< К заявке", colors.white, colors.gray, false)
  ui.button(output, 3 + leftWidth, 6, width - 3 - leftWidth, 1, "Сохранить текущий", colors.white, colors.blue, false)
  if #addresses == 0 then
    ui.text(output, 2, 9, "Адресов пока нет. Введи адрес в заявке и сохрани его.", colors.lightGray, colors.gray)
    return
  end
  for index = 1, math.min(7, #addresses) do
    ui.line(output, 2, 7 + index, width - 3, ru.fit(tostring(index) .. ". " .. addresses[index], width - 3, ""), colors.white, index % 2 == 0 and colors.gray or colors.black)
  end
  if #addresses > 7 then ui.text(output, 2, 16, "Показаны 7 последних адресов.", colors.lightGray, colors.gray) end
end

local function loadCatalog()
  local ticker = getTicker()
  if not ticker then setStatus("Stock Ticker не найден", colors.red) return end
  local ok, stock = pcall(ticker.stock, true)
  if not ok or type(stock) ~= "table" then setStatus("Не удалось прочитать склад", colors.red) return end

  local query = ru.lower(fields.search)
  catalogResults = {}
  for _, item in ipairs(stock) do
    local id, title = tostring(itemName(item) or ""), tostring(item.displayName or "")
    if itemCount(item) > 0 and (query == "" or ru.lower(id):find(query, 1, true) or ru.lower(title):find(query, 1, true)) then
      catalogResults[#catalogResults + 1] = item
    end
  end
  table.sort(catalogResults, function(a, b)
    return tostring(a.displayName or itemName(a) or "") < tostring(b.displayName or itemName(b) or "")
  end)
  catalogPage = 0
  setStatus(#catalogResults == 0 and "На складе ничего не найдено" or ("В каталоге: " .. tostring(#catalogResults)), colors.lightGray)
end

local function drawStock(width)
  inputBox(2, 5, width - 3, "Поиск по ID или названию (пусто — весь склад)", fields.search, activeField == "search")
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, 8, leftWidth, 1, "Искать", colors.white, colors.purple, false)
  ui.button(output, 3 + leftWidth, 8, width - 3 - leftWidth, 1, "Обновить склад", colors.white, colors.blue, false)
  if #catalogResults == 0 then
    ui.text(output, 2, 10, "Нажми «Искать» для чтения склада.", colors.lightGray, colors.gray)
    return
  end

  local totalPages = math.max(1, math.ceil(#catalogResults / CATALOG_PAGE_SIZE))
  if catalogPage >= totalPages then catalogPage = totalPages - 1 end
  local first = catalogPage * CATALOG_PAGE_SIZE + 1
  ui.text(output, 2, 10, "Клик по позиции — создать заявку. Стр. " .. tostring(catalogPage + 1) .. "/" .. tostring(totalPages), colors.lightGray, colors.gray)
  for offset = 0, CATALOG_PAGE_SIZE - 1 do
    local item = catalogResults[first + offset]
    if item then
      local label = tostring(item.displayName or itemName(item) or "?") .. " x" .. formatQuantity(itemCount(item))
      ui.line(output, 2, 11 + offset, width - 3, ru.fit(label, width - 3, ""), colors.white, offset % 2 == 0 and colors.gray or colors.black)
    end
  end
  ui.button(output, 2, 17, leftWidth, 1, "< Пред.", colors.white, colors.gray, catalogPage > 0)
  ui.button(output, 3 + leftWidth, 17, width - 3 - leftWidth, 1, "След. >", colors.white, colors.gray, catalogPage < totalPages - 1)
end

local function readClipboard()
  local clipboard = getClipboard()
  if not clipboard then setStatus("Планшет Create не найден", colors.red) return false end

  local ok, raw = pcall(clipboard.getMissingItems)
  if not ok or type(raw) ~= "table" then
    setStatus("Не удалось прочитать блокнот", colors.red)
    return false
  end

  clipboardResults = {}
  for key, entry in pairs(raw) do
    local name = itemName(entry, key)
    local count = itemCount(entry)
    if name and count > 0 then
      clipboardResults[#clipboardResults + 1] = {
        name = name,
        count = count,
        displayName = type(entry) == "table" and entry.displayName or nil,
      }
    end
  end
  table.sort(clipboardResults, function(a, b)
    return tostring(a.displayName or a.name) < tostring(b.displayName or b.name)
  end)
  clipboardPage = 0
  setStatus(#clipboardResults == 0 and "В блокноте нет недостающих предметов" or ("Считано позиций: " .. tostring(#clipboardResults)), colors.lightGray)
  return true
end

local function drawClipboard(width)
  ui.text(output, 2, 5, "Недостающие материалы из планшета Create", colors.lightGray, colors.gray)
  ui.button(output, 2, 6, width - 3, 1, "Считать блокнот", colors.white, colors.purple, false)
  if #clipboardResults == 0 then
    ui.text(output, 2, 8, "Нажми «Считать блокнот», затем выбери позицию.", colors.lightGray, colors.gray)
    return
  end
  local totalPages = math.max(1, math.ceil(#clipboardResults / CLIPBOARD_PAGE_SIZE))
  if clipboardPage >= totalPages then clipboardPage = totalPages - 1 end
  local first = clipboardPage * CLIPBOARD_PAGE_SIZE + 1
  ui.text(output, 2, 7, "Клик по позиции — создать заявку. Стр. " .. tostring(clipboardPage + 1) .. "/" .. tostring(totalPages), colors.lightGray, colors.gray)
  for offset = 0, CLIPBOARD_PAGE_SIZE - 1 do
    local item = clipboardResults[first + offset]
    if item then
      local label = tostring(item.displayName or item.name) .. " x" .. formatQuantity(item.count)
      ui.line(output, 2, 8 + offset, width - 3, ru.fit(label, width - 3, ""), colors.white, offset % 2 == 0 and colors.gray or colors.black)
    end
  end
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, 16, leftWidth, 1, "< Пред.", colors.white, colors.gray, clipboardPage > 0)
  ui.button(output, 3 + leftWidth, 16, width - 3 - leftWidth, 1, "След. >", colors.white, colors.gray, clipboardPage < totalPages - 1)
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
  local first = math.max(1, #data.orders - 2)
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
  elseif page == "addresses" then drawAddresses(width)
  elseif page == "stock" then drawStock(width)
  elseif page == "clipboard" then drawClipboard(width)
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
  if page == "order" and x >= 2 and x < width - 11 then
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
    if page == "stock" then loadCatalog() end
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
      elseif page == "stock" then loadCatalog()
      end
    elseif a == keys.f5 then draw()
    end
    draw()
  elseif event == "mouse_click" then
    local x, y = b, c
    if not confirmation and y == 1 then
      local homeX, homeWidth = homeButton(width)
      if x >= homeX and x < homeX + homeWidth then return end
    end
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
        if x < 3 + leftWidth then
          page, activeField = "clipboard", nil
          readClipboard()
        else
          confirmation = true
        end
      elseif page == "order" and x >= width - 9 and y >= 6 and y <= 7 then
        page, activeField = "addresses", nil
      elseif page == "addresses" and y == 6 then
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          page, activeField = "order", "address"
        elseif fields.address == "" then
          setStatus("Сначала введи адрес доставки", colors.orange)
        else
          orders.rememberAddress(fields.address)
          setStatus("Адрес сохранён в книге", colors.lime)
        end
      elseif page == "addresses" and y >= 8 and y <= 14 then
        local address = orders.addresses()[y - 7]
        if address then
          fields.address = address
          page, activeField = "order", "item"
          setStatus("Адрес выбран", colors.lime)
        end
      elseif page == "stock" and y == 8 then
        loadCatalog()
      elseif page == "stock" and y >= 11 and y <= 15 then
        local item = catalogResults[catalogPage * CATALOG_PAGE_SIZE + y - 10]
        if item then
          fields.item = itemName(item) or ""
          if fields.amount == "" then fields.amount = "64" end
          page, activeField = "order", "address"
          setStatus("Предмет добавлен в постоянную заявку", colors.lime)
        end
      elseif page == "stock" and y == 17 then
        local totalPages = math.max(1, math.ceil(#catalogResults / CATALOG_PAGE_SIZE))
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          catalogPage = math.max(0, catalogPage - 1)
        else
          catalogPage = math.min(totalPages - 1, catalogPage + 1)
        end
      elseif page == "clipboard" and y == 6 then
        readClipboard()
      elseif page == "clipboard" and y >= 8 and y <= 14 then
        local item = clipboardResults[clipboardPage * CLIPBOARD_PAGE_SIZE + y - 7]
        if item then
          fields.item = item.name
          fields.amount = tostring(item.count)
          page, activeField = "order", "address"
          setStatus("Предмет и количество перенесены в постоянную заявку", colors.lime)
        end
      elseif page == "clipboard" and y == 16 then
        local totalPages = math.max(1, math.ceil(#clipboardResults / CLIPBOARD_PAGE_SIZE))
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          clipboardPage = math.max(0, clipboardPage - 1)
        else
          clipboardPage = math.min(totalPages - 1, clipboardPage + 1)
        end
      elseif page == "orders" then
        local first = math.max(1, #orders.load().orders - 2)
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
