#!/bin/bash
# Chapter 01 Verification Script
# Checks that all ch01 challenges are complete
# Exit 0 = all checks passed
# Exit 1 = one or more checks failed

TARGET_CHALLENGE="${1:-all}"
FAILED=0

# ─── Helpers ──────────────────────────────────────────────────────────────────

check() {
    local description="$1"
    local command="$2"

    if eval "$command" > /dev/null 2>&1; then
        echo "PASS: $description"
    else
        echo "FAIL: $description"
        FAILED=1
    fi
}

check_output() {
    local description="$1"
    local command="$2"
    local expected="$3"

    local actual
    actual=$(eval "$command" 2>/dev/null)
    if echo "$actual" | grep -q "$expected"; then
        echo "PASS: $description"
    else
        echo "FAIL: $description"
        if [ -n "$actual" ]; then
            echo "      Got: $(echo "$actual" | head -1)"
            echo "      Expected to contain: $expected"
        fi
        FAILED=1
    fi
}

# ─── Header ───────────────────────────────────────────────────────────────────

echo "=== Chapter 01 Challenge Verification ==="
echo ""

# ─── Challenge 01: learn-ch01-nginx ───────────────────────────────────────────

verify_ch01() {
    echo "[ Challenge 01: Run Nginx ]"

    check \
        "Container 'learn-ch01-nginx' exists" \
        "docker ps -a --filter 'name=^learn-ch01-nginx$' -q | grep -q ."

    check \
        "Container 'learn-ch01-nginx' is running" \
        "docker ps --filter 'name=^learn-ch01-nginx$' --filter 'status=running' -q | grep -q ."

    check \
        "Container 'learn-ch01-nginx' has label app=learn-docker-k8s" \
        "docker inspect learn-ch01-nginx --format '{{index .Config.Labels \"app\"}}' | grep -q 'learn-docker-k8s'"

    check \
        "Container 'learn-ch01-nginx' has label chapter=ch01" \
        "docker inspect learn-ch01-nginx --format '{{index .Config.Labels \"chapter\"}}' | grep -q 'ch01'"

    check \
        "Port 8080 is accessible on 127.0.0.1" \
        "curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1:8080"

    check_output \
        "Response from 127.0.0.1:8080 contains 'Welcome to nginx'" \
        "curl -s --connect-timeout 2 --max-time 5 http://127.0.0.1:8080" \
        "Welcome to nginx"

    echo ""
}

# ─── Challenge 02: learn-ch01-app:v1 ──────────────────────────────────────────

verify_ch02() {
    echo "[ Challenge 02: Build First Image ]"

    check \
        "Image 'learn-ch01-app:v1' exists locally" \
        "docker image inspect learn-ch01-app:v1"

    check \
        "Container 'learn-ch01-app' exists" \
        "docker ps -a --filter 'name=^learn-ch01-app$' -q | grep -q ."

    check \
        "Container 'learn-ch01-app' is running" \
        "docker ps --filter 'name=^learn-ch01-app$' --filter 'status=running' -q | grep -q ."

    check \
        "Container 'learn-ch01-app' has label app=learn-docker-k8s" \
        "docker inspect learn-ch01-app --format '{{index .Config.Labels \"app\"}}' | grep -q 'learn-docker-k8s'"

    check \
        "Container 'learn-ch01-app' has label chapter=ch01" \
        "docker inspect learn-ch01-app --format '{{index .Config.Labels \"chapter\"}}' | grep -q 'ch01'"

    check \
        "Port 3000 is accessible on 127.0.0.1" \
        "curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1:3000"

    check_output \
        "Response from 127.0.0.1:3000 contains 'Hello from NoCappuccino'" \
        "curl -s --connect-timeout 2 --max-time 5 http://127.0.0.1:3000" \
        "Hello from NoCappuccino"

    echo ""
}

# ─── Challenge 03: learn-ch01-broken (fixed) ──────────────────────────────────

verify_ch03() {
    echo "[ Challenge 03: Debug Port Mapping ]"

    check \
        "Container 'learn-ch01-broken' exists" \
        "docker ps -a --filter 'name=^learn-ch01-broken$' -q | grep -q ."

    check \
        "Container 'learn-ch01-broken' is running" \
        "docker ps --filter 'name=^learn-ch01-broken$' --filter 'status=running' -q | grep -q ."

    check \
        "Container 'learn-ch01-broken' has a port mapping (8081 or 8080)" \
        "docker inspect learn-ch01-broken --format '{{json .HostConfig.PortBindings}}' | grep -qE '8081|8080'"

    check \
        "Container 'learn-ch01-broken' has label app=learn-docker-k8s" \
        "docker inspect learn-ch01-broken --format '{{index .Config.Labels \"app\"}}' | grep -q 'learn-docker-k8s'"

    # Check port 8081 first, fallback to 8080 if tested individually
    check \
        "Container responds on mapped port (8081 or 8080)" \
        "curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1:8081 || curl -sf --connect-timeout 2 --max-time 5 http://127.0.0.1:8080"

    echo ""
}

# ─── Execution ────────────────────────────────────────────────────────────────

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

# ─── Summary ──────────────────────────────────────────────────────────────────

if [ "$FAILED" -eq 0 ]; then
    echo "All checks passed!"
    if [ "$TARGET_CHALLENGE" = "all" ]; then
        echo "Chapter 01 complete!"
        echo ""
        echo "Dave's exact words when you showed him: 'Wait... it just... works?'"
        echo "Yes, Dave. That's the point."
        echo ""
        echo "Next up: Chapter 02 — 'The 2GB Espresso'"
        echo "Hint: Marcus is about to show you a very alarming deploy-time chart."
    fi
    exit 0
else
    echo "Some checks failed. Review the FAIL lines above and try again."
    echo "Run 'docker ps -a' to see the state of your containers."
    exit 1
fi
