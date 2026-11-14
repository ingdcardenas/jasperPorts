#!/usr/bin/env bash
#
# lib/jasper-api.sh
#
# Libreria comun para la API REST v2 de JasperReports Server.
# Debe ser SOURCEADA:  source "$(dirname "${BASH_SOURCE[0]}")/lib/jasper-api.sh"
# Requiere: curl, python3
#
# Notas:
#   - Se usa --noproxy '*' (proxy corporativo; confirmado que el servidor de
#     desarrollo es alcanzable asi).
#   - Login: POST /rest_v2/login (j_username/j_password, form). La password
#     viaja por stdin (--data-urlencode j_password@-), nunca en argv.
#   - Sesion: cookie JSESSIONID en JASPER_COOKIE_JAR (chmod 600). Solo
#     logout.sh la borra.
#   - Servidor por defecto: DESARROLLO. Produccion no se usa desde aqui.

set -uo pipefail

_JASPER_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

JASPER_DEFAULT_URL="http://10.6.206.57:8080/jasperserver"
JASPER_COOKIE_JAR="${JASPER_COOKIE_JAR:-${_JASPER_LIB_DIR}/.jasper-session}"
JASPER_HOSTS_FILE="${JASPER_HOSTS_FILE:-${_JASPER_LIB_DIR}/.jasper-hosts}"
JASPER_REPORTES_DIR="${JASPER_REPORTES_DIR:-${_JASPER_LIB_DIR}/reportes}"
JASPER_BACKUPS_DIR="${JASPER_BACKUPS_DIR:-${_JASPER_LIB_DIR}/backups}"

readonly JASPER_ERR_HTTP=10
readonly JASPER_ERR_LOGIN=11
readonly JASPER_ERR_NOTFOUND=12
readonly JASPER_ERR_SESSION_EXPIRED=13
readonly JASPER_ERR_USAGE=2
readonly JASPER_ERR_BACKUP=14
readonly JASPER_ERR_XML=15
readonly JASPER_ERR_UNEXPECTED=20

jasper_log() { echo "[jasper] $*" >&2; }
jasper_ok()  { echo "[OK]     $*" >&2; }
jasper_err() { echo "[ERROR]  $*" >&2; }

# ---------------------------------------------------------------------------
# Hosts: historial (mas reciente primero), 600.
# ---------------------------------------------------------------------------
jasper_hosts_list() { [[ -f "${JASPER_HOSTS_FILE}" ]] && cat "${JASPER_HOSTS_FILE}"; return 0; }
jasper_hosts_last() { jasper_hosts_list | head -n 1; }
jasper_hosts_add() {
    local url="${1:-}" tmp
    [[ -z "${url}" ]] && return 1
    tmp="$(mktemp)"
    { printf '%s\n' "${url}"
      [[ -f "${JASPER_HOSTS_FILE}" ]] && { grep -Fxv -- "${url}" "${JASPER_HOSTS_FILE}" || true; }
    } > "${tmp}"
    mv "${tmp}" "${JASPER_HOSTS_FILE}"
    chmod 600 "${JASPER_HOSTS_FILE}"
}

# JASPER_URL: entorno/.env > ultimo host usado > desarrollo. Sin "/" final.
JASPER_URL="${JASPER_URL:-$(jasper_hosts_last)}"
JASPER_URL="${JASPER_URL:-${JASPER_DEFAULT_URL}}"
JASPER_URL="${JASPER_URL%/}"

