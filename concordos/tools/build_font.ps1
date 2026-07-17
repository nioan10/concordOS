param(
    [string]$Source = "$PSScriptRoot\reference\term_font_original.png",
    [string]$Destination = "$PSScriptRoot\..\resourcepack\assets\computercraft\textures\gui\term_font.png"
)

Add-Type -AssemblyName System.Drawing

if (-not ('ConcordVga866' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Drawing.dll' -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class ConcordVga866 {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResourceEx(string path, uint flags, IntPtr reserved);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern bool RemoveFontResourceEx(string path, uint flags, IntPtr reserved);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFont(int height, int width, int escapement, int orientation, int weight,
        uint italic, uint underline, uint strikeOut, uint charset, uint outputPrecision,
        uint clipPrecision, uint quality, uint pitchAndFamily, string face);
    [DllImport("gdi32.dll")]
    static extern IntPtr SelectObject(IntPtr hdc, IntPtr objectHandle);
    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(IntPtr objectHandle);
    [DllImport("gdi32.dll")]
    static extern int SetBkMode(IntPtr hdc, int mode);
    [DllImport("gdi32.dll")]
    static extern uint SetTextColor(IntPtr hdc, uint colorRef);
    [DllImport("gdi32.dll", EntryPoint = "TextOutA")]
    static extern bool TextOutA(IntPtr hdc, int x, int y, byte[] text, int length);

    public static void DrawGlyph(Bitmap bitmap, byte character) {
        using (var graphics = Graphics.FromImage(bitmap)) {
            graphics.Clear(Color.Transparent);
            IntPtr hdc = graphics.GetHdc();
            IntPtr font = IntPtr.Zero;
            try {
                // OEM charset and 6x9 raster size select the vga866 glyphs exactly.
                font = CreateFont(9, 6, 0, 0, 400, 0, 0, 0, 255, 0, 0, 4, 49, "Terminal");
                IntPtr previous = SelectObject(hdc, font);
                SetBkMode(hdc, 1); // TRANSPARENT
                SetTextColor(hdc, 0x00FFFFFF);
                TextOutA(hdc, 0, 0, new byte[] { character }, 1);
                SelectObject(hdc, previous);
            } finally {
                if (font != IntPtr.Zero) DeleteObject(font);
                graphics.ReleaseHdc(hdc);
            }
        }
    }
}
'@
}

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Original CC:Tweaked terminal font not found: $Source"
}
$vgaFont = 'C:\Windows\Fonts\vga866.fon'
if (-not (Test-Path -LiteralPath $vgaFont)) {
    throw "Windows VGA866 font not found: $vgaFont"
}

$destinationDirectory = Split-Path -Parent $Destination
New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
Copy-Item -LiteralPath $Source -Destination $Destination -Force

$loaded = [System.Drawing.Bitmap]::FromFile($Destination)
$bitmap = New-Object System.Drawing.Bitmap $loaded
$loaded.Dispose()

function Set-Glyph([int]$Byte) {
    $column = $Byte % 16
    $row = [math]::Floor($Byte / 16)
    $left = 1 + $column * 8
    $top = 1 + $row * 11
    for ($x = 0; $x -lt 6; $x++) {
        for ($y = 0; $y -lt 9; $y++) { $bitmap.SetPixel($left + $x, $top + $y, [System.Drawing.Color]::Transparent) }
    }
    $glyph = New-Object System.Drawing.Bitmap 6,9
    try {
        [ConcordVga866]::DrawGlyph($glyph, [byte]$Byte)
        for ($x = 0; $x -lt 6; $x++) {
            for ($y = 0; $y -lt 9; $y++) { $bitmap.SetPixel($left + $x, $top + $y, $glyph.GetPixel($x, $y)) }
        }
    }
    finally {
        $glyph.Dispose()
    }
}

try {
    [void][ConcordVga866]::AddFontResourceEx($vgaFont, 0x10, [IntPtr]::Zero)
    for ($byte = 0x80; $byte -le 0xAF; $byte++) { Set-Glyph $byte }
    for ($byte = 0xE0; $byte -le 0xF1; $byte++) { Set-Glyph $byte }
    $temporary = "$Destination.tmp.png"
    $bitmap.Save($temporary, [System.Drawing.Imaging.ImageFormat]::Png)
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}
finally {
    $bitmap.Dispose()
    [void][ConcordVga866]::RemoveFontResourceEx($vgaFont, 0x10, [IntPtr]::Zero)
}
