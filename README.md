# Keryx Miner Docker

Docker image for mining Keryx (KRX) with the official
[`Keryx-Labs/keryx-miner`](https://github.com/Keryx-Labs/keryx-miner) miner.

The default image installs the official Linux amd64 release binary and its
`libkeryx*.so` plugin libraries into an NVIDIA CUDA 12.2 runtime image.

## Requirements

- Docker Engine with the NVIDIA Container Toolkit installed.
- Linux amd64 host for actual mining. The upstream release binary is amd64.
- NVIDIA driver 535 or newer on the host.
- A Keryx mining address such as `keryx:YOUR_ADDRESS`.

For OPoI GPU inference, the upstream miner expects CUDA 12 runtime libraries at
runtime. The CUDA runtime image includes the relevant CUDA 12.2 runtime stack.

## Build

Copy the example environment file and edit your wallet address:

```sh
cp .env.example .env
```

Build the image:

```sh
docker compose build
```

The default miner release is `v0.3.5-OPoI`. Override it in `.env` with
`KERYX_MINER_VERSION` and the matching `KERYX_MINER_SHA256` if you want a
different upstream release.

## Build, Push, And Run

These examples mirror the operational flow used by `pearl-docker-alpha`, but
for Keryx. Do not paste real GitHub personal access tokens into this repository
or commit them to disk. Use a token with the minimum package permissions needed,
and rotate any token that has been shared outside your password manager.

### Build And Push To GHCR

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_MINER_VERSION=v0.3.5-OPoI
KERYX_MINER_SHA256=c9770a52a7c41c4e17b20cb643b5e5c13e40b8bda9293a7d04e95c866c644b93

docker build --platform linux/amd64 \
  -t keryx-miner:${KERYX_MINER_VERSION} \
  --build-arg KERYX_MINER_VERSION=${KERYX_MINER_VERSION} \
  --build-arg KERYX_MINER_SHA256=${KERYX_MINER_SHA256} .

docker tag keryx-miner:${KERYX_MINER_VERSION} \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}

docker push ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

### Vast Host Docker Run

Use this form on hosts that expect the NVIDIA CDI device syntax.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_MINER_VERSION=v0.3.5-OPoI
docker pull ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION} &&
docker rm -f keryx-miner 2>/dev/null || true

docker run --rm \
  --runtime=runc \
  --device nvidia.com/gpu=all \
  --name keryx-miner \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_INFERENCE_TIER=default \
  -e KERYX_NO_OPOI=false \
  -e KERYX_GPU_PRESETS_URL=https://raw.githubusercontent.com/JoEasyCompute/keryx-miner-docker/main/examples/gpu-presets.csv \
  -e KERYX_GPU_PRESETS_SHA256=f5af787dde5e8558c13db2202c5c0b63de6d68b74ce647288fd77c5b87debab6 \
  -e KERYX_GPU_PRESETS_DRY_RUN=true \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

Set `KERYX_GPU_PRESETS_DRY_RUN=false` after the preset commands look correct in
the logs.

### Normal Host Docker Run

Use this form on ordinary Docker hosts with NVIDIA Container Toolkit.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_MINER_VERSION=v0.3.5-OPoI
docker pull ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION} &&
docker rm -f keryx-miner 2>/dev/null || true

docker run -d --restart unless-stopped --gpus all \
  --name keryx-miner \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_INFERENCE_TIER=default \
  -e KERYX_NO_OPOI=false \
  -e KERYX_GPU_PRESETS_URL=https://raw.githubusercontent.com/JoEasyCompute/keryx-miner-docker/main/examples/gpu-presets.csv \
  -e KERYX_GPU_PRESETS_SHA256=f5af787dde5e8558c13db2202c5c0b63de6d68b74ce647288fd77c5b87debab6 \
  -e KERYX_GPU_PRESETS_DRY_RUN=true \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

View logs:

```sh
docker logs -f keryx-miner
```

Stop mining:

```sh
docker rm -f keryx-miner
```

### Run On Specific GPUs

```sh
KERYX_MINER_VERSION=v0.3.5-OPoI

docker run -d --restart unless-stopped \
  --gpus '"device=0,1,2,3,4,5,7"' \
  --name keryx-miner \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_INFERENCE_TIER=default \
  -e KERYX_NO_OPOI=false \
  -e KERYX_GPU_PRESETS_URL=https://raw.githubusercontent.com/JoEasyCompute/keryx-miner-docker/main/examples/gpu-presets.csv \
  -e KERYX_GPU_PRESETS_SHA256=f5af787dde5e8558c13db2202c5c0b63de6d68b74ce647288fd77c5b87debab6 \
  -e KERYX_GPU_PRESETS_DRY_RUN=true \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

CSV presets match all GPUs visible to `nvidia-smi`; use Docker's
`--gpus '"device=..."'` flag to restrict visibility for both mining and preset
matching.

## Run

Start mining with Compose:

```sh
docker compose up -d
```

Follow logs:

```sh
docker compose logs -f
```

Stop mining:

```sh
docker compose down
```

## Runtime Configuration

Set these in `.env`:

| Variable | Default | Description |
| --- | --- | --- |
| `MINING_ADDRESS` | required | Keryx address passed as `--mining-address`. |
| `KERYX_INFERENCE_TIER` | `default` | Use `default`, `light`, `high`, or `very-high`. |
| `KERYX_NO_OPOI` | `false` | Set `true` for PoW-only mining with `--no-opoi`. |
| `KERYX_EXTRA_ARGS` | empty | Extra flags appended to the miner command. |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Select all GPUs or a comma-separated list such as `0,1`. |

You can also bypass the environment wrapper and pass a full miner command:

```sh
docker run --rm --gpus all keryx-miner:local \
  --mining-address keryx:YOUR_ADDRESS --no-opoi
