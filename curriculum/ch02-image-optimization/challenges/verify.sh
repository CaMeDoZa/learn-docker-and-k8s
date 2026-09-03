#!/bin/bash
# Chapter 2 Verification Script
# Checks all three challenges for Chapter 2: The 2GB Espresso
#
# Exit 0 = all checks passed
# Exit 1 = one or more checks failed

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAPTER_DIR="$(dirname "$SCRIPT_DIR")"

FAILED=0
PASS_COUNT=0
FAIL_COUNT=0

# ── Helpers ──────────────────────────────────────────────────────────────────

green()  { printf "\033[0;32m%s\033[0m\n" "$*"; }
red()    { printf "\033[0;31m%s\033[0m\n" "$*"; }
yellow() { printf "\033[0;33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

pass() {
    green "  PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    red "  FAIL: $1"
    if [ -n "${2:-}" ]; then
        yellow "  HINT: $2"
    fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED=1
}

check() {
    local description="$1"
    local hint="${3:-}"
    if eval "$2" > /dev/null 2>&1; then
        pass "$description"
    else
        fail "$description" "$hint"
    fi
}

TARGET_CHALLENGE="${1:-all}"

# ── Chapter 2 Verification ───────────────────────────────────────────────────

echo ""
bold "=== Chapter 2: The 2GB Espresso — Verification ==="
echo ""

# ── Challenge 1: Optimized Image ─────────────────────────────────────────────

verify_ch01() {
    bold "Challenge 1: Optimize the Bloated Image"
    echo ""

    # Check: image exists
    check \
        "Image 'learn-ch02-app:optimized' exists" \
        "docker image inspect learn-ch02-app:optimized" \
        "Build the image with: docker build -t learn-ch02-app:optimized -f $CHAPTER_DIR/challenges/app/Dockerfile $CHAPTER_DIR/challenges/app/"

    # Check: image is under 100MB (104857600 bytes)
    if docker image inspect learn-ch02-app:optimized > /dev/null 2>&1; then
        IMAGE_SIZE=$(docker image inspect learn-ch02-app:optimized --format '{{.Size}}')
        IMAGE_SIZE_MB=$(echo "scale=1; $IMAGE_SIZE / 1048576" | bc 2>/dev/null || echo "unknown")

        if [ "$IMAGE_SIZE" -lt 104857600 ]; then
            pass "Image size is under 100MB (actual: ${IMAGE_SIZE_MB}MB)"
        else
            fail "Image size is ${IMAGE_SIZE_MB}MB — must be under 100MB" \
                 "Use a multi-stage build with alpine or distroless as the final stage"
        fi
    else
        fail "Cannot check image size — image does not exist"
    fi

    # Check: container starts and responds
    if docker image inspect learn-ch02-app:optimized > /dev/null 2>&1; then
        # Start the container briefly on a random port
        docker rm -f learn-ch02-verify-app > /dev/null 2>&1 || true
        CONTAINER_ID=$(docker run -d -p 0:8080 \
            --label app=learn-docker-k8s \
            --label chapter=ch02 \
            --name learn-ch02-verify-app \
            learn-ch02-app:optimized 2>/dev/null || echo "")

        if [ -n "$CONTAINER_ID" ]; then
            ASSIGNED_PORT=$(docker port learn-ch02-verify-app 8080/tcp 2>/dev/null | cut -d: -f2 || echo "")
            sleep 1
            if [ -n "$ASSIGNED_PORT" ] && curl -sf --connect-timeout 2 --max-time 5 "http://127.0.0.1:${ASSIGNED_PORT}/health" > /dev/null 2>&1; then
                pass "Container starts and /health endpoint responds"
            else
                fail "Container started but /health endpoint did not respond" \
                     "Make sure the app listens on port 8080 and has a /health route"
            fi
            docker rm -f learn-ch02-verify-app > /dev/null 2>&1 || true
        else
            docker rm -f learn-ch02-verify-app > /dev/null 2>&1 || true
            fail "Could not start container from learn-ch02-app:optimized" \
                 "Try: docker run --rm -p 8080:8080 learn-ch02-app:optimized"
        fi
    else
        fail "Cannot test container startup — image does not exist"
    fi

    echo ""
}

# ── Challenge 2: Cache Bug Fix ────────────────────────────────────────────────

verify_ch02() {
    bold "Challenge 2: Fix the Cache Bug"
    echo ""

    # Check: fixed image exists
    check \
        "Image 'learn-ch02-cache-fixed:latest' exists" \
        "docker image inspect learn-ch02-cache-fixed:latest" \
        "Build with: docker build -t learn-ch02-cache-fixed:latest $CHAPTER_DIR/challenges/cache-bug/"

    # Check: Dockerfile exists
    check \
        "File 'challenges/cache-bug/Dockerfile' exists" \
        "test -f $CHAPTER_DIR/challenges/cache-bug/Dockerfile" \
        "Create the Dockerfile in challenges/cache-bug/"

    # Check: Dockerfile has the correct copy order (package.json before COPY . .)
    if [ -f "$CHAPTER_DIR/challenges/cache-bug/Dockerfile" ]; then
        PACKAGE_LINE=$(grep -n "COPY package" "$CHAPTER_DIR/challenges/cache-bug/Dockerfile" | head -1 | cut -d: -f1 || echo "0")
        COPY_ALL_LINE=$(grep -n "^COPY \. \." "$CHAPTER_DIR/challenges/cache-bug/Dockerfile" | head -1 | cut -d: -f1 || echo "0")
        NPM_LINE=$(grep -n "RUN npm install" "$CHAPTER_DIR/challenges/cache-bug/Dockerfile" | head -1 | cut -d: -f1 || echo "0")

        if [ "$PACKAGE_LINE" -gt 0 ] && [ "$NPM_LINE" -gt 0 ] && [ "$COPY_ALL_LINE" -gt 0 ]; then
            if [ "$PACKAGE_LINE" -lt "$NPM_LINE" ] && [ "$NPM_LINE" -lt "$COPY_ALL_LINE" ]; then
                pass "Layer order is correct: package.json → npm install → COPY source"
            else
                fail "Layer order is incorrect — package.json copy should come before npm install, and npm install before COPY . ." \
                     "Review the dependency-before-source pattern in Lesson 2"
            fi
        else
            fail "Could not detect expected Dockerfile instructions (COPY package*, RUN npm install, COPY . .)" \
                 "Make sure your Dockerfile contains all three patterns"
        fi

        # Check: apt-get update and install are chained
        APT_UPDATE_LINES=$(grep -c "^\s*RUN apt-get update$" "$CHAPTER_DIR/challenges/cache-bug/Dockerfile" 2>/dev/null || echo "0")
        if [ "$APT_UPDATE_LINES" -gt 0 ]; then
            fail "apt-get update is on its own RUN line — chain it with apt-get install" \
                 "Use: RUN apt-get update && apt-get install -y ... && rm -rf /var/lib/apt/lists/*"
        else
            pass "apt-get update is not on a standalone RUN line (correct)"
        fi
    fi

    echo ""
}

# ── Challenge 3: .dockerignore ────────────────────────────────────────────────

verify_ch03() {
    bold "Challenge 3: Tame the Build Context"
    echo ""

    # Check: .dockerignore exists
    check \
        "File 'challenges/big-context/.dockerignore' exists" \
        "test -f $CHAPTER_DIR/challenges/big-context/.dockerignore" \
        "Create a .dockerignore file in challenges/big-context/"

    # Check: .dockerignore excludes node_modules
    if [ -f "$CHAPTER_DIR/challenges/big-context/.dockerignore" ]; then
        check \
            ".dockerignore excludes 'node_modules'" \
            "grep -q 'node_modules' $CHAPTER_DIR/challenges/big-context/.dockerignore" \
            "Add 'node_modules' or 'node_modules/' to your .dockerignore"

        check \
            ".dockerignore excludes '.git'" \
            "grep -q '\.git' $CHAPTER_DIR/challenges/big-context/.dockerignore" \
            "Add '.git' to your .dockerignore"

        check \
            ".dockerignore excludes '.env'" \
            "grep -q '\.env' $CHAPTER_DIR/challenges/big-context/.dockerignore" \
            "Add '.env' to your .dockerignore — it may contain secrets"
    fi

    # Check: build context is actually small
    if [ -f "$CHAPTER_DIR/challenges/big-context/.dockerignore" ] && [ -f "$CHAPTER_DIR/challenges/big-context/Dockerfile" ]; then
        echo "  Measuring build context size (running docker build --dry-run)..."
        BUILD_OUTPUT=$(docker build \
            --progress=plain \
            --no-cache \
            -t learn-ch02-context-fixed \
            "$CHAPTER_DIR/challenges/big-context/" 2>&1 || true)

        CONTEXT_LINE=$(echo "$BUILD_OUTPUT" | grep "transferring context" | tail -1 || echo "")

        if [ -n "$CONTEXT_LINE" ]; then
            echo "  Context transfer: $CONTEXT_LINE"
            # Check if it's in MB (over 1MB is too large)
            if echo "$CONTEXT_LINE" | grep -qE "[0-9]+\.[0-9]+\s*MB|[0-9]{7,}\s*B"; then
                fail "Build context is still over 1MB" \
                     "Make sure node_modules, .git, and test-data are in your .dockerignore"
            else
                pass "Build context is under 1MB"
            fi
        else
            yellow "  SKIP: Could not measure build context (docker build may have failed or output format differs)"
        fi
    fi

    echo ""
}

# ── Execution ────────────────────────────────────────────────────────────────

case "$TARGET_CHALLENGE" in
    1|ch01|01)
        verify_ch01
        ;;
    2|ch02|02)
        verify_ch02
        ;;
    3|ch03|03)
        verify_ch03
        ;;
    all|*)
        verify_ch01
        verify_ch02
        verify_ch03
        ;;
esac

# ── Summary ───────────────────────────────────────────────────────────────────

bold "=== Results ==="
echo ""

if [ "$FAILED" -eq 0 ]; then
    green "All checks passed! ($PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)))"
    echo ""
    if [ "$TARGET_CHALLENGE" = "all" ]; then
        green "Chapter 2 complete! The Bean-Tracker image is lean, the builds are fast,"
        green "and Marcus stopped sending passive-aggressive Slack messages. For now."
        echo ""
        echo "Ready for Chapter 3: The Vanishing Beans."
    fi
else
    red "$FAIL_COUNT check(s) failed. $PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)) passed."
    echo ""
    yellow "Work through the failures above and run this script again."
    echo ""
fi

exit $FAILED
