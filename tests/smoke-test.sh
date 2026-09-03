#!/bin/bash
# ==============================================================================
# Smoke Test Suite for learn-docker-and-k8s
# Tests engine scripts, verification scripts, cross-chapter isolation,
# and end-to-end challenge lifecycle.
# ==============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASSED_TESTS=0
FAILED_TESTS=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

pass() {
    echo -e "  ${GREEN}[PASS]${RESET} $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

fail() {
    echo -e "  ${RED}[FAIL]${RESET} $1"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

test_section() {
    echo ""
    echo -e "${BOLD}=== $1 ===${RESET}"
}

test_section "1. Static Analysis & Syntax Verification"

# 1.1 All shell scripts must pass bash -n syntax check
SYNTAX_FAILURES=0
while IFS= read -r script; do
    if ! bash -n "$script" 2>/dev/null; then
        fail "Syntax error in $script"
        SYNTAX_FAILURES=$((SYNTAX_FAILURES + 1))
    fi
done < <(find . -type f -name "*.sh" ! -path "*/.git/*")

if [ "$SYNTAX_FAILURES" -eq 0 ]; then
    pass "All shell scripts passed syntax check (bash -n)"
fi

# 1.2 All verification and engine scripts must be executable
EXEC_FAILURES=0
while IFS= read -r script; do
    if [ ! -x "$script" ]; then
        fail "$script is not marked executable"
        EXEC_FAILURES=$((EXEC_FAILURES + 1))
    fi
done < <(find curriculum engine -type f -name "*.sh" 2>/dev/null)

if [ "$EXEC_FAILURES" -eq 0 ]; then
    pass "All verification and engine scripts have executable permissions (+x)"
fi

test_section "2. Engine Scripts Verification"

# 2.1 environment-check.sh runs and outputs valid report
ENV_CHECK_OUTPUT=$(bash engine/environment-check.sh 2>&1 || true)
if echo "$ENV_CHECK_OUTPUT" | grep -qE "Environment Check|=== Summary ==="; then
    pass "engine/environment-check.sh executes successfully and outputs results"
else
    fail "engine/environment-check.sh output unexpected"
fi

# 2.2 cleanup.sh runs without errors or hanging
CLEANUP_START=$(date +%s)
bash engine/cleanup.sh >/dev/null 2>&1 || true
CLEANUP_DURATION=$(( $(date +%s) - CLEANUP_START ))
if [ "$CLEANUP_DURATION" -le 5 ]; then
    pass "engine/cleanup.sh completed in ${CLEANUP_DURATION}s (no hang, fast-fail on unreachable K8s)"
else
    fail "engine/cleanup.sh took ${CLEANUP_DURATION}s (> 5s threshold)"
fi

test_section "3. Verification Scripts Fail-Fast & Timeout Benchmarking"

# 3.1 Every chapter verify.sh must fail gracefully and quickly on clean state
for ch in curriculum/ch0*/challenges/verify.sh; do
    CHAPTER_NAME=$(basename "$(dirname "$(dirname "$ch")")")
    START_TIME=$(date +%s%N 2>/dev/null || date +%s)
    
    # Run challenge 1 verification
    set +e
    bash "$ch" 1 >/dev/null 2>&1
    EXIT_CODE=$?
    set -u
    
    END_TIME=$(date +%s%N 2>/dev/null || date +%s)
    
    # Calculate duration in ms if nanoseconds supported, else seconds
    if [ ${#START_TIME} -gt 10 ]; then
        DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
        DURATION_STR="${DURATION_MS}ms"
        TOO_SLOW=$(( DURATION_MS > 6000 ))
    else
        DURATION_S=$(( END_TIME - START_TIME ))
        DURATION_STR="${DURATION_S}s"
        TOO_SLOW=$(( DURATION_S > 6 ))
    fi

    # verify.sh should exit non-zero on empty environment
    if [ "$EXIT_CODE" -ne 0 ]; then
        if [ "$TOO_SLOW" -eq 0 ]; then
            pass "$CHAPTER_NAME verify.sh 1 correctly failed fast ($DURATION_STR, exit $EXIT_CODE)"
        else
            fail "$CHAPTER_NAME verify.sh 1 was too slow ($DURATION_STR > 6s)"
        fi
    else
        fail "$CHAPTER_NAME verify.sh 1 unexpectedly passed on clean environment (exit 0)"
    fi
done

test_section "4. Granular Argument Verification (\$1 Support)"

# Test Ch01 with different argument forms: 1, 2, 3, all
CH01_V="curriculum/ch01-containers/challenges/verify.sh"
OUT_1=$(bash "$CH01_V" 1 2>&1 || true)
OUT_2=$(bash "$CH01_V" 2 2>&1 || true)
OUT_3=$(bash "$CH01_V" 3 2>&1 || true)
OUT_ALL=$(bash "$CH01_V" all 2>&1 || true)

if echo "$OUT_1" | grep -q "Challenge 01: Run Nginx" && ! echo "$OUT_1" | grep -q "Challenge 02: Build First Image"; then
    pass "ch01 verify.sh 1 targets ONLY Challenge 1"
else
    fail "ch01 verify.sh 1 does not isolate Challenge 1"
fi

if echo "$OUT_2" | grep -q "Challenge 02: Build First Image" && ! echo "$OUT_2" | grep -q "Challenge 01: Run Nginx"; then
    pass "ch01 verify.sh 2 targets ONLY Challenge 2"
else
    fail "ch01 verify.sh 2 does not isolate Challenge 2"
fi

if echo "$OUT_3" | grep -q "Challenge 03: Debug Port Mapping" && ! echo "$OUT_3" | grep -q "Challenge 01: Run Nginx"; then
    pass "ch01 verify.sh 3 targets ONLY Challenge 3"
else
    fail "ch01 verify.sh 3 does not isolate Challenge 3"
fi

if echo "$OUT_ALL" | grep -q "Challenge 01: Run Nginx" && echo "$OUT_ALL" | grep -q "Challenge 03: Debug Port Mapping"; then
    pass "ch01 verify.sh all targets ALL challenges"
else
    fail "ch01 verify.sh all does not execute all challenges"
fi

test_section "5. End-to-End Challenge Lifecycle & Cleanup (Live Docker)"

# 5.1 Test Chapter 1 Challenge 1 real-world solution
docker rm -f learn-ch01-nginx >/dev/null 2>&1 || true
docker run -d --name learn-ch01-nginx -p 8080:80 --label app=learn-docker-k8s --label chapter=ch01 nginx:alpine >/dev/null 2>&1
sleep 1

if bash curriculum/ch01-containers/challenges/verify.sh 1 >/dev/null 2>&1; then
    pass "ch01 Challenge 1 PASSES when correct solution is running on port 8080"
else
    fail "ch01 Challenge 1 failed verification despite valid container running"
fi

# 5.2 Test Chapter 1 Challenge 3 (the fixed port 8081)
docker rm -f learn-ch01-broken >/dev/null 2>&1 || true
docker run -d --name learn-ch01-broken -p 8081:80 --label app=learn-docker-k8s --label chapter=ch01 nginx:alpine >/dev/null 2>&1
sleep 1

if bash curriculum/ch01-containers/challenges/verify.sh 3 >/dev/null 2>&1; then
    pass "ch01 Challenge 3 PASSES when running on port 8081 (collision eliminated)"
else
    fail "ch01 Challenge 3 failed verification on port 8081"
fi

# 5.3 Test that both 1 and 3 can run simultaneously without port collision
if bash curriculum/ch01-containers/challenges/verify.sh 1 >/dev/null 2>&1 && \
   bash curriculum/ch01-containers/challenges/verify.sh 3 >/dev/null 2>&1; then
    pass "Simultaneous execution of ch01 Challenge 1 and Challenge 3 succeeds without port clash"
else
    fail "Simultaneous execution of Challenge 1 and 3 collided or failed"
fi

# 5.4 Test cleanup.sh removes both containers and leaves environment clean
bash engine/cleanup.sh >/dev/null 2>&1
if docker ps -a --format '{{.Names}}' | grep -qE '^learn-ch01-'; then
    fail "engine/cleanup.sh failed to remove learn-ch01 containers"
else
    pass "engine/cleanup.sh cleanly wiped test containers"
fi

# 5.5 Confirm verify fails again after cleanup
if ! bash curriculum/ch01-containers/challenges/verify.sh 1 >/dev/null 2>&1; then
    pass "ch01 verify.sh 1 correctly returns non-zero after cleanup"
else
    fail "ch01 verify.sh 1 still passed after cleanup"
fi

# 5.6 Test Chapter 3 fast-exit without MySQL (Sleep optimization test)
CH03_START=$(date +%s)
bash curriculum/ch03-persistence/challenges/verify.sh 1 >/dev/null 2>&1 || true
CH03_DURATION=$(( $(date +%s) - CH03_START ))
if [ "$CH03_DURATION" -le 2 ]; then
    pass "ch03 verify.sh 1 exits in ${CH03_DURATION}s when MySQL is absent (30s sleep eliminated)"
else
    fail "ch03 verify.sh 1 took ${CH03_DURATION}s (> 2s threshold)"
fi

test_section "6. Summary"

TOTAL=$((PASSED_TESTS + FAILED_TESTS))
echo ""
echo -e "${BOLD}Smoke Tests Total:${RESET} $TOTAL"
echo -e "  Passed: ${GREEN}$PASSED_TESTS${RESET}"
echo -e "  Failed: ${RED}$FAILED_TESTS${RESET}"
echo ""

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}ALL SMOKE TESTS PASSED!${RESET}"
    exit 0
else
    echo -e "${RED}${BOLD}$FAILED_TESTS SMOKE TEST(S) FAILED.${RESET}"
    exit 1
fi
