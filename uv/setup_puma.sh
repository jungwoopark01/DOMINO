#!/bin/bash
# PUMA policy environment -> policy/PUMA/.venv
#
#   bash uv/setup_puma.sh
#
# Run from the repo root on a GPU node. Recreates policy/PUMA/.venv every time.
# Weights are separate -- see the message printed at the end.
#
# Separate venv from DOMINO's ./.venv by necessity: DOMINO pins torch 2.4.1
# (cu121), PUMA needs 2.6.0 (cu124). Upstream recommends exactly this split.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PUMA_DIR="$REPO_ROOT/policy/PUMA"
GS_DIR="$PUMA_DIR/PUMA/model/modules/grounding_sam"
CONSTRAINTS="$REPO_ROOT/uv/constraints_puma.txt"

cd "$PUMA_DIR"

uv venv --python 3.10 --seed --clear
source .venv/bin/activate

# No --index-url needed: torchvision==0.21.0 forces torch 2.6.0, whose default
# PyPI wheel is already cu124. uv warns that transformers==4.57.0 is YANKED --
# install it anyway, the yank is a packaging defect and PUMA targets that exact
# version (PUMA/model/modules/vlm/ascend/qwen3_inference.py:28).
uv pip install -r requirements.txt

# --no-build-isolation: flash-attn's setup.py imports torch. Usually fetches a
# prebuilt wheel for torch 2.6 / py310 / cu12; without one it compiles from source.
uv pip install -c "$CONSTRAINTS" --no-build-isolation flash-attn==2.7.4.post1

# --- GroundingDINO ----------------------------------------------------------
# Its requirements.txt lists `transformers` unpinned, and `supervision>=0.22.0`
# resolves to 0.30.0 which needs av>=14.2 -- silently bumping av past the 12.3.0
# PUMA's dataloader expects. The constraints file holds both.
cd "$GS_DIR/grounding_dino"
uv pip install -c "$CONSTRAINTS" -r requirements.txt
uv pip install -c "$CONSTRAINTS" --no-build-isolation -e .
python setup.py build_ext --inplace     # expect "Compiling with CUDA"

# --- SAM2 -------------------------------------------------------------------
# SAM2_BUILD_ALLOW_ERRORS defaults to "1" (setup.py:15), which SWALLOWS a failed
# CUDA build and ships a package with no sam2._C. Force it loud.
cd "$GS_DIR"
SAM2_BUILD_ALLOW_ERRORS=0 uv pip install -c "$CONSTRAINTS" --no-build-isolation -e .

# pyproject.toml has `dependencies = []`, so this just registers the package.
cd "$PUMA_DIR"
uv pip install -c "$CONSTRAINTS" -e .

# The checkpoint's config.yaml points grounding_dino_config at this file, but the
# README never says to place it -- without it the policy server dies at startup.
# mkdir -p so this works whether or not the weights are downloaded yet.
mkdir -p playground/Pretrained_models/grounded_sam2
cp "$GS_DIR/grounding_dino/groundingdino/config/GroundingDINO_SwinT_OGC.py" \
   playground/Pretrained_models/grounded_sam2/

# torch must be imported before the extensions: both link libc10.so, so importing
# them standalone raises "libc10.so: cannot open shared object file".
python -c "
import torch, groundingdino._C, sam2._C, PUMA
print(f'torch {torch.__version__}  cuda {torch.version.cuda}  gpu {torch.cuda.is_available()}')
print('groundingdino._C, sam2._C, PUMA all import')"

cat <<'EOF'

done. next, download weights into policy/PUMA/playground/Pretrained_models/:

  cd policy/PUMA/playground/Pretrained_models
  hf download StarVLA/Qwen3-VL-4B-Instruct-Action --local-dir Qwen3-VL-4B-Instruct-Action
  cd grounded_sam2
  wget https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt
  wget https://github.com/IDEA-Research/GroundingDINO/releases/download/v0.1.0-alpha/groundingdino_swint_ogc.pth

and a trained checkpoint (or train your own):

  cd policy/PUMA/playground
  hf download H-EmbodVis/PUMA --local-dir PUMA_release --exclude "log/*"
EOF
