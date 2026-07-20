-- ConcordOS online updater. It deliberately never writes /concordos/data.
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
waitForUser()
