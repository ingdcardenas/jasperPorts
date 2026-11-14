#!/usr/bin/env bash
#
# test-conexion.sh - Prueba de conectividad:
#   1) alcance + version (GET /rest_v2/serverInfo, sin auth)
#   2) sesion (reusa la de ./login.sh; no loguea sola)
#
# Uso: ./test-conexion.sh [--solo-alcance]
# Salida: 0 OK | 10 HTTP/red | 11 sin sesion | 13 sesion expirada | 20 inesperado
# Con --solo-alcance solo valida el paso 1 (util sin sesion).

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
command -v curl >/dev/null 2>&1 || { echo "[ERROR] Se requiere curl." >&2; exit 20; }
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/jasper-api.sh"

echo "== Prueba de conexion a JasperReports Server: ${JASPER_URL}"
echo "--- Paso 1/2: alcance (sin autenticacion) ---"
info="$(jasper_check_reachable)"; rc=$?
if [[ ${rc} -ne 0 ]]; then echo "RESULTADO: ERROR (paso 1/2)"; exit "${rc}"; fi
ver="$(printf '%s' "${info}" | python3 -I -c 'import sys,json;d=json.load(sys.stdin);print(d.get("version","?"),d.get("edition",""))' 2>/dev/null || echo '?')"
jasper_ok "Servidor alcanzable. Version: ${ver}"
[[ "${1:-}" == "--solo-alcance" ]] && exit 0

echo "--- Paso 2/2: sesion persistente ---"
if [[ ! -s "${JASPER_COOKIE_JAR}" ]]; then
    jasper_err "No hay sesion. Ejecuta ./login.sh"; echo "RESULTADO: ERROR (sin sesion)"; exit "${JASPER_ERR_LOGIN}"
fi
http="$(jasper_curl_status -m 15 -H 'Accept: application/json' '/rest_v2/resources?limit=1')"
if jasper_check_session_expired "${http}"; then echo "RESULTADO: ERROR (sesion expirada)"; exit "${JASPER_ERR_SESSION_EXPIRED}"; fi
if [[ "${http}" != "200" && "${http}" != "204" ]]; then
    jasper_err "resources respondio HTTP ${http}."; exit "${JASPER_ERR_HTTP}"
fi
jasper_ok "Sesion valida."
echo "RESULTADO: OK"
exit 0
