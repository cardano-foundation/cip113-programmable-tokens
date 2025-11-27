#!/bin/bash
# Build Docker images for CIP-113 Programmable Tokens Frontend

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Docker image repository
DOCKER_REPO="easy1staking/cip113-frontend"

# Get git version tag
GIT_TAG=$(git describe --tags --always --dirty 2>/dev/null || echo "dev")
echo -e "${BLUE}Git version: ${GIT_TAG}${NC}"

# Function to build a single network
build_network() {
    local NETWORK=$1
    local API_KEY=""
    local BLOCKFROST_URL=""
    local PORT=""

    # Set Blockfrost API key based on network
    case $NETWORK in
        preview)
            API_KEY=$BLOCKFROST_PREVIEW_API_KEY
            BLOCKFROST_URL="https://cardano-preview.blockfrost.io/api/v0"
            PORT=3000
            ;;
        preprod)
            API_KEY=$BLOCKFROST_PREPROD_API_KEY
            BLOCKFROST_URL="https://cardano-preprod.blockfrost.io/api/v0"
            PORT=3001
            ;;
        mainnet)
            API_KEY=$BLOCKFROST_MAINNET_API_KEY
            BLOCKFROST_URL="https://cardano-mainnet.blockfrost.io/api/v0"
            PORT=3002
            ;;
        *)
            echo -e "${RED}Invalid network: $NETWORK${NC}"
            return 1
            ;;
    esac

    # Check if API key is set
    if [ -z "$API_KEY" ]; then
        echo -e "${YELLOW}Warning: Blockfrost API key for $NETWORK not found in .env.docker${NC}"
        echo -e "${YELLOW}Skipping $NETWORK build...${NC}"
        return 1
    fi

    # Create tags
    local VERSION_TAG="${GIT_TAG}-${NETWORK}"
    local NETWORK_TAG="${NETWORK}"

    echo ""
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}Building Docker image for $NETWORK network${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo -e "${BLUE}Version tag: ${VERSION_TAG}${NC}"
    echo -e "${BLUE}Blockfrost URL: ${BLOCKFROST_URL}${NC}"

    # Build the Docker image
    docker build \
        --build-arg NEXT_PUBLIC_NETWORK=$NETWORK \
        --build-arg NEXT_PUBLIC_BLOCKFROST_API_KEY=$API_KEY \
        --build-arg NEXT_PUBLIC_BLOCKFROST_URL=$BLOCKFROST_URL \
        -t ${DOCKER_REPO}:${VERSION_TAG} \
        -t ${DOCKER_REPO}:${NETWORK_TAG} \
        .

    echo -e "${GREEN}✓ Build complete for $NETWORK!${NC}"
    echo -e "${BLUE}Tags created:${NC}"
    echo -e "  - ${DOCKER_REPO}:${VERSION_TAG}"
    echo -e "  - ${DOCKER_REPO}:${NETWORK_TAG}"
    echo ""
    echo -e "${GREEN}To run:${NC}"
    echo -e "  docker run -p $PORT:3000 ${DOCKER_REPO}:${VERSION_TAG}"

    # Mark as latest if this is mainnet
    if [ "$NETWORK" = "mainnet" ]; then
        docker tag ${DOCKER_REPO}:${VERSION_TAG} ${DOCKER_REPO}:latest
        echo -e "  - ${DOCKER_REPO}:latest"
    fi

    echo ""
}

# Function to push images
push_network() {
    local NETWORK=$1
    local VERSION_TAG="${GIT_TAG}-${NETWORK}"

    echo -e "${BLUE}Pushing ${DOCKER_REPO}:${VERSION_TAG}...${NC}"
    docker push ${DOCKER_REPO}:${VERSION_TAG}

    echo -e "${BLUE}Pushing ${DOCKER_REPO}:${NETWORK}...${NC}"
    docker push ${DOCKER_REPO}:${NETWORK}

    if [ "$NETWORK" = "mainnet" ]; then
        echo -e "${BLUE}Pushing ${DOCKER_REPO}:latest...${NC}"
        docker push ${DOCKER_REPO}:latest
    fi

    echo -e "${GREEN}✓ Push complete for $NETWORK!${NC}"
}

