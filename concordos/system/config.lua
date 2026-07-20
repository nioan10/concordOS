return {
  name = "ConcordOS",
  country = "Конкордат Фессалоник",
  version = "0.3.3",
  mainApps = {
    { id = "master", title = "Мастер промзоны", subtitle = "Заявки, склад и сеть Create", path = "/concordos/apps/master_gui.lua", color = colors.red, featured = true },
    { id = "terminal", title = "Терминал", subtitle = "Русская командная строка", path = "/concordos/apps/rterm.lua", color = colors.black },
    { id = "ide", title = "Редактор", subtitle = "CCIDE: Lua и программы", path = "/ccide.lua", color = colors.blue },
    { id = "tools", title = "Инструменты", subtitle = "План, чеклист и диагностика", kind = "folder", color = colors.purple },
  },
  tools = {
    { id = "update", title = "Обновления", subtitle = "Проверить ConcordOS", path = "/update", color = colors.lightBlue },
    { id = "plan", title = "План производства", subtitle = "Очередь и диспетчеризация", path = "/plan.lua", color = colors.green },
    { id = "checklist", title = "Чеклист материалов", subtitle = "Create Material Checklist", path = "/checklist.lua", color = colors.orange },
    { id = "inspect", title = "Инспектор Create", subtitle = "Периферия и методы", path = "/inspect_create.lua", color = colors.purple },
  },
}
