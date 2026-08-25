-- Touch/mouse friendly graphical front-end for ConcordOS industrial orders.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local ru = ui.ru
local orders = dofile(ROOT .. "/system/lib/orders.lua")
local recipes = dofile(ROOT .. "/system/lib/recipes.lua")
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
local producedItems = {}
local selectedGroupId, groupDetailPage = nil, 0
local groupReturnPage = 'orders'
local GROUP_DETAIL_PAGE_SIZE = 3 -- positions per page
local groupSearch, groupSearchActive = '', false
local groupFilter, groupListPage = 'all', 0
local GROUP_LIST_PAGE_SIZE = 3
local pendingGroupCancelId = nil
local auditPage = 0
local AUDIT_PAGE_SIZE = 3

local tabs = {
  { id = "order", label = "Заказать" },
  { id = "orders", label = "Заявки" },
  { id = "stock", label = "Каталог" },
  { id = "network", label = "Сеть" },
}

local function setStatus(text, color)
  statusText, statusColor = tostring(text or ""), color or colors.lightGray
end

local function refreshProducedItems()
  producedItems = {}
  local ok, list = pcall(recipes.list)
  if ok and type(list) == "table" then
    for _, recipe in ipairs(list) do
      if recipe.output and recipe.output ~= "" then producedItems[recipe.output] = recipe end
    end
  end
end

local function isProduced(item)
  return producedItems[tostring(item or "")] ~= nil
end

