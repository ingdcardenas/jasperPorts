# listar.ps1 - Lista reportUnits de una carpeta del repositorio (equivale a listar.sh).
#   GET /rest_v2/resources?folderUri=<carpeta>&type=reportUnit
#
# Uso: .\listar.ps1 <carpeta> [--recursivo] [--tipo <tipo>]
#   ej: .\listar.ps1 /reports/hospital --recursivo
# Salida: TSV "uri<TAB>label". Codigos: 0 OK | 2 uso | 10 HTTP | 11 sin sesion
#         12 carpeta no existe | 13 sesion expirada | 20 inesperado
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force -DisableNameChecking
Initialize-Jasper

$carpeta = ""; $rec = $false; $tipo = "reportUnit"
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "--recursivo" { $rec = $true }
        "--tipo" { $i++; if ($i -lt $args.Count) { $tipo = $args[$i] } }
        { $_ -eq "-h" -or $_ -eq "--help" } { Get-Content -LiteralPath $PSCommandPath -TotalCount 8 | Select-Object -Skip 1; exit 0 }
        default { $carpeta = $args[$i] }
    }
}
if (-not $carpeta) { [Console]::Error.WriteLine("Uso: .\listar.ps1 <carpeta> [--recursivo] [--tipo <tipo>]"); exit $JasperErr.Usage }
$carpeta = ConvertTo-JasperUri $carpeta

$rc = Assert-JasperSession; if ($rc -ne 0) { exit $rc }

$q = "folderUri=" + [Uri]::EscapeDataString($carpeta) + "&type=" + [Uri]::EscapeDataString($tipo) + "&recursive=" + $rec.ToString().ToLower() + "&limit=0"
$r = Invoke-JasperRequest -Path "/rest_v2/resources?$q" -Accept "application/json" -TimeoutSec 60
if (Test-JasperSessionExpired $r.Status) { exit $JasperErr.SessionExpired }
switch ($r.Status) {
    200 { }
    204 { Write-JasperLog "Sin resultados en $carpeta."; exit 0 }
    404 { Write-JasperErr "Carpeta $carpeta no existe."; exit $JasperErr.NotFound }
    default { Write-JasperErr "HTTP $($r.Status) al listar $carpeta."; exit $JasperErr.Http }
}
$j = $r.Text | ConvertFrom-Json
foreach ($x in @($j.resourceLookup)) { if ($x) { Write-Output ("{0}`t{1}" -f $x.uri, $x.label) } }
exit 0
