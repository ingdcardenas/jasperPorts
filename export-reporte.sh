#!/usr/bin/env bash
#
# export-reporte.sh - Exporta (sube) un .jrxml local al servidor, actualizando el .jrxml principal de un reportUnit.
#   1) valida XML bien formado del archivo local
#   2) BACKUP previo automatico (import-reporte.sh) en backups/<fecha>/;
#      si falla, ABORTA (codigo 14)
#   3) PUT /rest_v2/resources<jrxml-uri> con
#      Content-Type: application/repository.file+json
#      {label, description, type:"jrxml", content:<base64>}
#
# Uso: ./export-reporte.sh <uri-reportUnit> <archivo.jrxml> [-y]
#   -y  no pedir confirmacion
# Codigos: 0 OK | 2 uso | 10 HTTP | 11 sin sesion | 12 no existe | 13 sesion
#          expirada | 14 backup fallido | 15 XML mal formado | 20 inesperado

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/jasper-api.sh"

uri=""; archivo=""; yes=false
for a in "$@"; do
    case "${a}" in
        -y) yes=true ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) if [[ -z "${uri}" ]]; then uri="${a}"; else archivo="${a}"; fi ;;
    esac
done
[[ -z "${uri}" || -z "${archivo}" ]] && { echo "Uso: $0 <uri-reportUnit> <archivo.jrxml> [-y]" >&2; exit "${JASPER_ERR_USAGE}"; }
[[ -f "${archivo}" ]] || { jasper_err "No existe ${archivo}"; exit "${JASPER_ERR_USAGE}"; }
uri="$(jasper_norm_uri "${uri}")"

if ! jasper_xml_check "${archivo}"; then
    jasper_err "${archivo} no es XML bien formado. Export abortado."; exit "${JASPER_ERR_XML}"
fi
jasper_require_session || exit $?

# Resolver jrxml destino
tmpd="$(mktemp)"; tmpb="$(mktemp)"; tmpm="$(mktemp)"
trap 'rm -f "${tmpd}" "${tmpb}" "${tmpm}"' EXIT
jasper_get_reportunit "${uri}" "${tmpd}"; rc=$?; [[ ${rc} -ne 0 ]] && exit "${rc}"
juri="$(jasper_jrxml_uri_from_descriptor "${tmpd}")"
[[ -z "${juri}" ]] && { jasper_err "No se pudo resolver el jrxml principal de ${uri}."; exit "${JASPER_ERR_HTTP}"; }

# Backup previo
fecha="$(date +%Y%m%d-%H%M%S)"
bdir="${JASPER_BACKUPS_DIR}/${fecha}"
jasper_log "Backup previo en ${bdir} ..."
if ! "${SCRIPT_DIR}/import-reporte.sh" "${uri}" -d "${bdir}" >/dev/null; then
    jasper_err "Backup fallido. Export ABORTADO (nada se modifico en el servidor)."
    exit "${JASPER_ERR_BACKUP}"
fi
jasper_ok "Backup listo."

if [[ "${yes}" != true ]]; then
    [[ -t 0 ]] || { jasper_err "Sin TTY: usar -y para confirmar."; exit "${JASPER_ERR_USAGE}"; }
    read -r -p "Sobrescribir ${juri} en ${JASPER_URL}? [s/N]: " r
    [[ "${r}" =~ ^[sS]$ ]] || { jasper_log "Cancelado."; exit 0; }
fi

# Metadatos actuales (label/description) para no perderlos
jenc="$(jasper_encode_uri "${juri}")"
jasper_curl -m 60 -H 'Accept: application/repository.file+json' -o "${tmpm}" -w '' "/rest_v2/resources${jenc}" >/dev/null

python3 -I -c '
import sys,json,base64
meta={}
try: meta=json.load(open(sys.argv[1]))
except Exception: pass
body={"label":meta.get("label") or "main_jrxml",
      "type":"jrxml",
      "content":base64.b64encode(open(sys.argv[2],"rb").read()).decode()}
if meta.get("description"): body["description"]=meta["description"]
json.dump(body,sys.stdout)
' "${tmpm}" "${archivo}" > "${tmpb}" || exit "${JASPER_ERR_UNEXPECTED}"

http="$(jasper_curl -X PUT -m 120 \
    -H 'Content-Type: application/repository.file+json' \
    -H 'Accept: application/repository.file+json' \
    --data-binary "@${tmpb}" -o "${tmpm}" -w '%{http_code}' "/rest_v2/resources${jenc}")"
jasper_check_session_expired "${http}" && exit "${JASPER_ERR_SESSION_EXPIRED}"
case "${http}" in
    200|201) jasper_ok "jrxml actualizado (HTTP ${http}). Backup: ${bdir}" ;;
    404) jasper_err "Recurso ${juri} no existe (404)."; exit "${JASPER_ERR_NOTFOUND}" ;;
    *)   jasper_err "PUT respondio HTTP ${http}: $(head -c 400 "${tmpm}")"; jasper_err "Backup disponible en ${bdir}"; exit "${JASPER_ERR_HTTP}" ;;
esac
