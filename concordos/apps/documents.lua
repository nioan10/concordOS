-- ConcordOS document centre: text files, editor and paged Printer output.
local ROOT = "/concordos"
local DOC_ROOT = ROOT .. "/data/docs"
local ui = dofile(ROOT .. "/system/lib/ui.lua")
local ru = ui.ru
local computer = term.current()
local monitor = peripheral.find("monitor")
local monitorName = monitor and peripheral.getName(monitor) or nil
local outputs = { computer }
if monitor then outputs[#outputs + 1] = monitor end

local screen = "files"
local entries, filePage, selected = {}, 0, 1
local document = nil
local cursorLine, cursorCol, scrollLine, scrollCol = 1, 1, 1, 1
local prompt, confirmDelete = nil, nil
local statusText, statusColor = "Готово", colors.lightGray
local undoStack, redoStack = {}, {}
local shiftHeld, ctrlHeld = false, false

-- CC:Tweaked on some clients only sends Latin characters from the physical
-- keyboard.  Keep a small, self-contained Russian layout for documents so
-- writing does not depend on the Minecraft/client keyboard layout.
local russianInput = true
local russianKeys = {
  [keys.q] = "й", [keys.w] = "ц", [keys.e] = "у", [keys.r] = "к", [keys.t] = "е",
  [keys.y] = "н", [keys.u] = "г", [keys.i] = "ш", [keys.o] = "щ", [keys.p] = "з",
  [keys.a] = "ф", [keys.s] = "ы", [keys.d] = "в", [keys.f] = "а", [keys.g] = "п",
  [keys.h] = "р", [keys.j] = "о", [keys.k] = "л", [keys.l] = "д",
  [keys.z] = "я", [keys.x] = "ч", [keys.c] = "с", [keys.v] = "м", [keys.b] = "и",
  [keys.n] = "т", [keys.m] = "ь", [keys.space] = " ",
}

-- These names exist in CC:Tweaked, but the checks keep the editor compatible
-- with older key tables as well.
for _, item in ipairs({
  { "zero", "0" }, { "one", "1" }, { "two", "2" }, { "three", "3" }, { "four", "4" },
  { "five", "5" }, { "six", "6" }, { "seven", "7" }, { "eight", "8" }, { "nine", "9" },
  { "grave", "ё" }, { "leftBracket", "х" }, { "rightBracket", "ъ" }, { "semicolon", "ж" },
  { "apostrophe", "э" }, { "comma", "б" }, { "period", "ю" }, { "minus", "-" }, { "equals", "=" },
}) do
  if keys[item[1]] then russianKeys[keys[item[1]]] = item[2] end
end

local function shiftDown()
  return shiftHeld or (keys.isShiftDown and keys.isShiftDown())
end

local function ctrlDown()
  return ctrlHeld or (keys.isCtrlDown and keys.isCtrlDown())
end

local function isNamedKey(keyCode, ...)
  for _, name in ipairs({ ... }) do
    if keys[name] and keyCode == keys[name] then return true end
  end
  return false
end

local function russianChar(keyCode)
  -- On the standard Russian PC layout this physical key produces . or ,.
  if keys.slash and keyCode == keys.slash then return shiftDown() and "," or "." end
  local character = russianKeys[keyCode]
  if character and shiftDown() then return ru.upper(character) end
  return character
end

local function inputLayoutName()
  return russianInput and "РУС" or "ENG"
end

local function setStatus(text, color)
  statusText, statusColor = tostring(text or ""), color or colors.lightGray
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function ensureRoot()
  if not fs.exists(DOC_ROOT) then fs.makeDir(DOC_ROOT) end
end

local function safeName(value)
  value = trim(value):gsub("[\\/:*?\"<>|]", "_")
  if value == "" then value = "Новый документ" end
  if not value:lower():match("%.txt$") then value = value .. ".txt" end
  return value
end

local function pathFor(name)
  return fs.combine(DOC_ROOT, safeName(name))
end

local function readLines(path)
  local file = fs.open(path, "r")
  if not file then return nil, "Не удалось открыть файл" end
  local result = {}
  while true do
    local line = file.readLine()
    if line == nil then break end
    result[#result + 1] = line
  end
  file.close()
  if #result == 0 then result[1] = "" end
  return result
end

local function writeLines(path, lines)
  ensureRoot()
  local file = assert(fs.open(path, "w"), "Не удалось сохранить файл")
  for index, line in ipairs(lines) do
    file.write(line)
    if index < #lines then file.write("\n") end
  end
  file.close()
end

local function scanFiles()
  ensureRoot()
  entries = {}
  for _, name in ipairs(fs.list(DOC_ROOT)) do
    local path = fs.combine(DOC_ROOT, name)
    if not fs.isDir(path) then entries[#entries + 1] = name end
  end
  table.sort(entries, function(a, b) return ru.lower(a) < ru.lower(b) end)
  selected = math.max(1, math.min(selected, #entries))
  filePage = 0
end

local function homeButton(target, label)
  local width = target.getSize()
  local buttonWidth = width >= 40 and 11 or 3
  return width - buttonWidth + 1, buttonWidth, buttonWidth == 3 and "<" or (label or "< Главная")
end

local function rowsPerPage(target, firstRow)
  local _, height = target.getSize()
  return math.max(1, height - firstRow - 1)
end

local function startPrompt(label, value, action)
  prompt = { label = label, value = value or "", action = action }
end

local function clearPrompt()
  prompt = nil
end

local function submitPrompt()
  if not prompt then return end
  local action, value = prompt.action, prompt.value
  clearPrompt()
  action(value)
end

local function openDocument(name)
  local path = pathFor(name)
  local lines, err = readLines(path)
  if not lines then setStatus(err, colors.red) return end
  document = { name = fs.getName(path), path = path, lines = lines, changed = false }
  undoStack, redoStack = {}, {}
  cursorLine, cursorCol, scrollLine, scrollCol = 1, 1, 1, 1
  screen = "editor"
  setStatus("Открыт: " .. document.name, colors.lime)
end

local function createDocument(name)
  local path = pathFor(name)
  local base, index = path, 2
  while fs.exists(path) do
    local stem = fs.getName(base):gsub("%.txt$", "")
    path = fs.combine(DOC_ROOT, stem .. " (" .. tostring(index) .. ").txt")
    index = index + 1
  end
  document = { name = fs.getName(path), path = path, lines = { "" }, changed = true }
  undoStack, redoStack = {}, {}
  cursorLine, cursorCol, scrollLine, scrollCol = 1, 1, 1, 1
  screen = "editor"
  setStatus("Создан новый документ", colors.lime)
end

local function saveDocument()
  if not document then return end
  local ok, err = pcall(writeLines, document.path, document.lines)
  if ok then
    document.changed = false
    scanFiles()
    setStatus("Сохранено: " .. document.name, colors.lime)
  else
    setStatus("Ошибка сохранения: " .. tostring(err), colors.red)
  end
end

local function editorGeometry(target)
  local width, height = target.getSize()
  return width, height, 5, math.max(1, height - 6), 5
end

local function lineCapacity()
  local capacity = math.huge
  for _, target in ipairs(outputs) do
    local width = target.getSize()
    capacity = math.min(capacity, math.max(8, width - 4))
  end
  return capacity == math.huge and 8 or capacity
end

local function keepCursorVisible(target)
  local _, _, firstRow, rows = editorGeometry(target)
  if cursorLine < scrollLine then scrollLine = cursorLine end
  if cursorLine >= scrollLine + rows then scrollLine = cursorLine - rows + 1 end
  scrollLine, scrollCol = math.max(1, scrollLine), 1
end

local function snapshot()
  local lines = {}
  for index, line in ipairs(document.lines) do lines[index] = line end
  return { lines = lines, cursorLine = cursorLine, cursorCol = cursorCol, changed = document.changed }
end

local function rememberEdit()
  if not document then return end
  undoStack[#undoStack + 1] = snapshot()
  if #undoStack > 80 then table.remove(undoStack, 1) end
  redoStack = {}
end

local function restoreSnapshot(state)
  document.lines, cursorLine, cursorCol, document.changed = state.lines, state.cursorLine, state.cursorCol, state.changed
end

local function undo()
  if #undoStack == 0 then setStatus("Нечего отменять", colors.lightGray) return end
  redoStack[#redoStack + 1] = snapshot()
  restoreSnapshot(table.remove(undoStack))
  setStatus("Отменено", colors.orange)
end

local function redo()
  if #redoStack == 0 then setStatus("Нечего повторять", colors.lightGray) return end
  undoStack[#undoStack + 1] = snapshot()
  restoreSnapshot(table.remove(redoStack))
  setStatus("Повторено", colors.lime)
end

local function autoWrapDocument()
  if not document then return end
  local maximum, index = lineCapacity(), 1
  while index <= #document.lines do
    local line = document.lines[index]
    if ru.len(line) <= maximum then
      index = index + 1
    else
      local split = maximum
      while split > 1 and ru.sub(line, split, split) ~= " " do split = split - 1 end
      local splitAtSpace = ru.sub(line, split, split) == " "
      if not splitAtSpace then split = maximum end
      local before = ru.sub(line, 1, splitAtSpace and split - 1 or split)
      local after = ru.sub(line, split + 1)
      document.lines[index] = before
      table.insert(document.lines, index + 1, after)
      if cursorLine == index and cursorCol > split then
        cursorLine, cursorCol = index + 1, cursorCol - split
      elseif cursorLine > index then
        cursorLine = cursorLine + 1
      end
      index = index + 1
    end
  end
end

local function insertPiece(piece)
  local line = document.lines[cursorLine]
  document.lines[cursorLine] = ru.sub(line, 1, cursorCol - 1) .. piece .. ru.sub(line, cursorCol)
  cursorCol = cursorCol + ru.len(piece)
end

local function newLine()
  local line = document.lines[cursorLine]
  local before, after = ru.sub(line, 1, cursorCol - 1), ru.sub(line, cursorCol)
  document.lines[cursorLine] = before
  table.insert(document.lines, cursorLine + 1, after)
  cursorLine, cursorCol = cursorLine + 1, 1
end

local function insertText(text)
  if not document then return end
  text = tostring(text or ""):gsub("\r", "")
  local first = true
  for part in (text .. "\n"):gmatch("(.-)\n") do
    if first then first = false else newLine() end
    insertPiece(part)
  end
  document.changed = true
  autoWrapDocument()
end

local function backspace()
  if not document then return end
  if cursorCol > 1 then
    local line = document.lines[cursorLine]
    document.lines[cursorLine] = ru.sub(line, 1, cursorCol - 2) .. ru.sub(line, cursorCol)
    cursorCol = cursorCol - 1
  elseif cursorLine > 1 then
    local previous = document.lines[cursorLine - 1]
    cursorCol = ru.len(previous) + 1
    document.lines[cursorLine - 1] = previous .. document.lines[cursorLine]
    table.remove(document.lines, cursorLine)
    cursorLine = cursorLine - 1
  end
  document.changed = true
  autoWrapDocument()
end

local function deleteChar()
  if not document then return end
  local line = document.lines[cursorLine]
  if cursorCol <= ru.len(line) then
    document.lines[cursorLine] = ru.sub(line, 1, cursorCol - 1) .. ru.sub(line, cursorCol + 1)
  elseif cursorLine < #document.lines then
    document.lines[cursorLine] = line .. document.lines[cursorLine + 1]
    table.remove(document.lines, cursorLine + 1)
  end
  document.changed = true
  autoWrapDocument()
end

local function wrapLine(line, width)
  local result = {}
  if line == "" then return { "" } end
  while ru.len(line) > width do
    result[#result + 1] = ru.sub(line, 1, width)
    line = ru.sub(line, width + 1)
  end
  result[#result + 1] = line
  return result
end

local function printableLines(lines, width)
  local result = {}
  for _, line in ipairs(lines) do
    for _, part in ipairs(wrapLine(line, width)) do result[#result + 1] = part end
  end
  return result
end

local function printDocument()
  if not document then return end
  local printer = peripheral.find("printer")
  if not printer then setStatus("Принтер CC:Tweaked не найден", colors.red) return end
  saveDocument()
  local okPage, started = pcall(printer.newPage)
  if not okPage or not started then
    setStatus("Не удалось начать печать: добавь бумагу и краситель", colors.red)
    return
  end
  local width, height = printer.getPageSize()
  local content = printableLines(document.lines, width)
  local index, pageCount = 1, 0
  repeat
    pageCount = pageCount + 1
    -- Printed pages use CC:Tweaked's one-byte terminal font too. Convert only
    -- at this boundary: document files remain ordinary UTF-8 text.
    printer.setPageTitle(ru.encode(document.name:gsub("%.txt$", "") .. " — " .. tostring(pageCount)))
    for row = 1, height do
      local line = content[index]
      if line then
        printer.setCursorPos(1, row)
        printer.write(ru.encode(line))
        index = index + 1
      end
    end
    if not printer.endPage() then
      setStatus("Печать остановлена: закончились бумага или чернила", colors.red)
      return
    end
    if content[index] then
      local nextOk, nextStarted = pcall(printer.newPage)
      if not nextOk or not nextStarted then
        setStatus("Напечатано страниц: " .. tostring(pageCount) .. "; нет бумаги или чернил", colors.orange)
        return
      end
    end
  until not content[index]
  setStatus("Напечатано страниц: " .. tostring(pageCount), colors.lime)
end

local function drawHeader(target, title, backLabel)
  local width = target.getSize()
  ui.line(target, 1, 1, width, "ConcordOS | " .. title, colors.white, colors.blue)
  local homeX, homeWidth, homeLabel = homeButton(target, backLabel)
  ui.button(target, homeX, 1, homeWidth, 1, "", colors.white, colors.blue, true)
  ui.text(target, homeX, 1, homeLabel, colors.white, colors.lightBlue)
end

local function drawFiles(target)
  local width = target.getSize()
  drawHeader(target, "Документы")
  ui.line(target, 1, 3, width, "Файловый менеджер текстов  ·  " .. DOC_ROOT, colors.lightGray, colors.gray)
  local part = math.floor((width - 3) / 4)
  ui.button(target, 2, 4, part, 1, "Новый", colors.white, colors.green, false)
  ui.button(target, 3 + part, 4, part, 1, "Открыть", colors.white, colors.blue, false)
  ui.button(target, 4 + part * 2, 4, part, 1, "Имя", colors.white, colors.orange, false)
  ui.button(target, 5 + part * 3, 4, width - (4 + part * 3), 1, "Удалить", colors.white, colors.red, false)
  if #entries == 0 then
    ui.text(target, 2, 7, "Документов пока нет. Нажми «Новый».", colors.white, colors.gray)
    return
  end
  local firstRow, perPage = 6, rowsPerPage(target, 6)
  local totalPages = math.max(1, math.ceil(#entries / perPage))
  if filePage >= totalPages then filePage = totalPages - 1 end
  local first = filePage * perPage + 1
  for offset = 0, perPage - 1 do
    local index, name = first + offset, entries[first + offset]
    if name then
      local active = index == selected
      ui.line(target, 2, firstRow + offset, width - 3, tostring(index) .. ". " .. name, colors.white, active and colors.lightBlue or (offset % 2 == 0 and colors.gray or colors.black))
    end
  end
  local _, height = target.getSize()
  ui.line(target, 1, height, width, "Стр. " .. tostring(filePage + 1) .. "/" .. tostring(totalPages) .. "  Колесо: страницы  Enter: открыть  F2: новый", colors.black, colors.lightGray)
end

local function drawEditor(target)
  local width, height, firstRow, rows, textX = editorGeometry(target)
  drawHeader(target, "Текстовый редактор", "< Файлы")
  ui.line(target, 1, 3, width, (document.changed and "* " or "") .. document.name, colors.white, colors.gray)
  local part = math.floor((width - 3) / 3)
  ui.button(target, 2, 4, part, 1, "Сохранить", colors.white, colors.green, false)
  ui.button(target, 3 + part, 4, part, 1, "Печать", colors.white, colors.orange, false)
  ui.button(target, 4 + part * 2, 4, width - (3 + part * 2), 1, "Название", colors.white, colors.blue, false)
  keepCursorVisible(target)
  for offset = 0, rows - 1 do
    local lineIndex, y = scrollLine + offset, firstRow + offset
    local line = document.lines[lineIndex]
    if line then
      ui.text(target, 1, y, ru.fit(tostring(lineIndex), 3, ""), colors.lightGray, colors.gray, 3)
      local shown = ru.sub(line, scrollCol, scrollCol + width - textX)
      if lineIndex == cursorLine then
        local position = cursorCol - scrollCol + 1
        if position >= 1 and position <= width - textX then
          shown = ru.sub(shown, 1, position - 1) .. "|" .. ru.sub(shown, position)
        end
      end
      ui.line(target, textX, y, width - textX + 1, shown, colors.white, lineIndex == cursorLine and colors.black or colors.gray)
    end
  end
  ui.line(target, 1, height, width, "F2: сохр. F3: печать F7: " .. inputLayoutName() .. " Ctrl+Z/Y: отмена  < Файлы", colors.black, colors.lightGray)
end

local function drawPrompt(target)
  if not prompt then return end
  local width = target.getSize()
  local boxWidth = math.max(20, math.min(width - 4, 42))
  local x = math.floor((width - boxWidth) / 2) + 1
  ui.fill(target, x, 7, boxWidth, 5, colors.black)
  ui.line(target, x + 1, 8, boxWidth - 2, prompt.label, colors.white, colors.black)
  ui.line(target, x + 1, 9, boxWidth - 2, prompt.value .. "|", colors.white, colors.blue)
  local leftWidth = math.floor((boxWidth - 3) / 2)
  ui.button(target, x + 1, 10, leftWidth, 1, "Отмена", colors.white, colors.gray, false)
  ui.button(target, x + 2 + leftWidth, 10, math.ceil((boxWidth - 3) / 2), 1, "Готово", colors.white, colors.green, false)
end

local function drawConfirm(target)
  if not confirmDelete then return end
  local width = target.getSize()
  local boxWidth, x = math.max(24, math.min(width - 4, 44)), math.floor((width - math.max(24, math.min(width - 4, 44))) / 2) + 1
  ui.fill(target, x, 7, boxWidth, 5, colors.black)
  ui.line(target, x + 1, 8, boxWidth - 2, "Удалить «" .. confirmDelete .. "»?", colors.white, colors.black)
  ui.button(target, x + 1, 10, math.floor((boxWidth - 3) / 2), 1, "Нет", colors.white, colors.gray, false)
  ui.button(target, x + 2 + math.floor((boxWidth - 3) / 2), 10, math.ceil((boxWidth - 3) / 2), 1, "Удалить", colors.white, colors.red, false)
end

local function drawTarget(target)
  local width = target.getSize()
  ui.clear(target, colors.gray)
  if screen == "files" then drawFiles(target) else drawEditor(target) end
  drawPrompt(target)
  drawConfirm(target)
  if not prompt and not confirmDelete then ui.line(target, 1, 2, width, ru.fit(statusText, width, ""), statusColor, colors.gray) end
end

local function draw()
  for _, target in ipairs(outputs) do drawTarget(target) end
end

local function clickedHome(target, x, y)
  local homeX, homeWidth = homeButton(target, screen == "editor" and "< Файлы" or nil)
  return y == 1 and x >= homeX and x < homeX + homeWidth
end

local function renameDocument(value)
  if not document then return end
  local newPath = pathFor(value)
  if newPath ~= document.path and fs.exists(newPath) then setStatus("Файл с таким именем уже есть", colors.red) return end
  if newPath ~= document.path and fs.exists(document.path) then fs.move(document.path, newPath) end
  document.path, document.name = newPath, fs.getName(newPath)
  scanFiles()
  setStatus("Новое имя: " .. document.name, colors.lime)
end

scanFiles()
draw()

while true do
  local event, a, b, c = os.pullEventRaw()
  if event == "key" then
    if isNamedKey(a, "leftShift", "rightShift") then shiftHeld = true end
    if isNamedKey(a, "leftCtrl", "rightCtrl") then ctrlHeld = true end
  elseif event == "key_up" then
    if isNamedKey(a, "leftShift", "rightShift") then shiftHeld = false end
    if isNamedKey(a, "leftCtrl", "rightCtrl") then ctrlHeld = false end
  end
  if event == "term_resize" or (event == "monitor_resize" and a == monitorName) then
    if screen == "editor" and document then autoWrapDocument() end
    draw()
  elseif prompt then
    if event == "paste" then prompt.value = prompt.value .. a
    elseif event == "char" and not russianInput then prompt.value = prompt.value .. a
    elseif event == "key" then
      local character = russianInput and russianChar(a)
      if a == keys.f7 then russianInput = not russianInput
      elseif character then prompt.value = prompt.value .. character
      elseif a == keys.backspace then prompt.value = ru.sub(prompt.value, 1, ru.len(prompt.value) - 1)
      elseif a == keys.enter then submitPrompt() end
    elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
      local target, x, y = event == "monitor_touch" and monitor or computer, b, c
      local width = target.getSize()
      local boxWidth = math.max(20, math.min(width - 4, 42))
      local boxX = math.floor((width - boxWidth) / 2) + 1
      local leftWidth = math.floor((boxWidth - 3) / 2)
      if y == 10 and x >= boxX + 1 and x < boxX + 1 + leftWidth then
        clearPrompt()
      elseif y == 10 and x >= boxX + 2 + leftWidth and x < boxX + boxWidth - 1 then
        submitPrompt()
      end
    end
    draw()
  elseif confirmDelete then
    if event == "mouse_click" then
      local width = computer.getSize()
      local boxWidth = math.max(24, math.min(width - 4, 44))
      local x = math.floor((width - boxWidth) / 2) + 1
      if c == 10 and b >= x + 2 + math.floor((boxWidth - 3) / 2) then
        local path = pathFor(confirmDelete)
        if fs.exists(path) then fs.delete(path) end
        confirmDelete = nil
        scanFiles()
        setStatus("Документ удалён", colors.orange)
      elseif c == 10 then confirmDelete = nil end
    elseif event == "key" and a == keys.enter then
      local path = pathFor(confirmDelete)
      if fs.exists(path) then fs.delete(path) end
      confirmDelete = nil
      scanFiles()
      setStatus("Документ удалён", colors.orange)
    end
    draw()
  elseif event == "paste" or (event == "char" and not russianInput) then
    if screen == "editor" then
      rememberEdit()
      insertText(a)
      keepCursorVisible(computer)
      draw()
    end
  elseif event == "key" then
    if screen == "files" then
      if a == keys.f2 then startPrompt("Название нового документа", "", createDocument)
      elseif a == keys.enter and entries[selected] then openDocument(entries[selected])
      elseif a == keys.up then selected = math.max(1, selected - 1)
      elseif a == keys.down then selected = math.min(#entries, selected + 1)
      elseif a == keys.delete and entries[selected] then confirmDelete = entries[selected]
      elseif a == keys.f3 and entries[selected] then
        local name = entries[selected]:gsub("%.txt$", "")
        startPrompt("Новое имя файла", name, function(value)
          local oldPath, newPath = pathFor(entries[selected]), pathFor(value)
          if fs.exists(newPath) and newPath ~= oldPath then setStatus("Файл с таким именем уже есть", colors.red) return end
          fs.move(oldPath, newPath)
          scanFiles()
          setStatus("Файл переименован", colors.lime)
        end)
      end
    else
      local line = document.lines[cursorLine]
      local character = russianInput and russianChar(a)
      if ctrlDown() and a == keys.z then undo()
      elseif ctrlDown() and a == keys.y then redo()
      elseif a == keys.f7 then russianInput = not russianInput
      elseif character then
        rememberEdit()
        insertText(character)
      elseif a == keys.f2 then saveDocument()
      elseif a == keys.f3 then printDocument()
      elseif a == keys.f4 then startPrompt("Название нового документа", "", createDocument)
      elseif a == keys.f6 then startPrompt("Новое название", document.name:gsub("%.txt$", ""), renameDocument)
      elseif a == keys.enter then
        rememberEdit()
        newLine()
        document.changed = true
      elseif a == keys.backspace then
        rememberEdit()
        backspace()
      elseif a == keys.delete then
        rememberEdit()
        deleteChar()
      elseif a == keys.left then cursorCol = math.max(1, cursorCol - 1)
      elseif a == keys.right then cursorCol = math.min(ru.len(line) + 1, cursorCol + 1)
      elseif a == keys.up then
        cursorLine = math.max(1, cursorLine - 1)
        cursorCol = math.min(cursorCol, ru.len(document.lines[cursorLine]) + 1)
      elseif a == keys.down then
        cursorLine = math.min(#document.lines, cursorLine + 1)
        cursorCol = math.min(cursorCol, ru.len(document.lines[cursorLine]) + 1)
      elseif a == keys.home then cursorCol = 1
      elseif a == keys['end'] then cursorCol = ru.len(line) + 1
      elseif a == keys.pageUp then
        cursorLine = math.max(1, cursorLine - 10)
        cursorCol = math.min(cursorCol, ru.len(document.lines[cursorLine]) + 1)
      elseif a == keys.pageDown then
        cursorLine = math.min(#document.lines, cursorLine + 10)
        cursorCol = math.min(cursorCol, ru.len(document.lines[cursorLine]) + 1)
      end
      keepCursorVisible(computer)
    end
    draw()
  elseif event == "mouse_scroll" and screen == "files" then
    local perPage = rowsPerPage(computer, 6)
    local maxPage = math.max(0, math.ceil(#entries / perPage) - 1)
    filePage = math.max(0, math.min(maxPage, filePage + (a > 0 and 1 or -1)))
    draw()
  elseif event == "mouse_click" or (event == "monitor_touch" and a == monitorName) then
    local target, x, y = event == "monitor_touch" and monitor or computer, b, c
    if clickedHome(target, x, y) then
      if screen == "editor" then
        screen = "files"
        scanFiles()
      else
        return
      end
    elseif screen == "files" then
      local width = target.getSize()
      local part = math.floor((width - 3) / 4)
      if y == 4 then
        if x < 3 + part then startPrompt("Название нового документа", "", createDocument)
        elseif x < 4 + part * 2 and entries[selected] then openDocument(entries[selected])
        elseif x < 5 + part * 3 and entries[selected] then
          startPrompt("Новое имя файла", entries[selected]:gsub("%.txt$", ""), function(value)
            local oldPath, newPath = pathFor(entries[selected]), pathFor(value)
            if fs.exists(newPath) and newPath ~= oldPath then setStatus("Файл с таким именем уже есть", colors.red) return end
            fs.move(oldPath, newPath)
            scanFiles()
            setStatus("Файл переименован", colors.lime)
          end)
        elseif entries[selected] then confirmDelete = entries[selected] end
      elseif y >= 6 then
        local index = filePage * rowsPerPage(target, 6) + y - 5
        if entries[index] then
          selected = index
          openDocument(entries[index])
        end
      end
    else
      local width = target.getSize()
      local part = math.floor((width - 3) / 3)
      if y == 4 then
        if x < 3 + part then saveDocument()
        elseif x < 4 + part * 2 then printDocument()
        else startPrompt("Новое название", document.name:gsub("%.txt$", ""), renameDocument) end
      else
        local _, targetHeight = target.getSize()
        if y >= 5 and y < targetHeight then
        local _, _, firstRow, rows, textX = editorGeometry(target)
        if y >= firstRow and y < firstRow + rows then
          local lineIndex = scrollLine + y - firstRow
          if document.lines[lineIndex] then
            cursorLine = lineIndex
            cursorCol = math.max(1, math.min(ru.len(document.lines[lineIndex]) + 1, scrollCol + x - textX))
          end
        end
        end
      end
    end
    draw()
  elseif event == "terminate" then
    return
  end
end
