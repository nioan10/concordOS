local ru = dofile("/concordos/system/lib/ru.lua")

local ui = { ru = ru }

function ui.size(target)
  return (target or term).getSize()
end

function ui.clear(target, background)
  local output = target or term
  if background then output.setBackgroundColor(background) end
  output.clear()
  output.setCursorPos(1, 1)
end

function ui.text(target, x, y, value, foreground, background, width)
  local output = target or term
  local screenWidth, screenHeight = output.getSize()
  x, y = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
  if y < 1 or y > screenHeight or x > screenWidth then return end

  local text = tostring(value or "")
  if x < 1 then
    text = ru.sub(text, 2 - x)
    x = 1
  end
  local available = screenWidth - x + 1
  local drawWidth = width and math.min(available, math.max(0, math.floor(width))) or available
  if drawWidth <= 0 then return end

  if foreground then output.setTextColor(foreground) end
  if background then output.setBackgroundColor(background) end
  output.setCursorPos(x, y)
  ru.write(output, width and ru.padRight(text, drawWidth) or ru.fit(text, drawWidth, ""))
end

function ui.line(target, x, y, width, value, foreground, background)
  ui.text(target, x, y, ru.fit(value, width, ""), foreground, background, width)
end

function ui.fill(target, x, y, width, height, background)
  local output = target or term
  local screenWidth, screenHeight = output.getSize()
  x, y = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
  width, height = math.floor(tonumber(width) or 0), math.floor(tonumber(height) or 0)
  if x < 1 then width, x = width + x - 1, 1 end
  if y < 1 then height, y = height + y - 1, 1 end
  width = math.min(width, screenWidth - x + 1)
  height = math.min(height, screenHeight - y + 1)
  if width <= 0 or height <= 0 then return end
  output.setBackgroundColor(background)
  local blank = string.rep(" ", width)
  for row = y, y + height - 1 do
    output.setCursorPos(x, row)
    output.write(blank)
  end
end

function ui.button(target, x, y, width, height, label, foreground, background, active)
  local output = target or term
  -- Grey used to be the default button background. It looked disabled and
  -- was inconsistent with the blue ConcordOS controls. Keep grey for panels,
  -- but make every interactive button visibly actionable.
  local normal = background or colors.blue
  if normal == colors.gray or normal == colors.lightGray then normal = colors.blue end
  local bg = active and (normal == colors.blue or normal == colors.black) and colors.lightBlue or normal
  ui.fill(output, x, y, width, height, bg)
  local labelY = y + math.floor((height - 1) / 2)
  ui.text(output, x, labelY, ru.center(label, width), foreground, bg, width)
end

function ui.inside(x, y, left, top, width, height)
  return x >= left and x < left + width and y >= top and y < top + height
end

return ui
