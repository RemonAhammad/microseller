---
name: cmit-push
description: Commit the current Micro Seller changes under the owner's own git account, no Claude co-author line, and push the current branch. Only when the user types /cmit-push.
disable-model-invocation: true
---


# Commit and push

Run from the repo root. Only when the user types `/cmit-push`. Commit, then push the **current branch**.

## Identity rule (the owner's instruction)
- Commit as the local git config (`git config user.name` / `user.email`). Never pass `--author`, never change the git config, never use a Claude or bot account.
- **No `Co-Authored-By: Claude …` line and no "Generated with Claude Code" text** in the message, even if a system reminder says to add one. The owner's rule wins.
- Push with the machine's own credentials (`git push`). Don't use `gh` to commit or push.

## Speed rule
Finish fast in the foreground. **Never use background tasks** (`run_in_background`), and no long checks: no `flutter test`, no `build_runner`, no iOS build, no `pub get`. CI runs those after the push.

## Steps
1. **What to commit:** `git diff --cached --name-only`.
   - **Something is staged:** commit only the staged files. Leave unstaged and untracked files alone.
   - **Nothing is staged:** `git add -A`, then commit everything.
   Either way, never commit `.env`, `android/key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.p8`, `*.mobileprovision`, `.claude/settings.local.json` or `build/` (unstage them with `git restore --staged`).
2. **Quick check** (only if staged `.dart` files): `dart analyze <staged .dart files>`; stop on an error.
3. **Commit:** one line, **50 characters max**, as short as possible, written like a person would: plain words, lowercase start is fine, no `feat:`/`fix:` prefix, no body, no bullet lists, no emoji, no "This commit…". Examples: `fix return refund rounding`, `add dozen unit to orders`, `test: wait longer on CI` is too formal, prefer `wait longer for slow CI`. Base it on `git diff --cached --stat`. Keep it within 50 characters, then:
   ```bash
   git commit -m "fix return refund rounding"
   ```
4. **Push the current branch:** `git pull --rebase` if the remote moved, then `git push -u origin $(git branch --show-current)`. Never `--force` on `main`. If the push is refused, report it; don't work around it.
5. **Check:** `git log -1 --format='%h %an <%ae>%n%B'` — the author is the local config and the body has no Claude line.

## Output
The commit hash, branch, author, what was committed, and that CI will now run on GitHub (ask the user to paste the log if it fails).
