-- ConcordOS Russian terminal. UTF-8 input, CP866 display.
local ROOT = "/concordos"
local ru = dofile(ROOT .. "/system/lib/ru.lua")
local native = term.current()

local function newline()
  local width, height = native.getSize()
  local _, y = native.getCursorPos()
  if y >= height then
    native.scroll(1)
    native.setCursorPos(1, height)
  else
    native.setCursorPos(1, y + 1)
  end
end

local function say(value)
  local text = tostring(value or "")
  local width = native.getSize()
  while ru.len(text) > width do
    ru.write(native, ru.sub(text, 1, width))
    newline()
    text = ru.sub(text, width + 1)
  end
  ru.write(native, text)
end

local function sayLine(value)
  say(value)
  newline()
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function split(value)
  local result = {}
  for word in value:gmatch("%S+") do result[#result + 1] = word end
  return result
end

local function readUtf8(prompt)
  local line, cursor = "", 1
  local startX, startY = native.getCursorPos()
  local width = native.getSize()
  local promptLength = ru.len(prompt)

  local function redraw()
    local available = math.max(1, width - promptLength)
    local first = math.max(1, cursor - available + 1)
    local visible = ru.sub(line, first, first + available - 1)
    native.setCursorPos(startX, startY)
    ru.write(native, ru.padRight(prompt .. visible, width - startX + 1))
    native.setCursorPos(math.min(width, startX + promptLength + cursor - first), startY)
  end

  native.setCursorBlink(true)
  redraw()
  while true do
    local event, a = os.pullEventRaw()
    if event == "char" or event == "paste" then
      local before = ru.sub(line, 1, cursor - 1)
      local after = ru.sub(line, cursor)
      line = before .. a .. after
      cursor = cursor + ru.len(a)
      redraw()
    elseif event == "key" then
      if a == keys.enter then
        native.setCursorBlink(false)
        newline()
        return line
      elseif a == keys.left then
        cursor = math.max(1, cursor - 1)
      elseif a == keys.right then
        cursor = math.min(ru.len(line) + 1, cursor + 1)
      elseif a == keys.home then
        cursor = 1
      elseif a == keys['end'] then
        cursor = ru.len(line) + 1
      elseif a == keys.backspace and cursor > 1 then
        line = ru.sub(line, 1, cursor - 2) .. ru.sub(line, cursor)
        cursor = cursor - 1
      elseif a == keys.delete and cursor <= ru.len(line) then
        line = ru.sub(line, 1, cursor - 1) .. ru.sub(line, cursor + 1)
      elseif a == keys.u and (keys.isCtrlDown and keys.isCtrlDown()) then
        line, cursor = "", 1
      end
      redraw()
    elseif event == "terminate" then
      native.setCursorBlink(false)
      return nil
    end
  end
end

local function proxyTerm()
  local wrapped = {}
  for name, value in pairs(native) do
    if type(value) == "function" then wrapped[name] = value end
  end
  wrapped.write = function(value) ru.write(native, value) end
  wrapped.blit = function(value, foreground, background) ru.blit(native, value, foreground, background) end
  wrapped.current = function() return wrapped end
  return wrapped
end

local function runLua(path, arguments)
  local wrappedTerm = proxyTerm()
  local environment = setmetatable({
    term = wrappedTerm,
    write = function(value) ru.write(wrappedTerm, value) end,
    print = function(...)
      local values = { ... }
      local out = {}
      for index = 1, #values do out[index] = tostring(values[index]) end
      sayLine(table.concat(out, "\t"))
    end,
  }, { __index = _G })

  local chunk, err = loadfile(path, "t", environment)
  if not chunk then return false, err end
  local unpackArgs = table.unpack or unpack
  return pcall(chunk, unpackArgs(arguments))
end

local function help()
  sayLine("Команды:")
  sayLine("  help / помощь       эта справка")
  sayLine("  clear / очистить    очистить экран")
  sayLine("  run <файл> [арг.]   запустить Lua-программу")
  sayLine("  shell               обычная оболочка CC")
  sayLine("  exit / выход        вернуться на рабочий стол")
  sayLine("  reboot, shutdown    питание компьютера")
end

native.setBackgroundColor(colors.black)
native.setTextColor(colors.white)
native.clear()
native.setCursorPos(1, 1)
native.setTextColor(colors.lightBlue)
sayLine("ConcordOS: русский терминал")
native.setTextColor(colors.lightGray)
sayLine("help — справка, exit — рабочий стол.")
native.setTextColor(colors.white)

while true do
  local commandLine = readUtf8("Фесолоник> ")
  if not commandLine then return end
  local parts = split(trim(commandLine))
  local command = ru.lower(parts[1] or "")

  if command == "" then
    -- Nothing to do.
  elseif command == "help" or command == "помощь" then
    help()
  elseif command == "clear" or command == "очистить" then
    native.clear()
    native.setCursorPos(1, 1)
  elseif command == "exit" or command == "выход" then
    return
  elseif command == "reboot" then
    os.reboot()
  elseif command == "shutdown" then
    os.shutdown()
  elseif command == "shell" then
    shell.run("shell")
  elseif command == "run" or command == "запуск" then
    local path = parts[2]
    if not path then
      sayLine("Укажи файл: run /имя.lua")
    elseif not fs.exists(path) then
      sayLine("Файл не найден: " .. path)
    else
      local arguments = {}
      for index = 3, #parts do arguments[#arguments + 1] = parts[index] end
      local ok, result = runLua(path, arguments)
      if not ok then sayLine("Ошибка программы: " .. tostring(result)) end
    end
  else
    sayLine("Неизвестная команда: " .. command .. ". Введи help.")
  end
end