local function itemLine(y, width, label, item, foreground, background)
  local badge = isProduced(item) and " КРАФТ" or ""
  local labelWidth = width - 3 - (badge == "" and 0 or 7)
  background = background or colors.black
  ui.line(output, 2, y, width - 3, ru.fit(label, labelWidth, ""), foreground or colors.white, background)
  if badge ~= "" then ui.text(output, width - 7, y, badge, colors.lime, background) end
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
  local tabWidth = math.max(1, math.floor(width / #tabs))
  for index, tab in ipairs(tabs) do
    local x = 1 + (index - 1) * tabWidth
    local size = index == #tabs and width - x + 1 or tabWidth
    ui.button(output, x, 3, size, 1, tab.label, colors.white, colors.gray, page == tab.id or ((page == 'group' or page == 'audit') and tab.id == 'orders'))
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
  refreshProducedItems()
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
      itemLine(11 + offset, width, label, itemName(item), colors.white, offset % 2 == 0 and colors.gray or colors.black)
    end
  end
  ui.button(output, 2, 17, leftWidth, 1, "< Пред.", colors.white, colors.gray, catalogPage > 0)
  ui.button(output, 3 + leftWidth, 17, width - 3 - leftWidth, 1, "След. >", colors.white, colors.gray, catalogPage < totalPages - 1)
end

local function readClipboard()
  refreshProducedItems()
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
      itemLine(8 + offset, width, label, item.name, colors.white, offset % 2 == 0 and colors.gray or colors.black)
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

local function orderStateLabel(order)
  if order.state == 'active' then return 'ожидание' end
  if order.state == 'accepted' then return 'принято' end
  if order.state == 'cancelled' then return 'отмена' end
  return tostring(order.state or '?')
end

local function orderStateColor(order)
  if order.state == 'accepted' then return colors.lime end
  if order.state == 'cancelled' then return colors.red end
  return colors.orange
end

local function groupStateLabel(progress)
  if progress.state == 'active' then return 'в работе' end
  if progress.state == 'partial' then return 'частично' end
  if progress.state == 'accepted' then return 'принято' end
  return 'отменено'
end

local function groupStateColor(progress)
  if progress.state == 'accepted' then return colors.lime end
  if progress.state == 'partial' then return colors.orange end
  if progress.state == 'cancelled' then return colors.red end
  return colors.lightBlue
end

local function groupPositionSummary(progress)
  local result = 'Поз.: ' .. tostring(progress.acceptedPositions or 0) .. '/' .. tostring(progress.totalPositions or 0) .. ' принято'
  if (progress.active or 0) > 0 then result = result .. ' · ожид.: ' .. tostring(progress.active) end
  if (progress.cancelled or 0) > 0 then result = result .. ' · отмен.: ' .. tostring(progress.cancelled) end
  return result
end

local function filteredGroups()
  local result = {}
  local query = ru.lower(tostring(groupSearch or ''):match('^%s*(.-)%s*$'))
  local allGroups = orders.groups()
  for index = #allGroups, 1, -1 do
    local group = allGroups[index]
    local progress = orders.groupProgress(group.id)
    local matchesState = groupFilter == 'all' or progress.state == groupFilter
    local searchable = ru.lower(tostring(group.title or '') .. ' ' .. tostring(group.address or ''))
    if matchesState and (query == '' or searchable:find(query, 1, true)) then
      result[#result + 1] = { group = group, progress = progress }
    end
  end
  return result
end

local function drawOrders(width, height)
  local filters = {
    { id = 'all', label = 'Все' },
    { id = 'active', label = 'Работа' },
    { id = 'partial', label = 'Часть' },
    { id = 'accepted', label = 'Принято' },
    { id = 'cancelled', label = 'Отмена' },
  }
  local overview = orders.overview()
  local summary = tostring(overview.groups) .. ' стр. | раб. ' .. tostring(overview.activeGroups) .. ' | часть ' .. tostring(overview.partialGroups) .. ' | принято ' .. tostring(overview.acceptedGroups)
  ui.line(output, 2, 5, width - 12, summary, overview.partialGroups > 0 and colors.orange or colors.lightGray, colors.gray)
  ui.button(output, width - 9, 5, 8, 1, overview.standaloneActive > 0 and ('Все ' .. tostring(overview.standaloneActive)) or 'Аудит', colors.white, colors.purple, false)

  for index, filter in ipairs(filters) do
    local x = 2 + math.floor((index - 1) * (width - 3) / #filters)
    local nextX = index == #filters and width - 1 or 2 + math.floor(index * (width - 3) / #filters)
    ui.button(output, x, 6, nextX - x - 1, 1, filter.label, colors.white, colors.blue, groupFilter == filter.id)
  end
  local searchText = groupSearch == '' and 'Поиск: название или адрес' or 'Поиск: ' .. groupSearch
  ui.line(output, 2, 7, width - 3, ru.fit(searchText .. (groupSearchActive and '|' or ''), width - 3, ''), groupSearch == '' and colors.lightGray or colors.white, groupSearchActive and colors.black or colors.gray)

  local groups = filteredGroups()
  local pages = math.max(1, math.ceil(#groups / GROUP_LIST_PAGE_SIZE))
  if groupListPage >= pages then groupListPage = pages - 1 end
  local first = groupListPage * GROUP_LIST_PAGE_SIZE + 1
  for offset = 0, GROUP_LIST_PAGE_SIZE - 1 do
    local entry = groups[first + offset]
    if entry then
      local row = 9 + offset * 3
      local group, progress = entry.group, entry.progress
      local background = offset % 2 == 0 and colors.gray or colors.black
      ui.line(output, 2, row, width - 3, '№' .. tostring(group.id) .. ' · ' .. groupStateLabel(progress) .. ' · ' .. ru.fit(group.title, width - 21, ''), groupStateColor(progress), background)
      ui.line(output, 2, row + 1, width - 18, progressBar(progress), colors.lightGray, colors.black)
      ui.button(output, width - 16, row + 1, 8, 1, 'Состав', colors.white, colors.purple, false)
      if progress.active > 0 then
        ui.button(output, width - 8, row + 1, 3, 1, 'R', colors.white, colors.blue, false)
        local confirming = pendingGroupCancelId == group.id
        ui.button(output, width - 4, row + 1, 3, 1, confirming and 'Да' or 'X', colors.white, confirming and colors.orange or colors.red, confirming)
      else
        ui.text(output, width - 8, row + 1, groupStateLabel(progress), groupStateColor(progress), colors.black)
      end
      ui.line(output, 2, row + 2, width - 3, ru.fit(groupPositionSummary(progress) .. '  → ' .. tostring(group.address), width - 3, ''), colors.lightGray, background)
    end
  end
  if #groups == 0 then
    ui.text(output, 2, 11, 'Стройзаказов по этому фильтру нет.', colors.lightGray, colors.gray)
  end
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, height - 1, leftWidth, 1, '< Пред.', colors.white, colors.gray, groupListPage > 0)
  ui.button(output, 3 + leftWidth, height - 1, width - 3 - leftWidth, 1, 'След. >', colors.white, colors.gray, groupListPage < pages - 1)
end

local function drawAudit(width, height)
  local audit = orders.audit()
  local entries = audit.entries
  local pages = math.max(1, math.ceil(#entries / AUDIT_PAGE_SIZE))
  if auditPage >= pages then auditPage = pages - 1 end
  ui.button(output, 2, 5, 11, 1, '< Назад', colors.white, colors.blue, false)
  ui.text(output, 14, 5, 'Все заявки и аудит', colors.white, colors.gray)
  local duplicateText = audit.duplicateSets > 0 and ('Дубли: ' .. tostring(audit.duplicateSets) .. ' (' .. tostring(audit.duplicateOrders) .. ' строк)') or 'Дублей нет'
  ui.line(output, 2, 6, width - 3, 'Активных: ' .. tostring(audit.active) .. ' | ' .. duplicateText, audit.duplicateSets > 0 and colors.red or colors.lime, colors.gray)
  ui.line(output, 2, 7, width - 3, 'Дубль = активный предмет на том же адресе. R/X только у активных.', colors.lightGray, colors.gray)

  local first = auditPage * AUDIT_PAGE_SIZE + 1
  for offset = 0, AUDIT_PAGE_SIZE - 1 do
    local entry = entries[first + offset]
    if entry then
      local order = entry.order
      local row = 9 + offset * 3
      local owner = entry.group and ('Стр. №' .. tostring(entry.group.id)) or 'Обычная'
      local title = (entry.duplicate and '! ДУБЛЬ ' or '') .. '№' .. tostring(order.id) .. ' [' .. owner .. '/' .. orderStateLabel(order) .. '] ' .. tostring(order.item)
      itemLine(row, width, title, order.item, entry.duplicate and colors.red or colors.white, offset % 2 == 0 and colors.gray or colors.black)
      ui.line(output, 2, row + 1, width - 11, orderBar(order), colors.lightGray, colors.black)
      if order.state == 'active' then
        ui.button(output, width - 8, row + 1, 3, 1, 'R', colors.white, colors.blue, false)
        ui.button(output, width - 4, row + 1, 3, 1, 'X', colors.white, colors.red, false)
      else
        ui.text(output, width - 9, row + 1, 'история', colors.lightGray, colors.black)
      end
      ui.line(output, 2, row + 2, width - 3, ru.fit('-> ' .. tostring(order.address) .. ' | ' .. tostring(order.lastResult or ''), width - 3, ''), colors.lightGray, colors.gray)
    end
  end
  if #entries == 0 then ui.text(output, 2, 10, 'Заявок нет.', colors.lime, colors.gray) end
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, height - 1, leftWidth, 1, '< Пред.', colors.white, colors.gray, auditPage > 0)
  ui.button(output, 3 + leftWidth, height - 1, width - 3 - leftWidth, 1, 'След. >', colors.white, colors.gray, auditPage < pages - 1)
end

local function drawGroupDetails(width, height)
  local group = orders.getGroup(selectedGroupId)
  if not group then
    ui.text(output, 2, 6, 'Заказ стройки не найден.', colors.red, colors.gray)
    return
  end
  local progress = orders.groupProgress(group.id)
  local entries = orders.groupOrders(group.id)
  local pages = math.max(1, math.ceil(#entries / GROUP_DETAIL_PAGE_SIZE))
  if groupDetailPage >= pages then groupDetailPage = pages - 1 end
  ui.button(output, 2, 5, 11, 1, '< Назад', colors.white, colors.blue, false)
  ui.text(output, 14, 5, ru.fit('Стройка №' .. tostring(group.id) .. ': ' .. tostring(group.title or ''), width - 15, ''), colors.white, colors.gray)
  ui.line(output, 2, 6, width - 3, groupStateLabel(progress) .. ' · ' .. groupPositionSummary(progress) .. ' → ' .. tostring(group.address or ''), groupStateColor(progress), colors.gray)
  ui.line(output, 2, 7, width - 3, 'Общий прогресс: ' .. progressBar(progress), colors.lightGray, colors.black)

  local first = groupDetailPage * GROUP_DETAIL_PAGE_SIZE + 1
  for offset = 0, GROUP_DETAIL_PAGE_SIZE - 1 do
    local order = entries[first + offset]
    if order then
      local row = 9 + offset * 3
      local title = '№' .. tostring(order.id) .. ' [' .. orderStateLabel(order) .. '] ' .. tostring(order.item)
      itemLine(row, width, title, order.item, orderStateColor(order), offset % 2 == 0 and colors.gray or colors.black)
      ui.line(output, 2, row + 1, width - 11, orderBar(order), colors.lightGray, colors.black)
      if order.state == 'active' then
        ui.button(output, width - 8, row + 1, 3, 1, 'R', colors.white, colors.blue, false)
        ui.button(output, width - 4, row + 1, 3, 1, 'X', colors.white, colors.red, false)
      else
        ui.text(output, width - 9, row + 1, order.state == 'accepted' and 'принято' or 'отмена', orderStateColor(order), colors.black)
      end
      ui.line(output, 2, row + 2, width - 3, ru.fit(tostring(order.lastResult or 'Ожидание'), width - 3, ''), colors.lightGray, colors.gray)
    end
  end
  if #entries == 0 then ui.text(output, 2, 10, 'Внутри заказа пока нет позиций.', colors.lightGray, colors.gray) end
  local leftWidth = math.floor((width - 3) / 2)
  ui.button(output, 2, height - 1, leftWidth, 1, '< Пред.', colors.white, colors.gray, groupDetailPage > 0)
  ui.button(output, 3 + leftWidth, height - 1, width - 3 - leftWidth, 1, 'След. >', colors.white, colors.gray, groupDetailPage < pages - 1)
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
  if page == 'group' then drawGroupDetails(width, height)
  elseif confirmation then drawConfirmation(width)
  elseif page == "order" then drawOrder(width)
  elseif page == "build" then drawBuildOrder(width)
  elseif page == "addresses" then drawAddresses(width)
  elseif page == "stock" then drawStock(width)
  elseif page == "clipboard" then drawClipboard(width)
  elseif page == "orders" then drawOrders(width, height)
  elseif page == 'audit' then drawAudit(width, height)
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
  local order, createErr = orders.create(fields.address, fields.item, amount)
  if not order then
    setStatus(tostring(createErr or 'Заявка заблокирована'), colors.red)
    confirmation = false
    return
  end
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
  if groupSearchActive then
    groupSearch = groupSearch .. text
    groupListPage = 0
  elseif activeField and fields[activeField] then
    fields[activeField] = fields[activeField] .. text
  end
end

local function backspace()
  if groupSearchActive then
    groupSearch = ru.sub(groupSearch, 1, ru.len(groupSearch) - 1)
    groupListPage = 0
  elseif activeField and fields[activeField] then
    local length = ru.len(fields[activeField])
    fields[activeField] = ru.sub(fields[activeField], 1, length - 1)
  end
end

local function activateTab(index)
  local tab = tabs[index]
  if tab then
    page, confirmation = tab.id, false
    if page == 'orders' then selectedGroupId, groupDetailPage, auditPage = nil, 0, 0 end
    groupSearchActive = false
    if page == "order" or page == "build" then
      activeField = "address"
    elseif page == "stock" then
      activeField = "search"
      loadCatalog()
    else
      activeField = nil
    end
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
    if a == keys.escape then
      if page == 'group' then
        page, selectedGroupId, groupDetailPage, activeField = groupReturnPage, nil, 0, nil
      elseif page == 'audit' then
        page, auditPage, activeField = 'orders', 0, nil
      elseif groupSearchActive then
        groupSearchActive = false
      else
        return
      end
    end
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
    elseif a == keys.f5 then
      if page == "stock" then
        loadCatalog()
      elseif page == "orders" then
        pcall(orders.tick)
        setStatus("Заявки обновлены", colors.lime)
      else
        refreshProducedItems()
        setStatus("Данные обновлены", colors.lime)
      end
    elseif a == keys.f and page == "orders" and not activeField and not confirmation then
      groupSearchActive = true
      setStatus("Поиск по названию или адресу", colors.lightBlue)
    elseif not activeField and not groupSearchActive and not confirmation then
      local tabKeys = { keys.one, keys.two, keys.three, keys.four }
      for index, code in ipairs(tabKeys) do
        if a == code then activateTab(index) break end
      end
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
      local tabWidth = math.max(1, math.floor(width / #tabs))
      activateTab(math.min(#tabs, math.floor((x - 1) / tabWidth) + 1))
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
      elseif page == 'orders' then
        if y == 5 and x >= width - 9 then
          page, auditPage, groupSearchActive, activeField = 'audit', 0, false, nil
        elseif y == 6 then
          local filters = { 'all', 'active', 'partial', 'accepted', 'cancelled' }
          local index = math.min(#filters, math.max(1, math.floor((x - 2) * #filters / (width - 3)) + 1))
          groupFilter, groupListPage, groupSearchActive = filters[index], 0, false
        elseif y == 7 then
          groupSearchActive, activeField = true, nil
        elseif y == height - 1 then
          local groups = filteredGroups()
          local totalPages = math.max(1, math.ceil(#groups / GROUP_LIST_PAGE_SIZE))
          local leftWidth = math.floor((width - 3) / 2)
          groupSearchActive = false
          if x < 3 + leftWidth then
            groupListPage = math.max(0, groupListPage - 1)
          else
            groupListPage = math.min(totalPages - 1, groupListPage + 1)
          end
        elseif y >= 9 and y <= 9 + (GROUP_LIST_PAGE_SIZE - 1) * 3 + 2 then
          local offset = math.floor((y - 9) / 3)
          local row = 9 + offset * 3
          local entry = filteredGroups()[groupListPage * GROUP_LIST_PAGE_SIZE + offset + 1]
          if entry and y >= row and y <= row + 2 then
            local group = entry.group
            groupSearchActive = false
            if entry.progress.active > 0 and y == row + 1 and x >= width - 8 and x <= width - 6 then
              pendingGroupCancelId = nil
              if orders.retryGroup(group.id) then
                pcall(orders.tick)
                setStatus('Повтор стройки отправлен', colors.lime)
              end
            elseif entry.progress.active > 0 and y == row + 1 and x >= width - 4 then
              if pendingGroupCancelId == group.id then
                pendingGroupCancelId = nil
                if orders.cancelGroup(group.id) then setStatus('Заказ стройки отменён', colors.orange) end
              else
                pendingGroupCancelId = group.id
                setStatus('Нажми «Да» ещё раз для отмены всей стройки', colors.orange)
              end
            else
              pendingGroupCancelId = nil
              groupReturnPage = 'orders'
              page, selectedGroupId, groupDetailPage, activeField = 'group', group.id, 0, nil
            end
          end
        end
      elseif page == 'audit' then
        if y == 5 and x < 13 then
          page, auditPage, activeField = 'orders', 0, nil
        elseif y == height - 1 then
          local entries = orders.audit().entries
          local totalPages = math.max(1, math.ceil(#entries / AUDIT_PAGE_SIZE))
          local leftWidth = math.floor((width - 3) / 2)
          if x < 3 + leftWidth then
            auditPage = math.max(0, auditPage - 1)
          else
            auditPage = math.min(totalPages - 1, auditPage + 1)
          end
        elseif y >= 9 and y <= 9 + (AUDIT_PAGE_SIZE - 1) * 3 + 1 then
          local offset = math.floor((y - 9) / 3)
          local row = 9 + offset * 3
          local entry = orders.audit().entries[auditPage * AUDIT_PAGE_SIZE + offset + 1]
          if entry then
            local order = entry.order
            if order.state == 'active' and y == row + 1 and x >= width - 8 and x <= width - 6 then
              if orders.retry(order.id) then
                pcall(orders.tick, order.id)
                setStatus('Повтор позиции отправлен', colors.lime)
              end
            elseif order.state == 'active' and y == row + 1 and x >= width - 4 then
              if orders.cancel(order.id) then setStatus('Заявка отменена', colors.orange) end
            elseif y == row and entry.group then
              groupReturnPage = 'audit'
              page, selectedGroupId, groupDetailPage, activeField = 'group', entry.group.id, 0, nil
            end
          end
        end
      elseif page == 'group' then
        if y == 5 and x < 13 then
          page, selectedGroupId, groupDetailPage, activeField = groupReturnPage, nil, 0, nil
        elseif y == height - 1 then
          local groupEntries = orders.groupOrders(selectedGroupId)
          local totalPages = math.max(1, math.ceil(#groupEntries / GROUP_DETAIL_PAGE_SIZE))
          local leftWidth = math.floor((width - 3) / 2)
          if x < 3 + leftWidth then
            groupDetailPage = math.max(0, groupDetailPage - 1)
          else
            groupDetailPage = math.min(totalPages - 1, groupDetailPage + 1)
          end
        elseif y >= 9 and y <= 9 + (GROUP_DETAIL_PAGE_SIZE - 1) * 3 + 1 then
          local offset = math.floor((y - 9) / 3)
          local row = 9 + offset * 3
          if y == row + 1 then
            local order = orders.groupOrders(selectedGroupId)[groupDetailPage * GROUP_DETAIL_PAGE_SIZE + offset + 1]
            if order and x >= width - 8 and x <= width - 6 then
              if orders.retry(order.id) then
                pcall(orders.tick, order.id)
                setStatus('Повтор позиции отправлен', colors.lime)
              end
            elseif order and x >= width - 4 then
              if orders.cancel(order.id) then setStatus('Позиция отменена', colors.orange) end
            end
          end
        end
      end
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
