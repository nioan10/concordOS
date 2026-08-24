-- Persistent Stock Ticker orders. Accepted means accepted by the Stock Ticker;
-- Create does not expose an arrival confirmation for the destination package.
local orders = {}

local ROOT = "/concordos"
local PATH = ROOT .. "/data/orders.db"
local TICK_LOCK_PATH = ROOT .. "/data/orders.tick.lock"
local activity = dofile(ROOT .. "/system/lib/activity.lua")
local RETRY_BASE_MS = 30000
local RETRY_MAX_MS = 120000
local TICK_LOCK_STALE_MS = 60000
local function now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

local function log(text)
  pcall(activity.record, "orders", text)
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

local function orderKey(address, item)
  return tostring(address or "") .. "\0" .. tostring(item or "")
end

local function duplicateEntries(data, address, items)
  local wanted, result = {}, {}
  for _, entry in ipairs(items or {}) do
    local item = type(entry) == "table" and (entry.item or entry.name) or entry
    if item and tostring(item) ~= "" then wanted[tostring(item)] = true end
  end
  for _, order in ipairs(data.orders or {}) do
    if order.state == "active" and tostring(order.address or "") == tostring(address or "") and wanted[tostring(order.item or "")] then
      result[#result + 1] = order
    end
  end
  table.sort(result, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
  return result
end

local function duplicateMessage(conflicts)
  local labels = {}
  for index = 1, math.min(3, #conflicts) do
    local order = conflicts[index]
    labels[#labels + 1] = "№" .. tostring(order.id) .. " (" .. tostring(order.item) .. ")"
  end
  if #conflicts > 3 then labels[#labels + 1] = "и ещё " .. tostring(#conflicts - 3) end
  return "Уже есть активная заявка: " .. table.concat(labels, ", ")
end

local function acquireTickLock(current)
  if fs.exists(TICK_LOCK_PATH) then
    local file = fs.open(TICK_LOCK_PATH, "r")
    local lockedAt = file and tonumber(file.readAll()) or nil
    if file then file.close() end
    if lockedAt and current >= lockedAt and current - lockedAt < TICK_LOCK_STALE_MS then return false end
    fs.delete(TICK_LOCK_PATH)
  end
  local directory = fs.getDir(TICK_LOCK_PATH)
  if not fs.exists(directory) then fs.makeDir(directory) end
  local file = fs.open(TICK_LOCK_PATH, "w")
  if not file then return false end
  file.write(tostring(current))
  file.close()
  return true
end

local function releaseTickLock()
  if fs.exists(TICK_LOCK_PATH) then fs.delete(TICK_LOCK_PATH) end
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
  local conflicts = duplicateEntries(data, address, { item })
  if #conflicts > 0 then
    local message = duplicateMessage(conflicts)
    log("Заблокирован дубль: " .. tostring(item) .. " → " .. tostring(address))
    return nil, message, conflicts
  end
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
  log("Создана заявка №" .. tostring(order.id) .. ": " .. order.item .. " ×" .. tostring(order.requested) .. " → " .. order.address)
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

  local conflicts = duplicateEntries(data, address, names)
  if #conflicts > 0 then
    local message = duplicateMessage(conflicts)
    log("Заблокирован дубль заказа стройки → " .. tostring(address))
    return nil, message, conflicts
  end

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
  log("Создан заказ стройки №" .. tostring(group.id) .. " «" .. group.title .. "»: " .. tostring(#created) .. " поз. → " .. group.address)
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

function orders.getGroup(groupId)
  for _, group in ipairs(orders.load().groups) do
    if group.id == tonumber(groupId) then return group end
  end
end

-- Individual persistent requests created from one construction order.
function orders.groupOrders(groupId)
  local result = {}
  for _, order in ipairs(orders.load().orders) do
    if order.groupId == tonumber(groupId) then result[#result + 1] = order end
  end
  table.sort(result, function(a, b)
    local aRank = a.state == 'active' and 0 or (a.state == 'cancelled' and 1 or 2)
    local bRank = b.state == 'active' and 0 or (b.state == 'cancelled' and 1 or 2)
    if aRank ~= bRank then return aRank < bRank end
    return tostring(a.item) < tostring(b.item)
  end)
  return result
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
      log("Отменена заявка №" .. tostring(order.id) .. ": " .. order.item)
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
  if changed then
    orders.save(data)
    log("Отменён заказ стройки №" .. tostring(groupId))
  end
  return changed
end

function orders.retry(id)
  local data = orders.load()
  for _, order in ipairs(data.orders) do
    if order.id == id and order.state == "active" then
      order.nextAttemptAt = 0
      order.lastResult = "Повтор назначен оператором"
      orders.save(data)
      log("Назначен повтор заявки №" .. tostring(order.id) .. ": " .. order.item)
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
  if changed then
    orders.save(data)
    log("Назначен повтор заказа стройки №" .. tostring(groupId))
  end
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

-- Read-only view used by the operations audit. Duplicate means same active item and address.
function orders.audit()
  local data = orders.load()
  local groups, buckets = {}, {}
  for _, group in ipairs(data.groups) do groups[group.id] = group end
  for _, order in ipairs(data.orders) do
    if order.state == 'active' then
      local key = orderKey(order.address, order.item)
      buckets[key] = buckets[key] or {}
      buckets[key][#buckets[key] + 1] = order
    end
  end

  local duplicateSets, duplicateOrders, active = 0, 0, 0
  for _, ordersAtKey in pairs(buckets) do
    if #ordersAtKey > 1 then
      duplicateSets = duplicateSets + 1
      duplicateOrders = duplicateOrders + #ordersAtKey
    end
  end

  local entries = {}
  for _, order in ipairs(data.orders) do
    local duplicate = order.state == 'active' and #(buckets[orderKey(order.address, order.item)] or {}) > 1
    if order.state == 'active' then active = active + 1 end
    entries[#entries + 1] = { order = order, group = groups[order.groupId], duplicate = duplicate }
  end
  table.sort(entries, function(a, b)
    if a.duplicate ~= b.duplicate then return a.duplicate end
    local aActive, bActive = a.order.state == 'active', b.order.state == 'active'
    if aActive ~= bActive then return aActive end
    return tonumber(a.order.id) > tonumber(b.order.id)
  end)
  return {
    entries = entries,
    active = active,
    duplicateSets = duplicateSets,
    duplicateOrders = duplicateOrders,
  }
end
local function performTick(forceOrderId, current)
  local data = orders.load()
  local changed = false
  local stockTicker = peripheral.find("Create_StockTicker")

  for _, order in ipairs(data.orders) do
    if order.state == "active" then
      local remaining = orders.remaining(order)
      if remaining <= 0 then
        order.state = "accepted"
        order.lastResult = "Сеть приняла весь объём; прибытие не подтверждается"
        log("Сеть приняла заявку №" .. tostring(order.id) .. ": " .. order.item .. " ×" .. tostring(order.requested))
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
            order.lastResult = "Сеть приняла весь объём; прибытие не подтверждается"
            log("Сеть приняла заявку №" .. tostring(order.id) .. ": " .. order.item .. " ×" .. tostring(order.requested))
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
          log("Ошибка отправки заявки №" .. tostring(order.id) .. ": " .. tostring(result))
        end
        changed = true
      elseif not stockTicker then
        if order.lastResult ~= "Stock Ticker не найден" then
          order.lastResult = "Stock Ticker не найден"
          order.nextAttemptAt = current + RETRY_BASE_MS
          log("Заявка №" .. tostring(order.id) .. " ждёт Stock Ticker")
          changed = true
        end
      end
    end
  end

  if changed then orders.save(data) end
  return data
end

local function runTick(forceOrderId)
  local current = now()
  if not acquireTickLock(current) then return orders.load(), 'busy' end
  local ok, result = xpcall(function()
    return performTick(forceOrderId, current)
  end, function(err)
    return tostring(err)
  end)
  releaseTickLock()
  if not ok then error(result, 0) end
  return result
end

function orders.tick(forceOrderId)
  return runTick(forceOrderId)
end
return orders
