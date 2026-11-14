# logout.ps1 - Cierra la sesion y borra la cookie (unico script que la borra). Equivale a logout.sh.
# Uso: .\logout.ps1   | Salida: 0
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force -DisableNameChecking
Initialize-Jasper

Invoke-JasperLogout
exit 0
