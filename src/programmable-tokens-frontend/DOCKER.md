# Docker Deployment Guide

This guide explains how to build and deploy the CIP-113 Programmable Tokens Frontend using Docker.

## Overview

The application uses a **build-time parameter strategy** where each network (preview, preprod, mainnet) gets its own Docker image with environment variables baked in at build time. This results in:

- ✅ Smaller, optimized images
- ✅ Faster startup times
- ✅ Better security (no runtime configuration exposure)
- ✅ CDN-friendly static assets

## Prerequisites

- Docker installed (version 20.10+)
- Docker Compose installed (version 2.0+)
- Blockfrost API keys for your target network(s)

## Quick Start

### 1. Set Up Environment Variables

Copy the example environment file:

```bash
cp .env.docker.example .env.docker
```

Edit `.env.docker` and add your Blockfrost API keys:

```bash
BLOCKFROST_PREVIEW_API_KEY=preview...
BLOCKFROST_PREPROD_API_KEY=preprod...
BLOCKFROST_MAINNET_API_KEY=mainnet...
```

### 2. Build for a Specific Network

Using the build script (recommended):

```bash
# Build for preview (default)
./build-docker.sh preview

# Build for preprod
./build-docker.sh preprod

# Build for mainnet
./build-docker.sh mainnet

# Build ALL networks at once
./build-docker.sh all

# Build all and push to Docker Hub
./build-docker.sh all --push
```

**Image Tags Created:**

For each build, two tags are created:
- `easy1staking/cip113-frontend:<git-tag>-<network>` (e.g., `v1.0.0-preview`)
- `easy1staking/cip113-frontend:<network>` (e.g., `preview`)

For mainnet, an additional tag is created:
- `easy1staking/cip113-frontend:latest`

Or manually with Docker:

```bash
# Get git version
GIT_TAG=$(git describe --tags --always --dirty)

# Build with version tag
docker build \
  --build-arg NEXT_PUBLIC_NETWORK=preview \
  --build-arg NEXT_PUBLIC_BLOCKFROST_API_KEY=your_key_here \
  --build-arg NEXT_PUBLIC_BLOCKFROST_URL=https://cardano-preview.blockfrost.io/api/v0 \
  -t easy1staking/cip113-frontend:${GIT_TAG}-preview \
  -t easy1staking/cip113-frontend:preview \
  .
```

### 3. Run the Container

**Single container:**

```bash
# Run preview network on port 3000
docker run -p 3000:3000 easy1staking/cip113-frontend:preview

# Run specific version
docker run -p 3000:3000 easy1staking/cip113-frontend:v1.0.0-preview

# Run preprod network on port 3001
docker run -p 3001:3000 easy1staking/cip113-frontend:preprod

# Run mainnet network on port 3002
docker run -p 3002:3000 easy1staking/cip113-frontend:mainnet
```

**With Docker Compose:**

```bash
# Run preview (default)
docker-compose up frontend-preview

# Run preprod
docker-compose --profile preprod up frontend-preprod

# Run mainnet
docker-compose --profile mainnet up frontend-mainnet

# Run all networks at once
docker-compose --profile preprod --profile mainnet up
```

## Docker Compose Configuration

The `docker-compose.yml` file defines three services:

- `frontend-preview` - Port 3000 (default, always available)
- `frontend-preprod` - Port 3001 (requires `--profile preprod`)
- `frontend-mainnet` - Port 3002 (requires `--profile mainnet`)

Each service builds its own image with network-specific configuration.

## Image Details

### Multi-Stage Build

The Dockerfile uses a 3-stage build process:

1. **deps** - Installs dependencies
2. **builder** - Builds the Next.js application
3. **runner** - Creates minimal runtime image

### Image Size

- **Final image**: ~200-250 MB (Node.js Alpine + Next.js)
- **Build cache**: ~500 MB (development dependencies)

### Security

- Runs as non-root user (`nextjs`)
- Only production dependencies included
- No unnecessary files copied
- Regular security scans with `docker scan cip113-frontend:preview`

