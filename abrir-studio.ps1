# abrir-studio.ps1 - Abre Jaspersoft Studio sobre el workspace local con los .jrxml del toolkit (equivale a abrir-studio.sh).
#
# Uso: .\abrir-studio.ps1 [ruta.jrxml]
#   Todo es local: no se sube nada al servidor Jasper.
#   Crea (idempotente) el proyecto "toolkit-jasper" en el workspace con la carpeta
#   enlazada "reportes" -> <toolkit>\reportes (Studio edita los archivos reales).
#   Si Studio esta CERRADO, activa ademas el refresco automatico del workspace
#   (respaldando antes el .prefs). Si esta abierto, no toca .metadata.
# Variables opcionales: $env:STUDIO_BIN (ejecutable), $env:STUDIO_WORKSPACE (workspace).
# Codigos de salida: 0 OK, 2 uso/archivo inexistente, 3 Studio no encontrado, 4 error de workspace.
$ErrorActionPreference = 'Continue'

$Aqui = $PSScriptRoot
$Reportes = Join-Path $Aqui 'reportes'
$Proyecto = 'toolkit-jasper'
$Archivo = if ($args.Count -gt 0) { [string]$args[0] } else { '' }

function Out-Err([string]$m) { [Console]::Error.WriteLine($m) }

if ($Archivo -eq '-h' -or $Archivo -eq '--help') { Get-Content -LiteralPath $PSCommandPath -TotalCount 11 | Select-Object -Skip 1; exit 0 }
if ($Archivo -and -not (Test-Path -LiteralPath $Archivo -PathType Leaf)) { Out-Err "ERROR: no existe el archivo: $Archivo"; exit 2 }
if (-not (Test-Path -LiteralPath $Reportes -PathType Container)) { Out-Err "ERROR: no existe $Reportes"; exit 2 }

