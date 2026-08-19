#!/bin/bash
# PUMA policy server. Runs in the PUMA venv. Leave it up; eval clients connect to it.
#
#   bash uv/serve_puma.sh
#   CKPT=/abs/path/to/steps_100000_pytorch_model.pt PORT=9001 bash uv/serve_puma.sh
#
# Run from the repo root on a GPU node. Loading the checkpoint is slow.
# Keep this running across many uv/eval_puma.sh invocations -- reloading a 10 GB
# model per task would repeat that cost across the 35-task suite.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PUMA_DIR="$REPO_ROOT/policy/PUMA"

CKPT="${CKPT:-$PUMA_DIR/playground/PUMA_release/checkpoints/steps_100000_pytorch_model.pt}"
PORT="${PORT:-9001}"
GPU_ID="${GPU_ID:-0}"
DEVICE="${DEVICE:-cuda}"   # cuda | npu  (Ascend, see policy/PUMA/docs/ascend_inference.md)

# read_mode_config (PUMA/model/tools.py:168-178) asserts config.yaml and
# dataset_statistics.json sit at checkpoint.parents[1], i.e. the .pt must live in
# a <run_dir>/checkpoints/ subdirectory. Fail here rather than inside an assert.
RUN_DIR=$(cd "$(dirname "$CKPT")/.." 2>/dev/null && pwd || echo "")
for f in "$CKPT" "$RUN_DIR/config.yaml" "$RUN_DIR/dataset_statistics.json"; do
    [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 1; }
done

# The checkpoint's config.yaml also points at these. GroundingDINO_SwinT_OGC.py
# is placed by uv/setup_puma.sh -- it is NOT one of the downloads.
GS="$PUMA_DIR/playground/Pretrained_models/grounded_sam2"
for f in groundingdino_swint_ogc.pth sam2.1_hiera_large.pt GroundingDINO_SwinT_OGC.py; do
    [ -f "$GS/$f" ] || { echo "ERROR: missing $GS/$f" >&2; exit 1; }
done

cd "$PUMA_DIR"
source .venv/bin/activate
export PYTHONPATH="$PUMA_DIR:${PYTHONPATH:-}"
export CUDA_VISIBLE_DEVICES="$GPU_ID"

echo "ckpt : $CKPT"
echo "serve: 0.0.0.0:$PORT  device=$DEVICE  gpu=$GPU_ID"
echo

python deployment/model_server/server_policy.py \
    --ckpt_path "$CKPT" --port "$PORT" --device "$DEVICE" --use_bf16
