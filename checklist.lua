-- checklist.lua
-- Первая программа для CC:Tweaked + CC Create: Material Checklist Peripheral.
-- Читает размещённый планшет Create с Material Checklist
-- и выводит недостающие материалы.

local clipboard = peripheral.find("create:clipboard")

if not clipboard then
    print("Планшет Create не найден.")
    print("Проверь, что он размещён в мире")
    print("и подключён к компьютеру через проводной модем.")
    print("")
    print("Подключённые периферийные устройства:")

    local names = peripheral.getNames()

    if #names == 0 then
        print("  Нет подключённых устройств.")
    else
        for _, name in ipairs(names) do
            local types = { peripheral.getType(name) }
            print("  " .. name .. " -> " .. table.concat(types, ", "))
        end
    end

    return
end

local ok, items = pcall(clipboard.getMissingItems)

if not ok then
    print("Не удалось прочитать Material Checklist:")
    print(tostring(items))
    return
end

if type(items) ~= "table" then
    print("Мод вернул неожиданный тип данных: " .. type(items))
    return
end

if #items == 0 then
    print("Список пуст.")
    print("В планшете нет недостающих материалов")
    print("или в нём не записан Material Checklist.")
    return
end

table.sort(items, function(a, b)
    return (a.name or "") < (b.name or "")
end)

print("=== MATERIAL CHECKLIST ===")
print("Позиций: " .. #items)
print("")

local total = 0

for index, item in ipairs(items) do
    local name = item.name or "<неизвестный предмет>"
    local count = tonumber(item.count) or 0

    total = total + count
    print(string.format("%d. %s x%d", index, name, count))
end

print("")
print("Всего блоков и предметов: " .. total)
