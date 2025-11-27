# Multi-stage Dockerfile for CIP-113 Programmable Tokens Frontend
# Creates optimized production build with Node.js server

# Stage 1: Dependencies
FROM node:20-alpine AS deps
WORKDIR /app

# Copy package files
COPY package.json package-lock.json ./

# Install dependencies
RUN npm ci

# Stage 2: Builder
FROM node:20-alpine AS builder
WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy source code
COPY . .

# Build arguments for environment variables
ARG NEXT_PUBLIC_NETWORK=preview
ARG NEXT_PUBLIC_BLOCKFROST_API_KEY
ARG NEXT_PUBLIC_BLOCKFROST_URL

# Set environment variables for build
ENV NEXT_PUBLIC_NETWORK=${NEXT_PUBLIC_NETWORK}
ENV NEXT_PUBLIC_BLOCKFROST_API_KEY=${NEXT_PUBLIC_BLOCKFROST_API_KEY}
ENV NEXT_PUBLIC_BLOCKFROST_URL=${NEXT_PUBLIC_BLOCKFROST_URL}
ENV NODE_ENV=production

# Build the application
RUN npm run build

# Stage 3: Runner
FROM node:20-alpine AS runner
WORKDIR /app

# Install only production dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Copy necessary files from builder
COPY --from=builder /app/next.config.js ./
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs && \
    chown -R nextjs:nodejs /app

# Switch to non-root user
USER nextjs

# Expose port
EXPOSE 3000

# Environment
ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Labels
LABEL org.opencontainers.image.title="CIP-113 Programmable Tokens Frontend"
LABEL org.opencontainers.image.description="Web interface for CIP-113 programmable tokens on Cardano"

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Start Next.js server
CMD ["npm", "start"]
