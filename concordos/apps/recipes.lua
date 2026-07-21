-- ConcordOS recipe registry: definitions first, execution comes later.
local ROOT = "/concordos"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local ru = ui.ru
local registry = dofile(ROOT .. "/system/lib/recipes.lua")
local output = term.current()

local screen = "list"
local selected, page = 1, 0
local activeField = nil
local fields = { name = "", output = "", outputCount = "1", line = "", ingredients = "", duration = "" }
local editingId = nil
local plan, status, statusColor = nil, "Реестр пуст — добавь первую технологию.", colors.lightGray
local picker = { target = nil, search = "", items = {}, page = 0, selected = 1 }
local components, componentPage = {}, 0
local componentPrompt = nil
local knownRecipeOutputs = {}
-- Five rows deliberately fit a normal 51×19 computer without covering footer.
local PAGE_SIZE = 5
local shiftHeld, metaHeld = false, false
local russianInput = true

-- CC:Tweaked often receives the physical Latin key even when the player uses
-- a Russian keyboard. Keep text fields independent from the client layout.
local russianKeys = {
  [keys.q] = "й", [keys.w] = "ц", [keys.e] = "у", [keys.r] = "к", [keys.t] = "е",
  [keys.y] = "н", [keys.u] = "г", [keys.i] = "ш", [keys.o] = "щ", [keys.p] = "з",
  [keys.a] = "ф", [keys.s] = "ы", [keys.d] = "в", [keys.f] = "а", [keys.g] = "п",
  [keys.h] = "р", [keys.j] = "о", [keys.k] = "л", [keys.l] = "д",
  [keys.z] = "я", [keys.x] = "ч", [keys.c] = "с", [keys.v] = "м", [keys.b] = "и",
  [keys.n] = "т", [keys.m] = "ь", [keys.space] = " ",
}
local englishKeys = {
  [keys.q] = "q", [keys.w] = "w", [keys.e] = "e", [keys.r] = "r", [keys.t] = "t",
  [keys.y] = "y", [keys.u] = "u", [keys.i] = "i", [keys.o] = "o", [keys.p] = "p",
  [keys.a] = "a", [keys.s] = "s", [keys.d] = "d", [keys.f] = "f", [keys.g] = "g",
  [keys.h] = "h", [keys.j] = "j", [keys.k] = "k", [keys.l] = "l",
  [keys.z] = "z", [keys.x] = "x", [keys.c] = "c", [keys.v] = "v", [keys.b] = "b",
  [keys.n] = "n", [keys.m] = "m", [keys.space] = " ",
}
for _, item in ipairs({
  { "zero", "0" }, { "one", "1" }, { "two", "2" }, { "three", "3" }, { "four", "4" },
  { "five", "5" }, { "six", "6" }, { "seven", "7" }, { "eight", "8" }, { "nine", "9" },
  { "grave", "ё" }, { "leftBracket", "х" }, { "rightBracket", "ъ" }, { "semicolon", "ж" },
  { "apostrophe", "э" }, { "comma", "б" }, { "period", "ю" }, { "minus", "-" }, { "equals", "=" },
}) do
  if keys[item[1]] then russianKeys[keys[item[1]]] = item[2] end
end
for _, item in ipairs({
  { "zero", "0", ")" }, { "one", "1", "!" }, { "two", "2", "@" }, { "three", "3", "#" },
  { "four", "4", "$" }, { "five", "5", "%" }, { "six", "6", "^" }, { "seven", "7", "&" },
  { "eight", "8", "*" }, { "nine", "9", "(" }, { "grave", "`", "~" }, { "leftBracket", "[", "{" },
  { "rightBracket", "]", "}" }, { "semicolon", ";", ":" }, { "apostrophe", "'", "\"" },
  { "comma", ",", "<" }, { "period", ".", ">" }, { "slash", "/", "?" }, { "minus", "-", "_" },
  { "equals", "=", "+" }, { "backslash", "\\", "|" },
}) do
  if keys[item[1]] then englishKeys[keys[item[1]]] = { item[2], item[3] } end
end

local function shiftDown()
  return shiftHeld or (keys.isShiftDown and keys.isShiftDown())
end

local function namedKey(keyCode, ...)
  for _, name in ipairs({ ... }) do
    if keys[name] and keyCode == keys[name] then return true end
  end
  return false
