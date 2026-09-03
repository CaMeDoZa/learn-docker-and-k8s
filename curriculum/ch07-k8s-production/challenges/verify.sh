#!/usr/bin/env bash
# =============================================================================
# Chapter 7 Verification Script: The Great Latte Leak
# =============================================================================
# Checks all three challenges:
#   Challenge 1 — Triage the Chaos
#   Challenge 2 — Zero-Downtime Update
#   Challenge 3 — Autoscaling
# =============================================================================

set -euo pipefail

TARGET_CHALLENGE="${1:-all}"
NAMESPACE="learn-ch07"
PASS=0
FAIL=0
WARNINGS=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

pass() {
  echo -e "  ${GREEN}[PASS]${RESET} $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}[FAIL]${RESET} $1"
  FAIL=$((FAIL + 1))
}

warn() {
  echo -e "  ${YELLOW}[WARN]${RESET} $1"
  WARNINGS=$((WARNINGS + 1))
}

section() {
  echo ""
  echo -e "${BOLD}--- $1 ---${RESET}"
}

# =============================================================================
# Preflight: namespace and kubectl connectivity
# =============================================================================
section "Preflight"

if ! kubectl cluster-info --request-timeout=5s &>/dev/null; then
  echo -e "${RED}ERROR: kubectl cannot connect to a cluster.${RESET}"
  echo "Make sure your kind cluster is running: kind get clusters"
  exit 1
fi
pass "kubectl can connect to cluster"

if ! kubectl get namespace "$NAMESPACE" --request-timeout=5s &>/dev/null; then
  fail "Namespace '$NAMESPACE' does not exist — run the challenge setup first"
  exit 1
fi
pass "Namespace '$NAMESPACE' exists"

