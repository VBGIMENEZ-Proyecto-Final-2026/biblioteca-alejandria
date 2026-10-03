#!/usr/bin/env bash
# Uso: ./bootstrap-repo.sh usuario/repo [--con-milestones]
set -euo pipefail

REPO="${1:?Falta usuario/repo}"
CON_MILESTONES="${2:-}"

LABELS=(
  "tarea:0e8a16" "bug:d73a4a" "consulta:d4c5f9"
  "atlas:1d76db" "cronos:5319e7" "hermes:fbca04"
  "docs:c5def5" "infra:ededed" "seguridad:b60205"
  "tests:bfd4f2" "bloqueante:000000"
  "integracion:006b75" "contrato:d4c5f9" "robustez:e99695"
  "evidencia:fef2c0" "consulta-profe:ff9f1c"
)

for l in "${LABELS[@]}"; do
  gh label create "${l%%:*}" --color "${l##*:}" --repo "$REPO" --force
done

# Los milestones son opcionales: si se usa Iteration en el board Odisea,
# son trabajo duplicado. Fallan si ya existen: correr una sola vez por repo.
if [[ "$CON_MILESTONES" == "--con-milestones" ]]; then
  MILESTONES=(
    "Isla 0 · Ítaca" "Isla 1 · Eolia" "Isla 2 · Ogigia"
    "Isla 3 · Escila y Caribdis" "Isla 4 · Regreso a Ítaca"
  )
  for m in "${MILESTONES[@]}"; do
    gh api "repos/$REPO/milestones" -f title="$m" >/dev/null
  done
fi

echo "Listo: $REPO"
