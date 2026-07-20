-- ConcordOS power-station telemetry node.
-- Place this on the computer next to a create_target connected to a Stressometer.
local CHANNEL = 38172
local PROTOCOL = "concordos.power.v1"

local function wirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    local device = peripheral.wrap(name)
    if device and type(device.isWireless) == "function" then
      local ok, wireless = pcall(device.isWireless)
      if ok and wireless then return device, name end
    end
  end
end

local target = peripheral.find("create_target")
if not target then error("create_target not found", 0) end

local modem, modemName = wirelessModem()
if not modem then error("wireless modem not found", 0) end

pcall(target.resize, 32, 8)
term.clear()
term.setCursorPos(1, 1)
print("ConcordOS power node")
print("Target: create_target")
print("Modem: " .. modemName)
print("Channel: " .. CHANNEL)
print("Broadcasting once per second.")

while true do
  local ok, lines = pcall(target.dump)
  local message = {
    protocol = PROTOCOL,
    node = os.getComputerID(),
    lines = ok and lines or {},
  }
  if not ok then message.error = tostring(lines) end
  modem.transmit(CHANNEL, CHANNEL, message)
  sleep(1)
end
