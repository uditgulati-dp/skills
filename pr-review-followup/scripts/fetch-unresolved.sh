#!/usr/bin/env bash
# Fetch open PRs by a given author in a repo and emit unresolved review threads
# + unanswered top-level issue comments and pending review feedback as JSON.
#
# Usage:
#   ./fetch-unresolved.sh [--repo owner/name] [--author login] [--pr <number>]
#                         [--reviewer login[,login...]] [--no-bots]
#
# Defaults: repo=dialpad/firespotter author=uditgulati-dp reviewer=<all>
#
# --reviewer  Comma-separated list (or repeatable flag) of reviewer logins to
#             keep. Matches the comment/review author. Substring/glob is NOT
#             applied — exact login match. Default: all reviewers.
# --no-bots   Drop comments/reviews authored by bot accounts (login ending in
#             "[bot]" or in a small built-in denylist: github-actions,
#             coderabbitai, dependabot, codecov, sonarcloud, sonarqubecloud).
#
# Output: JSON array on stdout. One object per PR that has at least one
# unresolved/unanswered item. Schema:
# [
#   {
#     "number": 123,
#     "title": "...",
#     "url": "...",
#     "headRefName": "...",
#     "author": "...",
#     "unresolvedThreads": [
#       {
#         "threadId": "...",
#         "path": "src/foo.js",
#         "line": 42,
#         "diffHunk": "...",
#         "isOutdated": false,
#         "comments": [
#           { "author": "x", "createdAt": "...", "body": "..." }
#         ]
#       }
#     ],
#     "unansweredIssueComments": [
#       { "id": "...", "author": "x", "createdAt": "...", "body": "..." }
#     ],
#     "openReviews": [
#       { "author": "x", "state": "CHANGES_REQUESTED", "submittedAt": "...", "body": "..." }
#     ]
#   }
# ]
#
# "Unresolved review thread": GitHub's native isResolved=false on a review thread.
# "Unanswered issue comment": a top-level PR comment by someone other than the
#    PR author where the most recent comment in the conversation is also not by
#    the PR author (i.e. author has not replied after it).
# "Open review": a review with state CHANGES_REQUESTED that has not been
#    dismissed/superseded by a later APPROVED review from the same reviewer.

set -euo pipefail

REPO="dialpad/firespotter"
AUTHOR="uditgulati-dp"
SINGLE_PR=""
REVIEWERS=""     # empty = all
NO_BOTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --author) AUTHOR="$2"; shift 2;;
    --pr) SINGLE_PR="$2"; shift 2;;
    --reviewer)
      if [[ -z "$REVIEWERS" ]]; then REVIEWERS="$2"; else REVIEWERS="$REVIEWERS,$2"; fi
      shift 2;;
    --no-bots) NO_BOTS=1; shift;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

# Build a JSON array of allowed reviewers (empty = allow all)
if [[ -n "$REVIEWERS" ]]; then
  REVIEWERS_JSON=$(printf '%s' "$REVIEWERS" | tr ',' '\n' | jq -R . | jq -s 'map(select(length>0))')
else
  REVIEWERS_JSON='[]'
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

if [[ -n "$SINGLE_PR" ]]; then
  PR_NUMBERS="$SINGLE_PR"
else
  PR_NUMBERS=$(gh pr list --repo "$REPO" --author "$AUTHOR" --state open --limit 100 --json number --jq '.[].number' | tr '\n' ' ')
fi

if [[ -z "${PR_NUMBERS// }" ]]; then
  echo "[]"
  exit 0
fi

# GraphQL query for one PR: meta + review threads + issue comments + reviews
read -r -d '' QUERY <<'GQL' || true
query($owner:String!, $name:String!, $number:Int!) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      number
      title
      url
      headRefName
      author { login }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          diffSide
          comments(first: 50) {
            nodes {
              author { login }
              createdAt
              body
              diffHunk
            }
          }
        }
      }
      comments(first: 100) {
        nodes {
          id
          author { login }
          createdAt
          body
        }
      }
      reviews(first: 100) {
        nodes {
          author { login }
          state
          submittedAt
          body
        }
      }
    }
  }
}
GQL

