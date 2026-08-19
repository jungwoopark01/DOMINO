#!/bin/bash
# Fixed-episode evaluation manifests -> ./eval_manifest/
#
#   bash uv/download_manifests.sh
#   REPO=you/your-manifests bash uv/download_manifests.sh
#
# Run from the repo root. ~40 MB, no login needed for a public dataset.
#
# These are pre-screened episode sets: 35 tasks x 100 expert-solvable episodes,
# each pinned to a seed AND that episode's dynamic-motion state (target object,
# start/end position, velocity, duration, RNG snapshot). Every policy evaluated
# against them sees identical physics, which the default protocol cannot give you
# -- it screens seeds online with a stochastic RRT planner, so two runs accept
# different episode sets.
#
# Producing them took ~12,400 expert-planner rollouts.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

REPO="${REPO:-jungwoopark01/DOMINO-eval-manifest}"

# Any venv with huggingface_hub works. Prefer DOMINO's, fall back to PUMA's.
for c in "$REPO_ROOT/.venv/bin/python" "$REPO_ROOT/policy/PUMA/.venv/bin/python"; do
    if [ -x "$c" ] && "$c" -c "import huggingface_hub" 2>/dev/null; then PY="$c"; break; fi
done
: "${PY:?no venv with huggingface_hub found -- run uv/setup_domino.sh first}"

echo "==> $REPO -> eval_manifest/"

# allow_patterns is not optional: the dataset also has its own README.md at the
# root, which would otherwise overwrite DOMINO's. Using the python API rather
# than the CLI because the command was renamed huggingface-cli -> hf in 0.34.
REPO="$REPO" "$PY" - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id=os.environ["REPO"],
    repo_type="dataset",
    local_dir=".",
    allow_patterns=["eval_manifest/*"],
)
PY

n=$(ls eval_manifest/*/*/seed*.pkl 2>/dev/null | wc -l)
echo
echo "manifests: $n"
[ "$n" -gt 0 ] || { echo "ERROR: nothing downloaded" >&2; exit 1; }

# The dataset must not have touched anything tracked.
if git rev-parse --git-dir >/dev/null 2>&1 && ! git diff --quiet -- README.md 2>/dev/null; then
    echo "WARNING: README.md was modified -- restore it with: git checkout README.md" >&2
fi

cat <<'EOF'

use them with:
  MANIFEST=auto bash uv/run_eval_puma.sh <task> <task_config>

e.g. click_bell is the cheapest task to sanity-check with:
  MANIFEST=auto bash uv/run_eval_puma.sh click_bell demo_clean_dynamic
EOF
