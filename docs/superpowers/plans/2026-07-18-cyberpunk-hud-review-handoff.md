# Handoff playbook — finish reviewing PR #21 and #22 (Cyberpunk HUD)

**For:** Codex (gpt-5.6-sol). **Repo:** `thewrz/plasma-applet-cellsignal` (local: `~/github/plasma-applet-cellsignal`).
**Author of this handoff:** Claude Fable 5 (ran out of token budget mid-loop).
**Attribution:** you are Codex — sign your commits `Co-Authored-By: Codex <noreply@openai.com>`, NOT Claude.

## Where things stand (live state at handoff)

Two stacked draft PRs, both already implemented + hardened by an ultracode workflow (19 agents,
4 findings fixed each). They are code-complete and independently verified green:

- **PR #21** `feat/contract-v2-feeder` → base `main`. Contract v2 + feeder. `pytest`: 54 pass, fixtures
  carry v1+v2, zero identifier leaks. Worktree: `~/github/plasma-applet-cellsignal-pr-21` (already created).
- **PR #22** `feat/cyberpunk-widget` → base `feat/contract-v2-feeder` (STACKED). qmllint exit 0.
  Not yet started in the review loop.

**In flight for #21 (started; Codex done, CodeRabbit pending):**
1. A manual `@coderabbitai full review` was posted on #21 (it had skipped as a draft). CodeRabbit
   was rate-limited earlier this session — verify its real state (comment body) before trusting a green check.
   Collect its threads when it lands.
2. **Codex #21 verdict already in (`/tmp/codex_pr_21.txt`) — 1 finding, VERIFIED REAL, START HERE:**
   - **[P2] `feeders/xmm7360/cellsignal-feeder-xmm7360:~209` — negative operator lookups bypass the cache.**
     `parse_cops_operator` returns `None` for a numeric-PLMN / no-operator `AT+COPS?` reply, and
     `write_operator_cache` refuses to write falsey values — so every 2 s tick re-queries `COPS`,
     defeating the TTL and extending shared AT-port lock time. **Fix:** cache the negative result too
     (write a sentinel/timestamp so a `None` lookup is also honored for `OP_TTL`; on read, distinguish
     "cached None, still fresh" from "no cache"). Re-run `pytest` (add a test that a `None` COPS result is
     not re-queried within the TTL). This is the same operator-cache area the ultracode finalize already
     touched (mtime TTL) — extend it to negative results.
   Document the outcome as a PR comment (Codex findings have no thread).

## Your job

Run the `review-remote-pr` skill loop to completion on **#21 first**, then **#22**. The skill file is at
`~/.claude/skills/review-remote-pr/SKILL.md` — read and follow it; the mechanics below are the compressed
version plus the repo-specific gotchas already learned this session.

### The loop, per PR (from `~/github/plasma-applet-cellsignal-pr-<N>`)

```bash
export REPO=thewrz/plasma-applet-cellsignal PR=21   # then 22
```

1. **Collect reviews.**
   - CodeRabbit health: fetch `gh api repos/$REPO/issues/$PR/comments --paginate | jq -s add`; a green
     check is NOT proof — look in the comment BODY for `actionable comments posted` / `<summary>walkthrough`
     (=reviewed) vs `rate limit` (=rate-limited). This org's CodeRabbit has been rate-limited repeatedly
     today; if so, Codex is the gate — do not wait on CodeRabbit, do not "buy credits" (fair-usage throttle).
   - Inline threads via GraphQL (need the `PRRT_...` node id to resolve): see skill Step 1.
   - Codex verdict: the tail `^codex$` block of `/tmp/codex_pr_$PR.txt` (for #22 you must launch it:
     `cd worktree && git fetch origin feat/contract-v2-feeder && codex review --base origin/feat/contract-v2-feeder > /tmp/codex_pr_22.txt 2>&1 &`).
     Config preset is already gpt-5.6-sol / high — pass NO `-m`/effort flags.

