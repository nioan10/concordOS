local ROOT = "/concordos"
local MARKER = ROOT .. "/.booting"
local CRASH_LOG = ROOT .. "/logs/crash.log"

local function loadRu()
  local ok, result = pcall(dofile, ROOT .. "/system/lib/ru.lua")
  return ok and result or nil
end

local ru = loadRu()
local function say(text)
  if ru then ru.write(term, text) else term.write(tostring(text)) end
end
local function nextLine()
  local _, y = term.getCursorPos()
  local _, height = term.getSize()
  if y >= height then
    term.scroll(1)
    term.setCursorPos(1, height)
  else
    term.setCursorPos(1, y + 1)
  end
end
local function sayLine(text)
  say(text)
  nextLine()
end

local function writeFile(path, content)
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
  local file = fs.open(path, "w")
  if file then file.write(content) file.close() end
end

local function recovery(reason)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.red)
  sayLine("ConcordOS: режим восстановления")
  term.setTextColor(colors.white)
  sayLine(reason)
  sayLine("")
  sayLine("1 - Запустить рабочий стол")
  sayLine("2 - Открыть безопасный терминал")
  sayLine("R - Перезагрузить компьютер")
  sayLine("Q - Выключить компьютер")

  while true do
    local event, key = os.pullEventRaw("key")
    if event == "key" then
      if key == keys.one then
        fs.delete(MARKER)
        return true
      elseif key == keys.two then
        fs.delete(MARKER)
        term.setCursorPos(1, 10)
        shell.run("shell")
        return false
      elseif key == keys.r then
        os.reboot()
      elseif key == keys.q then
        os.shutdown()
      end
    end
  end
end

if not fs.exists(ROOT .. "/system/desktop.lua") then
  recovery("Системные файлы не найдены: " .. ROOT .. "/system/desktop.lua")
elseif fs.exists(MARKER) then
  if not recovery("Предыдущая загрузка не завершилась корректно.") then return end
end

writeFile(MARKER, "booting " .. tostring(os.epoch and os.epoch("utc") or os.clock()))
local ok, result = xpcall(function()
  return parallel.waitForAny(
    function() return shell.run(ROOT .. "/system/desktop.lua") end,
    function() return shell.run(ROOT .. "/system/order_service.lua") end
  )
end, function(err) return tostring(err) end)

if ok and result ~= false then
  if fs.exists(MARKER) then fs.delete(MARKER) end
else
  writeFile(CRASH_LOG, "ConcordOS crash\n" .. tostring(result) .. "\n")
  recovery("Рабочий стол завершился с ошибкой. Лог: " .. CRASH_LOG)
end
