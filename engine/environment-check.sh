#!/bin/bash
# Environment pre-flight check for Learn Docker & K8s
# Run this before starting the game to verify prerequisites

PASSED=0
FAILED=0
WARNINGS=0

pass() { echo "  PASS: $1"; ((PASSED++)); }
fail() { echo "  FAIL: $1"; ((FAILED++)); }
warn() { echo "  WARN: $1"; ((WARNINGS++)); }

echo "=== Learn Docker & K8s: Environment Check ==="
echo ""

# --- Docker ---
echo "[Docker]"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    pass "Docker installed (v${DOCKER_VERSION})"
else
    fail "Docker is not installed. Install from https://docs.docker.com/get-docker/"
fi

if docker info &> /dev/null; then
    pass "Docker daemon is running"
else
    fail "Docker daemon is not running. Start Docker Desktop or run 'sudo systemctl start docker'"
fi

# --- Docker Compose ---
echo ""
echo "[Docker Compose]"
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null)
    pass "Docker Compose v2 available (v${COMPOSE_VERSION})"
elif command -v docker-compose &> /dev/null; then
    warn "Only docker-compose v1 found. Chapters 5+ work best with v2. Upgrade: https://docs.docker.com/compose/install/"
else
    fail "Docker Compose not found. Install: https://docs.docker.com/compose/install/"
fi

# --- Disk Space ---
echo ""
echo "[System]"
if command -v df &> /dev/null; then
    # Get available space in GB (POSIX-compliant, works on Linux, macOS, WSL)
    AVAIL_GB=$(df -Pk . 2>/dev/null | awk 'NR==2 {print int($4 / 1048576)}')
    AVAIL_GB=${AVAIL_GB:-0}
    if [ "$AVAIL_GB" -ge 5 ] 2>/dev/null; then
        pass "Disk space: ${AVAIL_GB}GB available (>5GB required)"
    else
        warn "Low disk space: ${AVAIL_GB}GB available. Docker images need space!"
    fi
fi

# --- OS ---
OS=$(uname -s)
ARCH=$(uname -m)
pass "OS: ${OS} (${ARCH})"

# --- Git (for the project itself) ---
echo ""
echo "[Tools]"
if command -v git &> /dev/null; then
    pass "Git installed"
else
    warn "Git not installed. Recommended for tracking your progress."
fi

# --- curl (for testing) ---
if command -v curl &> /dev/null; then
    pass "curl available (used for testing)"
else
    warn "curl not found. Some verifications may not work."
fi

# --- K8s tools (optional, needed for Ch06-07) ---
echo ""
echo "[Kubernetes (needed for Chapters 6-7)]"
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -oE '"gitVersion":\s*"v[^"]+' | grep -oE 'v[0-9.]+' | head -1 || echo "unknown")
    pass "kubectl installed (${KUBECTL_VERSION})"
else
    warn "kubectl not installed. You'll need it for Chapters 6-7. Install: https://kubernetes.io/docs/tasks/tools/"
fi

if command -v kind &> /dev/null; then
    KIND_VERSION=$(kind version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    pass "kind installed (v${KIND_VERSION})"
else
    warn "kind not installed. You'll need it for Chapters 6-7. Install: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
fi

# --- Port Conflicts ---
echo ""
echo "[Port Availability]"
check_port() {
    local port=$1
    local in_use=0
    if command -v ss &> /dev/null; then
        if ss -tuln 2>/dev/null | grep -qE "[: ]${port}[ \t]"; then
            in_use=1
        fi
    elif command -v lsof &> /dev/null; then
        if lsof -i :"$port" &> /dev/null 2>&1; then
            in_use=1
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln 2>/dev/null | grep -qE "[: ]${port}[ \t]"; then
            in_use=1
        fi
    else
        if (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
            exec 3>&-
            in_use=1
        fi
    fi

    if [ "$in_use" -eq 0 ]; then
        pass "Port $port is available"
    else
        warn "Port $port is in use. Some challenges may need a different port."
    fi
}
check_port 8080
check_port 8081
check_port 3000
check_port 5432

# --- Network Subnet Overlaps ---
if command -v ip &> /dev/null; then
    OVERLAP=$(ip route show 2>/dev/null | grep -E "172\.17\." | grep -v "dev docker0" | head -1 || true)
    if [ -n "$OVERLAP" ]; then
        warn "VPN route overlap detected: '$OVERLAP' shadows Docker default bridge (docker0)."
    fi
fi

# --- Leftover Resources ---
echo ""
echo "[Cleanup Check]"
LEFTOVER_CONTAINERS=$(docker ps -a --filter "label=app=learn-docker-k8s" -q 2>/dev/null | wc -l | tr -d ' ')
LEFTOVER_NETWORKS=$(docker network ls --filter "label=app=learn-docker-k8s" -q 2>/dev/null | wc -l | tr -d ' ')
LEFTOVER_VOLUMES=$(docker volume ls --filter "label=app=learn-docker-k8s" -q 2>/dev/null | wc -l | tr -d ' ')

if [ "$LEFTOVER_CONTAINERS" -gt 0 ] || [ "$LEFTOVER_NETWORKS" -gt 0 ] || [ "$LEFTOVER_VOLUMES" -gt 0 ]; then
    warn "Found leftover resources from previous sessions: ${LEFTOVER_CONTAINERS} containers, ${LEFTOVER_NETWORKS} networks, ${LEFTOVER_VOLUMES} volumes"
    echo "        Run ./engine/cleanup.sh to remove them."
else
    pass "No leftover resources from previous sessions"
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo "  Passed:   $PASSED"
echo "  Failed:   $FAILED"
echo "  Warnings: $WARNINGS"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "Some checks failed. Please fix the issues above before starting."
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    echo "Ready to start! (Some optional tools are missing — you can install them later.)"
    exit 0
else
    echo "All systems go! You're ready to learn Docker & Kubernetes."
    exit 0
fi
