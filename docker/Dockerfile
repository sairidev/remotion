# syntax=docker/dockerfile:1.7
#
# Remotion egg (Pterodactyl / Pelican ready)
#
# Build dari ROOT repository:
#   docker build -f docker/Dockerfile -t remotion-egg .
#
# Image ini sudah berisi Node.js, library untuk Chrome Headless Shell, font,
# dan project template lengkap dengan node_modules + Chrome. Server panel
# tinggal menyalin template ke /home/container, tanpa npm install atau download.

ARG NODE_IMAGE=node:22-bookworm-slim
FROM ${NODE_IMAGE}

LABEL org.opencontainers.image.title="remotion-egg" \
      org.opencontainers.image.description="Remotion dengan menu bernomor, banner dan auto start untuk Pterodactyl" \
      maintainer="sairidev@gmail.com"

ENV DEBIAN_FRONTEND=noninteractive \
    USER=container \
    HOME=/home/container \
    PROJECT_DIR=/home/container \
    REMOTION_TEMPLATE=/opt/remotion/template \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    TZ=UTC

# Baris 1: alat umum. Baris 2-3: library yang dibutuhkan Chrome Headless Shell
# (daftar dari dokumentasi Remotion). Baris 4: font, termasuk emoji.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates git procps iproute2 tzdata jq nano util-linux \
        libnss3 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 libgbm1 libasound2 \
        libxrandr2 libxkbcommon0 libxfixes3 libxcomposite1 libxdamage1 libpango-1.0-0 libcairo2 libcups2 \
        fontconfig fonts-liberation fonts-noto-core fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# Project template + dependencies + Chrome Headless Shell (masuk ke node_modules/.remotion)
COPY template/ /opt/remotion/template/
RUN cd /opt/remotion/template \
    && npm ci --no-audit --no-fund \
    && npx remotion browser ensure \
    && npm cache clean --force \
    && rm -rf /root/.npm /tmp/* \
    && chmod -R a+rX /opt/remotion

COPY docker/lib.sh /usr/local/lib/remotion/lib.sh
COPY docker/menu.sh /usr/local/bin/remotion-menu
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod 0755 /usr/local/bin/remotion-menu /entrypoint.sh \
    && chmod 0644 /usr/local/lib/remotion/lib.sh \
    && useradd -m -d /home/container -s /bin/bash container

USER container
WORKDIR /home/container

# Project, hasil render (out/) dan file sementara (.tmp/) ada di /home/container.
# Pterodactyl otomatis memasang volume di sana.
EXPOSE 3000

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
