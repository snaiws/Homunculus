# ============================================================
# Homunculus Dockerfile
# ============================================================
# OpenClaw 기반 + Homunculus 플러그인 + 워크스페이스
# ============================================================

FROM node:22-bookworm

# --- Build tools ---
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

# --- System packages ---
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git \
      curl \
      jq \
      python3 \
      python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# --- Build OpenClaw ---
WORKDIR /app/openclaw
RUN chown -R node:node /app

COPY --chown=node:node openclaw/package.json openclaw/pnpm-lock.yaml openclaw/pnpm-workspace.yaml ./
COPY --chown=node:node openclaw/.npmrc* ./
COPY --chown=node:node openclaw/ui/package.json ./ui/package.json
COPY --chown=node:node openclaw/patches ./patches
COPY --chown=node:node openclaw/scripts ./scripts

USER node
RUN NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile

USER root
COPY --chown=node:node openclaw/ .

USER node
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# --- Expose OpenClaw CLI ---
USER root
RUN ln -sf /app/openclaw/openclaw.mjs /usr/local/bin/openclaw \
    && chmod 755 /app/openclaw/openclaw.mjs

# --- Install Homunculus plugin dependencies ---
WORKDIR /app/plugin
COPY --chown=node:node plugin/package.json ./
RUN if [ -f package.json ] && grep -q '"dependencies"' package.json 2>/dev/null; then \
      npm install --omit=dev 2>/dev/null || true; \
    fi

# --- Copy Homunculus files ---
COPY --chown=node:node plugin/ /app/plugin/
COPY --chown=node:node config/ /app/config/
COPY --chown=node:node workspace/ /app/workspace/
COPY --chown=node:node docker/entrypoint.sh /app/entrypoint.sh

USER root
RUN chmod +x /app/entrypoint.sh

# --- Prepare directories ---
RUN mkdir -p /home/node/.openclaw/workspace \
    && mkdir -p /home/node/.openclaw/extensions \
    && chown -R node:node /home/node/.openclaw

ENV NODE_ENV=production
ENV HOME=/home/node

USER node
WORKDIR /app

EXPOSE 18789 18790

ENTRYPOINT ["/app/entrypoint.sh"]
