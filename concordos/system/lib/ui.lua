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
  if foreground then output.setTextColor(foreground) end
  if background then output.setBackgroundColor(background) end
  output.setCursorPos(x, y)
  ru.write(output, width and ru.padRight(value, width) or value)
end

function ui.line(target, x, y, width, value, foreground, background)
  ui.text(target, x, y, ru.fit(value, width, ""), foreground, background, width)
end

function ui.fill(target, x, y, width, height, background)
  local output = target or term
  output.setBackgroundColor(background)
  local blank = string.rep(" ", math.max(0, width))
  for row = y, y + height - 1 do
    output.setCursorPos(x, row)
    output.write(blank)
  end
end

function ui.button(target, x, y, width, height, label, foreground, background, active)
  local output = target or term
  local bg = active and colors.lightBlue or background
  ui.fill(output, x, y, width, height, bg)
  local labelY = y + math.floor((height - 1) / 2)
  ui.text(output, x, labelY, ru.center(label, width), foreground, bg, width)
end

function ui.inside(x, y, left, top, width, height)
  return x >= left and x < left + width and y >= top and y < top + height
end

return ui
