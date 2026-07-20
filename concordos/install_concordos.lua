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
  ["/update"] = [====[-- ConcordOS online updater. It deliberately never writes /concordos/data.
local BASE_URL = "https://raw.githubusercontent.com/nioan10/concordOS/main/concordos"
local ru = dofile("/concordos/system/lib/ru.lua")
local output = term.current()

local function sayLine(value)
  ru.print(output, value)
end

local function say(value)
  ru.write(output, value)
end

local function readRemote(url)
  if not http then return nil, "HTTP отключён в настройках CC:Tweaked" end
  local response, err = http.get(url)
  if not response then return nil, tostring(err or "не удалось подключиться") end
  local content = response.readAll()
  response.close()
  return content
end

local function writeFile(path, content)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local file = assert(fs.open(path, "w"), "Не удалось записать " .. path)
  file.write(content)
  file.close()
end

local function loadManifest(content)
  local chunk, err = load(content, "=ConcordOS manifest", "t", {})
  if not chunk then return nil, err end
  local ok, manifest = pcall(chunk)
  if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
    return nil, "манифест имеет неверный формат"
  end
  return manifest
end

local function safeTarget(path)
  return path == "/startup" or path == "/update" or path:sub(1, 11) == "/concordos/"
end

local function validLua(path, content)
  if path:sub(-4) ~= ".lua" and path ~= "/startup" and path ~= "/update" then return true end
  local chunk, err = load(content, "=" .. path, "t", {})
  return chunk ~= nil, err
end

local function localVersion()
  local path = "/concordos/system/config.lua"
  if not fs.exists(path) then return nil end
  local file = fs.open(path, "r")
  if not file then return nil end
  local content = file.readAll()
  file.close()
  return content:match("version%s*=%s*[\"']([^\"']+)[\"']")
end

local function runUpdate()
  sayLine("ConcordOS: проверка обновлений")
  local manifestText, manifestError = readRemote(BASE_URL .. "/manifest.lua")
  if not manifestText then return false, "Не удалось получить манифест: " .. manifestError end

  local manifest, parseError = loadManifest(manifestText)
  if not manifest then return false, "Ошибка манифеста: " .. tostring(parseError) end

  local installedVersion = localVersion()
  if installedVersion and manifest.version and tostring(installedVersion) == tostring(manifest.version) then
    return true, "ConcordOS уже актуальна: версия " .. tostring(installedVersion) .. ". Ничего не скачивалось.", false
  end

  if installedVersion then
    sayLine("Установлена " .. tostring(installedVersion) .. ", доступна " .. tostring(manifest.version) .. ".")
  else
    sayLine("Локальная версия не определена; выполняется проверочное обновление.")
  end

  local downloads = {}
  for index, entry in ipairs(manifest.files) do
    if type(entry) ~= "table" or type(entry.source) ~= "string" or type(entry.target) ~= "string" or not safeTarget(entry.target) then
      return false, "Некорректная запись манифеста №" .. tostring(index)
    end
    say("Скачивание " .. entry.source .. "... ")
    local content, err = readRemote(BASE_URL .. "/" .. entry.source)
    if not content then return false, "Ошибка загрузки " .. entry.source .. ": " .. tostring(err) end
    local valid, syntaxError = validLua(entry.target, content)
    if not valid then return false, "Ошибка синтаксиса " .. entry.source .. ": " .. tostring(syntaxError) end
    downloads[#downloads + 1] = { target = entry.target, content = content }
    sayLine("готово")
  end

  for _, file in ipairs(downloads) do
    local temporary = file.target .. ".new"
    local backup = file.target .. ".bak"
    if fs.exists(temporary) then fs.delete(temporary) end
    writeFile(temporary, file.content)
    if fs.exists(file.target) and not fs.exists(backup) then fs.copy(file.target, backup) end
    if fs.exists(file.target) then fs.delete(file.target) end
    fs.move(temporary, file.target)
  end

  return true, "ConcordOS обновлён до " .. tostring(manifest.version) .. ".", true
end

local function waitForUser()
  sayLine("")
  sayLine("Нажми любую клавишу или кликни для возврата.")
  while true do
    local event = os.pullEventRaw()
    if event == "key" or event == "mouse_click" or event == "monitor_touch" or event == "terminate" then return end
  end
end

output.setBackgroundColor(colors.black)
output.setTextColor(colors.white)
output.clear()
output.setCursorPos(1, 1)

local ran, success, message, changed = pcall(runUpdate)
if not ran then
  output.setTextColor(colors.red)
  sayLine("Внутренняя ошибка обновления: " .. tostring(success))
elseif not success then
  output.setTextColor(colors.red)
  sayLine(message)
else
  output.setTextColor(colors.lime)
  sayLine(message)
  if changed then
    output.setTextColor(colors.lightGray)
    sayLine("Заявки и данные не затрагивались. Затем выполни reboot.")
  end
end
output.setTextColor(colors.white)
waitForUser()]====],
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
sayLine("help — справка, exit — рабочий стол.")
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
local fields = { address = "", item = "", amount = "", search = "", buildName = "Стройка" }
local catalogResults = {}
local catalogPage = 0
local CATALOG_PAGE_SIZE = 5
local clipboardResults = {}
local clipboardPage = 0
local CLIPBOARD_PAGE_SIZE = 7
local clipboardSelected = {}
local addressReturnPage = "order"
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

local function selectedClipboardItems()
  local result = {}
  for _, item in ipairs(clipboardResults) do
    if clipboardSelected[item.name] then result[#result + 1] = { item = item.name, count = item.count } end
  end
  return result
end

local function selectedClipboardCount()
  return #selectedClipboardItems()
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

local function drawBuildOrder(width)
  local selected = selectedClipboardItems()
  local total = 0
  for _, item in ipairs(selected) do total = total + item.count end
  ui.text(output, 2, 5, "Заказ стройки: " .. tostring(#selected) .. " позиций из блокнота", colors.lightGray, colors.gray)
  inputBox(2, 6, width - 13, "Адрес доставки", fields.address, activeField == "address")
  ui.button(output, width - 9, 6, 9, 2, "Адреса", colors.white, colors.blue, false)
  inputBox(2, 9, width - 3, "Название заказа", fields.buildName, activeField == "buildName")
  ui.text(output, 2, 12, "Всего: " .. formatQuantity(total) .. ". Каждая позиция будет постоянной заявкой.", colors.lightGray, colors.gray)
  ui.text(output, 2, 14, "После подтверждения откроется общий статус стройки.", colors.lightGray, colors.gray)
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, 16, leftWidth, 2, "Отмена", colors.white, colors.gray, false)
  ui.button(output, 3 + leftWidth, 16, width - 3 - leftWidth, 2, "Создать заказ", colors.white, colors.red, false)
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
  clipboardSelected = {}
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
  for _, item in ipairs(clipboardResults) do clipboardSelected[item.name] = true end
  clipboardPage = 0
  setStatus(#clipboardResults == 0 and "В блокноте нет недостающих предметов" or ("Считано позиций: " .. tostring(#clipboardResults)), colors.lightGray)
  return true
end

local function drawClipboard(width)
  ui.text(output, 2, 5, "Недостающие материалы из планшета Create", colors.lightGray, colors.gray)
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, 6, leftWidth, 1, "Считать блокнот", colors.white, colors.purple, false)
  ui.button(output, 3 + leftWidth, 6, width - 3 - leftWidth, 1, "Все / снять", colors.white, colors.blue, false)
  if #clipboardResults == 0 then
    ui.text(output, 2, 8, "Нажми «Считать блокнот», затем отметь позиции.", colors.lightGray, colors.gray)
    return
  end
  local totalPages = math.max(1, math.ceil(#clipboardResults / CLIPBOARD_PAGE_SIZE))
  if clipboardPage >= totalPages then clipboardPage = totalPages - 1 end
  local first = clipboardPage * CLIPBOARD_PAGE_SIZE + 1
  ui.text(output, 2, 7, "Выбрано: " .. tostring(selectedClipboardCount()) .. ". Стр. " .. tostring(clipboardPage + 1) .. "/" .. tostring(totalPages), colors.lightGray, colors.gray)
  for offset = 0, CLIPBOARD_PAGE_SIZE - 1 do
    local item = clipboardResults[first + offset]
    if item then
      local mark = clipboardSelected[item.name] and "[x] " or "[ ] "
      local label = mark .. tostring(item.displayName or item.name) .. " x" .. formatQuantity(item.count)
      ui.line(output, 2, 8 + offset, width - 3, ru.fit(label, width - 3, ""), colors.white, offset % 2 == 0 and colors.gray or colors.black)
    end
  end
  ui.button(output, 2, 16, leftWidth, 1, "< Пред.", colors.white, colors.gray, clipboardPage > 0)
  ui.button(output, 3 + leftWidth, 16, width - 3 - leftWidth, 1, "След. >", colors.white, colors.gray, clipboardPage < totalPages - 1)
  ui.button(output, 2, 17, leftWidth, 1, "Очистить выбор", colors.white, colors.gray, false)
  ui.button(output, 3 + leftWidth, 17, width - 3 - leftWidth, 1, "Заказ: " .. tostring(selectedClipboardCount()), colors.white, colors.red, selectedClipboardCount() > 0)
end

local function orderBar(order)
  local requested = math.max(1, tonumber(order.requested) or 1)
  local accepted = tonumber(order.accepted) or 0
  local filled = math.min(8, math.floor(accepted * 8 / requested))
  return "[" .. string.rep("#", filled) .. string.rep("-", 8 - filled) .. "] " .. formatQuantity(accepted) .. "/" .. formatQuantity(requested)
end

local function progressBar(progress)
  local requested = math.max(1, tonumber(progress.requested) or 1)
  local accepted = tonumber(progress.accepted) or 0
  local filled = math.min(8, math.floor(accepted * 8 / requested))
  return "[" .. string.rep("#", filled) .. string.rep("-", 8 - filled) .. "] " .. formatQuantity(accepted) .. "/" .. formatQuantity(requested)
end

local function drawOrders(width)
  local groups = orders.groups()
  if #groups > 0 then
    local first = math.max(1, #groups - 2)
    local row = 5
    for index = first, #groups do
      local group = groups[index]
      local progress = orders.groupProgress(group.id)
      local state = progress.state == "active" and "в работе" or (progress.state == "accepted" and "готово" or "отмена")
      ui.line(output, 2, row, width - 3, "Стройка №" .. tostring(group.id) .. " [" .. state .. "] " .. ru.fit(group.title, width - 22, ""), colors.white, colors.gray)
      ui.line(output, 2, row + 1, width - 11, progressBar(progress), colors.lightGray, colors.black)
      ui.button(output, width - 8, row + 1, 3, 1, "R", colors.white, colors.blue, false)
      ui.button(output, width - 4, row + 1, 3, 1, "X", colors.white, colors.red, false)
      ui.line(output, 2, row + 2, width - 3, ru.fit("-> " .. tostring(group.address), width - 3, ""), colors.lightGray, colors.gray)
      row = row + 4
    end
    return
  end
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
  elseif page == "build" then drawBuildOrder(width)
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

local function submitBuildOrder()
  local items = selectedClipboardItems()
  if fields.address == "" or #items == 0 then
    setStatus("Выбери позиции и укажи адрес доставки", colors.red)
    return
  end
  local group, created = orders.createGroup(fields.address, items, fields.buildName)
  if not group then
    setStatus(tostring(created or "Не удалось создать заказ стройки"), colors.red)
    return
  end
  local ok, err = pcall(orders.tick)
  page, activeField = "orders", nil
  if ok then
    setStatus("Заказ стройки №" .. tostring(group.id) .. ": " .. tostring(#created) .. " позиций", colors.lime)
  else
    setStatus("Заказ сохранён: " .. tostring(err), colors.orange)
  end
end

local function fieldAt(x, y, width)
  if (page == "order" or page == "build") and x >= 2 and x < width - 11 then
    if y == 7 then return "address" end
    if page == "order" then
      if y == 10 then return "item" end
      if y == 13 then return "amount" end
    elseif y == 10 then
      return "buildName"
    end
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
      elseif page == "build" then
        activeField = activeField == "address" and "buildName" or "address"
      end
    elseif a == keys.backspace and not confirmation then backspace()
    elseif a == keys.enter then
      if confirmation then submitOrder()
      elseif page == "order" then confirmation = true
      elseif page == "build" then submitBuildOrder()
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
      elseif (page == "order" or page == "build") and x >= width - 9 and y >= 6 and y <= 7 then
        addressReturnPage = page
        page, activeField = "addresses", nil
      elseif page == "addresses" and y == 6 then
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          page, activeField = addressReturnPage, "address"
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
          page, activeField = addressReturnPage, addressReturnPage == "build" and "buildName" or "item"
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
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          readClipboard()
        else
          local selectAll = selectedClipboardCount() < #clipboardResults
          clipboardSelected = {}
          if selectAll then
            for _, item in ipairs(clipboardResults) do clipboardSelected[item.name] = true end
          end
        end
      elseif page == "clipboard" and y >= 8 and y <= 14 then
        local item = clipboardResults[clipboardPage * CLIPBOARD_PAGE_SIZE + y - 7]
        if item then
          clipboardSelected[item.name] = not clipboardSelected[item.name]
        end
      elseif page == "clipboard" and y == 16 then
        local totalPages = math.max(1, math.ceil(#clipboardResults / CLIPBOARD_PAGE_SIZE))
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          clipboardPage = math.max(0, clipboardPage - 1)
        else
          clipboardPage = math.min(totalPages - 1, clipboardPage + 1)
        end
      elseif page == "clipboard" and y == 17 then
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          clipboardSelected = {}
        elseif selectedClipboardCount() > 0 then
          page, activeField = "build", "address"
        else
          setStatus("Отметь хотя бы одну позицию", colors.orange)
        end
      elseif page == "build" and y >= 16 and y <= 17 then
        local leftWidth = math.floor((width - 3) / 2)
        if x < 3 + leftWidth then
          page, activeField = "clipboard", nil
        else
          submitBuildOrder()
        end
      elseif page == "orders" then
        local groups = orders.groups()
        if #groups > 0 then
          local first = math.max(1, #groups - 2)
          for index = first, #groups do
            local row = 5 + (index - first) * 4
            local group = groups[index]
            if y == row + 1 and x >= width - 8 and x <= width - 6 then
              if orders.retryGroup(group.id) then pcall(orders.tick) setStatus("Повтор стройки отправлен", colors.lime) end
            elseif y == row + 1 and x >= width - 4 then
              if orders.cancelGroup(group.id) then setStatus("Заказ стройки отменён", colors.orange) end
            end
          end
        else
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
    end
    draw()
  elseif event == "terminate" then
    return
  end
end]====],
  ["/concordos/apps/mines.lua"] = [====[-- A small touch-friendly Minesweeper for ConcordOS.
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
  { title = "Сложная", short = "Слож.", rows = 21, cols = 21, mines = 80 },
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

local function homeButton(target)
  local width = target.getSize()
  local buttonWidth = width >= 40 and 11 or 3
  return width - buttonWidth + 1, buttonWidth, buttonWidth == 3 and "<" or "< Главная"
end

local function drawTarget(target)
  local level = settings()
  local width, height, left, top = geometry(target)
  ui.clear(target, colors.gray)
  local state = lost and "Мина!" or (won and "Победа!" or "Мин: " .. tostring(level.mines - flagCount()))
  ui.line(target, 1, 1, width, "ConcordOS | Сапёр | " .. level.title .. " | " .. state, lost and colors.red or (won and colors.lime or colors.white), colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(target)
  ui.button(target, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(target, homeX, 1, homeLabel, colors.white, colors.lightBlue)
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

local function clickedHome(target, x, y)
  local homeX, homeWidth = homeButton(target)
  return y == 1 and x >= homeX and x < homeX + homeWidth
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
    if clickedHome(computer, b, c) then
      return
    elseif chooseDifficulty(computer, b, c) then
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
    if clickedHome(monitor, b, c) then
      return
    elseif chooseDifficulty(monitor, b, c) then
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
end]====],
  ["/concordos/apps/inspect.lua"] = [====[-- ConcordOS Create and ComputerCraft peripheral inspector.
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
  { "CC:C Bridge: create_source", colors.orange },
  { "Это терминал для Create Display Target. Он имеет", colors.white },
  { "25 методов: write(), clear(), blit(), scroll(),", colors.white },
  { "цвета, палитру, курсор и размер — как у term.", colors.white },
  { "Пример: source.clear(); source.write(\"Цех готов\").", colors.lightGray },
  { "", colors.gray },
  { "CC:C Bridge: create_target", colors.orange },
  { "Читает Create Display Source: dump(), getLine(),", colors.white },
  { "getSize(), resize(). Подходит для табло и датчиков.", colors.white },
  { "", colors.gray },
  { "CC:C Bridge: redrouter", colors.orange },
  { "getInput()/getOutput() читают сигнал; setOutput()", colors.white },
  { "задаёт его. Для аналогового сигнала есть методы", colors.white },
  { "getAnalogInput/Output и setAnalogOutput.", colors.white },
  { "", colors.gray },
  { "Все методы на вкладке «Методы» берутся прямо", colors.lightGray },
  { "с твоих блоков: это точнее любой статичной вики.", colors.lightGray },
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
end]====],
  ["/concordos/apps/power.lua"] = [====[-- Wireless power-station dashboard for ConcordOS.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end

local CHANNEL = 38172
local PROTOCOL = "concordos.power.v1"
local modem, modemName
local lastMessage, lastAt = nil, 0
local refreshTimer

local function now()
  return os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function findWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    local device = peripheral.wrap(name)
    if device and type(device.isWireless) == "function" then
      local ok, wireless = pcall(device.isWireless)
      if ok and wireless then return device, name end
    end
  end
end

local function homeButton(target)
  local width = target.getSize()
  local buttonWidth = width >= 40 and 11 or 3
  return width - buttonWidth + 1, buttonWidth, buttonWidth == 3 and "<" or "< Главная"
end

local function percent()
  if not lastMessage or type(lastMessage.lines) ~= "table" then return nil end
  local joined = table.concat(lastMessage.lines, " ")
  return tonumber(joined:match("(%d+%.?%d*)%s*%%"))
end

local function freshness()
  if not lastMessage then return nil end
  return math.max(0, math.floor((now() - lastAt) / 1000))
end

local function stateColor(value, age)
  if not value or (age and age > 4) then return colors.red end
  if value >= 90 then return colors.red end
  if value >= 70 then return colors.orange end
  return colors.lime
end

local function drawTarget(target)
  local width, height = target.getSize()
  ui.clear(target, colors.gray)
  ui.line(target, 1, 1, width, "ConcordOS | Энергопульт", colors.white, colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(target)
  ui.button(target, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(target, homeX, 1, homeLabel, colors.white, colors.lightBlue)

  if not modem then
    ui.text(target, 2, 5, "Беспроводной модем не найден.", colors.red, colors.gray)
    ui.text(target, 2, 7, "Поставь его на главный компьютер и открой пульт снова.", colors.lightGray, colors.gray)
    return
  end

  local age, load = freshness(), percent()
  if not lastMessage then
    ui.text(target, 2, 5, "Ожидание данных от электростанции…", colors.orange, colors.gray)
    ui.text(target, 2, 7, "Запусти power_node на компьютере рядом с create_target.", colors.lightGray, colors.gray)
  elseif age > 4 then
    ui.text(target, 2, 5, "Нет свежего сигнала: " .. tostring(age) .. " с.", colors.red, colors.gray)
    ui.text(target, 2, 7, "Проверь power_node и беспроводные модемы.", colors.lightGray, colors.gray)
  else
    local color = stateColor(load, age)
    ui.text(target, 2, 4, "Нагрузка центральной сети", colors.lightGray, colors.gray)
    ui.text(target, 2, 6, load and (tostring(load) .. "%") or "Нет процента в сообщении", color, colors.gray)
    local barWidth = math.max(8, width - 4)
    local filled = load and math.max(0, math.min(barWidth, math.floor(barWidth * load / 100))) or 0
    ui.line(target, 2, 8, barWidth, string.rep("#", filled) .. string.rep("-", barWidth - filled), color, colors.black)
    ui.text(target, 2, 10, load and (load >= 90 and "Критическая нагрузка" or (load >= 70 and "Высокая нагрузка" or "Запас мощности есть")) or "Проверь настройку Display Link", color, colors.gray)
    ui.text(target, 2, 12, "Узел: #" .. tostring(lastMessage.node or "?") .. "  Обновлено: " .. tostring(age) .. " с назад", colors.lightGray, colors.gray)
    if lastMessage.error then ui.text(target, 2, 14, "Ошибка узла: " .. trim(lastMessage.error), colors.red, colors.gray) end
    local rawRow = 16
    if height > rawRow + 1 and type(lastMessage.lines) == "table" then
      for _, line in ipairs(lastMessage.lines) do
        line = trim(line)
        if line ~= "" then
          ui.line(target, 2, rawRow, width - 3, "Источник: " .. line, colors.white, colors.black)
          break
        end
      end
    end
  end
  ui.line(target, 1, height, width, "Канал " .. tostring(CHANNEL) .. "  ·  F5: переподключить  ·  < Главная: выход", colors.black, colors.lightGray)
end

local function draw()
  for _, target in ipairs(outputs) do drawTarget(target) end
end

local function reconnect()
  if modem then pcall(modem.close, CHANNEL) end
  modem, modemName = findWirelessModem()
  if modem then modem.open(CHANNEL) end
end

local function clickedHome(target, x, y)
  local homeX, homeWidth = homeButton(target)
  return y == 1 and x >= homeX and x < homeX + homeWidth
end

reconnect()
draw()
refreshTimer = os.startTimer(1)

while true do
  local event, a, b, c, d = os.pullEventRaw()
  if event == "timer" and a == refreshTimer then
    refreshTimer = os.startTimer(1)
    draw()
  elseif event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    draw()
  elseif event == "modem_message" and b == CHANNEL and type(d) == "table" and d.protocol == PROTOCOL then
    lastMessage, lastAt = d, now()
    draw()
  elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
    local target, x, y = event == "monitor_touch" and monitor or computer, b, c
    if clickedHome(target, x, y) then return end
  elseif event == "key" then
    if a == keys.escape or a == keys.q then return end
    if a == keys.f5 then reconnect() end
    draw()
  elseif event == "peripheral" or event == "peripheral_detach" then
    reconnect()
    draw()
  elseif event == "terminate" then
    return
  end
end]====],
  ["/concordos/system/config.lua"] = [====[return {
  name = "ConcordOS",
  country = "Конкордат Фессалоник",
  version = "0.6.0",
  mainApps = {
    { id = "master", title = "Мастер промзоны", subtitle = "Заявки, склад и сеть Create", path = "/concordos/apps/master_gui.lua", color = colors.red, featured = true },
    { id = "terminal", title = "Терминал", subtitle = "Русская командная строка", path = "/concordos/apps/rterm.lua", color = colors.black },
    { id = "ide", title = "Редактор", subtitle = "CCIDE: Lua и программы", path = "/ccide.lua", color = colors.blue },
    { id = "tools", title = "Инструменты", subtitle = "План, чеклист и диагностика", kind = "folder", color = colors.purple },
  },
  tools = {
    { id = "update", title = "Обновления", subtitle = "Проверить ConcordOS", path = "/update", color = colors.lightBlue },
    { id = "plan", title = "План производства", subtitle = "Очередь и диспетчеризация", path = "/plan.lua", color = colors.green },
    { id = "checklist", title = "Чеклист материалов", subtitle = "Create Material Checklist", path = "/checklist.lua", color = colors.orange },
    { id = "inspect", title = "Инспектор Create", subtitle = "Периферии, методы и CC-интеграции", path = "/concordos/apps/inspect.lua", color = colors.purple },
    { id = "mines", title = "Сапёр", subtitle = "Короткая передышка от промзоны", path = "/concordos/apps/mines.lua", color = colors.green },
    { id = "power", title = "Энергопульт", subtitle = "Нагрузка центральной сети вращения", path = "/concordos/apps/power.lua", color = colors.yellow },
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
local section = "main"

local function hasAvailableApp(apps)
  for _, app in ipairs(apps or {}) do
    if app.path == "shell" or (app.path and fs.exists(app.path)) then return true end
  end
  return false
end

local function appList()
  visible = {}
  local source = section == "tools" and config.tools or config.mainApps
  for _, app in ipairs(source or {}) do
    local available = app.kind == "folder" and hasAvailableApp(config.tools)
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
  local sectionTitle = section == "tools" and "Инструменты и тесты" or "Главный пульт"
  local sectionSubtitle = section == "tools"
    and "Служебные программы и диагностика"
    or "Заказы, производство и управление сетью"

  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width,
    ultraCompact and (config.name .. " | " .. sectionTitle) or (config.name .. " | " .. config.country),
    colors.white, colors.blue)
  if section == "tools" then
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
  if section == "tools" then
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
    section = "tools"
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
    if section == "tools" and ui.inside(mouseX, mouseY, backX, backY, backWidth, 1) then
      section = "main"
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
      if section == "tools" then
        section = "main"
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
  return { version = 2, nextId = 1, nextGroupId = 1, orders = {}, addresses = {}, groups = {} }
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
  data.nextGroupId = tonumber(data.nextGroupId) or 1
  if type(data.addresses) ~= "table" then data.addresses = {} end
  if type(data.groups) ~= "table" then data.groups = {} end
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

function orders.createGroup(address, items, title)
  local data = orders.load()
  local grouped = {}
  for _, entry in ipairs(items or {}) do
    local item = tostring(type(entry) == "table" and entry.item or "")
    local count = math.max(0, math.floor(tonumber(type(entry) == "table" and entry.count) or 0))
    if item ~= "" and count > 0 then grouped[item] = (grouped[item] or 0) + count end
  end

  local names = {}
  for item in pairs(grouped) do names[#names + 1] = item end
  table.sort(names)
  if #names == 0 then return nil, "Нет позиций для заказа" end

  local group = {
    id = data.nextGroupId,
    title = tostring(title or "Стройка"),
    address = tostring(address or ""),
    createdAt = now(),
  }
  data.nextGroupId = group.id + 1
  data.groups[#data.groups + 1] = group

  local created = {}
  for _, item in ipairs(names) do
    local order = {
      id = data.nextId,
      groupId = group.id,
      address = group.address,
      item = item,
      requested = grouped[item],
      accepted = 0,
      state = "active",
      attempts = 0,
      emptyAttempts = 0,
      createdAt = now(),
      lastAttemptAt = 0,
      nextAttemptAt = 0,
      lastResult = "Создано в заказе стройки",
    }
    data.nextId = order.id + 1
    data.orders[#data.orders + 1] = order
    created[#created + 1] = order
  end
  rememberAddress(data, group.address)
  orders.save(data)
  return group, created
end

function orders.rememberAddress(address)
  local data = orders.load()
  rememberAddress(data, address)
  orders.save(data)
end

function orders.addresses()
  return orders.load().addresses
end

function orders.groups()
  return orders.load().groups
end

function orders.groupProgress(groupId)
  local requested, accepted, active, cancelled = 0, 0, 0, 0
  for _, order in ipairs(orders.load().orders) do
    if order.groupId == groupId then
      requested = requested + (tonumber(order.requested) or 0)
      accepted = accepted + (tonumber(order.accepted) or 0)
      if order.state == "active" then active = active + 1 end
      if order.state == "cancelled" then cancelled = cancelled + 1 end
    end
  end
  local state = active > 0 and "active" or (accepted >= requested and requested > 0 and "accepted" or "cancelled")
  return { requested = requested, accepted = accepted, active = active, cancelled = cancelled, state = state }
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

function orders.cancelGroup(groupId)
  local data = orders.load()
  local changed = false
  for _, order in ipairs(data.orders) do
    if order.groupId == groupId and order.state == "active" then
      order.state = "cancelled"
      order.lastResult = "Отменено вместе с заказом стройки"
      changed = true
    end
  end
  if changed then orders.save(data) end
  return changed
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

function orders.retryGroup(groupId)
  local data = orders.load()
  local changed = false
  for _, order in ipairs(data.orders) do
    if order.groupId == groupId and order.state == "active" then
      order.nextAttemptAt = 0
      order.lastResult = "Повтор назначен для заказа стройки"
      changed = true
    end
  end
  if changed then orders.save(data) end
  return changed
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
