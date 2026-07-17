return {
  name = "ConcordOS",
  country = "Конкордат Фессалоник",
  version = "0.1.0",
  apps = {
    { id = "terminal", title = "Терминал", subtitle = "Русская командная строка", path = "/concordos/apps/rterm.lua", color = colors.black },
    { id = "master", title = "Мастер промзоны", subtitle = "Графические заявки и склад", path = "/concordos/apps/master_gui.lua", color = colors.red },
    { id = "ide", title = "Редактор", subtitle = "CCIDE: Lua и программы", path = "/ccide.lua", color = colors.blue },
    { id = "plan", title = "План производства", subtitle = "Очередь и диспетчеризация", path = "/plan.lua", color = colors.green },
    { id = "checklist", title = "Чеклист материалов", subtitle = "Create Material Checklist", path = "/checklist.lua", color = colors.orange },
    { id = "inspect", title = "Инспектор Create", subtitle = "Периферия и методы", path = "/inspect_create.lua", color = colors.purple },
  },
}
