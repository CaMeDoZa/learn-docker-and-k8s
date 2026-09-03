# Validation Guide

## How to Verify Challenges

### Priority Order
1. If `challenges/verify.sh` exists for the chapter, run it
2. If not, use the inline verification commands specified in each challenge file
3. As a last resort, use Docker/kubectl inspection commands

### verify.sh Contract

Every `verify.sh` follows this contract:

```bash
#!/bin/bash
# Usage: ./verify.sh [challenge_number|all]
# Exit 0 = all checks passed
# Exit 1 = one or more checks failed
# Output: human-readable status for each check
```

# Example check pattern:
check_result() {
    local description="$1"
    local command="$2"

    if eval "$command" > /dev/null 2>&1; then
        echo "PASS: $description"
    else
        echo "FAIL: $description"
        FAILED=1
    fi
}
```

### Common Verification Patterns

#### Container Running
```bash
docker ps --filter "name=learn-ch01-nginx" --filter "status=running" -q | grep -q .
```

#### Port Accessible
```bash
curl -sf http://localhost:8080 > /dev/null
```

#### Image Size Below Threshold
```bash
size=$(docker image inspect learn-ch02-app:optimized --format '{{.Size}}')
[ "$size" -lt 104857600 ]  # 100MB in bytes
```

#### Volume Exists and Has Data
```bash
docker volume inspect learn-ch03-db-data > /dev/null 2>&1
```

#### Network Connectivity Between Containers
```bash
docker exec learn-ch04-frontend ping -c 1 learn-ch04-backend > /dev/null 2>&1
```

#### Container Name Resolution
```bash
docker exec learn-ch04-frontend nslookup learn-ch04-backend > /dev/null 2>&1
```

#### K8s Pod Count Matches
```bash
count=$(kubectl get pods -n learn-ch06 -l app=nginx --field-selector status.phase=Running --no-headers | wc -l)
[ "$count" -eq 3 ]
```

#### K8s Service Endpoint Reachable
```bash
kubectl run learn-test-curl --rm -i --restart=Never -n learn-ch06 --image=curlimages/curl -- curl -sf http://frontend-svc:80
```

### Verification Output Format

When reporting to the player:

**All Passed:**
```
=== Challenge Verification ===
PASS: Container 'learn-ch01-nginx' is running
PASS: Port 8080 is accessible
PASS: Response contains "Welcome to nginx"

All checks passed! Challenge complete!
```

**Some Failed:**
```
=== Challenge Verification ===
PASS: Container 'learn-ch01-nginx' is running
FAIL: Port 8080 is not accessible
HINT: Check if you mapped the port correctly with -p

1 of 2 checks passed. Keep going!
```
