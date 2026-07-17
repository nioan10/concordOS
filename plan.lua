-- plan.lua
-- CC:Tweaked + Create 6
-- Reads a Create Material Checklist and compares it with Stock Ticker contents.
-- This is a SAFE dry-run: it does not send any orders.

local clipboard = peripheral.find("create:clipboard")
local ticker = peripheral.find("Create_StockTicker")

if not clipboard then
    error("Create clipboard not found", 0)
end

if not ticker then
    error("Create Stock Ticker not found", 0)
end

local function callFirst(object, calls)
    local lastError = nil

    for _, call in ipairs(calls) do
        local ok, result = pcall(call, object)
        if ok then
            return result
        end
        lastError = result
    end

    error(tostring(lastError), 0)
end

local function itemName(entry, fallback)
    if type(entry) ~= "table" then
        return nil
    end

    if type(entry.name) == "string" then
        return entry.name
    end
    if type(entry.id) == "string" then
        return entry.id
    end
    if type(entry.item) == "string" then
        return entry.item
    end
    if type(entry.item) == "table" then
        return entry.item.name or entry.item.id
    end
    if type(fallback) == "string" and fallback:find(":") then
        return fallback
    end

    return nil
end

local function itemCount(entry)
    if type(entry) == "number" then
        return entry
    end
    if type(entry) ~= "table" then
        return 0
    end

    return tonumber(
        entry.count
        or entry.amount
        or entry.quantity
        or entry.total
        or entry.value
    ) or 0
end

local function aggregate(raw)
    local result = {}

    if type(raw) ~= "table" then
        return result
    end

    for key, entry in pairs(raw) do
        local name = itemName(entry, key)
        local count = itemCount(entry)

        if name and count > 0 then
            result[name] = (result[name] or 0) + count
        end
    end

    return result
end

local checklistRaw = callFirst(clipboard, {
    function(p) return p.getMissingItems() end
})

local stockRaw = callFirst(ticker, {
    function(p) return p.stock() end,
    function(p) return p.stock(false) end,
    function(p) return p.list() end
})

local required = aggregate(checklistRaw)
local available = aggregate(stockRaw)

if next(required) == nil then
    print("No missing items found.")
    print("")
    print("Raw clipboard data:")
    textutils.pagedPrint(textutils.serialize(checklistRaw))
    return
end

local names = {}
for name in pairs(required) do
    table.insert(names, name)
end
table.sort(names)

local lines = {
    "=== CREATE MATERIAL PLAN ===",
    "This is a dry run. No orders are sent.",
    ""
}

local totalRequired = 0
local totalAvailable = 0
local totalMissing = 0

for _, name in ipairs(names) do
    local need = required[name] or 0
    local stock = available[name] or 0
    local missing = math.max(need - stock, 0)

    totalRequired = totalRequired + need
    totalAvailable = totalAvailable + math.min(stock, need)
    totalMissing = totalMissing + missing

    table.insert(lines, name)
    table.insert(lines, string.format(
        "  need:%d  stock:%d  missing:%d",
        need,
        stock,
        missing
    ))
end

table.insert(lines, "")
table.insert(lines, "Required total: " .. totalRequired)
table.insert(lines, "Covered by stock: " .. totalAvailable)
table.insert(lines, "Still missing: " .. totalMissing)

textutils.pagedPrint(table.concat(lines, "\n"))
