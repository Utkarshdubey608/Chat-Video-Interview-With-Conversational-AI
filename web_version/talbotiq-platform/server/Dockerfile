# TalbotIQ API — container image for Render.
# Build context is the talbotiq-platform/ directory:
#   docker build -f server/Dockerfile -t talbotiq-api .
FROM node:20-slim

WORKDIR /app
ENV NODE_ENV=production

# Dependencies first, so this layer caches across source-only edits.
# `npm ci` is strict on purpose: if package-lock.json has drifted, fail loudly
# here rather than silently resolving different versions in production.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Source: the server, the shared contract it imports, and the tsconfig.
# The SPA (src/, public/) is NOT part of this image — Vercel serves it.
COPY tsconfig.json ./
COPY shared ./shared
COPY server ./server

# Render mounts its Persistent Disk here (see render.yaml). Without DATA_DIR the
# JSON store would sit on the container's ephemeral filesystem and be discarded
# on every deploy and restart.
ENV DATA_DIR=/var/data
RUN mkdir -p /var/data && chown -R node:node /var/data

USER node

# Render injects PORT and expects the process to bind it. 8787 is the local
# default that server/index.ts falls back to.
ENV PORT=8787
EXPOSE 8787

CMD ["npx", "tsx", "server/index.ts"]