end

local function russianChar(keyCode)
  if keys.slash and keyCode == keys.slash then return shiftDown() and "," or "." end
  local character = russianKeys[keyCode]
  return character and (shiftDown() and ru.upper(character) or character) or nil
end

local function englishChar(keyCode)
  local character = englishKeys[keyCode]
  if type(character) == "table" then return character[shiftDown() and 2 or 1] end
  if character and shiftDown() then return string.upper(character) end
  return character
end

local function inputChar(keyCode)
  return russianInput and russianChar(keyCode) or englishChar(keyCode)
end

local function isLayoutToggle(keyCode)
  return keyCode == keys.f7 or (keyCode == keys.space and metaHeld)
end

local function inputLayoutName()
  return russianInput and "РУС" or "ENG"
end

local function homeButton(width)
  local size = width >= 40 and 11 or 3
  return width - size + 1, size, size == 3 and "<" or "< Главная"
end

local function setStatus(text, color)
  status, statusColor = tostring(text or ""), color or colors.lightGray
end

local function itemName(entry, fallback)
  if type(entry) ~= "table" then return nil end
  return entry.name or entry.id or (type(entry.item) == "table" and (entry.item.name or entry.item.id))
    or (type(fallback) == "string" and fallback:find(":") and fallback)
end

local function itemCount(entry)
  if type(entry) ~= "table" then return 0 end
  return tonumber(entry.count or entry.amount or entry.quantity or entry.total) or 0
end

local function refreshKnownRecipeOutputs()
  knownRecipeOutputs = {}
  local ok, list = pcall(registry.list)
  if ok and type(list) == "table" then
    for _, recipe in ipairs(list) do
      if recipe.output and recipe.output ~= "" then knownRecipeOutputs[recipe.output] = true end
    end
  end
end

