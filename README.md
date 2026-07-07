# Keryx Miner Docker

Docker image for mining Keryx (KRX) with the official
[`Keryx-Labs/keryx-miner`](https://github.com/Keryx-Labs/keryx-miner) miner.

The default image installs the official Linux amd64 release binary and keeps its
`libkeryx*.so` plugin libraries beside the binary, because the miner discovers
workers by scanning its current directory.

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

The default miner release is `v0.3.6-OPoI`. Override it in `.env` with
`KERYX_MINER_VERSION` and the matching `KERYX_MINER_SHA256` if you want a
different upstream release.

For the H3 hard fork release line, pair miner `v0.3.6-OPoI` with node
`v1.3.1-OPoI`.

## Build, Push, And Run

These examples mirror the operational flow used by `pearl-docker-alpha`, but
for Keryx. Do not paste real GitHub personal access tokens into this repository
or commit them to disk. Use a token with the minimum package permissions needed,
and rotate any token that has been shared outside your password manager.

### Build And Push To GHCR

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_MINER_VERSION=v0.3.6-OPoI
KERYX_MINER_SHA256=f107d3d81d797836badeb9f79eca4486caa6947da40cd3ea1ae9bf6ab7d131f9

docker build --platform linux/amd64 \
  -t keryx-miner:${KERYX_MINER_VERSION} \
  --build-arg KERYX_MINER_VERSION=${KERYX_MINER_VERSION} \
  --build-arg KERYX_MINER_SHA256=${KERYX_MINER_SHA256} .

docker tag keryx-miner:${KERYX_MINER_VERSION} \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}

docker push ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

### Build And Push Keryx Node To GHCR

Build this image for the central `keryxd` node host. Use an immutable commit
SHA for `KERYX_NODE_REF` when you want reproducible fleet deployments.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_NODE_REF=v1.3.1-OPoI
KERYX_NODE_IMAGE_TAG=v1.3.1-OPoI

docker build --platform linux/amd64 \
  -f Dockerfile.node \
  -t keryx-node:${KERYX_NODE_IMAGE_TAG} \
  --build-arg KERYX_NODE_REF=${KERYX_NODE_REF} .

docker tag keryx-node:${KERYX_NODE_IMAGE_TAG} \
  ghcr.io/joeasycompute/keryx-node:${KERYX_NODE_IMAGE_TAG}

docker push ghcr.io/joeasycompute/keryx-node:${KERYX_NODE_IMAGE_TAG}
```

### Run Keryx Node From GHCR

Run this on the central node server. Expose gRPC only to your GPU servers and
P2P only where needed for node connectivity.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_NODE_IMAGE_TAG=v1.3.1-OPoI
docker pull ghcr.io/joeasycompute/keryx-node:${KERYX_NODE_IMAGE_TAG} &&
docker rm -f keryx-node 2>/dev/null || true

docker run -d --restart unless-stopped \
  --name keryx-node \
  -v keryx-node-data:/data \
  -p 22110:22110 \
  -p 22111:22111 \
  -e KERYXD_APPDIR=/data \
  -e KERYXD_RPCLISTEN=0.0.0.0:22110 \
  -e KERYXD_LISTEN=0.0.0.0:22111 \
  ghcr.io/joeasycompute/keryx-node:${KERYX_NODE_IMAGE_TAG}
```

For testnet, also publish `22210` and `22211`, then set:

```sh
-e KERYXD_EXTRA_ARGS=--testnet
```

### Build And Push Keryx Bridge To GHCR

Build this image when you want a stratum endpoint in front of the central
`keryxd` node.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_BRIDGE_REF=main
KERYX_BRIDGE_IMAGE_TAG=main

docker build --platform linux/amd64 \
  -f Dockerfile.bridge \
  -t keryx-bridge:${KERYX_BRIDGE_IMAGE_TAG} \
  --build-arg KERYX_BRIDGE_REF=${KERYX_BRIDGE_REF} .

docker tag keryx-bridge:${KERYX_BRIDGE_IMAGE_TAG} \
  ghcr.io/joeasycompute/keryx-bridge:${KERYX_BRIDGE_IMAGE_TAG}

