#!/usr/bin/env bash
#
# import-reporte.sh - Importa (descarga) un reportUnit y su .jrxml principal del servidor al disco local.
#   1) GET /rest_v2/resources<uri>  (Accept application/repository.reportUnit+json)
#   2) localiza jrxml.jrxmlFileReference.uri y descarga su contenido
# Salida en <dir>/<uri-saneada>/ : reportUnit.json, descriptor del jrxml
# (jrxml.meta.json si disponible) y <nombre>.jrxml. Default dir: ./reportes
#
# Uso: ./import-reporte.sh <uri-reportUnit> [-d <directorio-destino>]
# Codigos: 0 OK | 2 uso | 10 HTTP | 11 sin sesion | 12 no existe | 13 sesion
#          expirada | 15 XML mal formado | 20 inesperado
# Imprime por stdout la ruta del .jrxml descargado.

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/jasper-api.sh"

uri=""; destino="${JASPER_REPORTES_DIR}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) shift; destino="${1:-}" ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) uri="$1" ;;
    esac; shift
done
[[ -z "${uri}" || -z "${destino}" ]] && { echo "Uso: $0 <uri-reportUnit> [-d <dir>]" >&2; exit "${JASPER_ERR_USAGE}"; }
uri="$(jasper_norm_uri "${uri}")"

jasper_require_session || exit $?

rel="$(jasper_sanitize_path "${uri}")"
[[ -z "${rel}" ]] && { jasper_err "URI invalida: ${uri}"; exit "${JASPER_ERR_USAGE}"; }
out="${destino}/${rel}"
mkdir -p "${out}" || exit "${JASPER_ERR_UNEXPECTED}"

jasper_get_reportunit "${uri}" "${out}/reportUnit.json"; rc=$?
[[ ${rc} -ne 0 ]] && exit "${rc}"

juri="$(jasper_jrxml_uri_from_descriptor "${out}/reportUnit.json")"
if [[ -z "${juri}" ]]; then
    jasper_err "El descriptor no trae jrxmlFileReference.uri (jrxml inline?). Ver ${out}/reportUnit.json"
    exit "${JASPER_ERR_HTTP}"
fi
jasper_log "jrxml principal: ${juri}"
jenc="$(jasper_encode_uri "${juri}")"

# Metadatos del recurso file (label/description/type)
http="$(jasper_curl -m 60 -H 'Accept: application/repository.file+json' \
    -o "${out}/jrxml.meta.json" -w '%{http_code}' "/rest_v2/resources${jenc}")"
jasper_check_session_expired "${http}" && exit "${JASPER_ERR_SESSION_EXPIRED}"
[[ "${http}" != "200" ]] && { jasper_log "Metadatos del jrxml: HTTP ${http} (se continua)."; rm -f "${out}/jrxml.meta.json"; }

nombre="$(jasper_sanitize_path "${juri##*/}")"; nombre="${nombre:-main_jrxml}"
[[ "${nombre}" != *.jrxml ]] && nombre="${nombre}.jrxml"
tmpf="$(mktemp)"; trap 'rm -f "${tmpf}"' EXIT

# Contenido binario del file resource: Accept application/octet-stream
http="$(jasper_curl -m 120 -H 'Accept: application/octet-stream' \
    -o "${tmpf}" -w '%{http_code}' "/rest_v2/resources${jenc}")"
jasper_check_session_expired "${http}" && exit "${JASPER_ERR_SESSION_EXPIRED}"
if [[ "${http}" != "200" ]]; then
    jasper_err "Descarga del jrxml respondio HTTP ${http}."; exit "${JASPER_ERR_HTTP}"
fi
if ! jasper_xml_check "${tmpf}"; then
    jasper_err "El contenido descargado no es XML valido (revisar Accept/endpoint)."
    exit "${JASPER_ERR_XML}"
fi
cp "${tmpf}" "${out}/${nombre}"
printf '%s\n' "${juri}" > "${out}/jrxml.uri"
jasper_ok "Importado en ${out}/"
printf '%s\n' "${out}/${nombre}"
