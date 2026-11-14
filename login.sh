#!/usr/bin/env bash
#
# login.sh - Login interactivo contra JasperReports Server (REST v2).
# Guarda la cookie JSESSIONID en .jasper-session (600) y el servidor usado
# en .jasper-hosts (600). NUNCA persiste la contrasena.
#
# Uso:  ./login.sh
# Salida: 0 OK | 10 servidor no alcanzable | 11 login fallido | 20 inesperado

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
command -v curl >/dev/null 2>&1 || { echo "[ERROR] Se requiere curl." >&2; exit 20; }
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/jasper-api.sh"

_parse_host() {
    local e="${1:-}"
    if [[ "${e}" == http://* || "${e}" == https://* ]]; then printf '%s\n' "${e%/}"
    else printf 'http://%s/jasperserver\n' "${e%/}"; fi
}

# Servidor: ultimo usado (JASPER_URL ya lo resuelve) como default.
# Orden de prompts (igual en tty y por stdin): servidor, usuario, password.
# Con stdin no-tty la primera linea es SIEMPRE el servidor (vacia = default).
if true; then
    mapfile -t _hist < <(jasper_hosts_list)
    if [[ ${#_hist[@]} -gt 1 ]]; then
        echo "Servidores usados:"
        for i in "${!_hist[@]}"; do printf '  [%d] %s\n' "$((i+1))" "${_hist[$i]}"; done
    fi
    _sel=""
    read -r -p "Servidor [${JASPER_URL}] (Enter, numero, o URL/host:puerto): " _sel || true
    if [[ -z "${_sel}" ]]; then :
    elif [[ "${_sel}" =~ ^[0-9]+$ ]] && (( _sel >= 1 && _sel <= ${#_hist[@]} )); then
        JASPER_URL="${_hist[$((_sel-1))]}"
    else JASPER_URL="$(_parse_host "${_sel}")"; fi
fi

if [[ "${JASPER_URL}" == *10.6.206.114* ]]; then
    jasper_log "AVISO: es el servidor de PRODUCCION; el toolkit esta pensado solo para desarrollo."
    if [[ -t 0 ]]; then
        read -r -p "Escribe 'PRODUCCION' para continuar: " _c
        [[ "${_c}" == "PRODUCCION" ]] || { jasper_err "Cancelado."; exit 11; }
    fi
fi

echo "=============================================================="
echo " Login persistente contra JasperReports Server"
echo " URL objetivo:      ${JASPER_URL}"
echo " Archivo de sesion: ${JASPER_COOKIE_JAR}"
echo "=============================================================="

info="$(jasper_check_reachable)" || { jasper_err "Servidor no alcanzable."; exit "${JASPER_ERR_HTTP}"; }
jasper_log "serverInfo: ${info}"

if jasper_has_session; then
    jasper_log "Ya existe una sesion valida."
    if [[ -t 0 ]]; then
        read -r -p "¿Renovar login de todas formas? [s/N]: " _r
        [[ "${_r}" =~ ^[sS]$ ]] || { jasper_hosts_add "${JASPER_URL}"; jasper_ok "Se mantiene la sesion."; exit 0; }
    else
        jasper_hosts_add "${JASPER_URL}"; exit 0
    fi
fi

jasper_login || { echo "RESULTADO: ERROR - login fallido"; exit "${JASPER_ERR_LOGIN}"; }
jasper_hosts_add "${JASPER_URL}"
jasper_has_session || { jasper_err "Login aparente OK pero la sesion no valida contra el servidor."; exit "${JASPER_ERR_LOGIN}"; }
jasper_ok "Sesion activa en ${JASPER_COOKIE_JAR}. Usa ./logout.sh para cerrarla."
exit 0
