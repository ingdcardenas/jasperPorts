# import-reporte.ps1 - Importa (descarga) un reportUnit y su .jrxml principal del servidor al disco local (equivale a import-reporte.sh).
#   1) GET /rest_v2/resources<uri>  (Accept application/repository.reportUnit+json)
#   2) localiza jrxml.jrxmlFileReference.uri y descarga su contenido
# Salida en <dir>/<uri-saneada>/ : reportUnit.json, jrxml.meta.json (si disponible),
# jrxml.uri y <nombre>.jrxml. Default dir: .\reportes
#
# Uso: .\import-reporte.ps1 <uri-reportUnit> [-d <directorio-destino>]
# Codigos: 0 OK | 2 uso | 10 HTTP | 11 sin sesion | 12 no existe | 13 sesion
#          expirada | 15 XML mal formado | 20 inesperado
# Imprime por stdout la ruta del .jrxml descargado.
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force -DisableNameChecking
Initialize-Jasper

$uri = ""; $destino = $Jasper.ReportesDir
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "-d" { $i++; if ($i -lt $args.Count) { $destino = $args[$i] } else { $destino = "" } }
        { $_ -eq "-h" -or $_ -eq "--help" } { Get-Content -LiteralPath $PSCommandPath -TotalCount 12 | Select-Object -Skip 1; exit 0 }
        default { $uri = $args[$i] }
    }
}
if (-not $uri -or -not $destino) { [Console]::Error.WriteLine("Uso: .\import-reporte.ps1 <uri-reportUnit> [-d <dir>]"); exit $JasperErr.Usage }
$uri = ConvertTo-JasperUri $uri

$rc = Assert-JasperSession; if ($rc -ne 0) { exit $rc }

$rel = ConvertTo-JasperSafePath $uri
if (-not $rel) { Write-JasperErr "URI invalida: $uri"; exit $JasperErr.Usage }
$out = "$destino/$rel"
try { New-Item -ItemType Directory -Path $out -Force -ErrorAction Stop | Out-Null } catch { exit $JasperErr.Unexpected }

$rc = Get-JasperReportUnit $uri "$out/reportUnit.json"
if ($rc -ne 0) { exit $rc }

$juri = Get-JasperJrxmlUri "$out/reportUnit.json"
if (-not $juri) {
    Write-JasperErr "El descriptor no trae jrxmlFileReference.uri (jrxml inline?). Ver $out/reportUnit.json"
    exit $JasperErr.Http
}
Write-JasperLog "jrxml principal: $juri"
$jenc = ConvertTo-JasperEncodedUri $juri

# Metadatos del recurso file (label/description/type)
$m = Invoke-JasperRequest -Path "/rest_v2/resources$jenc" -Accept "application/repository.file+json" -TimeoutSec 60
if (Test-JasperSessionExpired $m.Status) { exit $JasperErr.SessionExpired }
if ($m.Status -ne 200) {
    Write-JasperLog "Metadatos del jrxml: HTTP $($m.Status) (se continua)."
    Remove-Item -LiteralPath "$out/jrxml.meta.json" -Force -ErrorAction SilentlyContinue
} else { [IO.File]::WriteAllBytes("$out/jrxml.meta.json", $m.Bytes) }

$leaf = $juri.Substring($juri.LastIndexOf("/") + 1)
$nombre = ConvertTo-JasperSafePath $leaf
if (-not $nombre) { $nombre = "main_jrxml" }
if (-not $nombre.EndsWith(".jrxml")) { $nombre = "$nombre.jrxml" }
$tmpf = [IO.Path]::GetTempFileName()
try {
    # Contenido binario del file resource: Accept application/octet-stream
    $c = Invoke-JasperRequest -Path "/rest_v2/resources$jenc" -Accept "application/octet-stream" -TimeoutSec 120
    if (Test-JasperSessionExpired $c.Status) { exit $JasperErr.SessionExpired }
    if ($c.Status -ne 200) { Write-JasperErr "Descarga del jrxml respondio HTTP $($c.Status)."; exit $JasperErr.Http }
    [IO.File]::WriteAllBytes($tmpf, $c.Bytes)
    if (-not (Test-JasperXml $tmpf)) {
        Write-JasperErr "El contenido descargado no es XML valido (revisar Accept/endpoint)."
        exit $JasperErr.Xml
    }
    Copy-Item -LiteralPath $tmpf -Destination "$out/$nombre" -Force
} finally { Remove-Item -LiteralPath $tmpf -Force -ErrorAction SilentlyContinue }
[IO.File]::WriteAllText("$out/jrxml.uri", "$juri`n", (New-Object System.Text.UTF8Encoding($false)))
Write-JasperOk "Importado en $out/"
Write-Output "$out/$nombre"
exit 0