docker push ghcr.io/joeasycompute/keryx-bridge:${KERYX_BRIDGE_IMAGE_TAG}
```

### Run Keryx Bridge From GHCR

Run this near the node when miners should connect to stratum instead of direct
gRPC.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_BRIDGE_IMAGE_TAG=main
docker pull ghcr.io/joeasycompute/keryx-bridge:${KERYX_BRIDGE_IMAGE_TAG} &&
docker rm -f keryx-bridge 2>/dev/null || true

docker run -d --restart unless-stopped \
  --name keryx-bridge \
  -p 5555:5555 \
  -p 2114:2114 \
  ghcr.io/joeasycompute/keryx-bridge:${KERYX_BRIDGE_IMAGE_TAG} \
  --log=false \
  --keryxd=grpc://YOUR_KERYXD_HOST:22110 \
  --stats=false \
  --prom=2114
```

GPU miners can then use:

```sh
-e KERYX_NODE_URL=stratum+tcp://YOUR_BRIDGE_HOST:5555
```

### Vast Host Docker Run

Use this form on hosts that expect the NVIDIA CDI device syntax.

```sh
GHCR_PAT=<your_github_token>
echo "$GHCR_PAT" | docker login ghcr.io -u joeasycompute --password-stdin

KERYX_MINER_VERSION=v0.3.6-OPoI
docker pull ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION} &&
docker rm -f keryx-miner 2>/dev/null || true

docker run --rm \
  --runtime=runc \
  --device nvidia.com/gpu=all \
  --name keryx-miner \
  -v keryx-data:/data \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_NODE_URL=grpc://YOUR_KERYXD_HOST:22110 \
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

KERYX_MINER_VERSION=v0.3.6-OPoI
docker pull ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION} &&
docker rm -f keryx-miner 2>/dev/null || true

docker run -d --restart unless-stopped --gpus all \
  --name keryx-miner \
  -v keryx-data:/data \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_NODE_URL=grpc://YOUR_KERYXD_HOST:22110 \
  -e KERYX_INFERENCE_TIER=default \
  -e KERYX_NO_OPOI=false \
  -e KERYX_GPU_PRESETS_URL=https://raw.githubusercontent.com/JoEasyCompute/keryx-miner-docker/main/examples/gpu-presets.csv \
  -e KERYX_GPU_PRESETS_SHA256=f5af787dde5e8558c13db2202c5c0b63de6d68b74ce647288fd77c5b87debab6 \
  -e KERYX_GPU_PRESETS_DRY_RUN=true \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

To apply GPU presets for real on a trusted self-managed host, change
`KERYX_GPU_PRESETS_DRY_RUN=false`. If the NVIDIA driver reports
`Insufficient Permissions` for `nvidia-smi -pl`, `-lgc`, or `-lmc`, recreate
the container with Docker privileges, for example by adding `--privileged` to
the `docker run` command. Hosted GPU providers may block these controls; keep
dry-run enabled there and apply clocks through the provider or host OS instead.

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
KERYX_MINER_VERSION=v0.3.6-OPoI

docker run -d --restart unless-stopped \
  --gpus '"device=0,1,2,3,4,5,7"' \
  --name keryx-miner \
  -v keryx-data:/data \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_NODE_URL=grpc://YOUR_KERYXD_HOST:22110 \
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

## Fleet Deployment

For multiple GPU servers, run the Keryx node once on a central server and keep
the GPU hosts as miner-only workers. This is especially useful when your
`keryxd` node sits in a different network: route miners to that private endpoint
over your VPN, private WAN, Tailscale/WireGuard, or site-to-site link instead of
running a node on every rig.

Recommended topology:

```text
keryx-node network:
  keryxd central node
  optional keryx-stratum-bridge

gpu network:
  gpu-server-01 -> grpc://central-node:22110
  gpu-server-02 -> grpc://central-node:22110
  gpu-server-03 -> grpc://central-node:22110
```

If direct gRPC from every GPU host to the node is inconvenient, run the stratum
bridge near the node and point miners at the bridge:

```text
gpu servers -> stratum+tcp://bridge-host:5555 -> keryxd
```

Do not expose node or bridge ports broadly on the public internet. Restrict
access with firewall rules or a private overlay network.

### Control Node With Bridge

Use this on the control-plane machine when you want one host to run both the
central `keryxd` node and the stratum bridge. In this compose file, the bridge
talks to the node through Docker DNS at `grpc://keryx-node:22110`.

