#!/bin/bash
# Chapter 4 Verification Script: The Silent Grinder
# Checks DNS resolution, port mapping, and network isolation
#
# Exit 0 = all checks passed
# Exit 1 = one or more checks failed

set -u

TARGET_CHALLENGE="${1:-all}"
PASSED=0
FAILED=0

pass() {
    echo "  PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "  FAIL: $1"
    FAILED=$((FAILED + 1))
}

check() {
    local description="$1"
    local command="$2"

    if eval "$command" > /dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

echo ""
echo "=== Chapter 4 Verification: The Silent Grinder ==="
echo ""

# ---------------------------------------------------------------------------
# Challenge 1: DNS Resolution
# frontend can reach backend by name on a user-defined network
# ---------------------------------------------------------------------------

verify_ch01() {
    echo "[Challenge 1: Fix the DNS]"

    check \
        "Container 'learn-ch04-frontend' is running" \
        "docker ps --filter name=learn-ch04-frontend --filter status=running -q | grep -q ."

    check \
        "Container 'learn-ch04-backend' is running" \
        "docker ps --filter name=learn-ch04-backend --filter status=running -q | grep -q ."

    check \
        "A user-defined network with 'learn-ch04-' prefix exists" \
        "docker network ls --filter 'label=app=learn-docker-k8s' --format '{{.Name}}' | grep -q 'learn-ch04-' || docker network ls --format '{{.Name}}' | grep -q 'learn-ch04-'"

    check \
        "learn-ch04-frontend can resolve learn-ch04-backend by name (DNS)" \
        "docker exec learn-ch04-frontend nslookup learn-ch04-backend"

    check \
        "learn-ch04-frontend can ping learn-ch04-backend by name" \
        "docker exec learn-ch04-frontend ping -c 1 -W 2 learn-ch04-backend"

    echo ""
}

# ---------------------------------------------------------------------------
# Challenge 2: Fix the Binding
# Fixed API container must be reachable from the host on port 3001
# (challenge spec asks them to run fixed container on port 3001)
# ---------------------------------------------------------------------------

verify_ch02() {
    echo "[Challenge 2: Fix the Binding]"

    check \
        "Container 'learn-ch04-api-fixed' is running" \
        "docker ps --filter name=learn-ch04-api-fixed --filter status=running -q | grep -q ."

    check \
        "Image 'learn-ch04-api:fixed' exists" \
        "docker image inspect learn-ch04-api:fixed"

    check \
        "learn-ch04-api-fixed has a port mapping to host" \
        "docker port learn-ch04-api-fixed | grep -q '3000'"

    # Detect the mapped host port dynamically
    API_HOST_PORT=$(docker port learn-ch04-api-fixed 3000/tcp 2>/dev/null | head -1 | cut -d: -f2 || echo "")

    if [ -n "$API_HOST_PORT" ]; then
        check \
            "Fixed API responds to HTTP requests on host port $API_HOST_PORT" \
            "curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1:${API_HOST_PORT}"

        check \
            "Fixed API response contains status ok" \
            "curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1:${API_HOST_PORT} | grep -q 'ok'"
    else
        fail "Could not detect mapped port for learn-ch04-api-fixed"
        fail "Fixed API HTTP check skipped (no port found)"
    fi

    # Confirm the broken container still fails (optional, but informative)
    BROKEN_PORT=$(docker port learn-ch04-api 3000/tcp 2>/dev/null | head -1 | cut -d: -f2 || echo "")
    if [ -n "$BROKEN_PORT" ]; then
        if curl -sf --connect-timeout 2 "http://127.0.0.1:${BROKEN_PORT}" > /dev/null 2>&1; then
            echo "  INFO: learn-ch04-api (broken) is now reachable — this is unexpected but not a blocker"
        else
            echo "  INFO: learn-ch04-api (broken) is correctly unreachable (confirms the 127.0.0.1 binding)"
        fi
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Challenge 3: Network Isolation
# frontend-iso <-> backend-iso: OK
# backend-iso  <-> db:          OK
# frontend-iso <-> db:          BLOCKED
# ---------------------------------------------------------------------------

verify_ch03() {
    echo "[Challenge 3: Network Isolation]"

    check \
        "Container 'learn-ch04-frontend-iso' is running" \
        "docker ps --filter name=learn-ch04-frontend-iso --filter status=running -q | grep -q ."

    check \
        "Container 'learn-ch04-backend-iso' is running" \
        "docker ps --filter name=learn-ch04-backend-iso --filter status=running -q | grep -q ."

    check \
        "Container 'learn-ch04-db' is running" \
        "docker ps --filter name=learn-ch04-db --filter status=running -q | grep -q ."

    check \
        "learn-ch04-frontend-iso can reach learn-ch04-backend-iso by name" \
        "docker exec learn-ch04-frontend-iso ping -c 1 -W 2 learn-ch04-backend-iso"

    check \
        "learn-ch04-backend-iso can reach learn-ch04-db by name" \
        "docker exec learn-ch04-backend-iso ping -c 1 -W 2 learn-ch04-db"

    # This check is inverted: we WANT the ping to FAIL
    echo -n "  Checking: learn-ch04-frontend-iso CANNOT reach learn-ch04-db ... "
    if docker exec learn-ch04-frontend-iso ping -c 1 -W 2 learn-ch04-db > /dev/null 2>&1; then
        echo ""
        fail "learn-ch04-frontend-iso CAN reach learn-ch04-db — isolation is BROKEN"
    else
        echo ""
        pass "learn-ch04-frontend-iso cannot reach learn-ch04-db (isolation works)"
    fi

    check \
        "learn-ch04-backend-iso is connected to two separate networks" \
        "docker inspect learn-ch04-backend-iso --format '{{len .NetworkSettings.Networks}}' | grep -qE '^[2-9]'"

    echo ""
}

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASSED + FAILED))

echo "=== Results ==="
echo "  Passed: $PASSED / $TOTAL"
echo "  Failed: $FAILED / $TOTAL"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "All checks passed!"
    if [ "$TARGET_CHALLENGE" = "all" ]; then
        echo "Chapter 4 complete."
        echo ""
        echo "The demo went perfectly. The networking is solid."
        echo "Time to meet Sarah in Chapter 5: The Symphony of Steam."
    fi
    exit 0
else
    echo "$FAILED check(s) failed. Keep going — you're close!"
    echo ""
    echo "Re-read the challenge files for hints, or ask Sarah."
    exit 1
fi
