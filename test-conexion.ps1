# test-conexion.ps1 - Prueba de conectividad (equivale a test-conexion.sh):
#   1) alcance + version (GET /rest_v2/serverInfo, sin auth)
#   2) sesion (reusa la de login; no loguea sola)
#
# Uso: .\test-conexion.ps1 [--solo-alcance]
# Salida: 0 OK | 10 HTTP/red | 11 sin sesion | 13 sesion expirada | 20 inesperado
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force -DisableNameChecking
Initialize-Jasper

Write-Host "== Prueba de conexion a JasperReports Server: $($Jasper.Url)"
Write-Host "--- Paso 1/2: alcance (sin autenticacion) ---"
$r = Test-JasperReachable
if ($r.Code -ne 0) { Write-Host "RESULTADO: ERROR (paso 1/2)"; exit $r.Code }
$ver = "?"
try { $j = $r.Info | ConvertFrom-Json; $ver = "$($j.version) $($j.edition)".Trim() } catch { }
Write-JasperOk "Servidor alcanzable. Version: $ver"
if ($args.Count -gt 0 -and $args[0] -eq "--solo-alcance") { exit 0 }

Write-Host "--- Paso 2/2: sesion persistente ---"
if (-not (Test-Path -LiteralPath $Jasper.CookieJar) -or (Get-Item -LiteralPath $Jasper.CookieJar).Length -eq 0) {
    Write-JasperErr "No hay sesion. Ejecuta .\login.ps1"; Write-Host "RESULTADO: ERROR (sin sesion)"; exit $JasperErr.Login
}
$h = Invoke-JasperRequest -Path "/rest_v2/resources?limit=1" -Accept "application/json" -TimeoutSec 15
if (Test-JasperSessionExpired $h.Status) { Write-Host "RESULTADO: ERROR (sesion expirada)"; exit $JasperErr.SessionExpired }
if ($h.Status -ne 200 -and $h.Status -ne 204) { Write-JasperErr "resources respondio HTTP $($h.Status)."; exit $JasperErr.Http }
Write-JasperOk "Sesion valida."
Write-Host "RESULTADO: OK"
exit 0
