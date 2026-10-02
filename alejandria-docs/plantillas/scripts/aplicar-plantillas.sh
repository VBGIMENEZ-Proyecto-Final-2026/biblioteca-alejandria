#!/usr/bin/env bash
# Uso: ./aplicar-plantillas.sh /ruta/al/repo-local usuario/repo [--con-milestones]
set -euo pipefail

DESTINO="${1:?Falta la ruta del repo local}"
REPO="${2:?Falta usuario/repo}"
EXTRA="${3:-}"

AQUI="$(cd "$(dirname "$0")" && pwd)"
ORIGEN="$AQUI/.."

[[ -d "$DESTINO/.git" ]] || { echo "Error: $DESTINO no es un repo git" >&2; exit 1; }

mkdir -p "$DESTINO/.github"
cp -r "$ORIGEN/.github/." "$DESTINO/.github/"
"$AQUI/bootstrap-repo.sh" "$REPO" $EXTRA

echo "Plantillas copiadas a $DESTINO. Revisá el diff y hacé un commit propio."
