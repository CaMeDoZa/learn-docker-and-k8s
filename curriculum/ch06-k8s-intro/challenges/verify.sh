#!/bin/bash
# Chapter 6 Verification Script
# Checks all three challenges: self-healing, service discovery, and CrashLoop fix
# Exit 0 = all checks passed
# Exit 1 = one or more checks failed

set -u

TARGET_CHALLENGE="${1:-all}"
PASSED=0
FAILED=0
NAMESPACE="learn-ch06"
CLUSTER_NAME="learn-k8s"
CONTEXT="${KUBE_CONTEXT:-kind-${CLUSTER_NAME}}"

# ─── Helpers ──────────────────────────────────────────────────────────────────

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

# ─── Pre-flight ───────────────────────────────────────────────────────────────

echo "=== Chapter 6: The Giant Roaster — Verification ==="
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "  ERROR: kubectl is not installed. Cannot verify chapter 6."
    exit 1
fi

# Check kind is available (unless custom context specified)
if [ -z "${KUBE_CONTEXT:-}" ] && ! command -v kind &> /dev/null; then
    echo "  ERROR: kind is not installed. Cannot verify chapter 6."
    exit 1
fi

# ─── Cluster Check ────────────────────────────────────────────────────────────

echo "[Cluster]"

# Check kind cluster exists (if using kind)
if [ -z "${KUBE_CONTEXT:-}" ]; then
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        pass "kind cluster '${CLUSTER_NAME}' exists"
    else
        fail "kind cluster '${CLUSTER_NAME}' not found (run: kind create cluster --name ${CLUSTER_NAME})"
    fi
fi

# Check kubectl can reach the cluster
if kubectl cluster-info --context "${CONTEXT}" --request-timeout=5s > /dev/null 2>&1; then
    pass "kubectl can connect to context '${CONTEXT}'"
else
    fail "kubectl cannot connect to context '${CONTEXT}' (run: kubectl cluster-info --context ${CONTEXT})"
fi

# Check namespace exists
if kubectl get namespace "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s > /dev/null 2>&1; then
    pass "Namespace '${NAMESPACE}' exists"
else
    fail "Namespace '${NAMESPACE}' not found (run: kubectl create namespace ${NAMESPACE})"
fi

echo ""

# ─── Challenge 1: Self-Healing ────────────────────────────────────────────────

