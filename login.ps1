# login.ps1 - Login interactivo contra JasperReports Server (REST v2). Equivale a login.sh.
# Guarda la cookie JSESSIONID en .jasper-session (misma que la version bash) y el
# servidor en .jasper-hosts. NUNCA persiste la contrasena (Read-Host -AsSecureString).
#
# Uso:  powershell -ExecutionPolicy Bypass -File .\login.ps1
# Salida: 0 OK | 10 servidor no alcanzable | 11 login fallido | 20 inesperado
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force -DisableNameChecking
Initialize-Jasper

function ConvertTo-HostUrl([string]$e) {
    if ($e -match "^https?://") { return $e.TrimEnd("/") }
    return "http://" + $e.TrimEnd("/") + "/jasperserver"
}

$hist = @(Get-JasperHosts)
if ($hist.Count -gt 1) {
    Write-Host "Servidores usados:"
    for ($i = 0; $i -lt $hist.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $hist[$i]) }
}
$sel = Read-Host "Servidor [$($Jasper.Url)] (Enter, numero, o URL/host:puerto)"
if ($sel) {
    if ($sel -match "^[0-9]+$" -and [int]$sel -ge 1 -and [int]$sel -le $hist.Count) { $Jasper.Url = $hist[[int]$sel - 1] }
    else { $Jasper.Url = ConvertTo-HostUrl $sel }
}

if ($Jasper.Url -like "*10.6.206.114*") {
    Write-JasperLog "AVISO: es el servidor de PRODUCCION; el toolkit esta pensado solo para desarrollo."
    if (-not [Console]::IsInputRedirected) {
        $c = Read-Host "Escribe PRODUCCION para continuar"
        if ($c -cne "PRODUCCION") { Write-JasperErr "Cancelado."; exit $JasperErr.Login }
    }
}

Write-Host "=============================================================="
Write-Host " Login persistente contra JasperReports Server"
Write-Host " URL objetivo:      $($Jasper.Url)"
Write-Host " Archivo de sesion: $($Jasper.CookieJar)"
Write-Host "=============================================================="

$r = Test-JasperReachable
if ($r.Code -ne 0) { Write-JasperErr "Servidor no alcanzable."; exit $JasperErr.Http }
Write-JasperLog "serverInfo: $($r.Info)"

if (Test-JasperSession) {
    Write-JasperLog "Ya existe una sesion valida."
    if (-not [Console]::IsInputRedirected) {
        $ans = Read-Host "Renovar login de todas formas? [s/N]"
        if ($ans -notmatch "^[sS]$") { Add-JasperHost $Jasper.Url; Write-JasperOk "Se mantiene la sesion."; exit 0 }
    } else { Add-JasperHost $Jasper.Url; exit 0 }
}

$rc = Invoke-JasperLogin
if ($rc -ne 0) { Write-Host "RESULTADO: ERROR - login fallido"; exit $JasperErr.Login }
Add-JasperHost $Jasper.Url
if (-not (Test-JasperSession)) { Write-JasperErr "Login aparente OK pero la sesion no valida contra el servidor."; exit $JasperErr.Login }
Write-JasperOk "Sesion activa en $($Jasper.CookieJar). Usa .\logout.ps1 para cerrarla."
exit 0