# ---------------------------------------------------------------------------
# jasper_curl [opciones-curl...] <path-o-url>   (ultimo arg = path)
# ---------------------------------------------------------------------------
jasper_curl() {
    if [[ $# -eq 0 ]]; then jasper_err "jasper_curl: falta el path."; return 1; fi
    local argc=$# path="${!#}"
    local -a args=("${@:1:$((argc-1))}")
    local url="${path}"
    [[ "${path}" != http://* && "${path}" != https://* ]] && url="${JASPER_URL}${path}"
    # El jar nace siempre con 600 (curl lo crearia con el umask por defecto).
    if [[ ! -e "${JASPER_COOKIE_JAR}" ]]; then
        ( umask 077; : > "${JASPER_COOKIE_JAR}" )
    fi
    chmod 600 "${JASPER_COOKIE_JAR}"
    curl -s --noproxy '*' -c "${JASPER_COOKIE_JAR}" -b "${JASPER_COOKIE_JAR}" "${args[@]}" "${url}"
}

# Igual pero devuelve solo el codigo HTTP.
jasper_curl_status() { jasper_curl -o /dev/null -w '%{http_code}' "$@"; }

# Escapa una URI de repositorio para usarla en path (conserva "/").
jasper_encode_uri() {
    python3 -I -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe="/"))' "${1:-}"
}

# Normaliza uri: asegura "/" inicial, sin "/" final (salvo raiz).
jasper_norm_uri() {
    local u="${1:-}"
    [[ "${u}" != /* ]] && u="/${u}"
    [[ "${u}" != "/" ]] && u="${u%/}"
    printf '%s\n' "${u}"
}

# Sanea una uri para usarla como ruta de filesystem: preserva "/" pero
# traduce cada segmento a [A-Za-z0-9._-] y bloquea "..".
jasper_sanitize_path() {
    python3 -I -c '
import sys,re,unicodedata
out=[]
for seg in sys.argv[1].split("/"):
    if not seg or seg in (".",".."): continue
    s=seg.replace("ñ","n").replace("Ñ","N")
    s=unicodedata.normalize("NFKD",s)
    s="".join(c for c in s if not unicodedata.combining(c))
    s=re.sub(r"[^A-Za-z0-9._-]","_",s).strip("_")
    if s: out.append(s)
print("/".join(out))
' "${1:-}"
}

# ---------------------------------------------------------------------------
# Alcance (sin auth): GET /rest_v2/serverInfo -> JSON por stdout.
# ---------------------------------------------------------------------------
jasper_check_reachable() {
    local tmp http rc
    tmp="$(mktemp)"
    # Sin cookie jar: el probe de alcance no debe crear/alterar la sesion.
    http="$(curl -s --noproxy '*' -m 15 -H 'Accept: application/json' -o "${tmp}" -w '%{http_code}' "${JASPER_URL}/rest_v2/serverInfo")"
    rc=$?
    if [[ ${rc} -ne 0 ]]; then
        jasper_err "No se pudo contactar a ${JASPER_URL} (curl rc=${rc})."
        rm -f "${tmp}"; return "${JASPER_ERR_HTTP}"
    fi
    if [[ "${http}" != "200" ]]; then
        jasper_err "serverInfo respondio HTTP ${http}."
        rm -f "${tmp}"; return "${JASPER_ERR_HTTP}"
    fi
    cat "${tmp}"; rm -f "${tmp}"
}

# Sesion: probe silencioso (sin cookie -> 1). Usa GET /rest_v2/resources?limit=1
jasper_has_session() {
    [[ -s "${JASPER_COOKIE_JAR}" ]] || return 1
    local http
    http="$(jasper_curl_status -m 15 -H 'Accept: application/json' '/rest_v2/resources?limit=1')"
    [[ "${http}" == "200" || "${http}" == "204" ]]
}

jasper_require_session() {
    jasper_has_session && return 0
    jasper_err "No hay sesion valida en ${JASPER_COOKIE_JAR} (servidor ${JASPER_URL})."
    jasper_err "Ejecuta './login.sh' primero y reintenta."
    return "${JASPER_ERR_LOGIN}"
}

# Chequeo ruidoso en operaciones reales: 0 (con mensaje) si http=401.
jasper_check_session_expired() {
    if [[ "${1:-}" == "401" ]]; then
        jasper_err "Sesion expirada o invalida (HTTP 401). Ejecuta ./login.sh para renovarla."
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# jasper_login [usuario]: password por read -s (o JASPER_PASSWORD de entorno),
# enviada por stdin. Jasper responde 200 + cookie si OK; en error suele
# redirigir (302) a login.html?error=1.
# ---------------------------------------------------------------------------
jasper_login() {
    local user="${1:-${JASPER_USER:-}}" password="${JASPER_PASSWORD:-}"
    [[ -z "${user}" ]] && read -r -p "Usuario de Jasper: " user
    if [[ -z "${user}" ]]; then jasper_err "No se indico usuario."; return "${JASPER_ERR_LOGIN}"; fi
    if [[ -z "${password}" ]]; then
        if [[ -t 0 ]]; then read -r -s -p "Password de ${user}: " password; echo >&2
        else IFS= read -r password; fi
    fi
    if [[ -z "${password}" ]]; then jasper_err "No se indico contrasena."; return "${JASPER_ERR_LOGIN}"; fi

    mkdir -p "$(dirname -- "${JASPER_COOKIE_JAR}")"
    : > "${JASPER_COOKIE_JAR}"; chmod 600 "${JASPER_COOKIE_JAR}"

    local http
    # password por stdin (printf es builtin: no aparece en ps)
    http="$(printf '%s' "${password}" | jasper_curl -X POST \
        --data-urlencode "j_username=${user}" \
        --data-urlencode 'j_password@-' \
        -o /dev/null -w '%{http_code}' '/rest_v2/login')"
    unset password JASPER_PASSWORD
    chmod 600 "${JASPER_COOKIE_JAR}"

    if [[ "${http}" != "200" ]] || ! grep -q 'JSESSIONID' "${JASPER_COOKIE_JAR}"; then
        jasper_err "Login fallido (HTTP ${http}). Revisar usuario/contrasena."
        : > "${JASPER_COOKIE_JAR}"
        return "${JASPER_ERR_LOGIN}"
    fi
    jasper_ok "Login exitoso como '${user}'."
}

# Solo logout.sh debe llamarla.
jasper_logout() {
    if [[ -f "${JASPER_COOKIE_JAR}" ]]; then
        # Jasper no documenta /logout REST; se invoca el de la webapp (best effort).
        jasper_curl -m 10 -o /dev/null '/logout.html' >/dev/null 2>&1 || true
        rm -f "${JASPER_COOKIE_JAR}"
        jasper_log "Sesion cerrada y cookie eliminada (${JASPER_COOKIE_JAR})."
    else
        jasper_log "No habia cookie de sesion en ${JASPER_COOKIE_JAR}."
    fi
}

# Valida que un archivo sea XML bien formado.
jasper_xml_check() {
    python3 -I -c '
import sys, xml.etree.ElementTree as ET
try: ET.parse(sys.argv[1])
except Exception as e: print(e, file=sys.stderr); sys.exit(1)
' "${1:-}"
}

# Lee una clave JSON por ruta "a.b.c" desde archivo; vacio si no existe.
jasper_json_get() {
    python3 -I -c '
import sys,json
try:
    d=json.load(open(sys.argv[1]))
    for k in sys.argv[2].split("."): d=d[k]
    print(d if not isinstance(d,(dict,list)) else json.dumps(d))
except Exception: pass
' "${1}" "${2}"
}

# ---------------------------------------------------------------------------
# jasper_get_reportunit <uri> <archivo-salida>
# Descarga el descriptor JSON del reportUnit. Retorna codigos JASPER_ERR_*.
# Imprime mensajes de error; no imprime nada si OK.
# ---------------------------------------------------------------------------
jasper_get_reportunit() {
    local uri enc out http
    uri="$(jasper_norm_uri "${1}")"; out="${2}"
    enc="$(jasper_encode_uri "${uri}")"
    http="$(jasper_curl -m 60 -H 'Accept: application/repository.reportUnit+json' \
        -o "${out}" -w '%{http_code}' "/rest_v2/resources${enc}")"
    if jasper_check_session_expired "${http}"; then return "${JASPER_ERR_SESSION_EXPIRED}"; fi
    case "${http}" in
        200) return 0 ;;
        404) jasper_err "No existe el recurso ${uri} (HTTP 404)."; return "${JASPER_ERR_NOTFOUND}" ;;
        *)   jasper_err "GET descriptor de ${uri} respondio HTTP ${http}."; return "${JASPER_ERR_HTTP}" ;;
    esac
}

# jasper_jrxml_uri_from_descriptor <descriptor.json>
# URI del recurso jrxml principal (referencia o inline). Vacio si no se halla.
jasper_jrxml_uri_from_descriptor() {
    python3 -I -c '
import sys,json
d=json.load(open(sys.argv[1]))
j=d.get("jrxml") or {}
ref=j.get("jrxmlFileReference") or {}
if ref.get("uri"): print(ref["uri"]); sys.exit()
f=j.get("jrxmlFile") or {}
if f.get("uri"): print(f["uri"])
' "${1}"
}