local function loadPicker(target)
  refreshKnownRecipeOutputs()
  picker = { target = target, search = "", items = {}, page = 0, selected = 1 }
  local ticker = peripheral.find("Create_StockTicker")
  if not ticker then
    setStatus("Stock Ticker не найден", colors.red)
    return false
  end
  local ok, stock = pcall(ticker.stock, false)
  if not ok or type(stock) ~= "table" then
    setStatus("Не удалось прочитать Stock Ticker", colors.red)
    return false
  end
  local merged = {}
  for key, entry in pairs(stock) do
    local name = itemName(entry, key)
    if name then merged[name] = (merged[name] or 0) + itemCount(entry) end
  end
  for name, count in pairs(merged) do picker.items[#picker.items + 1] = { name = name, count = count } end
  table.sort(picker.items, function(a, b) return ru.lower(a.name) < ru.lower(b.name) end)
  screen = "stock"
  setStatus("Выбери предмет — ID будет подставлен автоматически", colors.lime)
  return true
end

local function pickerResults()
  local raw = tostring(picker.search or "")
  local results, query = {}, ru.lower(raw:match("^%s*(.-)%s*$"))
  for _, item in ipairs(picker.items) do
    if query == "" or ru.lower(item.name):find(query, 1, true) then results[#results + 1] = item end
  end
  return results
end

local function choosePickerItem(item)
  if not item then return end
  if picker.target == "output" then
    fields.output = item.name
    activeField = "output"
    screen = "edit"
  elseif picker.target == "component" then
    components[#components + 1] = { item = item.name, count = 1 }
    screen = "components"
    activeField = nil
  else
    local separator = fields.ingredients == "" and "" or "; "
    fields.ingredients = fields.ingredients .. separator .. item.name .. " x1"
    activeField = "ingredients"
    screen = "edit"
  end
  setStatus("Подставлен ID: " .. item.name, colors.lime)
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function parseIngredients(value)
  local items, errors = {}, {}
  for chunk in (tostring(value or "") .. ";"):gmatch("(.-);") do
    chunk = trim(chunk)
    if chunk ~= "" then
      local item, count = chunk:match("^(.-)%s*[xх×]%s*(%d+)%s*$")
      item = trim(item)
      if not item or item == "" or not count then
        errors[#errors + 1] = chunk
      else
        items[#items + 1] = { item = item, count = tonumber(count) }
      end
    end
  end
  return items, errors
end

local function formatIngredients(items)
  local result = {}
  for _, ingredient in ipairs(items or {}) do
    result[#result + 1] = ingredient.item .. " x" .. tostring(ingredient.count)
  end
  return table.concat(result, "; ")
end

local function openComponents()
  local parsed, invalid = parseIngredients(fields.ingredients)
  if #invalid > 0 then
    setStatus("Сначала исправь вручную: " .. invalid[1], colors.red)
    return false
  end
  components, componentPage, activeField = parsed, 0, nil
  screen = "components"
  return true
end

local function saveComponents()
  fields.ingredients = formatIngredients(components)
  screen, activeField = "edit", "ingredients"
  setStatus("Состав рецепта сохранён: " .. tostring(#components) .. " поз.", colors.lime)
end

local function openComponentCount(index)
  local component = components[index]
  if not component then return end
  componentPrompt = { index = index, value = tostring(component.count) }
  screen = "componentCount"
end

local function saveComponentCount()
  local count = math.floor(tonumber(componentPrompt and componentPrompt.value) or 0)
  if count < 1 then setStatus("Количество должно быть не меньше 1", colors.red) return end
  components[componentPrompt.index].count = count
  componentPrompt = nil
  screen = "components"
  setStatus("Количество изменено", colors.lime)
end

local function resetForm(recipe)
  editingId = recipe and recipe.id or nil
  fields.name = recipe and recipe.name or ""
  fields.output = recipe and recipe.output or ""
  fields.outputCount = recipe and tostring(recipe.outputCount) or "1"
  fields.line = recipe and recipe.line or ""
  fields.ingredients = recipe and formatIngredients(recipe.ingredients) or ""
  fields.duration = recipe and (recipe.duration > 0 and tostring(recipe.duration) or "") or ""
  activeField = "name"
end

local function saveRecipe()
  local ingredients, invalid = parseIngredients(fields.ingredients)
  if #invalid > 0 then
    setStatus("Не понял ингредиент: " .. invalid[1] .. " (нужно id x число)", colors.red)
    return false
  end
  local outputCount = tonumber(fields.outputCount)
  if trim(fields.name) == "" then setStatus("Дай рецепту название", colors.red) return false end
  if trim(fields.output) == "" or not outputCount or outputCount < 1 then
    setStatus("Укажи ID результата и количество за цикл", colors.red)
    return false
  end
  local recipe, err = registry.upsert({
    id = editingId, name = trim(fields.name), output = trim(fields.output), outputCount = outputCount,
    line = trim(fields.line), duration = tonumber(fields.duration) or 0, ingredients = ingredients,
  })
  if not recipe then setStatus(err, colors.red) return false end
  setStatus("Рецепт «" .. recipe.name .. "» сохранён", colors.lime)
  screen, selected, page, activeField = "list", 1, 0, nil
  return true
end

local function deleteRecipe()
  if not editingId then return end
  local id = editingId
  registry.remove(id)
  screen, selected, page, activeField = "list", 1, 0, nil
  setStatus("Рецепт удалён", colors.orange)
end

local function stockMap()
  local ticker = peripheral.find("Create_StockTicker")
  if not ticker then return {}, false end
  local ok, items = pcall(ticker.stock, false)
  if not ok or type(items) ~= "table" then return {}, false end
  local stock = {}
  for key, entry in pairs(items) do
    local name = itemName(entry, key)
    local count = itemCount(entry)
    if name and count then stock[name] = (stock[name] or 0) + count end
  end
  return stock, true
end

local function makePlan(recipe)
  local stock, online = stockMap()
  plan = registry.plan(recipe.output, recipe.outputCount, stock)
  screen = "plan"
  setStatus(online and "Учтён текущий склад Stock Ticker" or "Stock Ticker не найден: расчёт без склада", online and colors.lime or colors.orange)
end

local function header(width, title)
  ui.clear(output, colors.gray)
  ui.line(output, 1, 1, width, "ConcordOS | " .. title, colors.white, colors.blue)
  local x, size, label = homeButton(width)
  ui.button(output, x, 1, size, 1, "", colors.white, colors.blue, true)
  ui.text(output, x, 1, label, colors.white, colors.lightBlue)
end

local function drawList(width, height)
  header(width, "Реестр рецептов")
  local recipes = registry.list()
  ui.text(output, 2, 3, "Технологии для будущего автокрафта. P — расчёт, N — новый рецепт.", colors.lightGray, colors.gray)
  ui.button(output, 2, 4, 12, 1, "+ Новый", colors.white, colors.green, false)
  ui.button(output, 15, 4, 14, 1, "Обновить", colors.white, colors.blue, false)
  if #recipes == 0 then
    ui.text(output, 2, 7, "Пока нет рецептов. Начни, например, с рельс.", colors.white, colors.gray)
  else
    local first = page * PAGE_SIZE + 1
    for row = 0, PAGE_SIZE - 1 do
      local recipe = recipes[first + row]
      if recipe then
        local y = 6 + row * 2
        local current = first + row == selected
        ui.line(output, 2, y, width - 3, ru.fit(recipe.name, width - 4, ""), colors.white, current and colors.blue or colors.black)
        local details = recipe.output .. " ×" .. tostring(recipe.outputCount)
        if recipe.line ~= "" then details = details .. "  |  " .. recipe.line end
        ui.text(output, 3, y + 1, ru.fit(details, width - 5, ""), colors.lightGray, colors.gray)
      end
    end
  end
  local pages = math.max(1, math.ceil(#recipes / PAGE_SIZE))
  ui.line(output, 1, height - 1, width, ru.fit(status, width, ""), statusColor, colors.gray)
  ui.line(output, 1, height, width, "Стр. " .. tostring(page + 1) .. "/" .. tostring(pages) .. "  Колесо: список  Enter: править  P: план", colors.black, colors.lightGray)
end

local fieldsOrder = { "name", "output", "outputCount", "line", "ingredients", "duration" }
local labels = {
  name = "Название технологии", output = "ID результата", outputCount = "Выход за один цикл", line = "Линия / станок (для оператора)",
  ingredients = "Ингредиенты: id x кол-во; id x кол-во", duration = "Время цикла, с (необязательно)",
}

local function input(width, y, key)
  ui.text(output, 2, y, labels[key], colors.lightGray, colors.gray)
  local hasPicker = key == "output" or key == "ingredients"
  local inputWidth = key == "ingredients" and width - 22 or (hasPicker and width - 12 or width - 3)
  ui.line(output, 2, y + 1, inputWidth, ru.fit(fields[key] .. (activeField == key and "|" or ""), inputWidth, ""), colors.white, activeField == key and colors.blue or colors.black)
  if key == "ingredients" then ui.button(output, width - 20, y + 1, 11, 1, "Компоненты", colors.white, colors.blue, false) end
  if hasPicker then ui.button(output, width - 9, y + 1, 8, 1, "Склад", colors.white, colors.purple, false) end
end

local function drawStockPicker(width, height)
  header(width, "Выбор ID со склада")
  local target = picker.target == "output" and "результата" or "ингредиента"
  ui.text(output, 2, 3, "Выбор " .. target .. ". Поиск по ID:", colors.lightGray, colors.gray)
  ui.line(output, 2, 4, width - 3, ru.fit(picker.search .. "|", width - 3, ""), colors.white, colors.blue)
  local results = pickerResults()
  local pageSize = math.max(1, math.min(7, height - 8))
  local pages = math.max(1, math.ceil(#results / pageSize))
  if picker.page >= pages then picker.page = pages - 1 end
  local first = picker.page * pageSize + 1
  for row = 0, pageSize - 1 do
    local item = results[first + row]
    if item then
      local y = 6 + row
      local current = first + row == picker.selected
      local background = current and colors.blue or colors.black
      local badge = knownRecipeOutputs[item.name] and " КРАФТ" or ""
      local labelWidth = width - 3 - (badge == "" and 0 or 7)
      ui.line(output, 2, y, width - 3, ru.fit(item.name .. "  ×" .. tostring(item.count), labelWidth, ""), colors.white, background)
      if badge ~= "" then ui.text(output, width - 7, y, badge, colors.lime, background) end
    end
  end
  if #results == 0 then ui.text(output, 2, 7, "Ничего не найдено.", colors.orange, colors.gray) end
  ui.line(output, 1, height - 1, width, ru.fit(status, width, ""), statusColor, colors.gray)
  ui.line(output, 1, height, width, "Стр. " .. tostring(picker.page + 1) .. "/" .. tostring(pages) .. "  Enter: выбрать  Win+Space/F7: " .. inputLayoutName(), colors.black, colors.lightGray)
end

local function drawComponents(width, height)
  header(width, "Компоненты рецепта")
  ui.button(output, 2, 3, 15, 1, "+ Со склада", colors.white, colors.purple, false)
  ui.button(output, 18, 3, 11, 1, "Готово", colors.white, colors.green, false)
  local pageSize = math.max(1, math.min(8, height - 7))
  local pages = math.max(1, math.ceil(#components / pageSize))
  if componentPage >= pages then componentPage = pages - 1 end
  local first = componentPage * pageSize + 1
  if #components == 0 then
    ui.text(output, 2, 6, "Пусто. Добавь предмет из склада.", colors.lightGray, colors.gray)
  end
  for row = 0, pageSize - 1 do
    local index = first + row
    local component = components[index]
    if component then
      local y = 5 + row
      ui.line(output, 2, y, width - 15, ru.fit(component.item .. " ×" .. tostring(component.count), width - 15, ""), colors.white, colors.black)
      ui.button(output, width - 12, y, 8, 1, "Кол-во", colors.white, colors.blue, false)
      ui.button(output, width - 3, y, 2, 1, "X", colors.white, colors.red, false)
    end
  end
  ui.line(output, 1, height - 1, width, ru.fit(status, width, ""), statusColor, colors.gray)
  ui.line(output, 1, height, width, "Стр. " .. tostring(componentPage + 1) .. "/" .. tostring(pages) .. "  Колесо: страницы  Enter: сохранить", colors.black, colors.lightGray)
end

local function drawComponentCount(width, height)
  header(width, "Количество компонента")
  local component = componentPrompt and components[componentPrompt.index]
  ui.text(output, 2, 4, component and ru.fit(component.item, width - 3, "") or "Компонент не найден", colors.white, colors.gray)
  ui.text(output, 2, 6, "Количество на один цикл", colors.lightGray, colors.gray)
  ui.line(output, 2, 7, width - 3, ru.fit((componentPrompt and componentPrompt.value or "") .. "|", width - 3, ""), colors.white, colors.blue)
  ui.button(output, 2, 10, 12, 1, "Готово", colors.white, colors.green, false)
  ui.button(output, 15, 10, 12, 1, "Отмена", colors.white, colors.gray, false)
  ui.line(output, 1, height, width, "Введи число. Enter: применить  ← Главная: выход", colors.black, colors.lightGray)
end

local function drawEdit(width, height)
  header(width, editingId and "Правка рецепта" or "Новый рецепт")
  input(width, 3, "name")
  input(width, 5, "output")
  input(width, 7, "outputCount")
  input(width, 9, "line")
  input(width, 11, "ingredients")
  if height >= 21 then input(width, 13, "duration") end
  local y = height - 3
  ui.button(output, 2, y, 12, 1, "Сохранить", colors.white, colors.green, false)
  ui.button(output, 15, y, 12, 1, "Отмена", colors.white, colors.gray, false)
  if editingId then ui.button(output, width - 11, y, 10, 1, "Удалить", colors.white, colors.red, false) end
  ui.line(output, 1, height - 1, width, ru.fit(status, width, ""), statusColor, colors.gray)
  ui.line(output, 1, height, width, "Tab: поле  F2: сохр.  Win+Space/F7: " .. inputLayoutName(), colors.black, colors.lightGray)
end

local function sortedMaterials(materials)
  local result = {}
  for item, count in pairs(materials or {}) do result[#result + 1] = { item = item, count = count } end
  table.sort(result, function(a, b) return a.item < b.item end)
  return result
end

local function drawPlan(width, height)
  header(width, "Расчёт производства")
  ui.text(output, 2, 3, "Нужно: " .. plan.item .. " ×" .. tostring(plan.wanted), colors.white, colors.gray)
  ui.text(output, 2, 5, "Запустить технологии:", colors.lightBlue, colors.gray)
  local y = 6
  for _, job in ipairs(plan.jobs) do
    if y >= height - 5 then break end
    local line = job.recipe.name .. " ×" .. tostring(job.batches) .. " = " .. tostring(job.output)
    if job.recipe.line ~= "" then line = line .. " | " .. job.recipe.line end
    ui.line(output, 2, y, width - 3, line, colors.white, colors.black)
    y = y + 1
  end
  y = y + 1
  if y < height - 3 then ui.text(output, 2, y, "Нужно взять со склада / добыть:", colors.orange, colors.gray) y = y + 1 end
  for _, material in ipairs(sortedMaterials(plan.materials)) do
    if y >= height - 2 then break end
    ui.line(output, 2, y, width - 3, material.item .. " ×" .. tostring(material.count), colors.white, colors.black)
    y = y + 1
  end
  if #plan.warnings > 0 and y < height - 1 then ui.text(output, 2, y, plan.warnings[1], colors.red, colors.gray) end
  ui.line(output, 1, height, width, "Enter / < Главная: к реестру. Это только расчёт — машины не запускались.", colors.black, colors.lightGray)
end

local function draw()
  local width, height = output.getSize()
  if screen == "list" then drawList(width, height)
  elseif screen == "edit" then drawEdit(width, height)
  elseif screen == "stock" then drawStockPicker(width, height)
  elseif screen == "components" then drawComponents(width, height)
  elseif screen == "componentCount" then drawComponentCount(width, height)
  else drawPlan(width, height) end
end

local function chooseRecipe(delta)
  local count = #registry.list()
  if count == 0 then selected = 1 return end
  selected = math.max(1, math.min(count, selected + delta))
  page = math.floor((selected - 1) / PAGE_SIZE)
end

local function openSelected()
  local recipe = registry.list()[selected]
  if recipe then resetForm(recipe) screen = "edit" end
end

local function fieldAt(y, height)
  local rows = { [4] = "name", [6] = "output", [8] = "outputCount", [10] = "line", [12] = "ingredients" }
  if height >= 21 then rows[14] = "duration" end
  return rows[y]
end

draw()
while true do
  local event, a, b, c = os.pullEventRaw()
  local width, height = output.getSize()
  if event == "key" and namedKey(a, "leftShift", "rightShift") then
    shiftHeld = true
  elseif event == "key_up" and namedKey(a, "leftShift", "rightShift") then
    shiftHeld = false
  end
  if event == "key" and namedKey(a, "leftMeta", "rightMeta", "leftWin", "rightWin", "leftSuper", "rightSuper") then
    metaHeld = true
  elseif event == "key_up" and namedKey(a, "leftMeta", "rightMeta", "leftWin", "rightWin", "leftSuper", "rightSuper") then
    metaHeld = false
  end
  if event == "term_resize" then
    draw()
  elseif event == "paste" then
    if screen == "edit" and activeField then fields[activeField] = fields[activeField] .. a draw() end
    if screen == "stock" then
      picker.search = picker.search .. a
      picker.page, picker.selected = 0, 1
      draw()
    end
    if screen == "componentCount" and componentPrompt then
      componentPrompt.value = componentPrompt.value .. tostring(a or ""):gsub("%D", "")
      draw()
    end
  elseif event == "key" then
    if screen == "list" then
      if a == keys.enter then openSelected()
      elseif a == keys.n then resetForm() screen = "edit"
      elseif a == keys.p then local recipe = registry.list()[selected] if recipe then makePlan(recipe) end
      elseif a == keys.up then chooseRecipe(-1)
      elseif a == keys.down then chooseRecipe(1)
      elseif a == keys.escape or a == keys.q then return end
    elseif screen == "edit" then
      local character = inputChar(a)
      if isLayoutToggle(a) then russianInput = not russianInput
      elseif character and activeField then fields[activeField] = fields[activeField] .. character
      elseif a == keys.tab then
        local index = 1
        for i, key in ipairs(fieldsOrder) do if key == activeField then index = i break end end
        activeField = fieldsOrder[index % #fieldsOrder + 1]
      elseif a == keys.backspace and activeField then fields[activeField] = ru.sub(fields[activeField], 1, ru.len(fields[activeField]) - 1)
      elseif a == keys.f2 then saveRecipe()
      elseif a == keys.f3 then
        if saveRecipe() then makePlan(registry.get(editingId) or registry.findOutput(fields.output)) end
      elseif a == keys.escape then screen, activeField = "list", nil
      end
    elseif screen == "stock" then
      local character = inputChar(a)
      local results = pickerResults()
      if isLayoutToggle(a) then russianInput = not russianInput
      elseif character then
        picker.search = picker.search .. character
        picker.page, picker.selected = 0, 1
      elseif a == keys.backspace then
        picker.search = ru.sub(picker.search, 1, ru.len(picker.search) - 1)
        picker.page, picker.selected = 0, 1
      elseif a == keys.up then picker.selected = math.max(1, picker.selected - 1)
      elseif a == keys.down then picker.selected = math.min(#results, picker.selected + 1)
      elseif a == keys.enter then choosePickerItem(results[picker.selected])
      elseif a == keys.escape then
        if picker.target == "component" then screen, activeField = "components", nil
        else screen, activeField = "edit", picker.target end
      end
    elseif screen == "components" then
      if a == keys.enter then saveComponents()
      elseif a == keys.n then loadPicker("component")
      elseif a == keys.escape then screen, activeField = "edit", "ingredients"
      end
    elseif screen == "componentCount" then
      local character = inputChar(a)
      if character and character:match("%d") then componentPrompt.value = componentPrompt.value .. character
      elseif a == keys.backspace then componentPrompt.value = componentPrompt.value:sub(1, -2)
      elseif a == keys.enter then saveComponentCount()
      elseif a == keys.escape then componentPrompt, screen = nil, "components"
      end
    elseif screen == "plan" and (a == keys.enter or a == keys.escape or a == keys.q) then screen = "list" end
    draw()
  elseif event == "mouse_scroll" and (screen == "list" or screen == "stock" or screen == "components") then
    if screen == "list" then
      local total = math.max(0, math.ceil(#registry.list() / PAGE_SIZE) - 1)
      page = math.max(0, math.min(total, page + (a > 0 and 1 or -1)))
      selected = math.min(math.max(1, #registry.list()), page * PAGE_SIZE + 1)
    elseif screen == "stock" then
      local pageSize = math.max(1, math.min(7, height - 8))
      local total = math.max(0, math.ceil(#pickerResults() / pageSize) - 1)
      picker.page = math.max(0, math.min(total, picker.page + (a > 0 and 1 or -1)))
      picker.selected = picker.page * pageSize + 1
    else
      local pageSize = math.max(1, math.min(8, height - 7))
      local total = math.max(0, math.ceil(#components / pageSize) - 1)
      componentPage = math.max(0, math.min(total, componentPage + (a > 0 and 1 or -1)))
    end
    draw()
  elseif event == "mouse_click" then
    local x, y = b, c
    local homeX, homeWidth = homeButton(width)
    if y == 1 and x >= homeX and x < homeX + homeWidth then return end
    if screen == "list" then
      if y == 4 and x < 14 then resetForm() screen = "edit"
      elseif y == 4 then setStatus("Список перечитан", colors.lime)
      elseif y >= 6 and y < 6 + PAGE_SIZE * 2 then
        local index = page * PAGE_SIZE + math.floor((y - 6) / 2) + 1
        if registry.list()[index] then selected = index openSelected() end
      end
    elseif screen == "edit" then
      local key = fieldAt(y, height)
      if (key == "output" or key == "ingredients") and x >= width - 9 then
        loadPicker(key)
      elseif key == "ingredients" and x >= width - 20 then
        openComponents()
      elseif key then activeField = key
      elseif y == height - 3 then
        if x < 14 then saveRecipe()
        elseif x < 27 then screen, activeField = "list", nil
        elseif editingId then deleteRecipe() end
      end
    elseif screen == "stock" then
      if y == 4 then
        -- Search field already stays active; this makes the click explicit.
      elseif y >= 6 then
        local pageSize = math.max(1, math.min(7, height - 8))
        local item = pickerResults()[picker.page * pageSize + y - 5]
        if item then choosePickerItem(item) end
      end
    elseif screen == "components" then
      if y == 3 and x < 17 then
        loadPicker("component")
      elseif y == 3 and x < 29 then
        saveComponents()
      elseif y >= 5 then
        local pageSize = math.max(1, math.min(8, height - 7))
        local index = componentPage * pageSize + y - 4
        if components[index] then
          if x >= width - 3 then
            table.remove(components, index)
            setStatus("Компонент удалён", colors.orange)
          elseif x >= width - 12 then
            openComponentCount(index)
          end
        end
      end
    elseif screen == "componentCount" then
      if y == 10 and x < 14 then saveComponentCount()
      elseif y == 10 and x < 27 then componentPrompt, screen = nil, "components" end
    else
      screen = "list"
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
