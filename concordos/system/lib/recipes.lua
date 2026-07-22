-- Persistent recipe registry and a side-effect-free production planner.
local recipes = {}

local ROOT = "/concordos"
local PATH = ROOT .. "/data/recipes.db"

local function defaultData()
  return { version = 1, nextId = 1, recipes = {} }
end

local function number(value, fallback)
  value = math.floor(tonumber(value) or fallback or 0)
  return value
end

local function normaliseIngredient(entry)
  if type(entry) ~= "table" then return nil end
  local item = tostring(entry.item or entry.name or "")
  local count = number(entry.count or entry.amount, 0)
  if item == "" or count < 1 then return nil end
  return { item = item, count = count }
end

local function normaliseTags(values)
  local tags, seen = {}, {}
  for _, value in ipairs(type(values) == "table" and values or {}) do
    local tag = tostring(value or ""):match("^%s*(.-)%s*$")
    if tag ~= "" and not seen[tag] then
      seen[tag] = true
      tags[#tags + 1] = tag
    end
  end
  table.sort(tags)
  return tags
end

local function normaliseRecipe(recipe, fallbackId)
  if type(recipe) ~= "table" then return nil end
  local output = tostring(recipe.output or recipe.item or "")
  if output == "" then return nil end
  local ingredients = {}
  for _, entry in ipairs(recipe.ingredients or {}) do
    local ingredient = normaliseIngredient(entry)
    if ingredient then ingredients[#ingredients + 1] = ingredient end
  end
  return {
    id = number(recipe.id, fallbackId),
    name = tostring(recipe.name or output),
    output = output,
    outputCount = math.max(1, number(recipe.outputCount or recipe.count, 1)),
    line = tostring(recipe.line or ""),
    duration = math.max(0, number(recipe.duration, 0)),
    ingredients = ingredients,
    tags = normaliseTags(recipe.tags),
  }
end

function recipes.load()
  if not fs.exists(PATH) then return defaultData() end
  local file = fs.open(PATH, "r")
  if not file then return defaultData() end
  local raw = file.readAll()
  file.close()
  local data = textutils.unserialize(raw)
  if type(data) ~= "table" then return defaultData() end
  local result = defaultData()
  result.nextId = math.max(1, number(data.nextId, 1))
  for index, recipe in ipairs(data.recipes or {}) do
    local clean = normaliseRecipe(recipe, index)
    if clean then
      result.recipes[#result.recipes + 1] = clean
      result.nextId = math.max(result.nextId, clean.id + 1)
    end
  end
  table.sort(result.recipes, function(a, b) return a.name:lower() < b.name:lower() end)
  return result
end

function recipes.save(data)
  local directory = fs.getDir(PATH)
  if not fs.exists(directory) then fs.makeDir(directory) end
  local file = assert(fs.open(PATH, "w"), "Cannot write " .. PATH)
  file.write(textutils.serialize(data))
  file.close()
end

function recipes.list()
  return recipes.load().recipes
end

function recipes.get(id)
  for _, recipe in ipairs(recipes.load().recipes) do
    if recipe.id == tonumber(id) then return recipe end
  end
end

function recipes.findOutput(item)
  item = tostring(item or "")
  for _, recipe in ipairs(recipes.load().recipes) do
    if recipe.output == item then return recipe end
  end
end

function recipes.upsert(input)
  local data = recipes.load()
  local id = tonumber(type(input) == "table" and input.id)
  local slot
  if id then
    for index, recipe in ipairs(data.recipes) do
      if recipe.id == id then slot = index break end
    end
  end
  local clean = normaliseRecipe(input, id or data.nextId)
  if not clean then return nil, "Укажи предмет результата" end
  if slot then
    clean.id = data.recipes[slot].id
    data.recipes[slot] = clean
  else
    clean.id = data.nextId
    data.nextId = clean.id + 1
    data.recipes[#data.recipes + 1] = clean
  end
  table.sort(data.recipes, function(a, b) return a.name:lower() < b.name:lower() end)
  recipes.save(data)
  return clean
end

function recipes.remove(id)
  local data = recipes.load()
  for index, recipe in ipairs(data.recipes) do
    if recipe.id == tonumber(id) then
      table.remove(data.recipes, index)
      recipes.save(data)
      return true
    end
  end
  return false
end

function recipes.allTags()
  local seen, result = {}, {}
  for _, recipe in ipairs(recipes.list()) do
    for _, tag in ipairs(recipe.tags or {}) do
      if not seen[tag] then seen[tag] = true result[#result + 1] = tag end
    end
  end
  table.sort(result)
  return result
end

-- Add or remove one tag on several recipes at once. Existing data is retained.
function recipes.setTag(ids, tag, enabled)
  tag = tostring(tag or ""):match("^%s*(.-)%s*$")
  if tag == "" then return false, "Введи тег" end
  local wanted = {}
  for _, id in ipairs(ids or {}) do wanted[tonumber(id)] = true end
  if not next(wanted) then return false, "Не выбраны рецепты" end
  local data, changed = recipes.load(), 0
  for _, recipe in ipairs(data.recipes) do
    if wanted[recipe.id] then
      local tags, found = normaliseTags(recipe.tags), false
      for index, existing in ipairs(tags) do
        if existing == tag then
          found = true
          if not enabled then table.remove(tags, index) end
          break
        end
      end
      if enabled and not found then tags[#tags + 1] = tag end
      recipe.tags = normaliseTags(tags)
      changed = changed + 1
    end
  end
  if changed > 0 then recipes.save(data) end
  return changed > 0, changed
end

-- Produces a tree and a consolidated materials list. Stocks is optional and
-- maps an item id to currently available amount. It never starts a machine.
function recipes.plan(item, wanted, stocks)
  wanted = math.max(1, number(wanted, 1))
  stocks = stocks or {}
  local data = recipes.load()
  local byOutput = {}
  for _, recipe in ipairs(data.recipes) do byOutput[recipe.output] = recipe end
  local materials, jobs, warnings, visiting = {}, {}, {}, {}

  local function addMaterial(name, count)
    materials[name] = (materials[name] or 0) + count
  end

  local function need(name, count)
    local available = math.max(0, number(stocks[name], 0))
    local used = math.min(count, available)
    stocks[name] = available - used
    local deficit = count - used
    if deficit == 0 then return end
    local recipe = byOutput[name]
    if not recipe then
      addMaterial(name, deficit)
      return
    end
    if visiting[name] then
      warnings[#warnings + 1] = "Цикл рецептов: " .. name
      addMaterial(name, deficit)
      return
    end
    visiting[name] = true
    local batches = math.ceil(deficit / recipe.outputCount)
    jobs[#jobs + 1] = { recipe = recipe, batches = batches, output = batches * recipe.outputCount }
    for _, ingredient in ipairs(recipe.ingredients) do
      need(ingredient.item, ingredient.count * batches)
    end
    visiting[name] = nil
  end

  need(tostring(item or ""), wanted)
  return { item = tostring(item or ""), wanted = wanted, jobs = jobs, materials = materials, warnings = warnings }
end

return recipes
