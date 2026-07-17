-- ConcordOS Master Control: Create logistics requests and craft packages.
local ROOT = "/concordos"
local ru = dofile(ROOT .. "/system/lib/ru.lua")
local config = dofile(ROOT .. "/system/config.lua")
local orders = dofile(ROOT .. "/system/lib/orders.lua")
local native = term.current()
local unpackArgs = table.unpack or unpack
local LOG_PATH = ROOT .. "/data/master.log"

local function nextLine()
  local _, y = native.getCursorPos()
  local _, height = native.getSize()
  if y >= height then
    native.scroll(1)
    native.setCursorPos(1, height)
  else
    native.setCursorPos(1, y + 1)
  end
end

local function say(value)
  local text = tostring(value or "")
  local width = native.getSize()
  while ru.len(text) > width do
    ru.write(native, ru.sub(text, 1, width))
    nextLine()
    text = ru.sub(text, width + 1)
  end
  ru.write(native, text)
end

local function sayLine(value)
  say(value)
  nextLine()
end

local function clear()
  native.setBackgroundColor(colors.black)
  native.setTextColor(colors.white)
  native.clear()
  native.setCursorPos(1, 1)
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function readUtf8(prompt, default)
  local line = default or ""
  local cursor = ru.len(line) + 1
  local startX, startY = native.getCursorPos()
  local width = native.getSize()
  local promptLength = ru.len(prompt)

  local function redraw()
    local available = math.max(1, width - promptLength - startX + 1)
    local first = math.max(1, cursor - available + 1)
    local visible = ru.sub(line, first, first + available - 1)
    native.setCursorPos(startX, startY)
    ru.write(native, ru.padRight(prompt .. visible, width - startX + 1))
    native.setCursorPos(math.min(width, startX + promptLength + cursor - first), startY)
  end

  native.setCursorBlink(true)
  redraw()
  while true do
    local event, a = os.pullEventRaw()
    if event == "char" or event == "paste" then
      line = ru.sub(line, 1, cursor - 1) .. a .. ru.sub(line, cursor)
      cursor = cursor + ru.len(a)
      redraw()
    elseif event == "key" then
      if a == keys.enter then
        native.setCursorBlink(false)
        nextLine()
        return trim(line)
      elseif a == keys.left then cursor = math.max(1, cursor - 1)
      elseif a == keys.right then cursor = math.min(ru.len(line) + 1, cursor + 1)
      elseif a == keys.home then cursor = 1
      elseif a == keys['end'] then cursor = ru.len(line) + 1
      elseif a == keys.backspace and cursor > 1 then
        line = ru.sub(line, 1, cursor - 2) .. ru.sub(line, cursor)
        cursor = cursor - 1
      elseif a == keys.delete and cursor <= ru.len(line) then
        line = ru.sub(line, 1, cursor - 1) .. ru.sub(line, cursor + 1)
      end
      redraw()
    elseif event == "terminate" then
      native.setCursorBlink(false)
      return nil
    end
  end
end

local function pause()
  sayLine("")
  sayLine("Нажми любую клавишу для продолжения.")
  os.pullEventRaw("key")
end

local function ask(prompt, default)
  local shown = default and (prompt .. " [" .. default .. "]: ") or (prompt .. ": ")
  return readUtf8(shown, default)
end

local function confirm(summary)
  sayLine("")
  sayLine(summary)
  local answer = readUtf8("Отправить запрос? [да/нет]: ")
  return answer and (ru.lower(answer) == "да" or ru.lower(answer) == "yes")
end

local function timestamp()
  return "день " .. tostring(os.day()) .. ", " .. textutils.formatTime(os.time(), true)
end

local function log(message)
  local directory = fs.getDir(LOG_PATH)
  if not fs.exists(directory) then fs.makeDir(directory) end
  local file = fs.open(LOG_PATH, "a")
  if file then
    file.writeLine("[" .. timestamp() .. "] " .. message)
    file.close()
  end
end

local function typesOf(name)
  return { peripheral.getType(name) }
end

