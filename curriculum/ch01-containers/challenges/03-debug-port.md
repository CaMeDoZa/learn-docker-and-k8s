# Challenge 03: Debug the Unreachable Container

*Sarah speaking:* Here's one I see constantly — even from experienced engineers. A container is running, Docker says it's healthy, but you can't reach it. The instinct is to restart it, check the firewall, or blame the network. But the answer is almost always simpler than that.

This one's a debugging challenge. I'm not going to tell you what's wrong. Figure it out.

---

## The Situation

A teammate started an nginx container for a quick test. They confirmed it's running. But when they try to open it in the browser, nothing loads. They've been staring at it for 20 minutes. Sound familiar?

---

## Setup

First, start the broken container exactly as your teammate did:

```bash
docker run -d \
  --name learn-ch01-broken \
  --label app=learn-docker-k8s \
  --label chapter=ch01 \
  nginx
```

Now try to access it:

```bash
curl http://localhost:8081
```

You'll get something like:
```
curl: (7) Failed to connect to localhost port 8081 after 0 ms: Connection refused
```

The container is running. You can verify:

```bash
docker ps --filter "name=learn-ch01-broken"
```

Status shows `Up`. But it's not reachable.

---

## Your Mission

1. **Diagnose** why the container is unreachable
2. **Fix it** — get nginx accessible at `http://localhost:8081`

The fix means stopping the broken container, removing it, and running a corrected version still named `learn-ch01-broken` on port 8081 (using port 8081 so it doesn't collide with `learn-ch01-nginx` on 8080).

---

## Requirements

Your fixed container must:

- Be named `learn-ch01-broken`
- Serve nginx content at `http://localhost:8081`
- Have both labels:
  - `--label app=learn-docker-k8s`
  - `--label chapter=ch01`

---

## Success Criteria

```bash
curl -s http://localhost:8081 | grep "Welcome to nginx"
```

You can also run the verification script:

```bash
bash curriculum/ch01-containers/challenges/verify.sh 3
```

---

## Hints

<details>
<summary>Hint 1 — How to investigate</summary>

When a container is running but unreachable, the first question is: does the container have any port mapping? Look at the output of `docker ps` carefully. What does the PORTS column show for `learn-ch01-broken`?

Compare it to a container you know is working correctly.

</details>

<details>
<summary>Hint 2 — What the PORTS column means</summary>

If the PORTS column is empty, the container has no ports exposed to the host. The container's nginx is listening on port 80 *inside* the container, but nothing is forwarding traffic from your host to that port.

Think of it like a room with no doors. The party is happening inside, but there's no way in from the outside.

The `-p` flag creates that door. Look at how you used `-p` in Challenge 01.

</details>

<details>
<summary>Hint 3 — The fix</summary>

You can't add port mapping to a running container. You need to stop it, remove it, and recreate it with the right flag.

```bash
docker stop learn-ch01-broken
docker rm learn-ch01-broken
```

Then run it again with the same name and labels — but this time include the flag that maps host port 8081 to the container's port 80 (`-p 8081:80`).

</details>

---

## Why This Matters

This is one of the most common Docker mistakes in the wild. The `EXPOSE` instruction in a Dockerfile (and the "Exposed Ports" in `docker inspect`) documents which port the app uses, but it **does not** publish that port to the host. Only `-p` does that.

If you understand this, you've just leveled past probably half the "Docker networking broken" Stack Overflow questions that get posted every day.

---

## Cleanup

```bash
docker stop learn-ch01-broken && docker rm learn-ch01-broken
```
