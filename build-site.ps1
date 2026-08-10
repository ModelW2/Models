# Сборка галереи: сканирует папку с моделями и скриншотами, делает превью
# и пишет манифест для сайта.
#
#   powershell -ExecutionPolicy Bypass -File C:\WV\build-site.ps1
#
# Запускать после того, как в папку добавлены новые .fbx или .png.
#
# Что делает:
#   Name.fbx + Name.png  ->  карточка модели (клик открывает вьюер)
#   *.png без пары       ->  просто скриншот в галерее
#
# Модели и скриншоты лежат в корне проекта, рядом с index.html.
#
# Исходные PNG весят до 15 МБ — грузить их в галерею нельзя, поэтому рядом
# кладутся сжатые JPEG: thumbs\ для карточек и large\ для просмотра.
# Манифест пишется как .js (а не .json) намеренно: тогда сайт открывается
# и по http, и двойным кликом с диска — fetch к локальному файлу браузер
# запрещает, а <script> отрабатывает.

param(
  [string]$Root = "C:\WV",
  # Модели и скриншоты лежат прямо в корне рядом с index.html.
  [string]$SourceDir = "C:\WV",
  [int]$ThumbWidth = 1000,
  [int]$LargeWidth = 2200,
  [int]$ThumbQuality = 82,
  [int]$LargeQuality = 86
)

Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $SourceDir)) {
  Write-Host "Папка не найдена: $SourceDir" -ForegroundColor Red
  exit 1
}

$thumbDir = Join-Path $Root "thumbs"
$largeDir = Join-Path $Root "large"
foreach ($d in @($thumbDir, $largeDir)) {
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
             Where-Object { $_.MimeType -eq 'image/jpeg' }

function Save-Resized {
  param([string]$SrcPath, [string]$DstPath, [int]$MaxWidth, [int]$Quality)

  $src = [System.Drawing.Image]::FromFile($SrcPath)
  try {
    $scale = [Math]::Min(1.0, $MaxWidth / $src.Width)
    $w = [int][Math]::Round($src.Width * $scale)
    $h = [int][Math]::Round($src.Height * $scale)

    $dst = New-Object System.Drawing.Bitmap($w, $h)
    try {
      $g = [System.Drawing.Graphics]::FromImage($dst)
      try {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($src, 0, 0, $w, $h)
      } finally { $g.Dispose() }

      $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
      $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
        [System.Drawing.Imaging.Encoder]::Quality, [int64]$Quality)
      $dst.Save($DstPath, $jpegCodec, $encParams)
      $encParams.Dispose()
    } finally { $dst.Dispose() }

    return @{ Width = $src.Width; Height = $src.Height; OutWidth = $w; OutHeight = $h }
  } finally { $src.Dispose() }
}

# -Include без -Recurse молча не фильтрует, поэтому отбираем по расширению
$images = Get-ChildItem -LiteralPath $SourceDir -File |
          Where-Object { $_.Extension -match '^\.(png|jpg|jpeg)$' }
$models = Get-ChildItem -LiteralPath $SourceDir -File |
          Where-Object { $_.Extension -match '^\.fbx$' }

# Сопоставление модели и её скриншота: сначала точное совпадение имён, потом
# по общему префиксу — экспортёр вполне может назвать файлы "KuvekinoLite.fbx"
# и "Kuvekino.png".
function Find-Shot {
  param($ModelBase, $Images)
  $exact = $Images | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $ModelBase }
  if ($exact) { return $exact[0] }
  $best = $null; $bestLen = 0
  foreach ($img in $Images) {
    $b = [IO.Path]::GetFileNameWithoutExtension($img.Name)
    if ($ModelBase.StartsWith($b, 'OrdinalIgnoreCase') -or $b.StartsWith($ModelBase, 'OrdinalIgnoreCase')) {
      $len = [Math]::Min($b.Length, $ModelBase.Length)
      if ($len -gt $bestLen) { $best = $img; $bestLen = $len }
    }
  }
  return $best
}

