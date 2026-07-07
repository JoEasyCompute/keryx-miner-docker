ARG CUDA_VERSION=12.2.2
ARG UBUNTU_VERSION=22.04
ARG KERYX_IMAGE_PLATFORM=linux/amd64

FROM --platform=${KERYX_IMAGE_PLATFORM} ubuntu:${UBUNTU_VERSION} AS downloader

ARG KERYX_MINER_VERSION=v0.3.5-OPoI
ARG KERYX_MINER_SHA256=c9770a52a7c41c4e17b20cb643b5e5c13e40b8bda9293a7d04e95c866c644b93

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/keryx

RUN curl -fsSL \
        "https://github.com/Keryx-Labs/keryx-miner/releases/download/${KERYX_MINER_VERSION}/keryx-miner-${KERYX_MINER_VERSION}-linux-gnu-amd64.zip" \
        -o keryx-miner.zip \
    && echo "${KERYX_MINER_SHA256}  keryx-miner.zip" | sha256sum -c - \
    && unzip keryx-miner.zip \
    && install -D -m 0755 keryx-miner /opt/keryx/bin/keryx-miner \
    && install -D -m 0644 libkeryxcuda.so /opt/keryx/lib/libkeryxcuda.so \
    && install -D -m 0644 libkeryxopencl.so /opt/keryx/lib/libkeryxopencl.so

FROM --platform=${KERYX_IMAGE_PLATFORM} nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS runtime

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    LD_LIBRARY_PATH=/opt/keryx/lib:$LD_LIBRARY_PATH \
    PATH=/opt/keryx/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=downloader /opt/keryx /opt/keryx
COPY docker-entrypoint.sh /usr/local/bin/keryx-entrypoint
COPY gpu-tune.sh /usr/local/bin/keryx-gpu-tune
COPY gpu-presets.sh /opt/keryx/gpu-presets.sh
COPY examples/gpu-presets.csv /etc/keryx/gpu-presets.example.csv

RUN mkdir -p /data \
    && rm -rf /opt/keryx/bin/models \
    && ln -s /data/models /opt/keryx/bin/models

WORKDIR /data
VOLUME ["/data"]

ENTRYPOINT ["keryx-entrypoint"]