```

## GPU Tuning

The container can apply GPU tuning before the miner starts when
`KERYX_GPU_TUNING=true`. This uses `nvidia-smi`, so the host must allow the
container to control the GPUs through the NVIDIA Container Toolkit.

Built-in presets:

| Preset | Effect |
| --- | --- |
| `none` | No tuning. |
| `efficiency` | Power limit at 70% of each GPU's default limit. |
| `balanced` | Power limit at 85% of each GPU's default limit. |
| `performance` | Power limit at 100% of each GPU's default limit. |
| `custom` | Only values explicitly set in `.env` are applied. |

Custom tuning variables:

| Variable | Description |
| --- | --- |
| `KERYX_GPU_DEVICES` | GPU indexes to tune, such as `0,1`. Defaults to `NVIDIA_VISIBLE_DEVICES`, then all GPUs. |
| `KERYX_GPU_POWER_LIMIT` | Absolute power limit in watts. |
| `KERYX_GPU_POWER_LIMIT_PERCENT` | Power limit as a percent of each GPU's default limit. |
| `KERYX_GPU_LOCK_CORE_CLOCK` | Locked graphics clock in MHz, such as `1500` or `1200:1500`. |
| `KERYX_GPU_LOCK_MEMORY_CLOCK` | Locked memory clock in MHz, such as `5001` or `5001:5001`. |
| `KERYX_GPU_RESET_CLOCKS_FIRST` | Reset locked clocks before applying new values. |
| `KERYX_GPU_TUNING_STRICT` | Set `true` to stop the container if tuning fails. |

Example:

```env
KERYX_GPU_TUNING=true
KERYX_GPU_PRESET=custom
KERYX_GPU_DEVICES=0,1
KERYX_GPU_POWER_LIMIT=320
KERYX_GPU_LOCK_CORE_CLOCK=1500
KERYX_GPU_TUNING_STRICT=true
```

### CSV GPU Presets

For mixed rigs or hosted fleets, the container can fetch or read a CSV preset
file at startup and apply the first row matching each GPU name from
`nvidia-smi`.

Enable a remote CSV:

```env
KERYX_GPU_PRESETS_URL=https://raw.githubusercontent.com/JoEasyCompute/keryx-miner-docker/main/examples/gpu-presets.csv
KERYX_GPU_PRESETS_SHA256=f5af787dde5e8558c13db2202c5c0b63de6d68b74ce647288fd77c5b87debab6
KERYX_GPU_PRESETS_DRY_RUN=true
```

The URL above points at the example CSV committed in this repository:
[examples/gpu-presets.csv](examples/gpu-presets.csv).

Or mount a local CSV:

```sh
docker run --rm --gpus all \
  -v "$PWD/examples/gpu-presets.csv:/etc/keryx/gpu-presets.csv:ro" \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_GPU_PRESETS_ENABLE=true \
  -e KERYX_GPU_PRESETS_DRY_RUN=true \
  keryx-miner:local
```

CSV schema:

```csv
enabled,algorithm,gpu_name_contains,power_limit_w,lock_core_clock_mhz,core_clock_offset_mhz,lock_memory_clock_mhz,memory_clock_offset_mhz,fan_speed_pct,delay_before_apply_s
true,keryx,RTX 5090,400,2490,200,7000,,,0
true,keryx,RTX 4090,360,2400,,7000,,,0
```

Rules:

- `gpu_name_contains` is a case-insensitive substring match against GPU names
  reported by `nvidia-smi`.
- First matching row wins.
- Empty fields are skipped.
- `KERYX_GPU_PRESETS_URL` enables CSV presets automatically.
- `KERYX_GPU_PRESETS_SHA256` is optional but recommended for remote CSVs.
- `KERYX_GPU_PRESETS_DRY_RUN=true` prints the commands without applying them.

Core and memory clock offsets are different from clock locks. On most GeForce
Linux hosts, offsets require host-side Coolbits/NV-CONTROL through
`nvidia-settings`, not plain `nvidia-smi`. The container exposes
`KERYX_GPU_CORE_CLOCK_OFFSET`, `KERYX_GPU_MEMORY_CLOCK_OFFSET`, and
`KERYX_GPU_USE_NVIDIA_SETTINGS=true` for rigs where you deliberately mount the
host X/NV-CONTROL setup into the container, but this is not enabled by default.

## Build From Source

The normal image uses upstream's release binary. If you need to compile a custom
miner build, use `Dockerfile.source`:

```sh
docker build -f Dockerfile.source \
  --build-arg KERYX_MINER_REF=v0.3.5-OPoI \
  --build-arg CUDA_COMPUTE_CAP=89 \
  -t keryx-miner:source .
```

Use `CUDA_COMPUTE_CAP=86` for RTX 30xx and `89` for RTX 40xx/50xx.

## Notes

- Do not set `CUDA_COMPUTE_CAP=100` for RTX 50xx when building with CUDA 12.2.
  Upstream recommends `89` so the PTX JIT-forwards on Blackwell cards.
- The upstream miner has a default development fund. Adjust it with
  `KERYX_EXTRA_ARGS="--devfund-percent 2.0"` if needed.