# =============================================================================
# Challenge 1: Triage the Chaos
# =============================================================================
verify_ch01() {
  section "Challenge 1: Triage the Chaos"

  # Check 1a: No pods in ImagePullBackOff
  PULL_BACK_OFF=$(kubectl get pods -n "$NAMESPACE" --request-timeout=5s --no-headers 2>/dev/null \
    | grep -c "ImagePullBackOff" || true)
  if [ "$PULL_BACK_OFF" -eq 0 ]; then
    pass "No pods in ImagePullBackOff state"
  else
    fail "Found $PULL_BACK_OFF pod(s) in ImagePullBackOff — check image tag on 'api' deployment"
  fi

  # Check 1b: No pods in CrashLoopBackOff or OOMKilled
  CRASH_LOOP=$(kubectl get pods -n "$NAMESPACE" --request-timeout=5s --no-headers 2>/dev/null \
    | grep -cE "CrashLoopBackOff|OOMKilled" || true)
  if [ "$CRASH_LOOP" -eq 0 ]; then
    pass "No pods in CrashLoopBackOff or OOMKilled state"
  else
    fail "Found $CRASH_LOOP pod(s) in CrashLoopBackOff or OOMKilled — check resource limits on 'worker' deployment"
  fi

  # Check 1c: api deployment has running pods
  API_RUNNING=$(kubectl get pods -n "$NAMESPACE" --request-timeout=5s \
    -l app=api \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$API_RUNNING" -ge 1 ]; then
    pass "api Deployment has $API_RUNNING Running pod(s)"
  else
    fail "api Deployment has no Running pods"
  fi

  # Check 1d: worker deployment has running pods
  WORKER_RUNNING=$(kubectl get pods -n "$NAMESPACE" --request-timeout=5s \
    -l app=worker \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$WORKER_RUNNING" -ge 1 ]; then
    pass "worker Deployment has $WORKER_RUNNING Running pod(s)"
  else
    fail "worker Deployment has no Running pods"
  fi

  # Check 1e: app-config ConfigMap does not contain credentials
  if kubectl get configmap app-config -n "$NAMESPACE" --request-timeout=5s &>/dev/null; then
    CONFIG_HAS_PASSWORD=$(kubectl get configmap app-config -n "$NAMESPACE" --request-timeout=5s -o yaml 2>/dev/null \
      | grep -cE "DB_PASSWORD|DB_USER" || true)
    if [ "$CONFIG_HAS_PASSWORD" -eq 0 ]; then
      pass "app-config ConfigMap does not contain DB_PASSWORD or DB_USER"
    else
      fail "app-config ConfigMap still contains sensitive credentials (DB_PASSWORD or DB_USER) — move them to a Secret"
    fi
  else
    warn "app-config ConfigMap not found — was it deleted or renamed?"
  fi

  # Check 1f: Secret named db-credentials exists
  if kubectl get secret db-credentials -n "$NAMESPACE" --request-timeout=5s &>/dev/null; then
    pass "Secret 'db-credentials' exists in namespace"

    # Check it contains DB_PASSWORD
    SECRET_HAS_PASSWORD=$(kubectl get secret db-credentials -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.data}' 2>/dev/null | grep -c "DB_PASSWORD" || true)
    if [ "$SECRET_HAS_PASSWORD" -ge 1 ]; then
      pass "Secret 'db-credentials' contains DB_PASSWORD"
    else
      fail "Secret 'db-credentials' exists but does not contain DB_PASSWORD"
    fi

    # Check it contains DB_USER
    SECRET_HAS_USER=$(kubectl get secret db-credentials -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.data}' 2>/dev/null | grep -c "DB_USER" || true)
    if [ "$SECRET_HAS_USER" -ge 1 ]; then
      pass "Secret 'db-credentials' contains DB_USER"
    else
      fail "Secret 'db-credentials' exists but does not contain DB_USER"
    fi
  else
    fail "Secret 'db-credentials' not found in namespace '$NAMESPACE'"
  fi

  # Check 1g: worker deployment has sensible memory limits (>= 32Mi)
  WORKER_MEM_LIMIT=$(kubectl get deployment worker -n "$NAMESPACE" --request-timeout=5s \
    -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' \
    2>/dev/null || echo "")
  if [ -n "$WORKER_MEM_LIMIT" ]; then
    # Extract numeric value and unit
    MEM_VALUE=$(echo "$WORKER_MEM_LIMIT" | sed 's/[^0-9]//g')
    MEM_UNIT=$(echo "$WORKER_MEM_LIMIT" | sed 's/[0-9]//g')

    # Convert to Mi for comparison
    if [[ "$MEM_UNIT" == "Gi" ]]; then
      MEM_MI=$((MEM_VALUE * 1024))
    else
      MEM_MI=$MEM_VALUE
    fi

    if [ "$MEM_MI" -ge 32 ]; then
      pass "worker memory limit is $WORKER_MEM_LIMIT (sufficient)"
    else
      fail "worker memory limit is $WORKER_MEM_LIMIT — too low, OOMKilled will recur (minimum 32Mi recommended)"
    fi
  else
    fail "worker Deployment memory limit is not set"
  fi
}

# =============================================================================
# Challenge 2: Zero-Downtime Update
# =============================================================================
verify_ch02() {
  section "Challenge 2: Zero-Downtime Update"

  # Check 2a: learn-frontend deployment exists
  if kubectl get deployment learn-frontend -n "$NAMESPACE" --request-timeout=5s &>/dev/null; then
    pass "learn-frontend Deployment exists"
  else
    fail "learn-frontend Deployment not found — run the Challenge 2 setup"
  fi

  # Check 2b: learn-frontend is running nginx:1.25
  FRONTEND_IMAGE=$(kubectl get deployment learn-frontend -n "$NAMESPACE" --request-timeout=5s \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
  if [ "$FRONTEND_IMAGE" = "nginx:1.25" ]; then
    pass "learn-frontend is running nginx:1.25"
  else
    fail "learn-frontend is running '$FRONTEND_IMAGE' — expected nginx:1.25"
  fi

  # Check 2c: rolling update strategy is configured
  UPDATE_STRATEGY=$(kubectl get deployment learn-frontend -n "$NAMESPACE" --request-timeout=5s \
    -o jsonpath='{.spec.strategy.type}' 2>/dev/null || echo "")
  if [ "$UPDATE_STRATEGY" = "RollingUpdate" ]; then
    pass "learn-frontend uses RollingUpdate strategy"
  else
    fail "learn-frontend strategy is '$UPDATE_STRATEGY' — expected RollingUpdate"
  fi

  MAX_UNAVAILABLE=$(kubectl get deployment learn-frontend -n "$NAMESPACE" --request-timeout=5s \
    -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null || echo "")
  if [ "$MAX_UNAVAILABLE" = "0" ]; then
    pass "maxUnavailable is 0 (zero-downtime configured)"
  else
    warn "maxUnavailable is '$MAX_UNAVAILABLE' — should be 0 for guaranteed zero downtime"
  fi

  MAX_SURGE=$(kubectl get deployment learn-frontend -n "$NAMESPACE" --request-timeout=5s \
    -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null || echo "")
  if [ -n "$MAX_SURGE" ] && [ "$MAX_SURGE" != "0" ]; then
    pass "maxSurge is set to $MAX_SURGE"
  else
    warn "maxSurge is '$MAX_SURGE' — should be >= 1 when maxUnavailable is 0"
  fi

  # Check 2d: frontend pods are Running
  FRONTEND_RUNNING=$(kubectl get pods -n "$NAMESPACE" --request-timeout=5s \
    -l app=learn-frontend \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$FRONTEND_RUNNING" -ge 1 ]; then
    pass "learn-frontend has $FRONTEND_RUNNING Running pod(s)"
  else
    fail "learn-frontend has no Running pods"
  fi

  # Check 2e: rollout history shows at least one revision
  REVISION_COUNT=$(kubectl rollout history deployment/learn-frontend -n "$NAMESPACE" --request-timeout=5s \
    2>/dev/null | grep -c "^[0-9]" || true)
  if [ "$REVISION_COUNT" -ge 1 ]; then
    pass "learn-frontend rollout history has $REVISION_COUNT revision(s)"
  else
    warn "learn-frontend rollout history is empty — was a rollout performed?"
  fi
}

# =============================================================================
# Challenge 3: Autoscaling
# =============================================================================
verify_ch03() {
  section "Challenge 3: Autoscaling"

  # Check 3a: HPA exists for learn-frontend
  HPA_NAME=$(kubectl get hpa -n "$NAMESPACE" --request-timeout=5s --no-headers 2>/dev/null \
    | grep -E "learn-frontend" | awk '{print $1}' | head -1 || true)

  if [ -n "$HPA_NAME" ]; then
    pass "HPA for learn-frontend exists (name: $HPA_NAME)"

    # Check 3b: min replicas
    HPA_MIN=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "")
    if [ "$HPA_MIN" = "2" ]; then
      pass "HPA minReplicas is 2"
    else
      fail "HPA minReplicas is '$HPA_MIN' — expected 2"
    fi

    # Check 3c: max replicas
    HPA_MAX=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "")
    if [ "$HPA_MAX" = "10" ]; then
      pass "HPA maxReplicas is 10"
    else
      fail "HPA maxReplicas is '$HPA_MAX' — expected 10"
    fi

    # Check 3d: CPU target is configured
    HPA_CPU_TARGET=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null || echo "")
    if [ -n "$HPA_CPU_TARGET" ]; then
      pass "HPA CPU target is set to $HPA_CPU_TARGET%"
    else
      # Try autoscaling/v1 path
      HPA_CPU_TARGET_V1=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --request-timeout=5s \
        -o jsonpath='{.spec.targetCPUUtilizationPercentage}' 2>/dev/null || echo "")
      if [ -n "$HPA_CPU_TARGET_V1" ]; then
        pass "HPA CPU target is set to $HPA_CPU_TARGET_V1%"
      else
        fail "HPA does not have a CPU target metric configured"
      fi
    fi

    # Check 3e: HPA current replicas >= minReplicas
    HPA_CURRENT=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
    if [ "$HPA_CURRENT" -ge 2 ]; then
      pass "HPA current replicas is $HPA_CURRENT (at or above minimum)"
    else
      warn "HPA current replicas is $HPA_CURRENT — may still be initializing"
    fi

    # Check 3f: HPA has observed conditions (is active)
    HPA_CONDITIONS=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" --request-timeout=5s \
      -o jsonpath='{.status.conditions}' 2>/dev/null || echo "")
    if [ -n "$HPA_CONDITIONS" ] && [ "$HPA_CONDITIONS" != "null" ]; then
      pass "HPA has active status conditions (Metrics Server is reachable)"
    else
      warn "HPA conditions not populated — Metrics Server may still be initializing (wait 60s and re-run)"
    fi

  else
    fail "No HPA found targeting learn-frontend in namespace '$NAMESPACE'"
    echo "         Create one with: kubectl autoscale deployment learn-frontend --min=2 --max=10 --cpu-percent=50 -n $NAMESPACE"
  fi
}

# =============================================================================
# Execution
# =============================================================================

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

# =============================================================================
# Summary
# =============================================================================
TOTAL=$((PASS + FAIL))
echo ""
echo -e "${BOLD}=============================================${RESET}"
echo -e "${BOLD}  Chapter 7 Verification Results${RESET}"
echo -e "${BOLD}=============================================${RESET}"
echo -e "  Passed:   ${GREEN}$PASS${RESET}"
echo -e "  Failed:   ${RED}$FAIL${RESET}"
if [ "$WARNINGS" -gt 0 ]; then
  echo -e "  Warnings: ${YELLOW}$WARNINGS${RESET}"
fi
echo -e "  Total:    $TOTAL checks"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed.${RESET}"
  if [ "$TARGET_CHALLENGE" = "all" ]; then
    echo -e "${GREEN}${BOLD}Chapter 7 complete.${RESET}"
    echo ""
    echo "  Sarah says: \"The dashboard is green. Dave just landed and"
    echo "  everything looks fine. You handled your first production"
    echo "  incident. Welcome to the team — for real this time.\""
    echo ""
    echo "  Read the Graduation section in:"
    echo "  curriculum/ch07-k8s-production/README.md"
  fi
  exit 0
else
  echo -e "${RED}${BOLD}$FAIL check(s) failed.${RESET}"
  echo ""
  echo "  Re-read the challenge file for the failing section."
  echo "  Use 'kubectl describe' and 'kubectl logs' to investigate."
  echo "  Run this script again after making your fix."
  exit 1
fi
