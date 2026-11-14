#!/usr/bin/env bash
# abrir-studio.sh - Abre Jaspersoft Studio sobre el workspace local con los .jrxml del toolkit.
#
# Uso: ./abrir-studio.sh [ruta.jrxml]
#   Todo es local: no se sube nada al servidor Jasper.
#   Crea (idempotente) el proyecto "toolkit-jasper" en el workspace con la carpeta
#   enlazada "reportes" -> <toolkit>/reportes (Studio edita los archivos reales).
#   Si Studio esta CERRADO, activa ademas el refresco automatico del workspace
#   (respaldando antes el .prefs). Si esta abierto, no toca .metadata.
# Variables opcionales: STUDIO_BIN (ejecutable), STUDIO_WORKSPACE (workspace).
# Codigos de salida: 0 OK, 2 uso/archivo inexistente, 3 Studio no encontrado, 4 error de workspace.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTES="$AQUI/reportes"
PROYECTO="toolkit-jasper"
ARCHIVO="${1:-}"

if [[ "${ARCHIVO}" == "-h" || "${ARCHIVO}" == "--help" ]]; then sed -n '2,11p' "$0"; exit 0; fi
if [[ -n "$ARCHIVO" && ! -f "$ARCHIVO" ]]; then echo "ERROR: no existe el archivo: $ARCHIVO" >&2; exit 2; fi
[[ -d "$REPORTES" ]] || { echo "ERROR: no existe $REPORTES" >&2; exit 2; }

# --- Detectar ejecutable y entorno ---
ENTORNO="linux"; BIN="${STUDIO_BIN:-}"
if [[ -z "$BIN" ]]; then
  shopt -s nullglob
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      ENTORNO="win"
      for d in "C:/Program Files/TIBCO/Jaspersoft Studio"* "C:/Program Files/Jaspersoft/Jaspersoft Studio"*; do
        [[ -f "$d/Jaspersoft Studio.exe" ]] && BIN="$d/Jaspersoft Studio.exe"
      done ;;
    *)
      for d in /opt/js-studiocomm_*; do [[ -x "$d/Jaspersoft Studio" ]] && BIN="$d/Jaspersoft Studio"; done
      if [[ -z "$BIN" ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        ENTORNO="wsl"
        for d in "/mnt/c/Program Files/TIBCO/Jaspersoft Studio"* "/mnt/c/Program Files/Jaspersoft/Jaspersoft Studio"*; do
          [[ -f "$d/Jaspersoft Studio.exe" ]] && BIN="$d/Jaspersoft Studio.exe"
        done
      fi ;;
  esac
  shopt -u nullglob
fi
if [[ -z "$BIN" || ! -e "$BIN" ]]; then
  echo "ERROR: no se encontro Jaspersoft Studio (Linux: /opt/js-studiocomm_*; Windows: C:/Program Files/TIBCO/Jaspersoft Studio*)." >&2
  echo "       Defina STUDIO_BIN=/ruta/al/ejecutable." >&2; exit 3
fi

# --- Rutas segun entorno (en Windows/WSL Studio necesita rutas Windows) ---
conv() { # $1 ruta unix -> ruta que entiende Studio
  case "$ENTORNO" in
    wsl) wslpath -m "$1" ;; win) cygpath -m "$1" ;; *) printf '%s' "$1" ;;
  esac
}
if [[ "$ENTORNO" == "wsl" ]]; then
  WINHOME="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')"
  WS="${STUDIO_WORKSPACE:-$(wslpath -u "$WINHOME")/JaspersoftWorkspace}"
else
  WS="${STUDIO_WORKSPACE:-$HOME/JaspersoftWorkspace}"
fi
mkdir -p "$WS" || { echo "ERROR: no se pudo crear workspace $WS" >&2; exit 4; }

# --- Estudio abierto? ---
ABIERTO=0
pgrep -f "Jaspersoft Studio" >/dev/null 2>&1 && ABIERTO=1
[[ "$ENTORNO" != "linux" ]] && tasklist.exe 2>/dev/null | grep -qi "Jaspersoft" && ABIERTO=1

# --- Proyecto con carpeta enlazada (idempotente) ---
P="$WS/$PROYECTO"
if [[ ! -f "$P/.project" ]]; then
  [[ $ABIERTO -eq 1 ]] && echo "AVISO: Studio abierto; el proyecto nuevo se registra con File > Import > Existing Projects into Workspace (ver README)."
  mkdir -p "$P" || exit 4
  LOC="$(conv "$REPORTES")"
  cat > "$P/.project" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$PROYECTO</name>
	<comment>Enlace a $LOC (generado por abrir-studio.sh)</comment>
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
XML
  cat > "$P/.classpath" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-11"/>
	<classpathentry exported="true" kind="con" path="net.sf.jasperreports.JR_CONTAINER"/>
	<classpathentry exported="true" kind="con" path="com.jaspersoft.server.JRS_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
XML
  echo "Proyecto creado: $P"
fi

# --- Refresco automatico (solo con Studio cerrado; respaldo previo) ---
PREFS="$WS/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.core.resources.prefs"
if [[ -f "$PREFS" ]] && ! grep -q '^refresh.enabled=true' "$PREFS"; then
  if [[ $ABIERTO -eq 1 ]]; then
    echo "AVISO: Studio abierto; no se editan prefs. Cierrelo y reejecute para activar el refresco, o: Window > Preferences > General > Workspace > 'Refresh using native hooks or polling'."
  else
    cp -p "$PREFS" "$PREFS.bak.$(date +%Y%m%d%H%M%S)" || { echo "ERROR: respaldo de prefs fallo" >&2; exit 4; }
    sed -i '/^refresh\.\(lightweight\.\)\?enabled=/d' "$PREFS"
    printf 'refresh.enabled=true\nrefresh.lightweight.enabled=true\n' >> "$PREFS"
    echo "Refresco automatico activado en prefs."
  fi
fi

# --- Abrir ---
if [[ $ABIERTO -eq 1 && "$ENTORNO" == "linux" ]]; then
  if [[ -n "$ARCHIVO" ]]; then
    echo "Studio ya esta abierto: se reenvia el archivo a la instancia abierta."
    nohup "$BIN" --launcher.openFile "$(cd "$(dirname "$ARCHIVO")" && pwd)/$(basename "$ARCHIVO")" >/dev/null 2>&1 &
  else
    echo "Studio ya esta abierto (no se toca). Indique un .jrxml para abrirlo en esa instancia."
  fi
  exit 0
fi
ARGS=(-data "$(conv "$WS")")
# Nota: Studio (RCP sin org.eclipse.ui.ide.application) ignora un directorio de proyecto
# como argumento: no hay smart import por linea de comandos. El archivo se abre con
# --launcher.openFile, que ademas se reenvia a una instancia ya abierta.
[[ -n "$ARCHIVO" ]] && ARGS+=(--launcher.openFile "$(conv "$(cd "$(dirname "$ARCHIVO")" && pwd)/$(basename "$ARCHIVO")")")
nohup "$BIN" "${ARGS[@]}" >/dev/null 2>&1 &
echo "Studio lanzado (workspace: $WS)."