# Main script
COMMAND=${1:-preview}
PUSH_FLAG=${2:-}

# Load environment variables
if [ -f .env.docker ]; then
    echo -e "${BLUE}Loading environment variables from .env.docker${NC}"
    export $(cat .env.docker | grep -v '^#' | xargs)
else
    echo -e "${YELLOW}Warning: .env.docker not found.${NC}"
    echo -e "${YELLOW}Copy .env.docker.example to .env.docker and add your API keys.${NC}"
    exit 1
fi

# Handle commands
case $COMMAND in
    all)
        echo -e "${GREEN}Building all networks...${NC}"
        NETWORKS=("preview" "preprod" "mainnet")
        FAILED_BUILDS=()

        for net in "${NETWORKS[@]}"; do
            if ! build_network $net; then
                FAILED_BUILDS+=($net)
            fi
        done

        echo ""
        echo -e "${GREEN}======================================${NC}"
        echo -e "${GREEN}Build Summary${NC}"
        echo -e "${GREEN}======================================${NC}"

        for net in "${NETWORKS[@]}"; do
            if [[ " ${FAILED_BUILDS[@]} " =~ " ${net} " ]]; then
                echo -e "${RED}✗ $net - FAILED${NC}"
            else
                echo -e "${GREEN}✓ $net - SUCCESS${NC}"
            fi
        done

        # Push if requested and no failures
        if [ "$PUSH_FLAG" = "--push" ] && [ ${#FAILED_BUILDS[@]} -eq 0 ]; then
            echo ""
            echo -e "${BLUE}Pushing all images to Docker Hub...${NC}"
            for net in "${NETWORKS[@]}"; do
                push_network $net
            done
            echo -e "${GREEN}✓ All images pushed successfully!${NC}"
        elif [ "$PUSH_FLAG" = "--push" ] && [ ${#FAILED_BUILDS[@]} -gt 0 ]; then
            echo -e "${YELLOW}Skipping push due to build failures${NC}"
            exit 1
        fi

        if [ ${#FAILED_BUILDS[@]} -gt 0 ]; then
            exit 1
        fi
        ;;
    preview|preprod|mainnet)
        build_network $COMMAND

        if [ "$PUSH_FLAG" = "--push" ]; then
            echo -e "${BLUE}Pushing image to Docker Hub...${NC}"
            push_network $COMMAND
            echo -e "${GREEN}✓ Image pushed successfully!${NC}"
        fi
        ;;
    help|--help|-h)
        echo "Usage: ./build-docker.sh [NETWORK|all] [--push]"
        echo ""
        echo "Networks:"
        echo "  preview  - Build for Cardano preview testnet (port 3000)"
        echo "  preprod  - Build for Cardano preprod testnet (port 3001)"
        echo "  mainnet  - Build for Cardano mainnet (port 3002)"
        echo "  all      - Build all networks"
        echo ""
        echo "Options:"
        echo "  --push   - Push images to Docker Hub after building"
        echo ""
        echo "Examples:"
        echo "  ./build-docker.sh preview          # Build preview only"
        echo "  ./build-docker.sh all              # Build all networks"
        echo "  ./build-docker.sh all --push       # Build all and push"
        echo "  ./build-docker.sh mainnet --push   # Build mainnet and push"
        echo ""
        echo "Tags created:"
        echo "  <repo>:<git-tag>-<network>  (e.g., easy1staking/cip113-frontend:v1.0.0-preview)"
        echo "  <repo>:<network>            (e.g., easy1staking/cip113-frontend:preview)"
        echo "  <repo>:latest               (only for mainnet)"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid command: $COMMAND${NC}"
        echo "Usage: ./build-docker.sh [preview|preprod|mainnet|all] [--push]"
        echo "Run './build-docker.sh help' for more information"
        exit 1
        ;;
esac
