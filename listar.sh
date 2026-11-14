#!/usr/bin/env bash
#
# listar.sh - Lista reportUnits de una carpeta del repositorio.
#   GET /rest_v2/resources?folderUri=<carpeta>&type=reportUnit
#
# Uso: ./listar.sh <carpeta> [--recursivo] [--tipo <tipo>]
#   ej: ./listar.sh /reports/hospital --recursivo
# Salida: TSV "uri<TAB>label". Codigos: 0 OK | 2 uso | 10 HTTP | 11 sin sesion
#         12 carpeta no existe | 13 sesion expirada | 20 inesperado

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/jasper-api.sh"

carpeta=""; rec=false; tipo="reportUnit"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --recursivo) rec=true ;;
        --tipo) shift; tipo="${1:-reportUnit}" ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) carpeta="$1" ;;
    esac; shift
done
[[ -z "${carpeta}" ]] && { echo "Uso: $0 <carpeta> [--recursivo] [--tipo <tipo>]" >&2; exit "${JASPER_ERR_USAGE}"; }
carpeta="$(jasper_norm_uri "${carpeta}")"

jasper_require_session || exit $?

tmp="$(mktemp)"; trap 'rm -f "${tmp}"' EXIT
http="$(jasper_curl -m 60 -G -H 'Accept: application/json' \
    --data-urlencode "folderUri=${carpeta}" --data-urlencode "type=${tipo}" \
    --data-urlencode "recursive=${rec}" --data-urlencode 'limit=0' \
    -o "${tmp}" -w '%{http_code}' '/rest_v2/resources')"

jasper_check_session_expired "${http}" && exit "${JASPER_ERR_SESSION_EXPIRED}"
case "${http}" in
    200) ;;
    204) jasper_log "Sin resultados en ${carpeta}."; exit 0 ;;
    404) jasper_err "Carpeta ${carpeta} no existe."; exit "${JASPER_ERR_NOTFOUND}" ;;
    *)   jasper_err "HTTP ${http} al listar ${carpeta}."; exit "${JASPER_ERR_HTTP}" ;;
esac
python3 -I -c '
import sys,json
for r in json.load(open(sys.argv[1])).get("resourceLookup",[]):
    print(r.get("uri",""), r.get("label",""), sep="\t")
' "${tmp}"
