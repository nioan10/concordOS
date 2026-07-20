-- Public ConcordOS update manifest. Served directly from the main branch.
return {
  version = "0.3.1",
  files = {
    { source = "startup.lua", target = "/startup" },
    { source = "update.lua", target = "/update" },
    { source = "apps/rterm.lua", target = "/concordos/apps/rterm.lua" },
    { source = "apps/master.lua", target = "/concordos/apps/master.lua" },
    { source = "apps/master_gui.lua", target = "/concordos/apps/master_gui.lua" },
    { source = "system/config.lua", target = "/concordos/system/config.lua" },
    { source = "system/boot.lua", target = "/concordos/system/boot.lua" },
    { source = "system/desktop.lua", target = "/concordos/system/desktop.lua" },
    { source = "system/order_service.lua", target = "/concordos/system/order_service.lua" },
    { source = "system/lib/orders.lua", target = "/concordos/system/lib/orders.lua" },
    { source = "system/lib/ru.lua", target = "/concordos/system/lib/ru.lua" },
    { source = "system/lib/ui.lua", target = "/concordos/system/lib/ui.lua" },
  },
}
