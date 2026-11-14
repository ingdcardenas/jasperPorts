#!/usr/bin/env bash
#
# logout.sh - Cierra la sesion y borra la cookie (unico script que la borra).
# Uso: ./logout.sh   | Salida: 0 siempre salvo 20 (sin curl)

set -uo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
command -v curl >/dev/null 2>&1 || { echo "[ERROR] Se requiere curl." >&2; exit 20; }
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/jasper-api.sh"
jasper_logout
exit 0
