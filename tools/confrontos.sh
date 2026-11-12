#!/usr/bin/env bash
# Tabela de confrontos entre classes, rodando os 6 pares em paralelo.
#   GODOT=/caminho/do/godot tools/confrontos.sh [partidas_por_par]
# Bot difícil x bot difícil, já com classe, sem itens. Mostra cada confronto
# e a porcentagem de vitórias de cada classe.
set -e
GODOT="${GODOT:-godot}"
N="${1:-12}"
DIR="$(mktemp -d)"
cd "$(dirname "$0")/.."
for par in "0 1" "0 2" "0 3" "1 2" "1 3" "2 3"; do
  set -- $par
  "$GODOT" --headless --fixed-fps 60 --path . -s tools/teste.gd -- --confrontos "$N" --par "$1" "$2" \
    > "$DIR/par_$1_$2.log" 2>&1 &
done
wait
cat "$DIR"/par_*.log | grep '^PAR ' | awk -v n="$N" '
  { printf "%-8s x %-8s : %2d x %-2d  (duração média %ss, %s foram à Morte Súbita)\n", $2, $3, $4, $5, $6, $7; v[$2]+=$4; v[$3]+=$5 }
  END { print "--- vitórias (" n*3 " partidas por classe)";
        for (c in v) printf "%-8s %3d%%\n", c, 100*v[c]/(n*3) }'
rm -rf "$DIR"
