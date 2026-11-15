# Simple local preview server (PowerShell only, no install needed).
# Usage: powershell -ExecutionPolicy Bypass -File serve.ps1   ->  http://localhost:47831/
param([int]$Port = 47831)

$root = Join-Path $PSScriptRoot "docs"   # the published site lives in docs/
$types = @{
  ".html" = "text/html; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".js"   = "text/javascript; charset=utf-8"
  ".svg"  = "image/svg+xml"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".webp" = "image/webp"
  ".ico"  = "image/x-icon"
  ".json" = "application/json; charset=utf-8"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $root at http://localhost:$Port/"

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart("/")
      if ($rel -eq "" -or $rel.EndsWith("/")) { $rel = $rel + "index.html" }
      $path = [IO.Path]::GetFullPath((Join-Path $root $rel))
      if ($path.StartsWith($root) -and (Test-Path $path -PathType Leaf)) {
        $bytes = [IO.File]::ReadAllBytes($path)
        $type = $types[[IO.Path]::GetExtension($path).ToLower()]
        if (-not $type) { $type = "application/octet-stream" }
        $ctx.Response.ContentType = $type
        $ctx.Response.Headers.Add("Cache-Control", "no-store")
        $ctx.Response.ContentLength64 = $bytes.Length
        if ($ctx.Request.HttpMethod -ne "HEAD") {
          $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
      } else {
        $ctx.Response.StatusCode = 404
      }
      $ctx.Response.Close()
    } catch {
      # A dropped connection must not stop the server.
      try { $ctx.Response.Abort() } catch {}
    }
  }
} finally {
  $listener.Stop()
}