results="[]"

for n in $PR_NUMBERS; do
  raw=$(gh api graphql \
    -F owner="$OWNER" -F name="$NAME" -F number="$n" \
    -f query="$QUERY")

  filtered=$(jq \
    --arg author "$AUTHOR" \
    --argjson reviewers "$REVIEWERS_JSON" \
    --argjson noBots "$NO_BOTS" '
    # ---- helpers ----
    def botDenylist: ["github-actions","coderabbitai","dependabot","codecov","sonarcloud","sonarqubecloud"];
    # NOTE: jq function args are filters re-evaluated against current input.
    # Bind to a local var on entry so deeper pipes do not re-resolve the path
    # against a different input (e.g. inside ($reviewers | index(...))).
    # (Also: avoid apostrophes here -- the whole filter is bash single-quoted.)
    def isBot(login):
      (login // "") as $l
      | ($l | endswith("[bot]")) or ((botDenylist | index($l)) != null);
    def reviewerAllowed(login):
      (login // "") as $l
      | ($reviewers | length == 0) or (($reviewers | index($l)) != null);
    def keepAuthor(login):
      (login // "") as $l
      | reviewerAllowed($l)
        and ((($noBots // 0) == 0) or (isBot($l) | not));

    .data.repository.pullRequest as $pr
    | ($pr.author.login) as $prAuthor
    | {
        number: $pr.number,
        title: $pr.title,
        url: $pr.url,
        headRefName: $pr.headRefName,
        author: $prAuthor,
        unresolvedThreads:
          [ $pr.reviewThreads.nodes[]
            | select(.isResolved == false)
            # keep thread only if its first (originating) comment is from a kept author
            | select( keepAuthor(.comments.nodes[0].author.login) )
            | {
                threadId: .id,
                path: .path,
                line: (.line // .originalLine),
                isOutdated: .isOutdated,
                diffHunk: ((.comments.nodes[0].diffHunk) // null),
                comments: [ .comments.nodes[] | {
                  author: (.author.login // "ghost"),
                  createdAt: .createdAt,
                  body: .body
                } ]
              }
          ],
        unansweredIssueComments:
          ( ($pr.comments.nodes) as $cs
            | [ $cs[] | select((.author.login // "") != $prAuthor) ]
            | if (length == 0) then []
              else
                ( ($cs | map(select((.author.login // "") == $prAuthor)) | (last // null)) ) as $lastByAuthor
                | map( select( ($lastByAuthor == null) or (.createdAt > $lastByAuthor.createdAt) ) )
                | map(select( keepAuthor(.author.login) ))
                | map({ id: .id, author: (.author.login // "ghost"), createdAt: .createdAt, body: .body })
              end ),
        openReviews:
          ( $pr.reviews.nodes as $rs
            | [ $rs[] | select(.state == "CHANGES_REQUESTED") | select( keepAuthor(.author.login) ) ]
            | map(. as $r
                | select(
                    ( [ $rs[]
                        | select(.author.login == $r.author.login)
                        | select(.submittedAt > $r.submittedAt)
                        | select(.state == "APPROVED" or .state == "DISMISSED")
                      ] | length ) == 0
                  )
              )
            | map({ author: (.author.login // "ghost"), state: .state, submittedAt: .submittedAt, body: .body })
          )
      }
    | select(
        (.unresolvedThreads | length) > 0
        or (.unansweredIssueComments | length) > 0
        or (.openReviews | length) > 0
      )
  ' <<< "$raw" || true)

  if [[ -n "$filtered" && "$filtered" != "null" ]]; then
    results=$(jq --argjson item "$filtered" '. + [$item]' <<< "$results")
  fi
done

echo "$results"
