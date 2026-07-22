-- ConcordOS: UTF-8 logic and CP866 terminal output for CC:Tweaked.
-- Requires the accompanying resource pack that replaces term_font.png.

local ru = {}

local utf = utf8

local replacements = {
  [0x2116] = "No", -- №
  [0x00AB] = '"', [0x00BB] = '"',
  [0x00B7] = ".", -- ·
  [0x00D7] = "x", -- ×
  [0x2013] = "-", [0x2014] = "-", [0x2212] = "-",
  [0x2026] = "...",
  [0x2190] = "<", [0x2192] = ">", -- arrows
  [0x00A0] = " ",
}

local function encodeCodepoint(code)
  if code < 0x80 then return string.char(code) end
  if code >= 0x0410 and code <= 0x042F then return string.char(0x80 + code - 0x0410) end
  if code >= 0x0430 and code <= 0x043F then return string.char(0xA0 + code - 0x0430) end
  if code >= 0x0440 and code <= 0x044F then return string.char(0xE0 + code - 0x0440) end
  if code == 0x0401 then return string.char(0xF0) end -- Ё
  if code == 0x0451 then return string.char(0xF1) end -- ё
  return replacements[code] or "?"
end

function ru.encode(value)
  local text = tostring(value or "")
  if not utf or not utf.codes then return text end

  local ok, result = pcall(function()
    local out = {}
    for _, code in utf.codes(text) do out[#out + 1] = encodeCodepoint(code) end
    return table.concat(out)
  end)
  return ok and result or text
end

function ru.len(value)
  local text = tostring(value or "")
  if utf and utf.len then return utf.len(text) or #text end
  return #text
end

function ru.sub(value, first, last)
  local text = tostring(value or "")
  local length = ru.len(text)
  first = first or 1
  last = last or length
  if first < 0 then first = length + first + 1 end
  if last < 0 then last = length + last + 1 end
  if first < 1 then first = 1 end
  if last < first then return "" end
  if not utf or not utf.offset then return text:sub(first, last) end
  local beginAt = utf.offset(text, first)
  if not beginAt then return "" end
  local afterAt = utf.offset(text, last + 1)
  return text:sub(beginAt, afterAt and afterAt - 1 or #text)
end

function ru.lower(value)
  local text = tostring(value or "")
  if not utf or not utf.codes then return text:lower() end
  local out = {}
  local ok = pcall(function()
    for _, code in utf.codes(text) do
      if code >= 0x41 and code <= 0x5A then code = code + 0x20 end
      if code >= 0x0410 and code <= 0x042F then code = code + 0x20 end
      if code == 0x0401 then code = 0x0451 end
      out[#out + 1] = utf.char(code)
    end
  end)
  return ok and table.concat(out) or text:lower()
end

function ru.upper(value)
  local text = tostring(value or "")
  if not utf or not utf.codes then return text:upper() end
  local out = {}
  local ok = pcall(function()
    for _, code in utf.codes(text) do
      if code >= 0x61 and code <= 0x7A then code = code - 0x20 end
      if code >= 0x0430 and code <= 0x044F then code = code - 0x20 end
      if code == 0x0451 then code = 0x0401 end
      out[#out + 1] = utf.char(code)
    end
  end)
  return ok and table.concat(out) or text:upper()
end

function ru.equalsIgnoreCase(a, b)
  return ru.lower(a) == ru.lower(b)
end

function ru.fit(value, width, suffix)
  local text = tostring(value or "")
  width = math.max(0, width or 0)
  if ru.len(text) <= width then return text end
  suffix = suffix == nil and "..." or suffix
  local room = width - ru.len(suffix)
  if room <= 0 then return ru.sub(suffix, 1, width) end
  return ru.sub(text, 1, room) .. suffix
end

function ru.padRight(value, width)
  local text = ru.fit(value, width, "")
  return text .. string.rep(" ", math.max(0, width - ru.len(text)))
end

function ru.center(value, width)
  local text = ru.fit(value, width, "")
  local left = math.max(0, math.floor((width - ru.len(text)) / 2))
  return string.rep(" ", left) .. text
end

function ru.write(target, value)
  (target or term).write(ru.encode(value))
end

function ru.blit(target, value, foreground, background)
  (target or term).blit(ru.encode(value), foreground, background)
end

function ru.print(target, value)
  local output = target or term
  ru.write(output, value)
  local _, y = output.getCursorPos()
  local _, height = output.getSize()
  if y >= height then
    output.scroll(1)
    output.setCursorPos(1, height)
  else
    output.setCursorPos(1, y + 1)
  end
end

return ru
