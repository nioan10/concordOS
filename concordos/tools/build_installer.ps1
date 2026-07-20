param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$Output = "$PSScriptRoot\..\install_concordos.lua"
)

$files = @(
    @{ Source = 'startup.lua'; Destination = '/startup' },
    @{ Source = 'update.lua'; Destination = '/update' },
    @{ Source = 'apps/rterm.lua'; Destination = '/concordos/apps/rterm.lua' },
    @{ Source = 'apps/master.lua'; Destination = '/concordos/apps/master.lua' },
    @{ Source = 'apps/master_gui.lua'; Destination = '/concordos/apps/master_gui.lua' },
    @{ Source = 'apps/mines.lua'; Destination = '/concordos/apps/mines.lua' },
    @{ Source = 'system/config.lua'; Destination = '/concordos/system/config.lua' },
    @{ Source = 'system/boot.lua'; Destination = '/concordos/system/boot.lua' },
    @{ Source = 'system/desktop.lua'; Destination = '/concordos/system/desktop.lua' },
    @{ Source = 'system/order_service.lua'; Destination = '/concordos/system/order_service.lua' },
    @{ Source = 'system/lib/orders.lua'; Destination = '/concordos/system/lib/orders.lua' },
    @{ Source = 'system/lib/ru.lua'; Destination = '/concordos/system/lib/ru.lua' },
    @{ Source = 'system/lib/ui.lua'; Destination = '/concordos/system/lib/ui.lua' }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('-- ConcordOS offline installer. Run once on a CC:Tweaked computer.')
$lines.Add('local files = {')

foreach ($file in $files) {
    $sourcePath = Join-Path $Root $file.Source
    if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Missing source file: $sourcePath" }
    $content = [System.IO.File]::ReadAllText($sourcePath, [System.Text.Encoding]::UTF8)
    if ($content.Contains(']====]')) { throw "Lua long-string delimiter occurs in $sourcePath" }
    $lines.Add(('  ["{0}"] = [====[{1}]====],' -f $file.Destination, $content.TrimEnd("`r", "`n")))
}

$lines.Add('}')
$lines.Add('')
$lines.Add('local function writeFile(path, content)')
$lines.Add('  local dir = fs.getDir(path)')
$lines.Add('  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end')
$lines.Add('  local file = assert(fs.open(path, "w"), "Cannot write " .. path)')
$lines.Add('  file.write(content)')
$lines.Add('  file.close()')
$lines.Add('end')
$lines.Add('')
$lines.Add('if fs.exists("/startup") and not fs.exists("/startup.before_concordos") then')
$lines.Add('  fs.copy("/startup", "/startup.before_concordos")')
$lines.Add('end')
$lines.Add('for path, content in pairs(files) do writeFile(path, content) end')
$lines.Add('print("ConcordOS installed.")')
$lines.Add('print("Previous startup: /startup.before_concordos (if it existed).")')
$lines.Add('print("Enable the ConcordOS resource pack on the Minecraft client, then run reboot.")')

$text = [string]::Join("`n", $lines) + "`n"
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Output, $text, $encoding)