2. **Verify every finding against the actual code before acting.** Both reviewers overstate/false-positive.
   Read the cited file (`git -C ~/github/plasma-applet-cellsignal show origin/<branch>:<path>`). Drop what
   doesn't reproduce. This codebase's real invariants to check findings against:
   - **Privacy is contract law**: no IMEI/ICCID/IMSI anywhere; TAC/CID/PCI parsed-past, never in
     `build_contract` output or fixtures. A finding claiming a leak is CRITICAL if real — confirm by grep.
   - **Contract back-compat**: widget must accept `version` 1 OR 2; absent v2 blocks (`aggregation`,
     `neighbors`) must be null-safe in QML.
   - **The HUD is intentionally always-dark** (approved single-look). Do NOT accept a finding that flags
     hardcoded dark colors as a "theme violation" — that's by design. DO accept findings that an accent
     bypasses `HudStyle` (the signal-reactive color engine).
   - Feeder must keep-last on AT failure and atomic-write `/run/cellsignal.json`.

3. **Fix or decline**, in skill Step 3 order (body nitpicks first → Codex findings → CodeRabbit threads
   reply-THEN-resolve last). Commit fixes on the PR's own branch from its worktree. Verify locally before
   push:
   - #21: `python3 -m pytest tests/ -q` (must stay 54+ green), `python3 -m json.tool fixtures/*.json`,
     `python3 -m py_compile feeders/xmm7360/*`.
   - #22: `qmllint package/contents/ui/*.qml package/contents/ui/hud/*.qml package/contents/config/*.qml`
     (exit 0; import-resolution warnings OK, syntax/logic errors not), `xmllint --noout` the config xml,
     `python3 -m json.tool package/metadata.json`. NO GUI here — the visual pass stays the user's.
   - Document Codex outcomes as PR comments (no thread to resolve); reply+resolve each CodeRabbit thread
     individually (NEVER bulk `@coderabbitai resolve`).

4. **Exit** when CI green + all CodeRabbit threads reply+resolved + body nitpicks handled + every confirmed
   Codex finding fixed/declined-with-comment. Cap: 3 cycles, then summarize and stop.

### Repo/session gotchas (already cost time — don't rediscover)

- Draft PRs: CodeRabbit auto-skips; a manual `@coderabbitai full review` is required (done for #21).
- `cmd | python3 << 'EOF'` breaks (pipe+heredoc share stdin) — write JSON to a temp file first, then read it.
- Never `python3 -c "multi-line"` in zsh — use a heredoc or a file.
- Branch protection blocks direct pushes to `main`; merges go through PRs (admin-merge is how the user has
  been landing them).
- `gh pr checks` exits 8 on pending — append `|| true`.

## After both PRs are green

1. **Merge order: #21 → main first.** Then retarget #22 to main (`gh pr edit 22 --base main`) and merge —
   the stack resolves cleanly. The user prefers to click merge themselves; present them as ready, don't
   auto-merge unless they say so.
2. **Deploy (needs the user + sudo)** — feeder gained AT commands, so reinstall it:
   ```
   cd ~/github/plasma-applet-cellsignal/feeders/xmm7360
   sudo install -Dm755 cellsignal-feeder-xmm7360 /usr/local/bin/cellsignal-feeder-xmm7360
   sudo install -Dm755 xmm7360_decode.py /usr/local/bin/xmm7360_decode.py
   sudo install -Dm644 cellsignal-xmm7360.service /etc/systemd/system/cellsignal-xmm7360.service
   sudo systemctl daemon-reload && sudo systemctl restart cellsignal-xmm7360.timer
   kpackagetool6 -t Plasma/Applet -u package/ && systemctl --user restart plasma-plasmashell
   ```
3. **The visual pass is the user's** — no agent has *seen* the neon render. Expect a tweak or two on glow
   intensity / spacing once it's real; that's a quick iteration, not a rebuild.
4. **Modem wedge warning**: do NOT run GNSS AT probes (`AT%GPS` / `XLCSLSR` / `GTCFGNMEA`) — they wedge the
   baseband into `A-CD_READY` which only `systemctl suspend` THEN `sudo lte recover` clears (see the
   `wrz-p52-lte-modem` memory). Read-only telemetry (XMCI/GTCAINFO/CSCON/COPS) is safe.

## Context / design source of truth

- Spec: `docs/superpowers/specs/2026-07-18-cyberpunk-hud-design.md` (on `main`) — contract v2 field table,
  feeder decode sources, HUD component breakdown, signal-reactive color thresholds.
- Hardware decode provenance: issue #15 comments (AT+XMCI/GTCAINFO/CSCON captured shapes, TA→distance).
- Closed as out-of-scope: #12/#13/#14 (GPS — no wired antenna). Open non-HUD roadmap: #16 mmcli feeder,
  #17 store.kde.org publish.
