# TalbotIQ API — Cloud Run image.
# Build context is the talbotiq-platform/ directory:  docker build -f server/Dockerfile -t talbotiq-api .
FROM node:20-slim

WORKDIR /app

# Install deps (the server shares the project's package.json).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev || npm install --omit=dev
# tsx is needed to run the TypeScript server directly.
RUN npm install tsx

# App source (server + shared contract).
COPY shared ./shared
COPY server ./server
COPY tsconfig.json ./

ENV NODE_ENV=production
# Cloud Run provides PORT; the server reads process.env.PORT.
ENV PORT=8080
EXPOSE 8080

CMD ["npx", "tsx", "server/index.ts"]
