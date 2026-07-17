-- Persistent Stock Ticker orders. An order is complete when Create accepts
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

return orders
