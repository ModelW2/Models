# Мини статический веб-сервер на чистом PowerShell (без Node.js/Python).
# Нужен, чтобы вьюер открывался по http:// и мог сам подгружать модель по URL.
#
#   Запуск:  powershell -ExecutionPolicy Bypass -File C:\WV\serve.ps1
#   Открыть: http://localhost:8080/            (стартовая сцена)
#            http://localhost:8080/?model=models/2.fbx
#
# /models/... отображается на папку с моделями (по умолчанию D:\P\GLB).

param(
  [int]$Port = 8080,
  [string]$Root = "C:\WV",
  [string]$ModelsDir = "D:\P\GLB",
  # Отладочное: разрешить странице класть картинки в C:\WV\_shots через
  # POST /save?name=... По умолчанию сервер работает только на чтение.
  [switch]$AllowSave
)

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".js"   = "text/javascript; charset=utf-8"
  ".mjs"  = "text/javascript; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".md"   = "text/markdown; charset=utf-8"
  ".fbx"  = "application/octet-stream"
  ".glb"  = "model/gltf-binary"
  ".gltf" = "model/gltf+json"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".webp" = "image/webp"
  ".tga"  = "image/x-tga"
  ".hdr"  = "image/vnd.radiance"
  ".exr"  = "image/x-exr"
  ".svg"  = "image/svg+xml"
  ".ico"  = "image/x-icon"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try {
  $listener.Start()
} catch {
  Write-Host "Не удалось занять порт $Port : $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

Write-Host "Сервер запущен:  http://localhost:$Port/" -ForegroundColor Green
Write-Host "  корень:  $Root"
Write-Host "  модели:  /models/  ->  $ModelsDir"
Write-Host "Остановить: Ctrl+C"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response

  try {
    $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }

    # POST /save?name=shot.png — сохранить картинку из браузера в _shots\
    # (используется кнопкой «Скриншот» как запасной путь и при отладке)
    if ($AllowSave -and $req.HttpMethod -eq "POST" -and $rel -eq "save") {
      $name = $req.QueryString["name"]
      if (-not $name) { $name = "shot.png" }
      $name = [System.IO.Path]::GetFileName($name)
      $shotDir = Join-Path $Root "_shots"
      if (-not (Test-Path -LiteralPath $shotDir)) { New-Item -ItemType Directory -Path $shotDir | Out-Null }
      $ms = New-Object System.IO.MemoryStream
      $req.InputStream.CopyTo($ms)
      [System.IO.File]::WriteAllBytes((Join-Path $shotDir $name), $ms.ToArray())
      $res.StatusCode = 200
      $ok = [System.Text.Encoding]::UTF8.GetBytes("saved: $name")
      $res.OutputStream.Write($ok, 0, $ok.Length)
      Write-Host ("SAVE {0} ({1:N0} B)" -f $name, $ms.Length) -ForegroundColor Cyan
      $res.Close()
      continue
    }

    if ($rel -like "models/*") {
      $path = Join-Path $ModelsDir ($rel.Substring(7))
      $baseDir = $ModelsDir
    } else {
      $path = Join-Path $Root $rel
      $baseDir = $Root
    }

    # не выпускаем запросы за пределы разрешённых папок (../ и т.п.)
    $full = [System.IO.Path]::GetFullPath($path)
    $baseFull = [System.IO.Path]::GetFullPath($baseDir)
    if (-not $full.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      $res.StatusCode = 403
      $res.Close()
      continue
    }

    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $ct = $mime[$ext]
      if (-not $ct) { $ct = "application/octet-stream" }
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $res.StatusCode = 200
      $res.ContentType = $ct
      $res.ContentLength64 = $bytes.Length
      $res.Headers.Add("Cache-Control", "no-cache")
      if ($req.HttpMethod -ne "HEAD") { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
      Write-Host ("200  {0}  ({1:N0} B)" -f $rel, $bytes.Length)
    } else {
      $res.StatusCode = 404
      $msg = [System.Text.Encoding]::UTF8.GetBytes("404: $rel")
      $res.ContentType = "text/plain; charset=utf-8"
      $res.OutputStream.Write($msg, 0, $msg.Length)
      Write-Host "404  $rel" -ForegroundColor DarkYellow
    }
  } catch {
    try { $res.StatusCode = 500 } catch {}
    Write-Host "500  $($_.Exception.Message)" -ForegroundColor Red
  } finally {
    try { $res.Close() } catch {}
  }
}
