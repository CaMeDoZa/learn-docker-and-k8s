#!/bin/bash
# Cleanup all learn-* Docker resources
# Safe: only removes resources with the learn-docker-k8s label

set -uo pipefail

echo "=== Learn Docker & K8s: Cleanup ==="
echo ""

# Shut down compose projects if present
for compose_file in \
    "curriculum/ch05-compose/challenges/docker-compose.yml" \
    "curriculum/ch05-compose/docker-compose.yml" \
    "./docker-compose.yml"
do
    if [ -f "$compose_file" ]; then
        echo "Tearing down Compose project ($compose_file)..."
        docker compose -f "$compose_file" down -v --remove-orphans 2>/dev/null || true
    fi
done

# Stop and remove containers
CONTAINERS=$(printf "%s\n%s" \
    "$(docker ps -a --filter "label=app=learn-docker-k8s" -q 2>/dev/null)" \
    "$(docker ps -a --filter "name=^learn-" -q 2>/dev/null)" | sort -u | grep -v '^$' || true)

if [ -n "$CONTAINERS" ]; then
    COUNT=$(echo "$CONTAINERS" | wc -l | tr -d ' ')
    echo "Stopping and removing $COUNT containers..."
    docker stop $CONTAINERS 2>/dev/null || true
    docker rm -f $CONTAINERS 2>/dev/null || true
    echo "  Done."
else
    echo "No containers to remove."
fi

# Remove networks
NETWORKS=$(printf "%s\n%s" \
    "$(docker network ls --filter "label=app=learn-docker-k8s" -q 2>/dev/null)" \
    "$(docker network ls --filter "name=^learn-" -q 2>/dev/null)" | sort -u | grep -v '^$' || true)

if [ -n "$NETWORKS" ]; then
    COUNT=$(echo "$NETWORKS" | wc -l | tr -d ' ')
    echo "Removing $COUNT networks..."
    docker network rm $NETWORKS 2>/dev/null || true
    echo "  Done."
else
    echo "No networks to remove."
fi

# Remove volumes
VOLUMES=$(printf "%s\n%s" \
    "$(docker volume ls --filter "label=app=learn-docker-k8s" -q 2>/dev/null)" \
    "$(docker volume ls --filter "name=^learn-" -q 2>/dev/null)" | sort -u | grep -v '^$' || true)

if [ -n "$VOLUMES" ]; then
    COUNT=$(echo "$VOLUMES" | wc -l | tr -d ' ')
    echo "Removing $COUNT volumes..."
    docker volume rm $VOLUMES 2>/dev/null || true
    echo "  Done."
else
    echo "No volumes to remove."
fi

# Remove images with label or learn- tag
IMAGES=$(printf "%s\n%s" \
    "$(docker images --filter "label=app=learn-docker-k8s" -q 2>/dev/null)" \
    "$(docker images --filter "reference=learn-*" -q 2>/dev/null)" | sort -u | grep -v '^$' || true)

if [ -n "$IMAGES" ]; then
    COUNT=$(echo "$IMAGES" | wc -l | tr -d ' ')
    echo "Removing $COUNT images..."
    docker rmi -f $IMAGES 2>/dev/null || true
    echo "  Done."
else
    echo "No images to remove."
fi

# K8s cleanup (if kubectl available and cluster is reachable)
if command -v kubectl &> /dev/null; then
    echo ""
    K8S_CONTEXT="${KUBE_CONTEXT:-}"
    if [ -z "$K8S_CONTEXT" ] && command -v kind &> /dev/null; then
        if kind get clusters 2>/dev/null | grep -q "^learn-k8s$"; then
            K8S_CONTEXT="kind-learn-k8s"
        fi
    fi
    CONTEXT_ARG=""
    [ -n "$K8S_CONTEXT" ] && CONTEXT_ARG="--context $K8S_CONTEXT"

    if kubectl cluster-info $CONTEXT_ARG --request-timeout=3s &> /dev/null; then
        NAMESPACES=$(kubectl get namespaces $CONTEXT_ARG --request-timeout=3s -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep "^learn-" || true)
        if [ -n "$NAMESPACES" ]; then
            echo "Removing Kubernetes namespaces..."
            for ns in $NAMESPACES; do
                kubectl delete namespace "$ns" $CONTEXT_ARG --timeout=60s --request-timeout=10s 2>/dev/null || true
            done
            echo "  Done."
        else
            echo "No Kubernetes namespaces to remove."
        fi
    else
        echo "Kubernetes cluster not reachable (skipping K8s namespace cleanup)."
    fi
fi

echo ""
echo "Cleanup complete!"
