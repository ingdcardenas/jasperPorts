# export-reporte.ps1 - Exporta (sube) un .jrxml local al servidor, actualizando el .jrxml principal de un reportUnit (equivale a export-reporte.sh).
#   1) valida XML bien formado del archivo local
#   2) BACKUP previo automatico (import-reporte.ps1) en backups/<fecha>/;
#      si falla, ABORTA (codigo 14)
#   3) PUT /rest_v2/resources<jrxml-uri> con
#      Content-Type: application/repository.file+json
#      {label, description, type:"jrxml", content:<base64>}
#
# Uso: .\export-reporte.ps1 <uri-reportUnit> <archivo.jrxml> [-y]
#   -y  no pedir confirmacion
# Codigos: 0 OK | 2 uso | 10 HTTP | 11 sin sesion | 12 no existe | 13 sesion
#          expirada | 14 backup fallido | 15 XML mal formado | 20 inesperado
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force -DisableNameChecking
Initialize-Jasper

$uri = ""; $archivo = ""; $yes = $false
foreach ($a in $args) {
    switch ($a) {
        "-y" { $yes = $true }
        { $_ -eq "-h" -or $_ -eq "--help" } { Get-Content -LiteralPath $PSCommandPath -TotalCount 13 | Select-Object -Skip 1; exit 0 }
        default { if (-not $uri) { $uri = $a } else { $archivo = $a } }
    }
}
if (-not $uri -or -not $archivo) { [Console]::Error.WriteLine("Uso: .\export-reporte.ps1 <uri-reportUnit> <archivo.jrxml> [-y]"); exit $JasperErr.Usage }
if (-not (Test-Path -LiteralPath $archivo -PathType Leaf)) { Write-JasperErr "No existe $archivo"; exit $JasperErr.Usage }
$uri = ConvertTo-JasperUri $uri

if (-not (Test-JasperXml $archivo)) { Write-JasperErr "$archivo no es XML bien formado. Export abortado."; exit $JasperErr.Xml }
$rc = Assert-JasperSession; if ($rc -ne 0) { exit $rc }

# Resolver jrxml destino
$tmpd = [IO.Path]::GetTempFileName()
try {
    $rc = Get-JasperReportUnit $uri $tmpd
    if ($rc -ne 0) { exit $rc }
    $juri = Get-JasperJrxmlUri $tmpd
} finally { Remove-Item -LiteralPath $tmpd -Force -ErrorAction SilentlyContinue }
if (-not $juri) { Write-JasperErr "No se pudo resolver el jrxml principal de $uri."; exit $JasperErr.Http }

# Backup previo
$fecha = Get-Date -Format "yyyyMMdd-HHmmss"
$bdir = "$($Jasper.BackupsDir)/$fecha"
Write-JasperLog "Backup previo en $bdir ..."
& (Join-Path $PSScriptRoot "import-reporte.ps1") $uri -d $bdir | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-JasperErr "Backup fallido. Export ABORTADO (nada se modifico en el servidor)."
    exit $JasperErr.Backup
}
Write-JasperOk "Backup listo."

if (-not $yes) {
    if ([Console]::IsInputRedirected) { Write-JasperErr "Sin TTY: usar -y para confirmar."; exit $JasperErr.Usage }
    $r = Read-Host "Sobrescribir $juri en $($Jasper.Url)? [s/N]"
    if ($r -notmatch "^[sS]$") { Write-JasperLog "Cancelado."; exit 0 }
}

# Metadatos actuales (label/description) para no perderlos
$jenc = ConvertTo-JasperEncodedUri $juri
$meta = $null
$mr = Invoke-JasperRequest -Path "/rest_v2/resources$jenc" -Accept "application/repository.file+json" -TimeoutSec 60
if ($mr.Status -eq 200) { try { $meta = $mr.Text | ConvertFrom-Json } catch { $meta = $null } }

$label = "main_jrxml"
if ($meta -and $meta.label) { $label = [string]$meta.label }
$body = [ordered]@{ label = $label; type = "jrxml"; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($archivo)) }
if ($meta -and $meta.description) { $body.description = [string]$meta.description }
$json = $body | ConvertTo-Json -Compress
$bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)

$r = Invoke-JasperRequest -Path "/rest_v2/resources$jenc" -Method PUT -Accept "application/repository.file+json" -ContentType "application/repository.file+json" -Body $bytes -TimeoutSec 120
if (Test-JasperSessionExpired $r.Status) { exit $JasperErr.SessionExpired }
switch ($r.Status) {
    { $_ -eq 200 -or $_ -eq 201 } { Write-JasperOk "jrxml actualizado (HTTP $($r.Status)). Backup: $bdir" }
    404 { Write-JasperErr "Recurso $juri no existe (404)."; exit $JasperErr.NotFound }
    default {
        $t = $r.Text; if ($t.Length -gt 400) { $t = $t.Substring(0, 400) }
        Write-JasperErr "PUT respondio HTTP $($r.Status): $t"
        Write-JasperErr "Backup disponible en $bdir"
        exit $JasperErr.Http
    }
}
exit 0
