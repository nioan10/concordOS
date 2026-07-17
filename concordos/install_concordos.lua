-- ConcordOS offline installer. Run once on a CC:Tweaked computer.
local files = {
  ["/startup"] = [====[-- Copy this file to /startup on the CC:Tweaked computer.
local boot = "/concordos/system/boot.lua"

term.setCursorBlink(false)
if not fs.exists(boot) then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("ConcordOS is not installed.")
  print("Expected: " .. boot)
  print("Run the installer or use the normal shell.")
  return
end

local ok, err = pcall(function() shell.run(boot) end)
if not ok then
  term.setTextColor(colors.red)
  print("ConcordOS startup error: " .. tostring(err))
end]====],
  ["/concordos/apps/rterm.lua"] = [====[-- ConcordOS Russian terminal. UTF-8 input, CP866 display.
local ROOT = "/concordos"
local ru = dofile(ROOT .. "/system/lib/ru.lua")
local native = term.current()

local function newline()
  local width, height = native.getSize()
  local _, y = native.getCursorPos()
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
    newline()
    text = ru.sub(text, width + 1)
  end
  ru.write(native, text)
end

local function sayLine(value)
  say(value)
  newline()
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function split(value)
  local result = {}
  for word in value:gmatch("%S+") do result[#result + 1] = word end
  return result
end

local function readUtf8(prompt)
  local line, cursor = "", 1
  local startX, startY = native.getCursorPos()
  local width = native.getSize()
  local promptLength = ru.len(prompt)

  local function redraw()
    local available = math.max(1, width - promptLength)
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
      local before = ru.sub(line, 1, cursor - 1)
      local after = ru.sub(line, cursor)
      line = before .. a .. after
      cursor = cursor + ru.len(a)
      redraw()
    elseif event == "key" then
      if a == keys.enter then
        native.setCursorBlink(false)
        newline()
        return line
      elseif a == keys.left then
        cursor = math.max(1, cursor - 1)
      elseif a == keys.right then
        cursor = math.min(ru.len(line) + 1, cursor + 1)
      elseif a == keys.home then
        cursor = 1
      elseif a == keys['end'] then
        cursor = ru.len(line) + 1
      elseif a == keys.backspace and cursor > 1 then
        line = ru.sub(line, 1, cursor - 2) .. ru.sub(line, cursor)
        cursor = cursor - 1
      elseif a == keys.delete and cursor <= ru.len(line) then
        line = ru.sub(line, 1, cursor - 1) .. ru.sub(line, cursor + 1)
      elseif a == keys.u and (keys.isCtrlDown and keys.isCtrlDown()) then
        line, cursor = "", 1
      end
      redraw()
    elseif event == "terminate" then
      native.setCursorBlink(false)
      return nil
    end
  end
end

local function proxyTerm()
  local wrapped = {}
  for name, value in pairs(native) do
    if type(value) == "function" then wrapped[name] = value end
  end
  wrapped.write = function(value) ru.write(native, value) end
  wrapped.blit = function(value, foreground, background) ru.blit(native, value, foreground, background) end
  wrapped.current = function() return wrapped end
  return wrapped
end

local function runLua(path, arguments)
  local wrappedTerm = proxyTerm()
  local environment = setmetatable({
    term = wrappedTerm,
    write = function(value) ru.write(wrappedTerm, value) end,
    print = function(...)
      local values = { ... }
      local out = {}
      for index = 1, #values do out[index] = tostring(values[index]) end
      sayLine(table.concat(out, "\t"))
    end,
  }, { __index = _G })

  local chunk, err = loadfile(path, "t", environment)
  if not chunk then return false, err end
  local unpackArgs = table.unpack or unpack
  return pcall(chunk, unpackArgs(arguments))
end

local function help()
  sayLine("Команды:")
  sayLine("  help / помощь       эта справка")
  sayLine("  clear / очистить    очистить экран")
  sayLine("  run <файл> [арг.]   запустить Lua-программу")
  sayLine("  shell               обычная оболочка CC")
  sayLine("  exit / выход        вернуться на рабочий стол")
  sayLine("  reboot, shutdown    питание компьютера")
end

native.setBackgroundColor(colors.black)
native.setTextColor(colors.white)
native.clear()
native.setCursorPos(1, 1)
native.setTextColor(colors.lightBlue)
sayLine("ConcordOS: русский терминал")
native.setTextColor(colors.lightGray)
sayLine("Введите help для справки. Русские строки можно вставлять.")
native.setTextColor(colors.white)

while true do
  local commandLine = readUtf8("Фесолоник> ")
  if not commandLine then return end
  local parts = split(trim(commandLine))
  local command = ru.lower(parts[1] or "")

  if command == "" then
    -- Nothing to do.
  elseif command == "help" or command == "помощь" then
    help()
  elseif command == "clear" or command == "очистить" then
    native.clear()
    native.setCursorPos(1, 1)
  elseif command == "exit" or command == "выход" then
    return
  elseif command == "reboot" then
    os.reboot()
  elseif command == "shutdown" then
    os.shutdown()
  elseif command == "shell" then
    shell.run("shell")
  elseif command == "run" or command == "запуск" then
    local path = parts[2]
    if not path then
      sayLine("Укажи файл: run /имя.lua")
    elseif not fs.exists(path) then
      sayLine("Файл не найден: " .. path)
    else
      local arguments = {}
      for index = 3, #parts do arguments[#arguments + 1] = parts[index] end
      local ok, result = runLua(path, arguments)
      if not ok then sayLine("Ошибка программы: " .. tostring(result)) end
    end
  else
    sayLine("Неизвестная команда: " .. command .. ". Введи help.")
  end
end]====],
  ["/concordos/apps/master.lua"] = [====[-- ConcordOS Master Control: Create logistics requests and craft packages.
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
end]====],
  ["/concordos/apps/master_gui.lua"] = [====[-- Touch/mouse friendly graphical front-end for ConcordOS industrial orders.
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
end]====],
  ["/concordos/system/config.lua"] = [====[return {
  name = "ConcordOS",
  country = "Конкордат Фессалоник",
  version = "0.1.0",
  apps = {
    { id = "terminal", title = "Терминал", subtitle = "Русская командная строка", path = "/concordos/apps/rterm.lua", color = colors.black },
    { id = "master", title = "Мастер промзоны", subtitle = "Графические заявки и склад", path = "/concordos/apps/master_gui.lua", color = colors.red },
    { id = "ide", title = "Редактор", subtitle = "CCIDE: Lua и программы", path = "/ccide.lua", color = colors.blue },
    { id = "plan", title = "План производства", subtitle = "Очередь и диспетчеризация", path = "/plan.lua", color = colors.green },
    { id = "checklist", title = "Чеклист материалов", subtitle = "Create Material Checklist", path = "/checklist.lua", color = colors.orange },
    { id = "inspect", title = "Инспектор Create", subtitle = "Периферия и методы", path = "/inspect_create.lua", color = colors.purple },
  },
}]====],
  ["/concordos/system/boot.lua"] = [====[local ROOT = "/concordos"
local MARKER = ROOT .. "/.booting"
local CRASH_LOG = ROOT .. "/logs/crash.log"

local function loadRu()
  local ok, result = pcall(dofile, ROOT .. "/system/lib/ru.lua")
  return ok and result or nil
end

local ru = loadRu()
local function say(text)
  if ru then ru.write(term, text) else term.write(tostring(text)) end
end
local function nextLine()
  local _, y = term.getCursorPos()
  local _, height = term.getSize()
  if y >= height then
    term.scroll(1)
    term.setCursorPos(1, height)
  else
    term.setCursorPos(1, y + 1)
  end
end
local function sayLine(text)
  say(text)
  nextLine()
end

local function writeFile(path, content)
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
  local file = fs.open(path, "w")
  if file then file.write(content) file.close() end
end

local function recovery(reason)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.red)
  sayLine("ConcordOS: режим восстановления")
  term.setTextColor(colors.white)
  sayLine(reason)
  sayLine("")
  sayLine("1 - Запустить рабочий стол")
  sayLine("2 - Открыть безопасный терминал")
  sayLine("R - Перезагрузить компьютер")
  sayLine("Q - Выключить компьютер")

  while true do
    local event, key = os.pullEventRaw("key")
    if event == "key" then
      if key == keys.one then
        fs.delete(MARKER)
        return true
      elseif key == keys.two then
        fs.delete(MARKER)
        term.setCursorPos(1, 10)
        shell.run("shell")
        return false
      elseif key == keys.r then
        os.reboot()
      elseif key == keys.q then
        os.shutdown()
      end
    end
  end
end

if not fs.exists(ROOT .. "/system/desktop.lua") then
  recovery("Системные файлы не найдены: " .. ROOT .. "/system/desktop.lua")
elseif fs.exists(MARKER) then
  if not recovery("Предыдущая загрузка не завершилась корректно.") then return end
end

writeFile(MARKER, "booting " .. tostring(os.epoch and os.epoch("utc") or os.clock()))
local ok, result = xpcall(function()
  return parallel.waitForAny(
    function() return shell.run(ROOT .. "/system/desktop.lua") end,
    function() return shell.run(ROOT .. "/system/order_service.lua") end
  )
end, function(err) return tostring(err) end)

if ok and result ~= false then
  if fs.exists(MARKER) then fs.delete(MARKER) end
else
  writeFile(CRASH_LOG, "ConcordOS crash\n" .. tostring(result) .. "\n")
  recovery("Рабочий стол завершился с ошибкой. Лог: " .. CRASH_LOG)
end]====],
  ["/concordos/system/desktop.lua"] = [====[local ROOT = "/concordos"
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
end]====],
  ["/concordos/system/order_service.lua"] = [====[-- Background service for persistent industrial requests.
local orders = dofile("/concordos/system/lib/orders.lua")

while true do
  pcall(orders.tick)
  sleep(15)
end]====],
  ["/concordos/system/lib/orders.lua"] = [====[-- Persistent Stock Ticker orders. An order is complete when Create accepts
-- the requested quantity for transport; delivery itself is handled by Create.
local orders = {}

local ROOT = "/concordos"
local PATH = ROOT .. "/data/orders.db"
local RETRY_BASE_MS = 30000
local RETRY_MAX_MS = 120000
local function now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

local function defaultData()
  return { version = 1, nextId = 1, orders = {}, addresses = {} }
end

local function rememberAddress(data, address)
  address = tostring(address or "")
  if address == "" then return end
  data.addresses = data.addresses or {}
  for index = #data.addresses, 1, -1 do
    if data.addresses[index] == address then table.remove(data.addresses, index) end
  end
  table.insert(data.addresses, 1, address)
  while #data.addresses > 12 do table.remove(data.addresses) end
end

function orders.load()
  if not fs.exists(PATH) then return defaultData() end
  local file = fs.open(PATH, "r")
  if not file then return defaultData() end
  local raw = file.readAll()
  file.close()
  local data = textutils.unserialize(raw)
  if type(data) ~= "table" or type(data.orders) ~= "table" then return defaultData() end
  data.nextId = tonumber(data.nextId) or 1
  if type(data.addresses) ~= "table" then data.addresses = {} end
  for _, order in ipairs(data.orders) do
    if order.state == "queued" or order.state == "pending" then order.state = "active" end
    order.nextAttemptAt = tonumber(order.nextAttemptAt) or 0
    order.emptyAttempts = tonumber(order.emptyAttempts) or 0
  end
  return data
end

function orders.save(data)
  local directory = fs.getDir(PATH)
  if not fs.exists(directory) then fs.makeDir(directory) end
  local file = assert(fs.open(PATH, "w"), "Cannot write " .. PATH)
  file.write(textutils.serialize(data))
  file.close()
end

function orders.create(address, item, count)
  local data = orders.load()
  local order = {
    id = data.nextId,
    address = tostring(address),
    item = tostring(item),
    requested = math.max(1, math.floor(tonumber(count) or 1)),
    accepted = 0,
    state = "active",
    attempts = 0,
    emptyAttempts = 0,
    createdAt = now(),
    lastAttemptAt = 0,
    nextAttemptAt = 0,
    lastResult = "Создано",
  }
  data.nextId = order.id + 1
  data.orders[#data.orders + 1] = order
  rememberAddress(data, order.address)
  orders.save(data)
  return order
end

function orders.rememberAddress(address)
  local data = orders.load()
  rememberAddress(data, address)
  orders.save(data)
end

function orders.addresses()
  return orders.load().addresses
end

function orders.cancel(id)
  local data = orders.load()
  for _, order in ipairs(data.orders) do
    if order.id == id and order.state == "active" then
      order.state = "cancelled"
      order.lastResult = "Отменено оператором"
      orders.save(data)
      return true
    end
  end
  return false
end

function orders.retry(id)
  local data = orders.load()
  for _, order in ipairs(data.orders) do
    if order.id == id and order.state == "active" then
      order.nextAttemptAt = 0
      order.lastResult = "Повтор назначен оператором"
      orders.save(data)
      return true
    end
  end
  return false
end

function orders.remaining(order)
  return math.max(0, (tonumber(order.requested) or 0) - (tonumber(order.accepted) or 0))
end

function orders.active()
  local result = {}
  for _, order in ipairs(orders.load().orders) do
    if order.state == "active" then result[#result + 1] = order end
  end
  return result
end

function orders.tick(forceOrderId)
  local data = orders.load()
  local changed = false
  local stockTicker = peripheral.find("Create_StockTicker")
  local current = now()

  for _, order in ipairs(data.orders) do
    if order.state == "active" then
      local remaining = orders.remaining(order)
      if remaining <= 0 then
        order.state = "accepted"
        order.lastResult = "Весь объём принят сетью"
        changed = true
      elseif stockTicker and (forceOrderId == order.id or current >= (tonumber(order.nextAttemptAt) or 0)) then
        order.lastAttemptAt = current
        order.attempts = (tonumber(order.attempts) or 0) + 1
        local ok, result = pcall(stockTicker.requestFiltered, order.address, {
          name = order.item,
          _requestCount = remaining,
        })
        if ok then
          local accepted = math.max(0, math.floor(tonumber(result) or 0))
          order.accepted = math.min(order.requested, (tonumber(order.accepted) or 0) + accepted)
          if orders.remaining(order) <= 0 then
            order.state = "accepted"
            order.lastResult = "Весь объём принят сетью"
          else
            if accepted > 0 then order.emptyAttempts = 0 else order.emptyAttempts = (tonumber(order.emptyAttempts) or 0) + 1 end
            local delay = math.min(RETRY_MAX_MS, RETRY_BASE_MS * (2 ^ math.max(0, (tonumber(order.emptyAttempts) or 0) - 1)))
            order.nextAttemptAt = current + delay
            order.lastResult = "Принято " .. tostring(accepted) .. ", остаток " .. tostring(orders.remaining(order)) .. "; повтор через " .. tostring(math.floor(delay / 1000)) .. " с"
          end
        else
          order.emptyAttempts = (tonumber(order.emptyAttempts) or 0) + 1
          local delay = math.min(RETRY_MAX_MS, RETRY_BASE_MS * (2 ^ math.max(0, order.emptyAttempts - 1)))
          order.nextAttemptAt = current + delay
          order.lastResult = "Ошибка Stock Ticker: " .. tostring(result)
        end
        changed = true
      elseif not stockTicker then
        if order.lastResult ~= "Stock Ticker не найден" then
          order.lastResult = "Stock Ticker не найден"
          order.nextAttemptAt = current + RETRY_BASE_MS
          changed = true
        end
      end
    end
  end

  if changed then orders.save(data) end
  return data
end

return orders]====],
  ["/concordos/system/lib/ru.lua"] = [====[-- ConcordOS: UTF-8 logic and CP866 terminal output for CC:Tweaked.
-- Requires the accompanying resource pack that replaces term_font.png.

local ru = {}

local utf = utf8

local replacements = {
  [0x2116] = "No", -- №
  [0x00AB] = '"', [0x00BB] = '"',
  [0x2013] = "-", [0x2014] = "-", [0x2212] = "-",
  [0x2026] = "...",
  [0x00A0] = " ",
}

local function encodeCodepoint(code)
  if code < 0x80 then return string.char(code) end
  if code >= 0x0410 and code <= 0x042F then return string.char(0x80 + code - 0x0410) end
  if code >= 0x0430 and code <= 0x043F then return string.char(0xA0 + code - 0x0430) end
  if code >= 0x0440 and code <= 0x044F then return string.char(0xE0 + code - 0x0440) end
  if code == 0x0401 then return string.char(0xF0) end -- Ё
  if code == 0x0451 then return string.char(0xF1) end -- ё
  return replacements[code] or "?"
end

function ru.encode(value)
  local text = tostring(value or "")
  if not utf or not utf.codes then return text end

  local ok, result = pcall(function()
    local out = {}
    for _, code in utf.codes(text) do out[#out + 1] = encodeCodepoint(code) end
    return table.concat(out)
  end)
  return ok and result or text
end

function ru.len(value)
  local text = tostring(value or "")
  if utf and utf.len then return utf.len(text) or #text end
  return #text
end

function ru.sub(value, first, last)
  local text = tostring(value or "")
  local length = ru.len(text)
  first = first or 1
  last = last or length
  if first < 0 then first = length + first + 1 end
  if last < 0 then last = length + last + 1 end
  if first < 1 then first = 1 end
  if last < first then return "" end
  if not utf or not utf.offset then return text:sub(first, last) end
  local beginAt = utf.offset(text, first)
  if not beginAt then return "" end
  local afterAt = utf.offset(text, last + 1)
  return text:sub(beginAt, afterAt and afterAt - 1 or #text)
end

function ru.lower(value)
  local text = tostring(value or "")
  if not utf or not utf.codes then return text:lower() end
  local out = {}
  local ok = pcall(function()
    for _, code in utf.codes(text) do
      if code >= 0x41 and code <= 0x5A then code = code + 0x20 end
      if code >= 0x0410 and code <= 0x042F then code = code + 0x20 end
      if code == 0x0401 then code = 0x0451 end
      out[#out + 1] = utf.char(code)
    end
  end)
  return ok and table.concat(out) or text:lower()
end

function ru.upper(value)
  local text = tostring(value or "")
  if not utf or not utf.codes then return text:upper() end
  local out = {}
  local ok = pcall(function()
    for _, code in utf.codes(text) do
      if code >= 0x61 and code <= 0x7A then code = code - 0x20 end
      if code >= 0x0430 and code <= 0x044F then code = code - 0x20 end
      if code == 0x0451 then code = 0x0401 end
      out[#out + 1] = utf.char(code)
    end
  end)
  return ok and table.concat(out) or text:upper()
end

function ru.equalsIgnoreCase(a, b)
  return ru.lower(a) == ru.lower(b)
end

function ru.fit(value, width, suffix)
  local text = tostring(value or "")
  width = math.max(0, width or 0)
  if ru.len(text) <= width then return text end
  suffix = suffix == nil and "..." or suffix
  local room = width - ru.len(suffix)
  if room <= 0 then return ru.sub(suffix, 1, width) end
  return ru.sub(text, 1, room) .. suffix
end

function ru.padRight(value, width)
  local text = ru.fit(value, width, "")
  return text .. string.rep(" ", math.max(0, width - ru.len(text)))
end

function ru.center(value, width)
  local text = ru.fit(value, width, "")
  local left = math.max(0, math.floor((width - ru.len(text)) / 2))
  return string.rep(" ", left) .. text
end

function ru.write(target, value)
  (target or term).write(ru.encode(value))
end

function ru.blit(target, value, foreground, background)
  (target or term).blit(ru.encode(value), foreground, background)
end

function ru.print(target, value)
  local output = target or term
  ru.write(output, value)
  local _, y = output.getCursorPos()
  local _, height = output.getSize()
  if y >= height then
    output.scroll(1)
    output.setCursorPos(1, height)
  else
    output.setCursorPos(1, y + 1)
  end
end

return ru]====],
  ["/concordos/system/lib/ui.lua"] = [====[local ru = dofile("/concordos/system/lib/ru.lua")

local ui = { ru = ru }

function ui.size(target)
  return (target or term).getSize()
end

function ui.clear(target, background)
  local output = target or term
  if background then output.setBackgroundColor(background) end
  output.clear()
  output.setCursorPos(1, 1)
end

function ui.text(target, x, y, value, foreground, background, width)
  local output = target or term
  if foreground then output.setTextColor(foreground) end
  if background then output.setBackgroundColor(background) end
  output.setCursorPos(x, y)
  ru.write(output, width and ru.padRight(value, width) or value)
end

function ui.line(target, x, y, width, value, foreground, background)
  ui.text(target, x, y, ru.fit(value, width, ""), foreground, background, width)
end

function ui.fill(target, x, y, width, height, background)
  local output = target or term
  output.setBackgroundColor(background)
  local blank = string.rep(" ", math.max(0, width))
  for row = y, y + height - 1 do
    output.setCursorPos(x, row)
    output.write(blank)
  end
end

function ui.button(target, x, y, width, height, label, foreground, background, active)
  local output = target or term
  local bg = active and colors.lightBlue or background
  ui.fill(output, x, y, width, height, bg)
  local labelY = y + math.floor((height - 1) / 2)
  ui.text(output, x, labelY, ru.center(label, width), foreground, bg, width)
end

function ui.inside(x, y, left, top, width, height)
  return x >= left and x < left + width and y >= top and y < top + height
end

return ui]====],
}

local function writeFile(path, content)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local file = assert(fs.open(path, "w"), "Cannot write " .. path)
  file.write(content)
  file.close()
end

if fs.exists("/startup") and not fs.exists("/startup.before_concordos") then
  fs.copy("/startup", "/startup.before_concordos")
end
for path, content in pairs(files) do writeFile(path, content) end
print("ConcordOS installed.")
print("Previous startup: /startup.before_concordos (if it existed).")
print("Enable the ConcordOS resource pack on the Minecraft client, then run reboot.")
