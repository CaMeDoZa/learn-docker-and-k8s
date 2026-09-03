---
name: verify
description: Verify if the current challenge is completed in Learn Docker & K8s. Runs the verification script and reports results. Use when the user says "check", "verify", "did I do it right", "am I done", or "test my solution".
---

# Verify Challenge Completion

## Step 1: Determine Current Challenge

Read `.player/progress.yaml` to find the current chapter and challenge number.

## Step 2: Run Verification

Check if a `verify.sh` exists for the current chapter:

```bash
ls curriculum/chXX-*/challenges/verify.sh
```

If it exists, run it for the current challenge (or omit argument to run all):
```bash
bash curriculum/chXX-*/challenges/verify.sh [challenge_number]
```
For example, to verify challenge 1:
```bash
bash curriculum/ch01-containers/challenges/verify.sh 1
```
Or to verify all challenges in the chapter:
```bash
bash curriculum/ch01-containers/challenges/verify.sh all
```

If it doesn't exist, read the challenge file and check the success criteria manually using Docker/kubectl commands.

## Step 3: Report Results

### All Checks Passed

1. Celebrate! Use Sarah's voice: "Nailed it! Dave is going to be so relieved."
2. Deliver the **post-mission debrief** (from the challenge file or chapter README):
   - **What you did:** Brief summary
   - **Why it works:** The underlying concept
   - **Real-world connection:** When you'd see this at work
   - **Interview angle:** How this comes up in interviews
   - **Pro tip:** Advanced insight
3. Update `.player/progress.yaml`: add challenge number to completed list
4. Check if all challenges in the chapter are done:
   - If yes: mark chapter as completed, deliver chapter-end story beat, tease next chapter
   - If no: offer to move to the next challenge

### Some Checks Failed

1. Show which checks passed and which failed
2. Give a gentle hint about the failing check WITHOUT giving the answer
3. Encourage them: "Almost there — one thing is off. Take another look at..."
4. Remind them they can use `/hint` if stuck

### No Challenges Started

If they haven't started any challenge yet, let them know: "Nothing to verify yet! Want to start a challenge?"

## Important

- Read `engine/validation.md` for the verification patterns
- Always run the actual check — don't assume success
- Be specific about what failed without revealing the fix
