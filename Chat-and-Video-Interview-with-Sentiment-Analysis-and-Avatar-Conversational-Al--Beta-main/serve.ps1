$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:3000/')
$listener.Start()
Write-Host "TalbotIQ server running at http://localhost:3000" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
$filePath = 'c:\Users\thoshith.a\Downloads\Virtual\talbotiq-tavus.html'
while ($true) {
    $ctx = $listener.GetContext()
    $content = [System.IO.File]::ReadAllBytes($filePath)
    $ctx.Response.ContentType = 'text/html; charset=utf-8'
    $ctx.Response.ContentLength64 = $content.Length
    $ctx.Response.OutputStream.Write($content, 0, $content.Length)
    $ctx.Response.OutputStream.Close()
}
