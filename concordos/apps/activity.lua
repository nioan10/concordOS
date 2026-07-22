-- Read-only industrial activity journal.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local activity = dofile(ROOT .. "/system/lib/activity.lua")
local output = term.current()

local filter, page = "all", 0
local PAGE_SIZE = 11
local filters = {
  { id = "all", label = "Все" },
  { id = "orders", label = "Заявки" },
  { id = "recipes", label = "Рецепты" },
  { id = "system", label = "Система" },
}

local function homeButton(width)
  local size = width >= 40 and 11 or 3
  return width - size + 1, size, size == 3 and "<" or "< Главная"
end

local function categoryLabel(category)
  if category == "orders" then return "Заявки" end
  if category == "recipes" then return "Рецепты" end
  return "Система"
end

local function entries()
  return activity.list(filter)
end

local function draw()
  local width, height = output.getSize()
  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width, "ConcordOS | Журнал активности", colors.white, colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(width)
  ui.button(output, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(output, homeX, 1, homeLabel, colors.white, colors.lightBlue)

  local tabWidth = math.floor((width - 2) / #filters)
  for index, entry in ipairs(filters) do
    local x = 2 + (index - 1) * tabWidth
    local buttonWidth = index == #filters and width - x - 1 or tabWidth - 1
    ui.button(output, x, 3, buttonWidth, 1, entry.label, colors.white, colors.blue, filter == entry.id)
  end

  local list = entries()
  local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
  if page >= pages then page = pages - 1 end
  ui.text(output, 2, 5, "Последние события; новые сверху.", colors.lightGray, colors.gray)
  local first = page * PAGE_SIZE + 1
  for row = 0, PAGE_SIZE - 1 do
    local entry = list[first + row]
    if entry then
      local y = 6 + row
      local line = activity.timeLabel(entry.at) .. " " .. categoryLabel(entry.category) .. " · " .. tostring(entry.text)
      ui.line(output, 2, y, width - 3, line, colors.white, row % 2 == 0 and colors.black or colors.gray)
    end
  end
  if #list == 0 then ui.text(output, 2, 7, "Пока нет событий этого типа.", colors.lightGray, colors.gray) end
  ui.line(output, 1, height - 1, width, "В журнале: " .. tostring(activity.count()) .. "/250", colors.black, colors.lightGray)
  ui.line(output, 1, height, width, "Стр. " .. tostring(page + 1) .. "/" .. tostring(pages) .. "  Колесо: страницы  F5: обновить", colors.black, colors.lightGray)
end

draw()
while true do
  local event, a, b, c = os.pullEventRaw()
  local width = output.getSize()
  if event == "term_resize" then
    draw()
  elseif event == "key" then
    if a == keys.escape or a == keys.q then return end
    if a == keys.up then page = math.max(0, page - 1) end
    if a == keys.down then page = page + 1 end
    draw()
  elseif event == "mouse_scroll" then
    page = math.max(0, page + (a > 0 and 1 or -1))
    draw()
  elseif event == "mouse_click" or event == "monitor_touch" then
    local x, y = b, c
    local homeX, homeWidth = homeButton(width)
    if y == 1 and x >= homeX and x < homeX + homeWidth then return end
    if y == 3 then
      local tabWidth = math.floor((width - 2) / #filters)
      local index = math.floor((x - 2) / tabWidth) + 1
      local selected = filters[index]
      if selected then filter, page = selected.id, 0 end
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
