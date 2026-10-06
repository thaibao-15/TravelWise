# ==========================================
# TravelWise Web (Next.js 16) Dockerfile
# Runtime: Bun on Alpine Linux
# Output: Standalone
# ==========================================

# 1. Base stage
FROM oven/bun:1-alpine AS base
WORKDIR /app

# 2. Dependencies stage
FROM base AS deps
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# 3. Builder stage
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build-time environment variables
ARG NEXT_PUBLIC_API_URL=http://localhost:8000
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production

# Build the Next.js application with standalone output
RUN bun run build

# 4. Production Runner stage
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME="0.0.0.0"

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy static assets and standalone build output
COPY --from=builder /app/public ./public

# In monorepos / workspaces, Next.js may nest standalone at ./ or ./apps/web
# Copy standalone bundle and static assets
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

# Check if server.js is at root or inside apps/web and start
CMD ["sh", "-c", "if [ -f server.js ]; then bun server.js; elif [ -f apps/web/server.js ]; then cd apps/web && bun server.js; else find . -name server.js -exec bun {} \\;; fi"]
