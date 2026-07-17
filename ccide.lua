-- CCIDE: a compact in-game Lua editor for CC:Tweaked.
-- Usage: ccide [file.lua]

local args = { ... }

local TAB_SIZE = 2
local SCROLL_STEP = 3
local UNDO_LIMIT = 100

local lines = { "" }
local filePath = nil
local cursorX, cursorY = 1, 1
local scrollX, scrollY = 0, 0
local dirty = false
local statusMessage = "Ready"
local findText = nil
local heldKeys = {}
local undoStack, redoStack = {}, {}
local buttons = {}

local screenW, screenH = term.getSize()
local gutterWidth = 3

local theme = {
    background = colors.black,
    foreground = colors.white,
    gutterBackground = colors.gray,
    gutterForeground = colors.lightGray,
    headerBackground = colors.blue,
    headerForeground = colors.white,
    statusBackground = colors.gray,
    statusForeground = colors.white,
    keyword = colors.yellow,
    string = colors.lime,
    number = colors.lightBlue,
    comment = colors.lightGray,
    builtin = colors.cyan,
}

local keywords = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

local builtins = {
    ["assert"] = true, ["error"] = true, ["ipairs"] = true, ["next"] = true,
    ["pairs"] = true, ["pcall"] = true, ["print"] = true, ["require"] = true,
    ["select"] = true, ["tonumber"] = true, ["tostring"] = true, ["type"] = true,
    ["xpcall"] = true, ["fs"] = true, ["http"] = true, ["keys"] = true,
    ["os"] = true, ["peripheral"] = true, ["rednet"] = true,
    ["redstone"] = true, ["shell"] = true, ["term"] = true,
    ["textutils"] = true, ["turtle"] = true,
}

local function copyLines(source)
    local result = {}
    for i = 1, #source do result[i] = source[i] end
    return result
end

local function snapshot()
    return {
        lines = copyLines(lines),
        cursorX = cursorX,
        cursorY = cursorY,
        scrollX = scrollX,
        scrollY = scrollY,
    }
end

local function restore(state)
    lines = copyLines(state.lines)
    cursorX, cursorY = state.cursorX, state.cursorY
    scrollX, scrollY = state.scrollX, state.scrollY
    dirty = true
end

