-- Background service for persistent industrial requests.
local orders = dofile("/concordos/system/lib/orders.lua")

while true do
  pcall(orders.tick)
  sleep(15)
end
