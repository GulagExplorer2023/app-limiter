param(
    [string]$Source = (Join-Path $PSScriptRoot 'app_limiter_source.png'),
    [string]$Destination = (Join-Path $PSScriptRoot 'AppLimiter.ico')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$sourceImage = [Drawing.Image]::FromFile($Source)
try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'The icon source must be square.'
    }
    $frames = [Collections.Generic.List[byte[]]]::new()
    foreach ($size in $sizes) {
        $bitmap = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.DrawImage($sourceImage, 0, 0, $size, $size)
            } finally {
                $graphics.Dispose()
            }
            $stream = [IO.MemoryStream]::new()
            try {
                # Lazarus reads classic DIB icon frames. PNG-compressed ICO frames
                # can make TIcon raise "Bitmap with unknown compression" at startup.
                $dib = [IO.BinaryWriter]::new($stream)
                $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
                $dib.Write([uint32]40)               # BITMAPINFOHEADER size
                $dib.Write([int]$size)
                $dib.Write([int]($size * 2))          # color image plus AND mask
                $dib.Write([uint16]1)
                $dib.Write([uint16]32)
                $dib.Write([uint32]0)                # BI_RGB
                $dib.Write([uint32]0)
                $dib.Write([int]0)
                $dib.Write([int]0)
                $dib.Write([uint32]0)
                $dib.Write([uint32]0)
                for ($y = $size - 1; $y -ge 0; $y--) {
                    for ($x = 0; $x -lt $size; $x++) {
                        $pixel = $bitmap.GetPixel($x, $y)
                        $dib.Write([byte]$pixel.B)
                        $dib.Write([byte]$pixel.G)
                        $dib.Write([byte]$pixel.R)
                        $dib.Write([byte]$pixel.A)
                    }
                }
                $dib.Write([byte[]]::new($maskStride * $size))
                $frames.Add($stream.ToArray())
            } finally {
                $stream.Dispose()
            }
        } finally {
            $bitmap.Dispose()
        }
    }
    $file = [IO.File]::Open($Destination, [IO.FileMode]::Create)
    try {
        $writer = [IO.BinaryWriter]::new($file)
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write($frame) }
    } finally {
        $file.Dispose()
    }
} finally {
    $sourceImage.Dispose()
}
