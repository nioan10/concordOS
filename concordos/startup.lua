-- Copy this file to /startup on the CC:Tweaked computer.
local boot = "/concordos/system/boot.lua"

term.setCursorBlink(false)
if not fs.exists(boot) then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1, 1)
  print("ConcordOS is not installed.")
  print("Expected: " .. boot)
  print("Run the installer or use the normal shell.")
  return
end

local ok, err = pcall(function() shell.run(boot) end)
if not ok then
  term.setTextColor(colors.red)
  print("ConcordOS startup error: " .. tostring(err))
end
