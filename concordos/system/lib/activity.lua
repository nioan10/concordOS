-- Persistent, compact activity history for ConcordOS.
local activity = {}

local ROOT = "/concordos"
local PATH = ROOT .. "/data/activity.db"
local MAX_ENTRIES = 250

local function now()
  if os.epoch then return os.epoch("utc") end
  return math.floor(os.clock() * 1000)
end

local function defaultData()
  return { version = 1, nextId = 1, entries = {} }
end

function activity.load()
  if not fs.exists(PATH) then return defaultData() end
  local file = fs.open(PATH, "r")
  if not file then return defaultData() end
  local raw = file.readAll()
  file.close()
  local data = textutils.unserialize(raw)
  if type(data) ~= "table" or type(data.entries) ~= "table" then return defaultData() end
  data.version = 1
  data.nextId = math.max(1, math.floor(tonumber(data.nextId) or 1))
  return data
end

local function save(data)
  local directory = fs.getDir(PATH)
  if not fs.exists(directory) then fs.makeDir(directory) end
  local file = fs.open(PATH, "w")
  if not file then return false end
  file.write(textutils.serialize(data))
  file.close()
  return true
end

-- Logging must never be able to stop orders or other industrial logic.
function activity.record(category, text)
  local ok, result = pcall(function()
    local data = activity.load()
    local entry = {
      id = data.nextId,
      at = now(),
      category = tostring(category or "system"),
      text = tostring(text or ""):gsub("[\r\n]+", " "),
    }
    data.nextId = entry.id + 1
    data.entries[#data.entries + 1] = entry
    while #data.entries > MAX_ENTRIES do table.remove(data.entries, 1) end
    return save(data)
  end)
  return ok and result or false
end

function activity.list(category)
  local result = {}
  local data = activity.load()
  for index = #data.entries, 1, -1 do
    local entry = data.entries[index]
    if category == nil or category == "all" or entry.category == category then
      result[#result + 1] = entry
    end
  end
  return result
end

function activity.count()
  return #activity.load().entries
end

function activity.timeLabel(timestamp)
  local seconds = math.floor((tonumber(timestamp) or 0) / 1000)
  local ok, label = pcall(os.date, "%d.%m %H:%M", seconds)
  if ok and type(label) == "string" then return label end
  return "время ?"
end

return activity
