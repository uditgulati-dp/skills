---
name: pr-review-followup
description: Lists the user's open GitHub pull requests in dialpad/firespotter that still have unresolved review threads, unanswered reviewer comments, or open CHANGES_REQUESTED reviews, then drafts a proposed solution summary for each item. Use when the user wants to triage PR review feedback, see what needs a reply, or get suggestions for addressing reviewer comments. Defaults to repo dialpad/firespotter and the currently authenticated `gh` user as author; both can be overridden.
---

# PR Review Follow-up

Helps the user triage review feedback on their open pull requests. For each PR that still has something unresolved, propose a concrete solution per comment grounded in the actual code.

## Defaults

- Repo: `dialpad/firespotter`
- Author: the login of the currently authenticated `gh` user (`gh api user --jq .login`)

If the user passes arguments, override accordingly. Recognized forms:
- `--repo owner/name`
- `--author login`
- `--pr <number>` (focus on a single PR)
- `--reviewer login` (repeatable, or comma-separated: `--reviewer alice,bob`). Exact login match. Default: all reviewers.
- `--no-bots` drops comments/reviews authored by `*[bot]` accounts and a built-in denylist (`github-actions`, `coderabbitai`, `dependabot`, `codecov`, `sonarcloud`, `sonarqubecloud`). For review threads this is judged by the **originating** comment's author.

When the user mentions a reviewer by name (e.g. "only show comments from alice"), translate that to `--reviewer alice`. If they say "ignore bots" / "skip noise" / "hide coderabbit", add `--no-bots`.

## Prerequisites

- `gh` CLI authenticated (`gh auth status`).
- `jq` available.

## Step 1 — Fetch unresolved items

Run from the skill directory (use the absolute path to this skill, not `cd`):

```bash
bash .pi/skills/pr-review-followup/scripts/fetch-unresolved.sh \
  [--repo owner/name] [--author login] [--pr N] \
  [--reviewer login[,login...]] [--no-bots]
```

Output is a JSON array. Each element is a PR with at least one of:
- `unresolvedThreads[]` — GitHub review threads where `isResolved=false`. Each has `path`, `line`, `isOutdated`, `diffHunk`, and the full `comments[]` chain.
- `unansweredIssueComments[]` — top-level PR conversation comments by someone other than the PR author where the author has not replied afterward.
- `openReviews[]` — reviews in `CHANGES_REQUESTED` not later superseded by an `APPROVED`/`DISMISSED` review from the same reviewer. The review `body` is the overall summary; line-level feedback lives in `unresolvedThreads`.

If the array is empty, tell the user there are no PRs needing follow-up and stop.

## Step 2 — Ground each comment in code

For every unresolved item:

1. Note the PR's `headRefName`. The local working tree may not be on that branch — do **not** check it out. Instead, read the file at `HEAD` of that branch via:
   ```bash
   gh api "repos/<owner>/<repo>/contents/<path>?ref=<headRefName>" --jq '.content' | base64 -d
   ```
   Or just read the local file if the user confirms they're on the same branch.
2. Look at the surrounding code (use `read` with an `offset` near `line`, ±40 lines of context) to understand what the reviewer is referring to. The `diffHunk` shows what the comment was anchored to originally; the file may have moved on.
3. If `isOutdated=true`, mention that the thread is on stale code and verify whether the concern still applies.

Do not blindly trust the comment — check the code.

## Step 3 — Produce the report

Output Markdown with this shape:

```markdown
# Open PRs needing follow-up

## #<number> — <title>
<url>

### Unresolved review threads
- **`<path>:<line>`** (outdated: yes/no) — @<reviewer>: "<short quote>"
  - **Proposed solution:** <1–4 sentence concrete fix referencing real symbols/lines>
  - **Reply draft:** <one-paragraph reply the user can paste into GitHub>

### Unanswered comments
- @<author> on <date>: "<short quote>"
  - **Proposed solution / reply:** ...

### Open change requests
- @<reviewer> (CHANGES_REQUESTED on <date>): "<summary quote>"
  - **Proposed solution:** ...
```

Quote rules: keep each quoted snippet ≤ ~200 chars; include the quote so the user recognizes it without opening GitHub. Multi-comment threads: summarize the conversation, not just the first comment.

Proposed solutions must be **specific** — name the function/file/line you'd change and what the change is. Vague suggestions ("consider refactoring") are not acceptable. If you genuinely cannot tell from the code, say so and list what you'd need to check.

## Step 4 — Offer next actions

After the report, ask the user whether they want to:
1. Draft commits/edits for any of the proposed solutions
2. Post replies via `gh pr comment` / `gh api` (review thread replies need GraphQL `addPullRequestReviewThreadReply`)
3. Resolve threads (`resolveReviewThread` GraphQL mutation) once addressed

Do not take any of these actions without explicit confirmation.

## Notes

- "Unanswered" is heuristic: a non-author top-level comment with no later author reply. A reviewer's question answered only inside a review thread will still appear here — flag that possibility in the report when relevant.
- Bot filtering: prefer `--no-bots` over post-filtering. The flag judges review threads by the originating comment's author, so a bot-started thread is dropped even if a human replied to it. If that's not what the user wants, run without `--no-bots` and filter in the report.
- Reviewer filter is exact-match on GitHub login (case-sensitive). If the user gives a display name, ask for the login or look it up via `gh api repos/<owner>/<repo>/pulls/<n>/reviews --jq '.[].user.login'`.
- Rate limits: the script does one GraphQL call per open PR. For users with >50 open PRs, consider `--pr` to target one.