# --- Detectar ejecutable ---
$Bin = $env:STUDIO_BIN
if (-not $Bin) {
    $raices = @(
        (Join-Path $env:ProgramFiles 'TIBCO'),
        (Join-Path $env:ProgramFiles 'Jaspersoft'),
        $env:LOCALAPPDATA,
        (Join-Path $env:LOCALAPPDATA 'Programs')
    )
    if (${env:ProgramFiles(x86)}) {
        $raices += (Join-Path ${env:ProgramFiles(x86)} 'TIBCO')
        $raices += (Join-Path ${env:ProgramFiles(x86)} 'Jaspersoft')
    }
    foreach ($r in $raices) {
        if (-not $r -or -not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        foreach ($d in (Get-ChildItem -LiteralPath $r -Directory -Filter 'Jaspersoft Studio*' -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $exe = Join-Path $d.FullName 'Jaspersoft Studio.exe'
            if (Test-Path -LiteralPath $exe -PathType Leaf) { $Bin = $exe }
        }
    }
}
if (-not $Bin -or -not (Test-Path -LiteralPath $Bin)) {
    Out-Err 'ERROR: no se encontro Jaspersoft Studio (C:\Program Files\TIBCO\Jaspersoft Studio*, C:\Program Files\Jaspersoft\Jaspersoft Studio*, %LOCALAPPDATA%).'
    Out-Err '       Defina STUDIO_BIN con la ruta al ejecutable, ej.: $env:STUDIO_BIN = "C:\ruta\Jaspersoft Studio.exe"'
    exit 3
}

# --- Workspace ---
$WS = $env:STUDIO_WORKSPACE
if (-not $WS) { $WS = Join-Path $env:USERPROFILE 'JaspersoftWorkspace' }
try { New-Item -ItemType Directory -Path $WS -Force -ErrorAction Stop | Out-Null }
catch { Out-Err "ERROR: no se pudo crear workspace $WS"; exit 4 }

function ConvPath([string]$p) { return ([IO.Path]::GetFullPath($p)) -replace '\\', '/' }

# --- Studio abierto? ---
$Abierto = $false
if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Jaspersoft*Studio*' -or $_.MainWindowTitle -like '*Jaspersoft Studio*' }) { $Abierto = $true }

# --- Proyecto con carpeta enlazada (idempotente) ---
$P = Join-Path $WS $Proyecto
if (-not (Test-Path -LiteralPath (Join-Path $P '.project') -PathType Leaf)) {
    if ($Abierto) { Write-Output 'AVISO: Studio abierto; el proyecto nuevo se registra con File > Import > Existing Projects into Workspace (ver README).' }
    try { New-Item -ItemType Directory -Path $P -Force -ErrorAction Stop | Out-Null } catch { exit 4 }
    $LOC = ConvPath $Reportes
    $projXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$Proyecto</name>
	<comment>Enlace a $LOC (generado por abrir-studio.ps1)</comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
		<buildCommand>
			<name>net.sf.jasperreports.builder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
		<nature>net.sf.jasperreports.nature</nature>
	</natures>
	<linkedResources>
		<link>
			<name>reportes</name>
			<type>2</type>
			<location>$LOC</location>
		</link>
	</linkedResources>
</projectDescription>
"@
    $cpXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-11"/>
	<classpathentry exported="true" kind="con" path="net.sf.jasperreports.JR_CONTAINER"/>
	<classpathentry exported="true" kind="con" path="com.jaspersoft.server.JRS_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
'@
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText((Join-Path $P '.project'), ($projXml -replace "`r`n", "`n") + "`n", $utf8)
        [IO.File]::WriteAllText((Join-Path $P '.classpath'), ($cpXml -replace "`r`n", "`n") + "`n", $utf8)
    } catch { Out-Err "ERROR: no se pudo escribir el proyecto en $P"; exit 4 }
    Write-Output "Proyecto creado: $P"
}

# --- Refresco automatico (solo con Studio cerrado; respaldo previo) ---
$Prefs = Join-Path $WS '.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.core.resources.prefs'
if ((Test-Path -LiteralPath $Prefs -PathType Leaf) -and -not (Select-String -LiteralPath $Prefs -Pattern '^refresh\.enabled=true' -Quiet)) {
    if ($Abierto) {
        Write-Output "AVISO: Studio abierto; no se editan prefs. Cierrelo y reejecute para activar el refresco, o: Window > Preferences > General > Workspace > 'Refresh using native hooks or polling'."
    } else {
        try {
            Copy-Item -LiteralPath $Prefs -Destination "$Prefs.bak.$(Get-Date -Format 'yyyyMMddHHmmss')" -ErrorAction Stop
            $lineas = @(Get-Content -LiteralPath $Prefs | Where-Object { $_ -notmatch '^refresh\.(lightweight\.)?enabled=' })
            $lineas += 'refresh.enabled=true'
            $lineas += 'refresh.lightweight.enabled=true'
            [IO.File]::WriteAllText($Prefs, (($lineas -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
            Write-Output 'Refresco automatico activado en prefs.'
        } catch { Out-Err 'ERROR: respaldo/edicion de prefs fallo'; exit 4 }
    }
}

# --- Abrir ---
$argsStudio = @('-data', (ConvPath $WS))
if ($Archivo) { $argsStudio += @('--launcher.openFile', (ConvPath (Resolve-Path -LiteralPath $Archivo).Path)) }
if ($Abierto) {
    if ($Archivo) { Write-Output 'Studio ya esta abierto: se reenvia el archivo a la instancia abierta.' }
    else { Write-Output 'Studio ya esta abierto (no se toca). Indique un .jrxml para abrirlo en esa instancia.'; exit 0 }
}
# Nota: Studio ignora un directorio de proyecto como argumento (sin smart import por linea de
# comandos); el archivo se abre con --launcher.openFile.
Start-Process -FilePath $Bin -ArgumentList ($argsStudio | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) | Out-Null
Write-Output "Studio lanzado (workspace: $WS)."
exit 0
