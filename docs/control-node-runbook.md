# Keryx Control Node Runbook

This runbook covers operating the central `keryxd` node used by GPU miner
servers. It focuses on sync stages, miner behavior during sync, monitoring,
backup, and moving a synced node to another host.

## Architecture

A typical fleet has one central node and many GPU miner hosts:

```text
gpu-server-01 \
gpu-server-02  ->  central keryxd node  ->  Keryx P2P network
gpu-server-03 /
```

Miners can connect directly to `keryxd`:

```env
KERYX_NODE_URL=grpc://YOUR_CONTROL_NODE_HOST:22110
```

Or miners can connect through a stratum bridge:

```env
KERYX_NODE_URL=stratum+tcp://YOUR_BRIDGE_HOST:5555
```

The central node must be fully caught up before mined blocks can be submitted
successfully. Until then, the miner may initialize, build OPoI/GPU state, or
hash briefly, but `keryxd` can still reject submissions with `node is not
synced`.

## Sync Stages

`keryxd` uses the term IBD for more than one stage. The log percentage can
appear to reset because the node moves from one kind of work to another.

### 1. Header Download

Example log:

```text
IBD: Processed 1206794 block headers (100%)
Header download stage of IBD with headers proof completed successfully ...
```

This means the node has completed the header stage only. It is not yet fully
usable for mining.

### 2. Pruning Point UTXO Set

Example logs:

```text
downloading the pruning point utxoset, this can take a little while.
Finished receiving the UTXO set. Total UTXOs: ...
Importing the UTXO set of the pruning point ...
```

This stage downloads and imports the UTXO set used as the starting point for
catch-up. It can take minutes and writes a large amount of data.

### 3. Block Body Validation And Catch-Up

Example log:

```text
IBD: Processed 12177 blocks (1%) last block timestamp: ...
IBD: Processed 350163 blocks (29%) last block timestamp: ...
```

This is the stage where the node validates and applies historical block bodies
from the pruning point toward the current tip. This is still IBD, but it is not
the same as the earlier header percentage. Mining submissions are still rejected
until this reaches the current tip and the node reports itself as synced.

## Miner Behavior During Sync

During node sync, the miner can show a few different states:

```text
Workers stalled or crashed. Consider reducing workload and check that your node is synced
Keryxd is not synced, skipping current template
OPoI inference in progress - PoW paused, stand by
Current hashrate is ...
Failed submitting block: ... node is not synced
```

These messages are expected while the node is still in IBD. They do not
necessarily mean the GPU preset, CUDA runtime, or miner binary is broken.

The miner is only truly productive when:

- `keryxd` has finished IBD and accepts submitted blocks.
- The miner reports hashrate without repeated `node is not synced` submission
  failures.
- GPUs show actual utilization while mining.

## Check Sync Progress

On the control node host:

```sh
docker logs -f keryx-node | grep 'IBD: Processed'
```

To inspect recent node progress without following logs:

```sh
docker logs --since 10m keryx-node 2>&1 \
  | grep -E 'IBD: Processed|Processed [0-9]+ blocks|completed|synced' \
  | tail -60
```

Useful signs that the node is healthy:

- IBD percentage increases over time.
- The `last block timestamp` moves forward.
- `Processed ... blocks` continues to appear.
- `docker inspect keryx-node` shows `RestartCount=0` or no unexpected
  restarts.
- Disk has enough free space.

Check container status and resources:

```sh
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
docker inspect keryx-node --format 'RestartCount={{.RestartCount}} StartedAt={{.State.StartedAt}}'
docker stats --no-stream keryx-node
df -h
```

If the IBD percentage does not move for 20-30 minutes, or the logs show repeated
errors, panics, database failures, or peer failures, then treat it as a node
problem. If the percentage is moving, let it continue.

## Check Miner Status

On a GPU miner host:

```sh
docker logs -f keryx-miner \
  | grep -E 'Current hashrate|Failed submitting block|Submitted|accepted|node is not synced|Workers stalled'
```

Check GPU activity:

```sh
nvidia-smi --query-gpu=index,utilization.gpu,power.draw,memory.used \
  --format=csv,noheader,nounits
```

If the miner reports `node is not synced`, fix or wait for the control node
first. Restarting miners will not make a syncing node accept blocks.

## Persistent Node Data

The node stores chain data under `/data` inside the container. This repository's
compose files mount that path from either:

- The default Docker volume `keryx-node-data`.
- A bind-mounted host directory provided through `KERYX_NODE_DATA_SOURCE`.

Do not remove this volume or directory unless you intentionally want to resync
from scratch.

For production, prefer a persistent host path or external disk:

```sh
mkdir -p /mnt/keryx-node-data
KERYX_NODE_DATA_SOURCE=/mnt/keryx-node-data \
docker compose -f docker-compose.control.yml up -d --build
```

Use the same `KERYX_NODE_DATA_SOURCE` every time you recreate the control node.

## Back Up A Synced Node Volume

Stop the node before copying database files. Copying RocksDB while `keryxd` is
running can create an inconsistent backup.

For the default named volume:

```sh
docker stop keryx-node

docker run --rm \
  -v keryx-node-data:/data:ro \
  -v "$PWD:/backup" \
  ubuntu:22.04 \
  tar -C /data -czf /backup/keryx-node-data.tgz .

docker start keryx-node
```

For a bind-mounted directory:

```sh
docker stop keryx-node
tar -C /mnt/keryx-node-data -czf keryx-node-data.tgz .
docker start keryx-node
```

## Move The Control Node To Another Host

1. Stop the old node.

```sh
docker stop keryx-node
```

2. Archive the data.

```sh
docker run --rm \
  -v keryx-node-data:/data:ro \
  -v "$PWD:/backup" \
  ubuntu:22.04 \
  tar -C /data -czf /backup/keryx-node-data.tgz .
```

3. Copy `keryx-node-data.tgz` to the new host.

4. Restore into a Docker volume on the new host.

```sh
docker volume create keryx-node-data

docker run --rm \
  -v keryx-node-data:/data \
  -v "$PWD:/backup" \
  ubuntu:22.04 \
  tar -C /data -xzf /backup/keryx-node-data.tgz
```

5. Start the node on the new host with the restored volume mounted to `/data`.

```sh
docker run -d --restart unless-stopped \
  --name keryx-node \
  -v keryx-node-data:/data \
  -p 22110:22110 \
  -p 22111:22111 \
  -e KERYXD_APPDIR=/data \
  -e KERYXD_RPCLISTEN=0.0.0.0:22110 \
  -e KERYXD_LISTEN=0.0.0.0:22111 \
  ghcr.io/joeasycompute/keryx-node:v1.3.1-OPoI
```

6. Point GPU miners or the bridge at the new control node address.

Direct miner mode:

```env
KERYX_NODE_URL=grpc://NEW_CONTROL_NODE_HOST:22110
```

Bridge mode:

```env
KERYX_BRIDGE_KERYXD_ADDRESS=grpc://NEW_CONTROL_NODE_HOST:22110
KERYX_NODE_URL=stratum+tcp://NEW_BRIDGE_HOST:5555
```

After moving, the node may still catch up recent blocks, but it should not need
to redo the full header download, UTXO download, and block validation stages if
the backup was consistent.

## Operational Notes

- Do not expose gRPC or bridge ports broadly on the public internet.
- Restrict `22110` to GPU servers or bridge hosts that need it.
- Restrict `5555` to miner hosts if using the bridge.
- Keep `22111` reachable only as needed for P2P connectivity.
- Do not run `docker volume rm keryx-node-data` unless you are deliberately
  deleting chain state.
- Do not restart the node during active IBD unless logs show a real failure; a
  restart usually slows sync down.