local function pushUndo()
    undoStack[#undoStack + 1] = snapshot()
    if #undoStack > UNDO_LIMIT then table.remove(undoStack, 1) end
    redoStack = {}
end

local function undo()
    if #undoStack == 0 then
        statusMessage = "Nothing to undo"
        return
    end
    redoStack[#redoStack + 1] = snapshot()
    local state = table.remove(undoStack)
    restore(state)
    statusMessage = "Undo"
end

local function redo()
    if #redoStack == 0 then
        statusMessage = "Nothing to redo"
        return
    end
    undoStack[#undoStack + 1] = snapshot()
    local state = table.remove(redoStack)
    restore(state)
    statusMessage = "Redo"
end

local function splitText(text)
    text = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local result = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        result[#result + 1] = line
    end
    if #result == 0 then result[1] = "" end
    return result
end

local function resolvePath(path)
    if not path or path == "" then return nil end
    if shell.resolve then return shell.resolve(path) end
    return fs.combine(shell.dir(), path)
end

local function loadFile(path)
    path = resolvePath(path)
    if not path then return false, "No file name" end
    if fs.exists(path) and fs.isDir(path) then return false, "Path is a directory" end

    if fs.exists(path) then
        local handle, reason = fs.open(path, "r")
        if not handle then return false, reason or "Cannot open file" end
        local content = handle.readAll()
        handle.close()
        lines = splitText(content)
        statusMessage = "Opened " .. path
    else
        lines = { "" }
        statusMessage = "New file " .. path
    end

    filePath = path
    cursorX, cursorY = 1, 1
    scrollX, scrollY = 0, 0
    dirty = false
    undoStack, redoStack = {}, {}
    return true
end

local function setTerminal(background, foreground)
    term.setBackgroundColor(background)
    term.setTextColor(foreground)
end

local function fit(text, width)
    text = tostring(text or "")
    if width <= 0 then return "" end
    if #text > width then
        if width == 1 then return text:sub(1, 1) end
        return text:sub(1, width - 1) .. "~"
    end
    return text .. string.rep(" ", width - #text)
end

local function prompt(label, default)
    screenW, screenH = term.getSize()
    term.setCursorBlink(false)
    setTerminal(theme.statusBackground, theme.statusForeground)
    term.setCursorPos(1, screenH)
    term.clearLine()

    local prefix = label .. (default and default ~= "" and " [" .. default .. "]" or "") .. ": "
    prefix = prefix:sub(1, math.max(1, screenW - 1))
    term.write(prefix)
    term.setCursorBlink(true)

    local ok, value = pcall(read)
    heldKeys = {}
    if not ok then return nil end
    if value == "" and default then value = default end
    return value
end

local function saveFile()
    if not filePath then
        local entered = prompt("Save as", "untitled.lua")
        if not entered or entered == "" then
            statusMessage = "Save cancelled"
            return false
        end
        filePath = resolvePath(entered)
    end

    if fs.exists(filePath) and fs.isDir(filePath) then
        statusMessage = "Cannot save: path is a directory"
        return false
    end
    if fs.isReadOnly(filePath) then
        statusMessage = "Cannot save: read-only path"
        return false
    end

    local directory = fs.getDir(filePath)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end

    local handle, reason = fs.open(filePath, "w")
    if not handle then
        statusMessage = "Save failed: " .. tostring(reason)
        return false
    end
    handle.write(table.concat(lines, "\n"))
    handle.close()
    dirty = false
    statusMessage = "Saved " .. filePath
    return true
end

local function confirmDiscard()
    if not dirty then return true end
    local answer = prompt("Save changes? y/n/c", "c")
    if not answer then return false end
    answer = answer:lower()
    if answer == "y" or answer == "yes" then return saveFile() end
    return answer == "n" or answer == "no"
end

local function calculateLayout()
    screenW, screenH = term.getSize()
    gutterWidth = math.max(3, #tostring(#lines) + 1)
    return math.max(1, screenH - 2), math.max(1, screenW - gutterWidth - 1)
end

local function clampCursor()
    cursorY = math.max(1, math.min(cursorY, #lines))
    cursorX = math.max(1, math.min(cursorX, #lines[cursorY] + 1))
end

local function ensureCursorVisible()
    clampCursor()
    local bodyHeight, editorWidth = calculateLayout()

    if cursorY <= scrollY then scrollY = cursorY - 1 end
    if cursorY > scrollY + bodyHeight then scrollY = cursorY - bodyHeight end
    if cursorX <= scrollX then scrollX = cursorX - 1 end
    if cursorX > scrollX + editorWidth then scrollX = cursorX - editorWidth end

    scrollX = math.max(0, scrollX)
    scrollY = math.max(0, math.min(scrollY, math.max(0, #lines - bodyHeight)))
end

local function paintRange(colorsText, first, last, blitColor)
    for i = first, math.min(last, #colorsText) do colorsText[i] = blitColor end
end

local function highlight(line)
    local normal = colors.toBlit(theme.foreground)
    local result = {}
    for i = 1, #line do result[i] = normal end

    local i = 1
    while i <= #line do
        local char = line:sub(i, i)
        local pair = line:sub(i, i + 1)

        if pair == "--" then
            paintRange(result, i, #line, colors.toBlit(theme.comment))
            break
        elseif char == "\"" or char == "'" then
            local quote, finish = char, i + 1
            while finish <= #line do
                local current = line:sub(finish, finish)
                if current == "\\" then
                    finish = finish + 2
                elseif current == quote then
                    finish = finish + 1
                    break
                else
                    finish = finish + 1
                end
            end
            paintRange(result, i, finish - 1, colors.toBlit(theme.string))
            i = finish
        elseif char:match("[%d]") then
            local finish = i + 1
            while finish <= #line and line:sub(finish, finish):match("[%w%.]") do
                finish = finish + 1
            end
            paintRange(result, i, finish - 1, colors.toBlit(theme.number))
            i = finish
        elseif char:match("[%a_]") then
            local finish = i + 1
            while finish <= #line and line:sub(finish, finish):match("[%w_]") do
                finish = finish + 1
            end
            local word = line:sub(i, finish - 1)
            if keywords[word] then
                paintRange(result, i, finish - 1, colors.toBlit(theme.keyword))
            elseif builtins[word] then
                paintRange(result, i, finish - 1, colors.toBlit(theme.builtin))
            end
            i = finish
        else
            i = i + 1
        end
    end
    return table.concat(result)
end

local function addButton(label, action, rightEdge)
    local startX = rightEdge - #label + 1
    if startX > 1 then
        term.setCursorPos(startX, 1)
        term.write(label)
        buttons[#buttons + 1] = { x1 = startX, x2 = rightEdge, action = action }
    end
    return startX - 2
end

local function drawHeader()
    setTerminal(theme.headerBackground, theme.headerForeground)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", screenW))

    buttons = {}
    local right = screenW
    right = addButton("[Q]", "quit", right)
    right = addButton("[S]", "save", right)
    right = addButton("[F5]", "run", right)
    right = addButton("[F1]", "help", right)

    local name = filePath and fs.getName(filePath) or "untitled.lua"
    if dirty then name = name .. " *" end
    term.setCursorPos(1, 1)
    term.write(fit(" CCIDE | " .. name, math.max(0, right)))
end

local function drawStatus()
    setTerminal(theme.statusBackground, theme.statusForeground)
    term.setCursorPos(1, screenH)
    local position = ("Ln %d Col %d"):format(cursorY, cursorX)
    local message = statusMessage or "Ctrl-S Save | F5 Run | F1 Help"
    local room = screenW - #position - 1
    term.write(fit(message, math.max(0, room)))
    if room >= 0 then term.write(" " .. position) end
end

local function drawScrollbar(bodyHeight)
    local maxScroll = math.max(0, #lines - bodyHeight)
    for row = 1, bodyHeight do
        term.setCursorPos(screenW, row + 1)
        setTerminal(theme.background, theme.gutterForeground)
        term.write("|")
    end
    if maxScroll == 0 then return end

    local thumbSize = math.max(1, math.floor(bodyHeight * bodyHeight / #lines))
    thumbSize = math.min(bodyHeight, thumbSize)
    local travel = bodyHeight - thumbSize
    local thumbStart = 1 + math.floor((scrollY / maxScroll) * travel + 0.5)
    for row = thumbStart, thumbStart + thumbSize - 1 do
        term.setCursorPos(screenW, row + 1)
        setTerminal(theme.gutterForeground, theme.background)
        term.write("#")
    end
end

local function draw()
    term.setCursorBlink(false)
    local bodyHeight, editorWidth = calculateLayout()
    drawHeader()

    for row = 1, bodyHeight do
        local lineNumber = scrollY + row
        local screenRow = row + 1

        setTerminal(theme.gutterBackground, theme.gutterForeground)
        term.setCursorPos(1, screenRow)
        if lineNumber <= #lines then
            term.write(string.format("%" .. (gutterWidth - 1) .. "d ", lineNumber))
        else
            term.write(string.rep(" ", gutterWidth))
        end

        setTerminal(theme.background, theme.foreground)
        term.setCursorPos(gutterWidth + 1, screenRow)
        if lineNumber <= #lines then
            local source = lines[lineNumber]
            local visible = source:sub(scrollX + 1, scrollX + editorWidth)
            local colorData = highlight(source):sub(scrollX + 1, scrollX + editorWidth)
            local padding = editorWidth - #visible
            term.blit(
                visible .. string.rep(" ", padding),
                colorData .. string.rep(colors.toBlit(theme.foreground), padding),
                string.rep(colors.toBlit(theme.background), editorWidth)
            )
        else
            term.write(string.rep(" ", editorWidth))
        end
    end

    drawScrollbar(bodyHeight)
    drawStatus()

    local cursorScreenX = gutterWidth + cursorX - scrollX
    local cursorScreenY = 1 + cursorY - scrollY
    if cursorScreenX > gutterWidth and cursorScreenX < screenW
        and cursorScreenY >= 2 and cursorScreenY < screenH then
        term.setCursorPos(cursorScreenX, cursorScreenY)
        setTerminal(theme.background, theme.foreground)
        term.setCursorBlink(true)
    end
end

local function markChanged(message)
    dirty = true
    statusMessage = message or "Modified"
    ensureCursorVisible()
end

local function insertText(text)
    if not text or text == "" then return end
    pushUndo()
    local inserted = splitText(text)
    local current = lines[cursorY]
    local before = current:sub(1, cursorX - 1)
    local after = current:sub(cursorX)

    if #inserted == 1 then
        lines[cursorY] = before .. inserted[1] .. after
        cursorX = cursorX + #inserted[1]
    else
        lines[cursorY] = before .. inserted[1]
        for i = 2, #inserted do
            table.insert(lines, cursorY + i - 1, inserted[i])
        end
        cursorY = cursorY + #inserted - 1
        lines[cursorY] = lines[cursorY] .. after
        cursorX = #inserted[#inserted] + 1
    end
    markChanged()
end

local function newLine()
    pushUndo()
    local current = lines[cursorY]
    local before = current:sub(1, cursorX - 1)
    local after = current:sub(cursorX)
    local indent = before:match("^%s*") or ""
    local trimmed = before:match("^%s*(.-)%s*$") or ""
    local opensBlock = trimmed:match("then$") or trimmed:match("do$")
        or trimmed:match("function.-$" ) or trimmed:match("repeat$")
        or trimmed:match("{$")
    if opensBlock then indent = indent .. string.rep(" ", TAB_SIZE) end

    lines[cursorY] = before
    table.insert(lines, cursorY + 1, indent .. after)
    cursorY = cursorY + 1
    cursorX = #indent + 1
    markChanged()
end

local function backspace()
    if cursorX > 1 then
        pushUndo()
        local current = lines[cursorY]
        lines[cursorY] = current:sub(1, cursorX - 2) .. current:sub(cursorX)
        cursorX = cursorX - 1
        markChanged()
    elseif cursorY > 1 then
        pushUndo()
        local previousLength = #lines[cursorY - 1]
        lines[cursorY - 1] = lines[cursorY - 1] .. lines[cursorY]
        table.remove(lines, cursorY)
        cursorY = cursorY - 1
        cursorX = previousLength + 1
        markChanged()
    end
end

local function deleteForward()
    local current = lines[cursorY]
    if cursorX <= #current then
        pushUndo()
        lines[cursorY] = current:sub(1, cursorX - 1) .. current:sub(cursorX + 1)
        markChanged()
    elseif cursorY < #lines then
        pushUndo()
        lines[cursorY] = current .. lines[cursorY + 1]
        table.remove(lines, cursorY + 1)
        markChanged()
    end
end

local function indentLine(reverse)
    pushUndo()
    local current = lines[cursorY]
    if reverse then
        local count = math.min(TAB_SIZE, #(current:match("^ *") or ""))
        if count == 0 then
            table.remove(undoStack)
            return
        end
        lines[cursorY] = current:sub(count + 1)
        cursorX = math.max(1, cursorX - count)
    else
        local spaces = string.rep(" ", TAB_SIZE)
        lines[cursorY] = spaces .. current
        cursorX = cursorX + TAB_SIZE
    end
    markChanged()
end

local function isHeld(name)
    local code = keys[name]
    return code and heldKeys[code] or false
end

local function ctrlHeld()
    return isHeld("leftCtrl") or isHeld("rightCtrl")
end

local function shiftHeld()
    return isHeld("leftShift") or isHeld("rightShift")
end

local function findNext()
    if not findText or findText == "" then
        findText = prompt("Find", findText)
        if not findText or findText == "" then
            statusMessage = "Find cancelled"
            return
        end
    end

    local startLine, startColumn = cursorY, cursorX + 1
    for offset = 0, #lines - 1 do
        local lineNumber = ((startLine - 1 + offset) % #lines) + 1
        local from = lineNumber == startLine and startColumn or 1
        local found = lines[lineNumber]:find(findText, from, true)
        if found then
            cursorY, cursorX = lineNumber, found
            statusMessage = "Found: " .. findText
            ensureCursorVisible()
            return
        end
    end
    statusMessage = "Not found: " .. findText
end

local function askFind()
    local value = prompt("Find", findText)
    if value and value ~= "" then
        findText = value
        findNext()
    else
        statusMessage = "Find cancelled"
    end
end

local function goToLine()
    local value = prompt("Go to line", tostring(cursorY))
    local number = tonumber(value)
    if not number then
        statusMessage = "Invalid line number"
        return
    end
    cursorY = math.max(1, math.min(math.floor(number), #lines))
    cursorX = math.min(cursorX, #lines[cursorY] + 1)
    statusMessage = "Line " .. cursorY
    ensureCursorVisible()
end

local function showHelp()
    term.setCursorBlink(false)
    setTerminal(theme.background, theme.foreground)
    term.clear()
    term.setCursorPos(1, 1)

    local help = {
        "CCIDE controls",
        "",
        "Mouse wheel      Scroll 3 lines",
        "Left click       Place cursor",
        "Scrollbar        Jump through file",
        "Ctrl-S           Save",
        "Ctrl-O / Ctrl-N  Open / new file",
        "Ctrl-Z / Ctrl-Y  Undo / redo",
        "Ctrl-F / F3      Find / find next",
        "Ctrl-G           Go to line",
        "F5               Save and run",
        "Ctrl-Q           Exit",
        "Tab / Shift-Tab  Indent / unindent",
        "Home/End/PgUp/PgDn are supported",
        "",
        "Press any key or click to return",
    }
    for i = 1, math.min(#help, screenH) do
        term.setCursorPos(1, i)
        term.write(help[i]:sub(1, screenW))
    end

    while true do
        local event = os.pullEventRaw()
        if event == "key" or event == "char" or event == "mouse_click" or event == "terminate" then break end
    end
    heldKeys = {}
    statusMessage = "Ready"
end

local function runCurrent()
    if dirty or not filePath then
        if not saveFile() then return end
    end

    term.setCursorBlink(false)
    setTerminal(colors.black, colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("Running " .. filePath)
    print(string.rep("-", math.min(screenW, #filePath + 8)))

    local ok, result = pcall(shell.run, filePath)
    if not ok then
        setTerminal(colors.black, colors.red)
        print(tostring(result))
    elseif result == false then
        setTerminal(colors.black, colors.red)
        print("Program returned an error.")
    end

    setTerminal(colors.black, colors.lightGray)
    print("")
    print("Press any key to return to CCIDE.")
    while true do
        local event = os.pullEventRaw()
        if event == "key" or event == "mouse_click" or event == "terminate" then break end
    end
    heldKeys = {}
    statusMessage = "Program finished"
end

local function newBuffer()
    if not confirmDiscard() then return end
    lines = { "" }
    filePath = nil
    cursorX, cursorY = 1, 1
    scrollX, scrollY = 0, 0
    dirty = false
    undoStack, redoStack = {}, {}
    statusMessage = "New file"
end

local function openFile()
    if not confirmDiscard() then return end
    local entered = prompt("Open file", filePath or "")
    if not entered or entered == "" then
        statusMessage = "Open cancelled"
        return
    end
    local ok, reason = loadFile(entered)
    if not ok then statusMessage = "Open failed: " .. tostring(reason) end
end

local running = true

local function quit()
    if confirmDiscard() then running = false end
end

local function doAction(action)
    if action == "save" then saveFile()
    elseif action == "run" then runCurrent()
    elseif action == "help" then showHelp()
    elseif action == "quit" then quit()
    end
end

local function moveCursor(dx, dy)
    if dy ~= 0 then
        cursorY = math.max(1, math.min(#lines, cursorY + dy))
        cursorX = math.min(cursorX, #lines[cursorY] + 1)
    else
        cursorX = cursorX + dx
        if cursorX < 1 and cursorY > 1 then
            cursorY = cursorY - 1
            cursorX = #lines[cursorY] + 1
        elseif cursorX > #lines[cursorY] + 1 and cursorY < #lines then
            cursorY = cursorY + 1
            cursorX = 1
        end
    end
    clampCursor()
    statusMessage = "Ready"
    ensureCursorVisible()
end

local function handleKey(code)
    local ctrl = ctrlHeld()
    local shift = shiftHeld()
    local bodyHeight = select(1, calculateLayout())

    if ctrl and code == keys.s then saveFile()
    elseif ctrl and code == keys.q then quit()
    elseif ctrl and code == keys.o then openFile()
    elseif ctrl and code == keys.n then newBuffer()
    elseif ctrl and code == keys.z then undo(); ensureCursorVisible()
    elseif ctrl and code == keys.y then redo(); ensureCursorVisible()
    elseif ctrl and code == keys.f then askFind()
    elseif ctrl and code == keys.g then goToLine()
    elseif code == keys.f1 then showHelp()
    elseif code == keys.f3 then findNext()
    elseif code == keys.f5 then runCurrent()
    elseif code == keys.left then moveCursor(-1, 0)
    elseif code == keys.right then moveCursor(1, 0)
    elseif code == keys.up then moveCursor(0, -1)
    elseif code == keys.down then moveCursor(0, 1)
    elseif code == keys.pageUp then moveCursor(0, -bodyHeight)
    elseif code == keys.pageDown then moveCursor(0, bodyHeight)
    elseif code == keys.home then
        if ctrl then cursorY = 1 end
        cursorX = 1
        ensureCursorVisible()
    elseif code == keys["end"] then
        if ctrl then cursorY = #lines end
        cursorX = #lines[cursorY] + 1
        ensureCursorVisible()
    elseif code == keys.enter or code == keys.numpadEnter then newLine()
    elseif code == keys.backspace then backspace()
    elseif code == keys.delete then deleteForward()
    elseif code == keys.tab then indentLine(shift)
    end
end

local function scrollBy(direction)
    local bodyHeight = select(1, calculateLayout())
    local maximum = math.max(0, #lines - bodyHeight)
    scrollY = math.max(0, math.min(maximum, scrollY + direction * SCROLL_STEP))
    statusMessage = "Scrolled"
end

local function clickEditor(x, y)
    local bodyHeight, editorWidth = calculateLayout()
    if y < 2 or y > bodyHeight + 1 then return end

    if x == screenW then
        local maximum = math.max(0, #lines - bodyHeight)
        if maximum > 0 then
            local ratio = (y - 2) / math.max(1, bodyHeight - 1)
            scrollY = math.floor(ratio * maximum + 0.5)
            statusMessage = "Scrolled"
        end
        return
    end

    if x > gutterWidth and x <= gutterWidth + editorWidth then
        cursorY = math.min(#lines, scrollY + y - 1)
        cursorX = math.max(1, math.min(
            #lines[cursorY] + 1,
            scrollX + x - gutterWidth
        ))
        statusMessage = "Ready"
        ensureCursorVisible()
    end
end

if args[1] then
    local ok, reason = loadFile(args[1])
    if not ok then statusMessage = "Open failed: " .. tostring(reason) end
else
    statusMessage = "Ctrl-O Open | Ctrl-N New | F1 Help"
end

ensureCursorVisible()

while running do
    draw()
    local event = { os.pullEventRaw() }
    local name = event[1]

    if name == "char" then
        if not ctrlHeld() then insertText(event[2]) end
    elseif name == "paste" then
        insertText(event[2])
    elseif name == "key" then
        heldKeys[event[2]] = true
        handleKey(event[2])
    elseif name == "key_up" then
        heldKeys[event[2]] = nil
    elseif name == "mouse_scroll" then
        scrollBy(event[2])
    elseif name == "mouse_click" then
        local button, x, y = event[2], event[3], event[4]
        if button == 1 and y == 1 then
            for _, item in ipairs(buttons) do
                if x >= item.x1 and x <= item.x2 then
                    doAction(item.action)
                    break
                end
            end
        elseif button == 1 then
            clickEditor(x, y)
        end
    elseif name == "mouse_drag" and event[2] == 1 then
        clickEditor(event[3], event[4])
    elseif name == "term_resize" then
        ensureCursorVisible()
        statusMessage = "Terminal resized"
    elseif name == "terminate" then
        quit()
    end
end

term.setCursorBlink(false)
setTerminal(colors.black, colors.white)
term.clear()
term.setCursorPos(1, 1)