verify_ch01() {
    echo "[Challenge 1: Self-Healing — nginx Deployment with 3 replicas]"

    # Check Deployment exists
    check "Deployment 'learn-nginx' exists in ${NAMESPACE}" \
        "kubectl get deployment learn-nginx -n ${NAMESPACE} --context ${CONTEXT} --request-timeout=5s"

    # Check desired replicas
    DESIRED=$(kubectl get deployment learn-nginx -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "${DESIRED}" -eq 3 ]; then
        pass "Deployment 'learn-nginx' has 3 desired replicas"
    else
        fail "Deployment 'learn-nginx' has ${DESIRED} desired replicas (expected 3)"
    fi

    # Check 3 Pods are Running
    RUNNING_COUNT=$(kubectl get pods -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s \
        -l app=nginx \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${RUNNING_COUNT}" -ge 3 ]; then
        pass "3 nginx Pods are Running in ${NAMESPACE} (found ${RUNNING_COUNT})"
    else
        fail "Expected 3 Running nginx Pods, found ${RUNNING_COUNT} (check: kubectl get pods -n ${NAMESPACE} -l app=nginx)"
    fi

    echo ""
}

# ─── Challenge 2: Service Discovery ──────────────────────────────────────────

verify_ch02() {
    echo "[Challenge 2: Service Discovery — frontend/backend with ClusterIP Service]"

    # Check backend Deployment exists
    check "Deployment 'learn-backend' exists in ${NAMESPACE}" \
        "kubectl get deployment learn-backend -n ${NAMESPACE} --context ${CONTEXT} --request-timeout=5s"

    # Check backend-svc Service exists
    check "Service 'backend-svc' exists in ${NAMESPACE}" \
        "kubectl get service backend-svc -n ${NAMESPACE} --context ${CONTEXT} --request-timeout=5s"

    # Check Service type is ClusterIP
    SVC_TYPE=$(kubectl get service backend-svc -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s \
        -o jsonpath='{.spec.type}' 2>/dev/null || echo "unknown")
    if [ "${SVC_TYPE}" = "ClusterIP" ]; then
        pass "Service 'backend-svc' is of type ClusterIP"
    else
        fail "Service 'backend-svc' type is '${SVC_TYPE}' (expected ClusterIP)"
    fi

    # Check Service has Endpoints (Pods are backing it)
    ENDPOINT_COUNT=$(kubectl get endpoints backend-svc -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s \
        -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
    if [ "${ENDPOINT_COUNT}" -ge 1 ]; then
        pass "Service 'backend-svc' has ${ENDPOINT_COUNT} endpoint(s) configured"
    else
        fail "Service 'backend-svc' has no endpoints — selector may not match backend Pod labels"
    fi

    # Check connectivity: curl from within the cluster to backend-svc
    echo "  INFO: Verifying in-cluster connectivity to backend-svc (may take 10-15s)..."
    kubectl delete pod learn-ch06-verify-curl -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s --ignore-not-found=true 2>/dev/null || true
    if kubectl run learn-ch06-verify-curl \
        --rm -i \
        --restart=Never \
        -n "${NAMESPACE}" \
        --context "${CONTEXT}" \
        --timeout=30s \
        --image=curlimages/curl:latest \
        -- curl -sf --connect-timeout 5 --max-time 10 "http://backend-svc:80" > /dev/null 2>&1; then
        pass "In-cluster curl to 'http://backend-svc' succeeded"
    else
        fail "In-cluster curl to 'http://backend-svc' failed — check backend Pods are Running and Service selector matches"
    fi

    echo ""
}

# ─── Challenge 3: CrashLoop Fix ───────────────────────────────────────────────

verify_ch03() {
    echo "[Challenge 3: CrashLoop Fix — learn-cloudbrew Deployment]"

    # Check Deployment exists
    check "Deployment 'learn-cloudbrew' exists in ${NAMESPACE}" \
        "kubectl get deployment learn-cloudbrew -n ${NAMESPACE} --context ${CONTEXT} --request-timeout=5s"

    # Check no Pods in CrashLoopBackOff or ImagePullBackOff
    BAD_PODS=$(kubectl get pods -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s \
        -l app=cloudbrew \
        --no-headers 2>/dev/null \
        | awk '{print $3}' \
        | grep -E "CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error" \
        | wc -l | tr -d ' ')
    if [ "${BAD_PODS}" -eq 0 ]; then
        pass "No Pods in CrashLoopBackOff/ImagePullBackOff/ErrImagePull in ${NAMESPACE}"
    else
        fail "${BAD_PODS} Pod(s) still in a failed state — run 'kubectl describe pod <name> -n ${NAMESPACE}' to diagnose"
    fi

    # Check 2 cloudbrew Pods are Running
    CLOUDBREW_RUNNING=$(kubectl get pods -n "${NAMESPACE}" --context "${CONTEXT}" --request-timeout=5s \
        -l app=cloudbrew \
        --field-selector=status.phase=Running \
        --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${CLOUDBREW_RUNNING}" -ge 2 ]; then
        pass "2+ cloudbrew Pods are Running (found ${CLOUDBREW_RUNNING})"
    else
        fail "Expected 2+ Running cloudbrew Pods, found ${CLOUDBREW_RUNNING}"
    fi

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

echo "=== Summary ==="
echo "  Passed: ${PASSED}"
echo "  Failed: ${FAILED}"
echo ""

if [ "${FAILED}" -eq 0 ]; then
    echo "All checks passed!"
    if [ "$TARGET_CHALLENGE" = "all" ]; then
        echo "Chapter 6 complete."
        echo ""
        echo "Dave sent a voice memo. He sounds relieved."
        echo "The cluster is healthy. Time for a well-earned coffee."
    fi
    exit 0
else
    echo "${FAILED} check(s) failed. Review the output above and try again."
    echo ""
    echo "Quick diagnostic commands:"
    echo "  kubectl get pods -n ${NAMESPACE}"
    echo "  kubectl get deployments -n ${NAMESPACE}"
    echo "  kubectl get services -n ${NAMESPACE}"
    echo "  kubectl describe pod <pod-name> -n ${NAMESPACE}"
    exit 1
fi
