# SerwisDiag - generuje assets\app.ico (niebieska plakietka z linia pulsu). Plik celowo wylacznie ASCII.
param([string]$OutFile)
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $root 'assets\app.ico' }
$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Add-Type -AssemblyName System.Drawing

function New-IconFrame {
    param([int]$Size)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $m = [single]($Size * 0.04)
    $r = [single]($Size * 0.22)
    $w = [single]($Size - 2 * $m)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($m, $m, $r, $r, 180, 90)
    $path.AddArc($m + $w - $r, $m, $r, $r, 270, 90)
    $path.AddArc($m + $w - $r, $m + $w - $r, $r, $r, 0, 90)
    $path.AddArc($m, $m + $w - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $p0 = New-Object System.Drawing.PointF(0, 0)
    $p1 = New-Object System.Drawing.PointF([single]$Size, [single]$Size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($p0, $p1, [System.Drawing.Color]::FromArgb(255, 10, 58, 102), [System.Drawing.Color]::FromArgb(255, 15, 108, 189))
    $g.FillPath($brush, $path)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single]([math]::Max(1.5, $Size * 0.075)))
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $xs = 0.16, 0.34, 0.44, 0.56, 0.66, 0.74, 0.84
    $ys = 0.52, 0.52, 0.26, 0.76, 0.44, 0.52, 0.52
    $pts = New-Object 'System.Drawing.PointF[]' 7
    for ($i = 0; $i -lt 7; $i++) { $pts[$i] = New-Object System.Drawing.PointF([single]($xs[$i] * $Size), [single]($ys[$i] * $Size)) }
    $g.DrawLines($pen, $pts)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return , $ms.ToArray()
}

$sizes = 16, 24, 32, 48, 64, 128, 256
$frames = @()
foreach ($s in $sizes) { $frames += , (New-IconFrame -Size $s) }

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$frames[$i].Length); $bw.Write([uint32]$offset)
    $offset += $frames[$i].Length
}
foreach ($f in $frames) { $bw.Write([byte[]]$f) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($OutFile, $ms.ToArray())
Write-Host ("Zapisano {0} ({1} KB)" -f $OutFile, [math]::Round((Get-Item $OutFile).Length / 1KB, 1))
