#!/bin/bash
# PUMA weights -> policy/PUMA/playground/
#
#   bash uv/download_weights_puma.sh              # base models + released checkpoint (~29 GB)
#   NO_CKPT=1 bash uv/download_weights_puma.sh    # base models only (~20 GB), if you train your own
#
# Run from the repo root. Resumable: rerunning skips what is already complete.
#
# Downloads three things:
#   Qwen3-VL-4B-Instruct-Action   base VLM the architecture is built on   ~8.3 GB
#   grounded_sam2/*.pt,*.pth      SAM2 + GroundingDINO weights            ~1.5 GB
#   PUMA_release/                 trained checkpoint, for evaluation      ~9.4 GB
#
# The huggingface CLI is named `huggingface-cli` in hf_hub <0.34 and `hf` after,
# so this uses the Python API instead and works with either.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLAYGROUND="$REPO_ROOT/policy/PUMA/playground"
PRETRAINED="$PLAYGROUND/Pretrained_models"

# Any venv with huggingface_hub works. Prefer PUMA's, fall back to DOMINO's.
for c in "$REPO_ROOT/policy/PUMA/.venv/bin/python" "$REPO_ROOT/.venv/bin/python"; do
    if [ -x "$c" ] && "$c" -c "import huggingface_hub" 2>/dev/null; then PY="$c"; break; fi
done
: "${PY:?no venv with huggingface_hub found -- run uv/setup_domino.sh or uv/setup_puma.sh first}"

mkdir -p "$PRETRAINED/grounded_sam2"

echo "==> Qwen3-VL-4B-Instruct-Action (~8.3 GB)"
LOCAL_DIR="$PRETRAINED/Qwen3-VL-4B-Instruct-Action" "$PY" - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download("StarVLA/Qwen3-VL-4B-Instruct-Action", local_dir=os.environ["LOCAL_DIR"])
PY

echo "==> SAM2 + GroundingDINO weights (~1.5 GB)"
cd "$PRETRAINED/grounded_sam2"
wget -nc -q --show-progress https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt
wget -nc -q --show-progress https://github.com/IDEA-Research/GroundingDINO/releases/download/v0.1.0-alpha/groundingdino_swint_ogc.pth

if [ -z "${NO_CKPT:-}" ]; then
    echo "==> PUMA_release trained checkpoint (~9.4 GB)"
    # `log/*` is ~140 files of the authors' own eval results -- not needed.
    # Layout matters: read_mode_config (PUMA/model/tools.py:168-178) asserts that
    # config.yaml and dataset_statistics.json sit at checkpoint.parents[1], so the
    # .pt must stay inside checkpoints/.
    LOCAL_DIR="$PLAYGROUND/PUMA_release" "$PY" - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download("H-EmbodVis/PUMA", local_dir=os.environ["LOCAL_DIR"], ignore_patterns=["log/*"])
PY
fi

# GroundingDINO_SwinT_OGC.py is placed by uv/setup_puma.sh -- it ships in the
# repo rather than being downloaded, and the checkpoint's config.yaml requires it.
cd "$REPO_ROOT"
echo
echo "==> verifying"
fail=0
for f in "$PRETRAINED/Qwen3-VL-4B-Instruct-Action/config.json" \
         "$PRETRAINED/grounded_sam2/sam2.1_hiera_large.pt" \
         "$PRETRAINED/grounded_sam2/groundingdino_swint_ogc.pth" \
         "$PRETRAINED/grounded_sam2/GroundingDINO_SwinT_OGC.py"; do
    [ -f "$f" ] && printf '  ok      %s\n' "${f#"$REPO_ROOT"/}" || { printf '  MISSING %s\n' "${f#"$REPO_ROOT"/}"; fail=1; }
done
if [ -z "${NO_CKPT:-}" ]; then
    for f in "$PLAYGROUND/PUMA_release/checkpoints/steps_100000_pytorch_model.pt" \
             "$PLAYGROUND/PUMA_release/config.yaml" \
             "$PLAYGROUND/PUMA_release/dataset_statistics.json"; do
        [ -f "$f" ] && printf '  ok      %s\n' "${f#"$REPO_ROOT"/}" || { printf '  MISSING %s\n' "${f#"$REPO_ROOT"/}"; fail=1; }
    done
fi
exit $fail
