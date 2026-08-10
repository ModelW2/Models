# Готовит папку для ручной загрузки на GitHub через сайт.
#
#   powershell -ExecutionPolicy Bypass -File C:\WV\make-upload.ps1
#
# Зачем отдельный шаг: веб-загрузчик GitHub не читает .gitignore (утащит
# исходники фото) и плохо переносит папки — кнопка «choose your files»
# каталоги вообще не умеет, остаётся только перетаскивание, которое
# срабатывает не всегда.
#
# Поэтому здесь всё раскладывается ПЛОСКО: ни одной вложенной папки,
# только файлы в один уровень. Такую пачку можно выделить целиком и
# перетащить — терять нечего.
#
#   thumbs\Butovo.jpg  ->  t_Butovo.jpg   (превью карточки)
#   large\Butovo.jpg   ->  f_Butovo.jpg   (полный экран)
#
# Пути внутри site-data.js переписываются под новые имена.

param(
  [string]$Root = "C:\WV",
  [string]$Dest = "C:\WV-upload"
)

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
New-Item -ItemType Directory -Path $Dest | Out-Null

# ---- разметка, скрипты, служебное ----
$plain = @('index.html', 'viewer.html', '.nojekyll', '.gitignore',
           'README.md', 'build-site.ps1', 'make-upload.ps1', 'serve.ps1')
foreach ($f in $plain) {
  $src = Join-Path $Root $f
  if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $Dest }
}

# ---- модели ----
$models = Get-ChildItem -LiteralPath $Root -File | Where-Object { $_.Extension -match '^\.fbx$' }
foreach ($m in $models) { Copy-Item -LiteralPath $m.FullName -Destination $Dest }

# ---- превью: из папок в корень с префиксами ----
$map = @{}
foreach ($pair in @(@('thumbs', 't_'), @('large', 'f_'))) {
  $dir = Join-Path $Root $pair[0]
  if (-not (Test-Path -LiteralPath $dir)) { continue }
  foreach ($img in Get-ChildItem -LiteralPath $dir -File) {
    $flat = $pair[1] + $img.Name
    Copy-Item -LiteralPath $img.FullName -Destination (Join-Path $Dest $flat)
    $map["$($pair[0])/$($img.Name)"] = $flat
  }
}

# ---- манифест с переписанными путями ----
$js = [System.IO.File]::ReadAllText((Join-Path $Root 'site-data.js'),
      [System.Text.UTF8Encoding]::new($false))
foreach ($k in $map.Keys) { $js = $js.Replace("`"$k`"", "`"$($map[$k])`"") }
[System.IO.File]::WriteAllText((Join-Path $Dest 'site-data.js'), $js,
      (New-Object System.Text.UTF8Encoding($false)))

$left = [regex]::Matches($js, '"(?:thumbs|large)/[^"]+"')
if ($left.Count) {
  Write-Host "Внимание: в манифесте остались ссылки на папки:" -ForegroundColor Red
  $left | ForEach-Object { Write-Host "   $($_.Value)" -ForegroundColor Red }
}

$files = Get-ChildItem -LiteralPath $Dest -File -Force
Write-Host ""
Write-Host ("Готово: {0} файлов, {1:N1} МБ, ни одной вложенной папки" -f `
  $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB)) -ForegroundColor Green
Write-Host "Папка: $Dest"
Write-Host ""
Write-Host "Модели крупнее 25 МБ веб-загрузчик не примет — проверьте:" -ForegroundColor DarkGray
$files | Where-Object { $_.Length -gt 20MB } | ForEach-Object {
  $mb = [math]::Round($_.Length / 1MB, 1)
  $color = if ($_.Length -gt 25MB) { 'Red' } else { 'Yellow' }
  Write-Host ("   {0,-24} {1} МБ" -f $_.Name, $mb) -ForegroundColor $color
}
