#!/bin/bash
# DOMINO simulation environment -> ./.venv    (uv replacement for script/_install.sh)
#
#   bash uv/setup_domino.sh
#
# Run from the repo root on a GPU node. Recreates ./.venv every time.
# Assets are separate: `bash script/_download_assets.sh` afterwards.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

CUROBO_REF=${CUROBO_REF:-v0.7.8}
CONSTRAINTS="$REPO_ROOT/uv/constraints_domino.txt"

# --seed: without it the venv has no pip, and later `pip`/`pip show` calls
# silently hit the system pip.
uv venv --python 3.10 --seed --clear
source .venv/bin/activate

uv pip install -r script/requirements.txt

# setuptools 81 removed pkg_resources, which sapien/__init__.py:2 hard-imports.
uv pip install "setuptools<81" ninja

# --- patch sapien + mplib in site-packages (upstream does this too) ---------
# These live in the venv, not the repo, so recreating the venv reverts them.
SP=$(python -c 'import sysconfig;print(sysconfig.get_paths()["purelib"])')

# sapien: utf-8 when reading urdf/srdf
sed -i -E 's/("r")(\))( as)/\1, encoding="utf-8") as/g' "$SP/sapien/wrapper/urdf_loader.py"

# mplib: drop the `or collide` early-return in the screw planner. Unpatched,
# expert planning fails constantly during collection and eval screening.
sed -i -E 's/(if np.linalg.norm\(delta_twist\) < 1e-4 )(or collide )(or not within_joint_limit:)/\1\3/g' \
    "$SP/mplib/planner.py"

# Fail loudly if either sed matched nothing.
grep -q 'encoding="utf-8"' "$SP/sapien/wrapper/urdf_loader.py"
grep -q 'delta_twist) < 1e-4 or not within_joint_limit' "$SP/mplib/planner.py"

# --- CuRobo ----------------------------------------------------------------
# Required: CuroboPlanner is defined inside the try block at
# envs/robot/planner.py:13, so without it envs/robot/robot.py:15 fails to import.
# v0.8.0 deleted src/curobo/types/ and cannot work here.
[ -d envs/curobo/.git ] || git clone https://github.com/NVlabs/curobo.git envs/curobo
( cd envs/curobo && git fetch --tags -q && git checkout -q "$CUROBO_REF" && git clean -xfdq )

# CuRobo deps that script/requirements.txt does not provide. Constrained because
# its setup.cfg:50 asks for an unpinned torch>=1.10 and warp-lang>=0.9.0.
uv pip install -c "$CONSTRAINTS" \
    pybind11 numpy-quaternion setuptools_scm importlib_resources \
    scikit-image "yourdfpy>=0.0.53" "warp-lang>=0.9.0"

# --no-deps: --no-build-isolation only controls the BUILD env, not runtime
# resolution. Without it uv installs torch 2.13+cu13 and the build fails.
uv pip install -e envs/curobo --no-build-isolation --no-deps

# The PUMA websocket client runs in THIS venv.
uv pip install -c "$CONSTRAINTS" -r policy/PUMA/examples/Robotwin/eval_files/requirements.txt

cat <<'EOF'

done. next, in YOUR shell:

  source .venv/bin/activate
  bash script/_download_assets.sh
EOF