## Health Checks

All containers include health checks:

```bash
# Check container health
docker ps

# View health check logs
docker inspect --format='{{json .State.Health}}' cip113-frontend-preview
```

## Environment Variables

### Build-Time (ARG)

These are baked into the image at build time:

- `NEXT_PUBLIC_NETWORK` - Network name (preview/preprod/mainnet)
- `NEXT_PUBLIC_BLOCKFROST_API_KEY` - Blockfrost API key
- `NEXT_PUBLIC_BLOCKFROST_URL` - Blockfrost API endpoint

### Runtime (ENV)

These can be overridden at runtime (though not recommended):

- `NODE_ENV` - Always `production`
- `PORT` - Server port (default: 3000)
- `HOSTNAME` - Server hostname (default: 0.0.0.0)

## Production Deployment

### Using Docker Compose

```bash
# Build and start in detached mode
docker-compose up -d frontend-preview

# View logs
docker-compose logs -f frontend-preview

# Stop
docker-compose down
```

### Using Docker Swarm

```bash
# Initialize swarm
docker swarm init

# Deploy stack
docker stack deploy -c docker-compose.yml cip113

# Check services
docker service ls

# Remove stack
docker stack rm cip113
```

### Using Kubernetes

Create deployment YAML:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cip113-frontend-preview
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cip113-frontend
      network: preview
  template:
    metadata:
      labels:
        app: cip113-frontend
        network: preview
    spec:
      containers:
      - name: frontend
        image: cip113-frontend:preview
        ports:
        - containerPort: 3000
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

## Troubleshooting

### Build Fails

**Problem**: Build fails with "API key not found"

**Solution**: Check that `.env.docker` exists and contains valid API keys

### Container Won't Start

**Problem**: Container exits immediately

**Solution**: Check logs:

```bash
docker logs cip113-frontend-preview
```

### Port Already in Use

**Problem**: "port is already allocated"

**Solution**: Change the port mapping:

```bash
docker run -p 4000:3000 cip113-frontend:preview
```

### WASM Warnings

**Problem**: WASM-related warnings in logs

**Solution**: These are expected and non-blocking. The Mesh SDK uses WASM for Cardano operations.

## Advanced Configuration

### Custom Networks

To add a custom network:

1. Update `docker-compose.yml` with new service
2. Add API key to `.env.docker`
3. Update `build-docker.sh` with network case

### Nginx Reverse Proxy

Example nginx config:

```nginx
server {
    listen 80;
    server_name cip113.example.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### Resource Limits

Limit container resources:

```bash
docker run \
  --memory="512m" \
  --cpus="0.5" \
  -p 3000:3000 \
  cip113-frontend:preview
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Build Docker Images

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        network: [preview, preprod, mainnet]
    steps:
      - uses: actions/checkout@v3

      - name: Build image
        run: |
          docker build \
            --build-arg NEXT_PUBLIC_NETWORK=${{ matrix.network }} \
            --build-arg NEXT_PUBLIC_BLOCKFROST_API_KEY=${{ secrets.BLOCKFROST_KEY }} \
            -t cip113-frontend:${{ matrix.network }} \
            .
```

## Monitoring

### Logs

```bash
# Follow logs
docker logs -f cip113-frontend-preview

# Last 100 lines
docker logs --tail 100 cip113-frontend-preview

# Logs since timestamp
docker logs --since 2024-01-01T00:00:00 cip113-frontend-preview
```

### Metrics

```bash
# Container stats
docker stats cip113-frontend-preview

# Detailed inspection
docker inspect cip113-frontend-preview
```

## Cleanup

```bash
# Stop and remove containers
docker-compose down

# Remove images
docker rmi cip113-frontend:preview
docker rmi cip113-frontend:preprod
docker rmi cip113-frontend:mainnet

# Clean up build cache
docker builder prune

# Remove all unused resources
docker system prune -a
```

## Support

For issues or questions:
- GitHub Issues: https://github.com/cardano-foundation/cip113-programmable-tokens/issues
- Documentation: See README.md
