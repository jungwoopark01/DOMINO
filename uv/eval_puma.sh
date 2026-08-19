#!/bin/bash
# DOMINO simulation client. Runs in the DOMINO venv, against a running server.
# Start uv/serve_puma.sh first, in another terminal.
#
#   bash uv/eval_puma.sh adjust_bottle demo_clean_dynamic
#   bash uv/eval_puma.sh <task> <task_config> [ckpt_setting] [seed] [gpu_id]
#
#   MANIFEST=auto  bash uv/eval_puma.sh ...   # fixed-episode mode, see below
#   MANIFEST=<path> ...
#
# BOTH sides need the checkpoint: the server loads the weights, and this client
# calls read_mode_config for action/state normalization stats
# (model2robotwin_interface.py:91-93).
#
# Results -> eval_result/<task>/model2robotwin_interface/<config>/<setting>/<ts>/

set -euo pipefail

TASK_NAME=${1:?usage: bash uv/eval_puma.sh <task> <task_config> [ckpt_setting] [seed] [gpu_id]}
TASK_CONFIG=${2:?missing task_config, e.g. demo_clean_dynamic}
CKPT_SETTING=${3:-puma}
SEED=${4:-0}
GPU_ID=${5:-0}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PUMA_DIR="$REPO_ROOT/policy/PUMA"
EVAL_FILES="$PUMA_DIR/examples/Robotwin/eval_files"
CKPT="${CKPT:-$PUMA_DIR/playground/PUMA_release/checkpoints/steps_100000_pytorch_model.pt}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-9001}"

cd "$REPO_ROOT"
source .venv/bin/activate

# Guard against running this in the PUMA venv -- both exist, and the failure
# otherwise is a confusing sapien/curobo ImportError.
python -c "import sapien, curobo" 2>/dev/null || {
    echo "ERROR: run this in the DOMINO venv ($REPO_ROOT/.venv). Got: ${VIRTUAL_ENV:-none}" >&2
    exit 1; }

# repo root for envs/ + script/, PUMA_DIR for PUMA.* and deployment.*, EVAL_FILES
# so eval_policy.py:47 can import_module("model2robotwin_interface") by name.
export PYTHONPATH="$REPO_ROOT:$PUMA_DIR:$EVAL_FILES:${PYTHONPATH:-}"
export CUDA_VISIBLE_DEVICES="$GPU_ID"

# eval_policy.py:489 merges --overrides into the config with a flat update(), so
# policy_ckpt_path beats the /path/to/... placeholder in deploy_policy.yml and no
# upstream file needs editing.
overrides=(
    --task_name "$TASK_NAME" --task_config "$TASK_CONFIG"
    --ckpt_setting "$CKPT_SETTING" --seed "$SEED"
    --policy_name model2robotwin_interface
    --policy_ckpt_path "$CKPT" --host "$HOST" --port "$PORT"
)

# Fixed-episode mode. Default is the RoboTwin protocol: seeds screened online by
# the stochastic RRT expert planner, so two runs accept different episode sets. A
# manifest pins the seeds AND each episode's dynamic motion + RNG state, so every
# policy sees identical physics. Build one with script/screen_episodes.py.
MANIFEST="${MANIFEST:-}"
[ "$MANIFEST" = "auto" ] && MANIFEST="eval_manifest/$TASK_NAME/$TASK_CONFIG/seed${SEED}.pkl"
if [ -n "$MANIFEST" ]; then
    [ -f "$MANIFEST" ] || {
        echo "ERROR: no manifest at $MANIFEST" >&2
        echo "  python script/screen_episodes.py --task_name $TASK_NAME --task_config $TASK_CONFIG --seed $SEED" >&2
        exit 1; }
    echo "manifest: $MANIFEST"
    overrides+=(--episode_manifest "$MANIFEST")
fi

echo "task    : $TASK_NAME / $TASK_CONFIG   seed=$SEED  gpu=$GPU_ID"
echo "server  : $HOST:$PORT"
echo

PYTHONWARNINGS=ignore::UserWarning \
python script/eval_policy.py --config "$EVAL_FILES/deploy_policy.yml" --overrides "${overrides[@]}"
