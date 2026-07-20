-- Wireless power-station dashboard for ConcordOS.
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
end
