-- ConcordOS online updater. It deliberately never writes /concordos/data.
local BASE_URL = "https://raw.githubusercontent.com/nioan10/concordOS/main/concordos"

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

local function validLua(path, content)
  if path:sub(-4) ~= ".lua" and path ~= "/startup" and path ~= "/update" then return true end
  local chunk, err = load(content, "=" .. path, "t", {})
  return chunk ~= nil, err
end

print("ConcordOS: проверка обновлений...")
local manifestText, manifestError = readRemote(BASE_URL .. "/manifest.lua")
if not manifestText then error("Не удалось получить манифест: " .. manifestError, 0) end

local manifest, parseError = loadManifest(manifestText)
if not manifest then error("Ошибка манифеста: " .. tostring(parseError), 0) end

local downloads = {}
for index, entry in ipairs(manifest.files) do
  if type(entry) ~= "table" or type(entry.source) ~= "string" or type(entry.target) ~= "string" then
    error("Некорректная запись манифеста №" .. tostring(index), 0)
  end
  write("Скачивание " .. entry.source .. "... ")
  local content, err = readRemote(BASE_URL .. "/" .. entry.source)
  if not content then error("ошибка: " .. tostring(err), 0) end
  local valid, syntaxError = validLua(entry.target, content)
  if not valid then error("синтаксис " .. entry.source .. ": " .. tostring(syntaxError), 0) end
  downloads[#downloads + 1] = { target = entry.target, content = content }
  print("готово")
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

print("ConcordOS обновлён до " .. tostring(manifest.version) .. ".")
print("Заявки и данные не затрагивались. Выполни reboot.")