local function findByType(expected)
  local matches = {}
  for _, name in ipairs(peripheral.getNames()) do
    local matchesType = peripheral.hasType and peripheral.hasType(name, expected)
    if not matchesType then
      for _, kind in ipairs(typesOf(name)) do
        if kind == expected then matchesType = true break end
      end
    end
    if matchesType then matches[#matches + 1] = name end
  end
  table.sort(matches)
  return matches
end

local function ticker()
  local names = findByType("Create_StockTicker")
  if #names == 0 then return nil, nil end
  return peripheral.wrap(names[1]), names[1]
end

local function selectRequester()
  local names = findByType("Create_RedstoneRequester")
  if #names == 0 then
    sayLine("Redstone Requester не найден.")
    pause()
    return nil
  end
  if #names == 1 then return peripheral.wrap(names[1]), names[1] end

  sayLine("Выбери Redstone Requester:")
  for index, name in ipairs(names) do sayLine(tostring(index) .. ". " .. name) end
  local selected = tonumber(ask("Номер"))
  if not selected or not names[selected] then return nil end
  return peripheral.wrap(names[selected]), names[selected]
end

local function itemName(item)
  if type(item) ~= "table" then return nil end
  return item.name or item.id or (type(item.item) == "table" and item.item.name)
end

local function itemCount(item)
  if type(item) == "number" then return item end
  if type(item) ~= "table" then return 0 end
  return tonumber(item.count or item.amount or item.quantity or item.total) or 0
end

local function getStock(detailed)
  local stockTicker, name = ticker()
  if not stockTicker then return nil, "Stock Ticker не найден" end
  local ok, result = pcall(stockTicker.stock, detailed == true)
  if not ok then return nil, tostring(result) end
  return result, nil, stockTicker, name
end

local function askAddress(label)
  local addresses = orders.addresses()
  if #addresses > 0 then
    sayLine("Недавние адреса:")
    for index = 1, math.min(#addresses, 5) do sayLine("  " .. tostring(index) .. ". " .. addresses[index]) end
  end
  local answer = ask(label .. " (номер или новый)")
  local index = tonumber(answer)
  return index and addresses[index] or answer
end

local function chooseStockItem()
  local query = ru.lower(ask("Поиск ID или названия"))
  if not query or query == "" then return nil end
  local stock, err = getStock(true)
  if not stock then sayLine("Ошибка склада: " .. tostring(err)) return nil end
  local matches = {}
  for _, item in ipairs(stock) do
    local id = tostring(itemName(item) or "")
    local title = tostring(item.displayName or "")
    if ru.lower(id):find(query, 1, true) or ru.lower(title):find(query, 1, true) then
      matches[#matches + 1] = item
      if #matches >= 9 then break end
    end
  end
  if #matches == 0 then sayLine("Совпадений нет.") return nil end
  for index, item in ipairs(matches) do
    local title = item.displayName and (item.displayName .. " | ") or ""
    sayLine(tostring(index) .. ". " .. title .. tostring(itemName(item)) .. " x" .. tostring(itemCount(item)))
  end
  local selected = tonumber(ask("Номер предмета"))
  return selected and matches[selected] and itemName(matches[selected]) or nil
end

local function askItem()
  local item = ask("ID предмета (Enter = поиск)")
  if item and item ~= "" then return item end
  return chooseStockItem()
end

local function parseItems(value)
  local items = {}
  for entry in tostring(value or ""):gmatch("[^;]+") do
    local name, count = entry:match("^%s*([^,]+)%s*,?%s*(%d*)%s*$")
    name = trim(name)
    if name ~= "" then
      items[#items + 1] = { name = name, count = math.max(1, tonumber(count) or 1) }
    end
  end
  return items
end

local function parseQuantity(value)
  local text = ru.lower(trim(value))
  local stacks = text:match("^(%d+)%s*[сc]")
  if stacks then return tonumber(stacks) * 64 end
  local count = tonumber(text)
  return count and math.floor(count) or nil
end

local function formatQuantity(count)
  count = tonumber(count) or 0
  local stacks, remainder = math.floor(count / 64), count % 64
  if stacks > 0 and remainder == 0 then return tostring(count) .. " (" .. tostring(stacks) .. " стаков)" end
  if stacks > 0 then return tostring(count) .. " (" .. tostring(stacks) .. " стаков + " .. tostring(remainder) .. ")" end
  return tostring(count)
end

local function availableCount(itemNameToFind)
  local stock = getStock(false)
  local total = 0
  if stock then
    for _, entry in ipairs(stock) do
      if itemName(entry) == itemNameToFind then total = total + itemCount(entry) end
    end
  end
  return total
end

local function formatItems(items)
  local labels = {}
  for _, item in ipairs(items) do labels[#labels + 1] = item.name .. " x" .. tostring(item.count or 1) end
  return table.concat(labels, "; ")
end

local function directRequest()
  clear()
  native.setTextColor(colors.lightBlue)
  sayLine("Прямой запрос через Stock Ticker")
  native.setTextColor(colors.white)
  local stockTicker, tickerName = ticker()
  if not stockTicker then sayLine("Stock Ticker не найден.") pause() return end

  sayLine("Ticker: " .. tickerName)
  local address = askAddress("Адрес доставки")
  local item = askItem()
  local count = parseQuantity(ask("Количество или стеки"))
  if not address or address == "" or not item or item == "" or not count or count < 1 then
    sayLine("Запрос отменён: не хватает данных.") pause() return
  end

  local stock = getStock(false)
  if stock then
    local available = 0
    for _, entry in ipairs(stock) do
      if itemName(entry) == item then available = available + itemCount(entry) end
    end
    sayLine("В сети сейчас: " .. tostring(available))
  end

  if not confirm("Адрес: " .. address .. " | " .. item .. " x" .. tostring(count)) then
    sayLine("Отменено.") pause() return
  end

  local ok, result = pcall(stockTicker.requestFiltered, address, { name = item, _requestCount = count })
  if ok then
    orders.rememberAddress(address)
    log("Stock Ticker -> " .. address .. ": " .. item .. " x" .. tostring(count) .. ", принято: " .. tostring(result))
    sayLine("Запрос отправлен. Принято предметов: " .. tostring(result))
  else
    sayLine("Ошибка Stock Ticker: " .. tostring(result))
  end
  pause()
end

local function persistentRequest()
  clear()
  native.setTextColor(colors.red)
  sayLine("Постоянная заявка на производство и доставку")
  native.setTextColor(colors.white)
  local stockTicker, tickerName = ticker()
  if not stockTicker then sayLine("Stock Ticker не найден.") pause() return end

  sayLine("Ticker: " .. tickerName)
  sayLine("Количество можно указать как 448 или 7с (семь стаков).")
  local address = askAddress("Адрес доставки")
  local item = askItem()
  local amount = ask("Количество или стеки")
  local count = parseQuantity(amount)
  if not address or address == "" or not item or item == "" or not count or count < 1 then
    sayLine("Заявка отменена: не хватает данных.") pause() return
  end
  sayLine("В сети сейчас: " .. tostring(availableCount(item)))
  if not confirm("Постоянная заявка: " .. item .. " x" .. formatQuantity(count) .. " -> " .. address) then
    sayLine("Отменено.") pause() return
  end

  local order = orders.create(address, item, count)
  local ok, err = pcall(orders.tick, order.id)
  if not ok then
    sayLine("Заявка сохранена, но первая отправка не удалась: " .. tostring(err))
  else
    local fresh = orders.load()
    for _, entry in ipairs(fresh.orders) do
      if entry.id == order.id then order = entry break end
    end
    sayLine("Заявка №" .. tostring(order.id) .. " сохранена.")
    sayLine("Принято сетью: " .. tostring(order.accepted) .. "/" .. tostring(order.requested))
    sayLine(order.lastResult or "Ожидание")
  end
  log("Постоянная заявка №" .. tostring(order.id) .. ": " .. item .. " x" .. tostring(count) .. " -> " .. address)
  pause()
end

local function showOrders()
  clear()
  native.setTextColor(colors.red)
  sayLine("Постоянные заявки")
  native.setTextColor(colors.white)
  pcall(orders.tick)
  local data = orders.load()
  if #data.orders == 0 then sayLine("Заявок ещё нет.") pause() return end
  local first = math.max(1, #data.orders - 5)
  for index = first, #data.orders do
    local order = data.orders[index]
    local state = order.state == "active" and "автозаказ" or order.state
    local requested = math.max(1, tonumber(order.requested) or 1)
    local accepted = tonumber(order.accepted) or 0
    local filled = math.min(10, math.floor(accepted * 10 / requested))
    local bar = "[" .. string.rep("#", filled) .. string.rep("-", 10 - filled) .. "]"
    sayLine("№" .. tostring(order.id) .. " [" .. state .. "] " .. order.item)
    sayLine("  " .. bar .. " " .. formatQuantity(accepted) .. "/" .. formatQuantity(requested))
    sayLine("  -> " .. order.address)
    sayLine("  " .. tostring(order.lastResult or ""))
  end
  local action = ru.lower(ask("Команда: c<ID>/отмена N, r<ID>/повтор N"))
  if action and action ~= "" then
    local cancelId = tonumber(action:match("^[cс](%d+)$") or action:match("^отмена%s+(%d+)$"))
    local retryId = tonumber(action:match("^[rр](%d+)$") or action:match("^повтор%s+(%d+)$"))
    if cancelId then
      if orders.cancel(cancelId) then sayLine("Заявка отменена.") else sayLine("Активная заявка не найдена.") end
    elseif retryId then
      if orders.retry(retryId) then
        pcall(orders.tick, retryId)
        sayLine("Повтор отправлен.")
      else
        sayLine("Активная заявка не найдена.")
      end
    else
      sayLine("Неизвестная команда.")
    end
    pause()
  end
end

local function packageRequest()
  clear()
  native.setTextColor(colors.orange)
  sayLine("Пакетный запрос через Redstone Requester")
  native.setTextColor(colors.white)
  local requester, requesterName = selectRequester()
  if not requester then return end
  local okAddress, currentAddress = pcall(requester.getAddress)
  local okConfig, currentConfig = pcall(requester.getConfiguration)
  if okAddress then sayLine("Текущий адрес Requester: " .. tostring(currentAddress)) end
  if okConfig then sayLine("Текущий режим Requester: " .. tostring(currentConfig)) end
  local address = askAddress("Адрес доставки")
  local mode = ask("Режим: strict или allow_partial")
  local rawItems = ask("Предметы: id,кол-во; id,кол-во")
  local items = parseItems(rawItems)
  if #items == 0 or #items > 9 or not address or address == "" then
    sayLine("Нужно от 1 до 9 позиций и адрес.") pause() return
  end
  if mode ~= "strict" and mode ~= "allow_partial" then
    sayLine("Режим должен быть strict или allow_partial.") pause() return
  end
  if not confirm(requesterName .. " -> " .. address .. ": " .. formatItems(items)) then
    sayLine("Отменено.") pause() return
  end

  local ok, err = pcall(function()
    requester.setAddress(address)
    requester.setConfiguration(mode)
    requester.setRequest(unpackArgs(items, 1, #items))
    requester.request()
  end)
  if ok then
    orders.rememberAddress(address)
    log("Requester " .. requesterName .. " -> " .. address .. ": " .. formatItems(items))
    sayLine("Пакетный запрос отправлен.")
  else
    sayLine("Ошибка Requester: " .. tostring(err))
  end
  pause()
end

local function craftingRequest()
  clear()
  native.setTextColor(colors.lime)
  sayLine("Крафтовый запрос через Redstone Requester")
  native.setTextColor(colors.white)
  sayLine("Нужен настроенный Package Crafter / автокрафтер Create.")
  local requester, requesterName = selectRequester()
  if not requester then return end
  local okAddress, currentAddress = pcall(requester.getAddress)
  if okAddress then sayLine("Текущий адрес Requester: " .. tostring(currentAddress)) end
  local address = askAddress("Адрес крафтера")
  local batches = tonumber(ask("Число крафтов"))
  local rawRecipe = ask("Слоты рецепта через ; (до 9 ID)")
  local recipe = {}
  for item in tostring(rawRecipe or ""):gmatch("[^;]+") do
    item = trim(item)
    if item ~= "" then recipe[#recipe + 1] = item end
  end
  if not address or address == "" or not batches or batches < 1 or #recipe == 0 or #recipe > 9 then
    sayLine("Нужны адрес, число крафтов и от 1 до 9 слотов рецепта.") pause() return
  end
  if not confirm(requesterName .. " -> " .. address .. ": " .. table.concat(recipe, "; ") .. " | крафтов: " .. tostring(batches)) then
    sayLine("Отменено.") pause() return
  end

  local ok, err = pcall(function()
    requester.setAddress(address)
    requester.setConfiguration("strict")
    requester.setCraftingRequest(batches, unpackArgs(recipe, 1, #recipe))
    requester.request()
  end)
  if ok then
    orders.rememberAddress(address)
    log("Craft " .. requesterName .. " -> " .. address .. ": " .. table.concat(recipe, "; ") .. " x" .. tostring(batches))
    sayLine("Крафтовый пакет отправлен.")
  else
    sayLine("Ошибка крафтового запроса: " .. tostring(err))
  end
  pause()
end

local function stockSearch()
  clear()
  native.setTextColor(colors.yellow)
  sayLine("Поиск по складу")
  native.setTextColor(colors.white)
  local query = ru.lower(ask("Часть ID или названия"))
  if not query or query == "" then return end
  local stock, err = getStock(true)
  if not stock then sayLine("Ошибка склада: " .. err) pause() return end
  local found = 0
  for _, item in ipairs(stock) do
    local id = tostring(itemName(item) or "")
    local title = tostring(item.displayName or "")
    if ru.lower(id):find(query, 1, true) or ru.lower(title):find(query, 1, true) then
      sayLine(id .. " x" .. tostring(itemCount(item)))
      found = found + 1
      if found >= 14 then break end
    end
  end
  sayLine(found == 0 and "Совпадений нет." or "Показано: " .. tostring(found))
  pause()
end

local function checklist()
  clear()
  native.setTextColor(colors.purple)
  sayLine("Material Checklist")
  native.setTextColor(colors.white)
  local clipboard = peripheral.find("create:clipboard")
  if not clipboard then sayLine("Планшет Create не найден.") pause() return end
  local ok, items = pcall(clipboard.getMissingItems)
  if not ok or type(items) ~= "table" then sayLine("Ошибка чтения: " .. tostring(items)) pause() return end
  local total, shown = 0, 0
  for _, item in pairs(items) do
    local name, count = itemName(item) or "?", itemCount(item)
    total = total + count
    if shown < 14 then
      sayLine(name .. " x" .. tostring(count))
      shown = shown + 1
    end
  end
  sayLine("Позиций: " .. tostring(shown) .. " | Всего: " .. tostring(total))
  pause()
end

local function showLog()
  clear()
  native.setTextColor(colors.lightGray)
  sayLine("Журнал мастера")
  native.setTextColor(colors.white)
  if not fs.exists(LOG_PATH) then sayLine("Запросов ещё не было.") pause() return end
  local file = fs.open(LOG_PATH, "r")
  local lines = {}
  while true do
    local line = file.readLine()
    if not line then break end
    lines[#lines + 1] = line
  end
  file.close()
  local start = math.max(1, #lines - 11)
  for index = start, #lines do sayLine(lines[index]) end
  pause()
end

local function status()
  clear()
  native.setTextColor(colors.cyan)
  sayLine("Состояние промзоны")
  native.setTextColor(colors.white)
  local stockNames = findByType("Create_StockTicker")
  local requesterNames = findByType("Create_RedstoneRequester")
  local clipboardNames = findByType("create:clipboard")
  sayLine("Stock Ticker: " .. tostring(#stockNames))
  sayLine("Redstone Requester: " .. tostring(#requesterNames))
  sayLine("Material Checklist: " .. tostring(#clipboardNames))
  for _, name in ipairs(requesterNames) do
    local requester = peripheral.wrap(name)
    local ok, address = pcall(requester.getAddress)
    sayLine(name .. " -> " .. (ok and tostring(address) or "ошибка"))
  end
  pause()
end

while true do
  clear()
  native.setTextColor(colors.blue)
  sayLine(config.name .. " | Мастер промзоны")
  native.setTextColor(colors.lightGray)
  sayLine(config.country)
  native.setTextColor(colors.white)
  sayLine("")
  sayLine("1. Постоянная заявка (доставка/производство)")
  sayLine("2. Разовый запрос со Stock Ticker")
  sayLine("3. Пакетный запрос Requester")
  sayLine("4. Крафтовый запрос Requester")
  sayLine("5. Поиск по складу")
  sayLine("6. Material Checklist")
  sayLine("7. Состояние периферии")
  sayLine("8. Постоянные заявки")
  sayLine("9. Журнал запросов")
  sayLine("0. Вернуться на рабочий стол")
  sayLine("")
  local choice = readUtf8("Выбор: ")
  if not choice or choice == "0" then return end
  if choice == "1" then persistentRequest()
  elseif choice == "2" then directRequest()
  elseif choice == "3" then packageRequest()
  elseif choice == "4" then craftingRequest()
  elseif choice == "5" then stockSearch()
  elseif choice == "6" then checklist()
  elseif choice == "7" then status()
  elseif choice == "8" then showOrders()
  elseif choice == "9" then showLog()
  else sayLine("Неизвестный пункт.") sleep(0.8) end
end