$usedShots = @{}
$modelEntries = @()

foreach ($m in $models) {
  $base = [IO.Path]::GetFileNameWithoutExtension($m.Name)
  $shot = Find-Shot -ModelBase $base -Images $images
  $thumbRel = $null; $largeRel = $null; $dims = $null

  if ($shot) {
    $usedShots[$shot.FullName] = $true
    $thumbName = "$base.jpg"
    $dims = Save-Resized -SrcPath $shot.FullName -DstPath (Join-Path $thumbDir $thumbName) -MaxWidth $ThumbWidth -Quality $ThumbQuality
    Save-Resized -SrcPath $shot.FullName -DstPath (Join-Path $largeDir $thumbName) -MaxWidth $LargeWidth -Quality $LargeQuality | Out-Null
    $thumbRel = "thumbs/$thumbName"
    $largeRel = "large/$thumbName"
    Write-Host ("модель  {0,-18} превью {1}" -f $base, $shot.Name) -ForegroundColor Green
  } else {
    Write-Host ("модель  {0,-18} без скриншота" -f $base) -ForegroundColor DarkYellow
  }

  $modelEntries += [ordered]@{
    name  = $base
    file  = $m.Name
    sizeMB = [math]::Round($m.Length / 1MB, 1)
    thumb = $thumbRel
    large = $largeRel
    width  = if ($dims) { $dims.Width } else { 0 }
    height = if ($dims) { $dims.Height } else { 0 }
  }
}

$shotEntries = @()
foreach ($img in $images) {
  if ($usedShots.ContainsKey($img.FullName)) { continue }
  $base = [IO.Path]::GetFileNameWithoutExtension($img.Name)
  $name = "$base.jpg"
  $dims = Save-Resized -SrcPath $img.FullName -DstPath (Join-Path $thumbDir $name) -MaxWidth $ThumbWidth -Quality $ThumbQuality
  Save-Resized -SrcPath $img.FullName -DstPath (Join-Path $largeDir $name) -MaxWidth $LargeWidth -Quality $LargeQuality | Out-Null
  $shotEntries += [ordered]@{
    name  = $base
    thumb = "thumbs/$name"
    large = "large/$name"
    width = $dims.Width
    height = $dims.Height
  }
  Write-Host ("скриншот {0,-17} {1}x{2}" -f $base, $dims.Width, $dims.Height) -ForegroundColor Cyan
}

# Убираем превью, оставшиеся от прошлых сборок: если исходник переименовали
# или удалили, его картинки иначе так и лежали бы в папке и уехали в репозиторий.
$keep = @{}
foreach ($e in $modelEntries) { if ($e.thumb) { $keep[[IO.Path]::GetFileName($e.thumb)] = $true } }
foreach ($e in $shotEntries)  { $keep[[IO.Path]::GetFileName($e.thumb)] = $true }
foreach ($dir in @($thumbDir, $largeDir)) {
  Get-ChildItem -LiteralPath $dir -File | ForEach-Object {
    if (-not $keep.ContainsKey($_.Name)) {
      Remove-Item -LiteralPath $_.FullName -Force
      Write-Host ("удалено лишнее  {0}" -f $_.Name) -ForegroundColor DarkGray
    }
  }
}

$data = [ordered]@{
  generated = (Get-Date).ToString("yyyy-MM-dd HH:mm")
  models    = $modelEntries
  shots     = $shotEntries
}

$json = $data | ConvertTo-Json -Depth 6
$js = "// Файл создан build-site.ps1 — править вручную нет смысла.`r`nwindow.SITE_DATA = $json;`r`n"
[System.IO.File]::WriteAllText((Join-Path $Root "site-data.js"), $js, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host ("Готово: моделей {0}, отдельных скриншотов {1}" -f $modelEntries.Count, $shotEntries.Count) -ForegroundColor Green
Write-Host "Манифест: $Root\site-data.js"
