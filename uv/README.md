# uv setup & evaluation

[uv](https://docs.astral.sh/uv/)-based setup for DOMINO + PUMA, plus one-command
evaluation on fixed episode sets. Replaces the conda instructions; no upstream
workflow is changed.

Requirements: Linux GPU node, `uv`, CUDA toolkit (`nvcc`), Vulkan
(`vulkaninfo`), `ffmpeg`, `git`, `unzip`. Verified on A100 / CUDA 12.4 / Python 3.10.

DOMINO and PUMA cannot share a venv (torch 2.4.1+cu121 vs 2.6.0+cu124), so there
are two: `./.venv` (simulator) and `policy/PUMA/.venv` (policy), talking over a
WebSocket.

## Setup (in this order)

```bash
# 1. DOMINO venv: deps, sapien/mplib patches, CuRobo v0.7.8
bash uv/setup_domino.sh

# 2. assets, ~16 GB — needs the venv from step 1
source .venv/bin/activate
bash script/_download_assets.sh

# 3. verify
python script/test_render.py                             # -> "Render Well"
python -c "from envs.robot.robot import Robot; print('robot ok')"
grep -m1 urdf_path assets/embodiments/aloha-agilex/curobo_left.yml   # must show THIS repo's path

# 4. fixed-episode manifests, ~40 MB (see below)
bash uv/download_manifests.sh                            # -> "manifests: 35"

# 5. PUMA venv: torch 2.6, flash-attn, GroundingDINO + SAM2
bash uv/setup_puma.sh                                    # -> "... all import"

# 6. weights + released checkpoint, ~29 GB — must follow step 5
bash uv/download_weights_puma.sh                         # -> 7x "ok"
```

Hard ordering: 1 → 2 (assets need the venv) and 5 → 6 (the weight check expects
a config file that step 5 places). Steps 1 and 5 recreate their venv from
scratch every run; step 2 re-downloads if repeated.

## Evaluate

```bash
MANIFEST=auto bash uv/run_eval_puma.sh adjust_bottle demo_clean_dynamic
```

Starts the policy server (loading the 10 GB checkpoint takes a while), runs the
simulation, shuts the server down on exit. Results land in
`eval_result/<task>/.../<timestamp>/`: aggregate metrics (`_result.txt`,
`_metrics_report.txt`, `_metrics.json`, `_episodes_detail.json`) plus one
`episode<N>/` directory per episode with `video.mp4` and `info.json` (seed,
the exact language instruction, outcome, scores, object-motion parameters).

For many tasks, keep one server up and run clients against it:

```bash
bash uv/serve_puma.sh                                    # terminal 1, leave running
bash uv/eval_puma.sh <task> demo_clean_dynamic           # terminal 2, per task
```

## Fixed episodes

DOMINO's default protocol screens seeds online with a stochastic RRT expert
planner, so two runs accept different episode sets. A manifest pins the accepted
seeds and each episode's dynamic-motion state (start/end position, velocity,
RNG snapshot): every policy sees identical episodes, and eval skips the online
screening. `MANIFEST=auto` uses `eval_manifest/<task>/<config>/seed<seed>.pkl`.

Step 4 downloads pre-screened sets for all 35 tasks (100 episodes each,
`demo_clean_dynamic`, seed 0) from
[jungwoopark01/DOMINO-eval-manifest](https://huggingface.co/datasets/jungwoopark01/DOMINO-eval-manifest)
— ~12,400 expert-planner rollouts that you don't have to repeat. To
screen your own instead:

```bash
python script/screen_episodes.py --task_name <task> --task_config demo_clean_dynamic --seed 0
```

Note: physics replay is not bit-exact across machines; manifests remove
episode-set and initial-state drift, the dominant variance sources.

## Files

| | |
|---|---|
| `setup_domino.sh` / `setup_puma.sh` | build the two venvs |
| `constraints_domino.txt` / `constraints_puma.txt` | version pins, with the reason for each pin inline |
| `download_weights_puma.sh` | base VLM, SAM2 + GroundingDINO, released checkpoint |
| `download_manifests.sh` | fixed-episode manifests from HF |
| `run_eval_puma.sh` | server + sim in one command |
| `serve_puma.sh` / `eval_puma.sh` | the two halves, for long sessions |

Env knobs: `MANIFEST` (`auto` or a path), `CKPT`, `HOST`, `PORT`, `GPU_ID`,
`CUROBO_REF`, `REPO` (manifest source).