```sh
docker compose -f docker-compose.control.yml up -d --build
docker compose -f docker-compose.control.yml logs -f keryx-node keryx-bridge
```

The control host publishes:

| Port | Service | Purpose |
| --- | --- | --- |
| `22110` | `keryx-node` | Mainnet gRPC for direct miner connections or bridge access. |
| `22111` | `keryx-node` | Mainnet P2P. |
| `5555` | `keryx-bridge` | Stratum endpoint for GPU miners. |
| `2114` | `keryx-bridge` | Prometheus metrics when bridge metrics are enabled. |

GPU servers can point at the control host directly:

```sh
-e KERYX_NODE_URL=grpc://YOUR_CONTROL_NODE_HOST:22110
```

Or point at the bridge on the same control host:

```sh
-e KERYX_NODE_URL=stratum+tcp://YOUR_CONTROL_NODE_HOST:5555
```

If the bridge runs on a different machine from the node, set
`KERYX_BRIDGE_KERYXD_ADDRESS=grpc://YOUR_KERYXD_HOST:22110` before starting the
bridge.

### Central Node

Build and run a central `keryxd` node:

```sh
docker compose -f docker-compose.node.yml up -d --build
docker compose -f docker-compose.node.yml logs -f keryx-node
```

The node compose file persists data in the `keryx-node-data` volume. By default
it binds `keryxd` to `0.0.0.0:22110` for mainnet gRPC and `0.0.0.0:22111` for
mainnet P2P. It also maps testnet gRPC/P2P ports `22210` and `22211` for
operators who enable testnet through `KERYXD_EXTRA_ARGS=--testnet`. If the node
runs in another network, expose only the needed ports to your GPU servers and
peers.

### Optional Stratum Bridge

Run this on the node side of the network when you prefer a single stratum
endpoint for the fleet:

```sh
KERYX_BRIDGE_KERYXD_ADDRESS=grpc://YOUR_KERYXD_HOST:22110 \
docker compose -f docker-compose.bridge.yml up -d --build
```

The bridge exposes stratum on port `5555`. GPU hosts can then use:

```sh
-e KERYX_NODE_URL=stratum+tcp://YOUR_BRIDGE_HOST:5555
```

### GPU Server Template

For direct node mode:

```sh
KERYX_MINER_VERSION=v0.3.6-OPoI
docker pull ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION} &&
docker rm -f keryx-miner 2>/dev/null || true

docker run -d --restart unless-stopped --gpus all \
  --name keryx-miner \
  -v keryx-data:/data \
  -e MINING_ADDRESS=keryx:YOUR_ADDRESS \
  -e KERYX_NODE_URL=grpc://YOUR_KERYXD_HOST:22110 \
  -e KERYX_INFERENCE_TIER=default \
  -e KERYX_GPU_PRESETS_URL=https://raw.githubusercontent.com/JoEasyCompute/keryx-miner-docker/main/examples/gpu-presets.csv \
  -e KERYX_GPU_PRESETS_SHA256=f5af787dde5e8558c13db2202c5c0b63de6d68b74ce647288fd77c5b87debab6 \
  -e KERYX_GPU_PRESETS_DRY_RUN=true \
  ghcr.io/joeasycompute/keryx-miner:${KERYX_MINER_VERSION}
```

Set `KERYX_GPU_PRESETS_DRY_RUN=false` only after confirming the commands in the
logs. If the host rejects power or clock changes, add `--privileged` on trusted
self-managed GPU servers, or leave tuning to the host/provider.

For bridge mode, replace `KERYX_NODE_URL` with:

```sh
-e KERYX_NODE_URL=stratum+tcp://YOUR_BRIDGE_HOST:5555
```

Use [examples/fleet.env](examples/fleet.env) as the baseline environment file
for rolling the same settings across multiple GPU servers.

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

The image uses `/data` for persistent runtime state. Keep a volume mounted there
so OPoI model downloads plus `escrow.key` and `escrow_state.json` survive
container recreation. The miner starts from `/opt/keryx/bin` so it can discover
its GPU worker plugins; only the model directory and escrow file paths are
redirected into `/data`.

Default OPoI mode downloads multi-GB model files on first startup. This can make
the container look idle for a while even though it is still running.

