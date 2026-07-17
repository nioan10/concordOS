local lines = {}
local names = peripheral.getNames()

if #names == 0 then
    print("Подключённых устройств нет.")
    return
end

table.insert(lines, "=== ПЕРИФЕРИЯ CC:TWEAKED ===")
table.insert(lines, "Найдено устройств: " .. #names)
table.insert(lines, "")

for _, name in ipairs(names) do
    table.insert(lines, "--------------------------------")
    table.insert(lines, "Имя: " .. name)

    local types = { peripheral.getType(name) }
    table.insert(lines, "Типы: " .. table.concat(types, ", "))

    local methods = peripheral.getMethods(name) or {}
    table.sort(methods)

    table.insert(lines, "Методы:")

    if #methods == 0 then
        table.insert(lines, "  <нет методов>")
    else
        for _, method in ipairs(methods) do
            table.insert(lines, "  " .. method)
        end
    end
end

local _, cursorY = term.getCursorPos()

textutils.pagedPrint(
    table.concat(lines, "\n"),
    cursorY - 2
)