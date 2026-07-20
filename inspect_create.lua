-- Legacy command kept for users who launch inspect_create.lua directly.
if fs.exists("/concordos/apps/inspect.lua") then
  shell.run("/concordos/apps/inspect.lua")
else
  print("Инспектор теперь входит в ConcordOS. Установи или обнови ОС.")
end