The miner also needs a reachable Keryx endpoint. Upstream defaults to
`127.0.0.1:22110`, which means "inside the container", so this wrapper requires
an explicit endpoint by default. Set one of:

```env
KERYX_NODE_URL=grpc://YOUR_KERYXD_HOST:22110
# or
KERYX_NODE_URL=stratum+tcp://YOUR_POOL_HOST:YOUR_POOL_PORT
# or
KERYXD_ADDRESS=YOUR_KERYXD_HOST
KERYXD_PORT=22110
# or
KERYX_POOL_HOST=YOUR_POOL_HOST
KERYX_POOL_PORT=YOUR_POOL_PORT
```

If `keryxd` runs on the Docker host, add
`--add-host=host.docker.internal:host-gateway` to `docker run` and set
`KERYX_NODE_URL=grpc://host.docker.internal:22110`. Use
`KERYX_ALLOW_LOCAL_KERYXD_DEFAULT=true` only if `keryxd` runs inside this same
container.

## Runtime Configuration

Set these in `.env`:

| Variable | Default | Description |
| --- | --- | --- |
| `MINING_ADDRESS` | required | Keryx address passed as `--mining-address`. |
| `KERYX_NODE_URL` | required | Full endpoint passed as `--keryxd-address`, such as `grpc://HOST:22110` or `stratum+tcp://POOL:PORT`. |
| `KERYXD_ADDRESS` | empty | Alternative keryxd host passed as `--keryxd-address`. |
| `KERYXD_PORT` | empty | Optional keryxd port passed as `--port`; mainnet is usually `22110`. |
| `KERYX_POOL_HOST` | empty | Alternative stratum pool host. Requires `KERYX_POOL_PORT`. |
| `KERYX_POOL_PORT` | empty | Stratum pool port used with `KERYX_POOL_HOST`. |
| `KERYX_ALLOW_LOCAL_KERYXD_DEFAULT` | `false` | Set `true` only to allow the upstream container-local `127.0.0.1` default. |
| `KERYX_INFERENCE_TIER` | `default` | Use `default`, `light`, `high`, or `very-high`. |
| `KERYX_NO_OPOI` | `false` | `true` exits with a clear error because the OPoI miner release has no `--no-opoi` flag. |
| `KERYX_ESCROW_KEY_FILE` | `/data/escrow.key` | Escrow key path inside the container. |
| `KERYX_ESCROW_STATE_FILE` | `/data/escrow_state.json` | Escrow state path inside the container. |
| `KERYX_EXTRA_ARGS` | empty | Extra flags appended to the miner command. |
| `NVIDIA_VISIBLE_DEVICES` | `all` | Select all GPUs or a comma-separated list such as `0,1`. |

You can also bypass the environment wrapper and pass a full miner command:

```sh
docker run --rm --gpus all keryx-miner:local \
  --mining-address keryx:YOUR_ADDRESS \
  --keryxd-address grpc://YOUR_KERYXD_HOST:22110
```

## GPU Tuning

The container can apply GPU tuning before the miner starts when
`KERYX_GPU_TUNING=true`. This uses `nvidia-smi`, so the host must allow the
container to control the GPUs through the NVIDIA Container Toolkit.

The examples default to `KERYX_GPU_PRESETS_DRY_RUN=true` so a fleet rollout can
verify matches without changing clocks. To apply settings, set
`KERYX_GPU_PRESETS_DRY_RUN=false`. On self-managed hosts where the driver still
rejects `nvidia-smi` power or clock changes from Docker, run the miner container
with `--privileged`, or set `KERYX_GPU_TUNING_PRIVILEGED=true` when using
`docker compose`. Do not enable privileged containers on shared or untrusted
hosts.

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
  --build-arg KERYX_MINER_REF=v0.3.6-OPoI \
  --build-arg CUDA_COMPUTE_CAP=89 \
  -t keryx-miner:source .
```

Use `CUDA_COMPUTE_CAP=86` for RTX 30xx and `89` for RTX 40xx/50xx.

## Notes

- Do not set `CUDA_COMPUTE_CAP=100` for RTX 50xx when building with CUDA 12.2.
  Upstream recommends `89` so the PTX JIT-forwards on Blackwell cards.
- The upstream miner has a default development fund. Adjust it with
  `KERYX_EXTRA_ARGS="--devfund-percent 2.0"` if needed.
