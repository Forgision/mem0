# syntax=docker.io/docker/dockerfile:1

# Base stage for common setup
FROM node:18-alpine AS base

# Install dependencies for pnpm
RUN apk add --no-cache libc6-compat curl && \
    PNPM_VERSION="9.15.0" && \
    curl -4 -L "https://registry.npmjs.org/pnpm/-/pnpm-${PNPM_VERSION}.tgz" -o /tmp/pnpm.tgz && \
    npm install -g /tmp/pnpm.tgz && \
    rm /tmp/pnpm.tgz

# Configure pnpm to prefer IPv4
RUN echo "network-family=ipv4" > /root/.npmrc && \
    echo "fetch-retries=5" >> /root/.npmrc && \
    echo "fetch-retry-mintimeout=10000" >> /root/.npmrc

ENV NODE_OPTIONS="--dns-result-order=ipv4first"

WORKDIR /app

FROM base AS deps

COPY package.json pnpm-lock.yaml ./

RUN pnpm install --frozen-lockfile

FROM base AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY . .

RUN cp next.config.dev.mjs next.config.mjs
RUN pnpm build

FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

COPY --chown=nextjs:nodejs entrypoint.sh /home/nextjs/entrypoint.sh
RUN chmod +x /home/nextjs/entrypoint.sh

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

ENTRYPOINT ["/home/nextjs/entrypoint.sh"]
CMD ["node", "server.js"]
