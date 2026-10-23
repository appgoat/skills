# Post a competitor digest to a GitHub issue or a Slack channel.
#
#   bash post_digest.sh previous --repo owner/name --app apple:284882215
#   bash post_digest.sh issue    --repo owner/name --app apple:284882215 --title "…" --body-file digest.md [--week 2026-W43] [--dry-run]
#   bash post_digest.sh slack    --file digest.slack.md [--dry-run]
#
# previous  prints the body of the newest digest issue for the app (nothing when there is none),
#           so a run can avoid repeating last week's news.
# issue     keeps one issue per app and ISO week (label appgoat-digest, hidden marker
#           <!-- appgoat:competitor-digest app=<app> week=<week> -->): edits this week's issue on a
#           rerun, otherwise creates it and closes older open digest issues of the app with a link.
#           Prints the issue URL.
# slack     posts the file as one message to the incoming webhook in SLACK_WEBHOOK_URL
#           (Slack mrkdwn; cut at 39,000 characters).
#
# Requires gh (authenticated: gh auth login, or GH_TOKEN in CI) for previous/issue, curl and jq
# for slack. GH and CURL override the binaries.

set -euo pipefail

GH=${GH:-gh}
CURL=${CURL:-curl}
LABEL=appgoat-digest

cmd=${1:-}
shift || true
repo= app= title= body_file= file= week= dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --app) app=$2; shift 2 ;;
    --title) title=$2; shift 2 ;;
    --body-file) body_file=$2; shift 2 ;;
    --file) file=$2; shift 2 ;;
    --week) week=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

run() {
  if [ "$dry" = 1 ]; then
    { printf 'dry-run:'; printf ' %q' "$@"; printf '\n'; } >&2
  else
    "$@"
  fi
}

need_issue_args() {
  if [ -z "$repo" ] || [ -z "$app" ]; then
    echo "usage: post_digest.sh $cmd --repo owner/name --app store:id [...]" >&2
    exit 2
  fi
  case "$app" in
    apple:*|play:*) ;;
    *) echo "--app must be store:id, e.g. apple:284882215 or play:com.example.app" >&2; exit 2 ;;
  esac
}

# Open and closed digest issues of the app, newest first: "<number> <state> <week>"
list_digests() {
  $GH issue list --repo "$repo" --label "$LABEL" --state all --limit 200 --json number,state,body \
    --jq "map(select(.body | contains(\"<!-- appgoat:competitor-digest app=$app \"))) | sort_by(-.number) | .[]
      | \"\(.number) \(.state) \(.body | capture(\"week=(?<w>[0-9W-]+)\").w // \"\")\""
}

case "$cmd" in
  previous)
    need_issue_args
    newest=$(list_digests | head -n 1 | cut -d' ' -f1)
    [ -n "$newest" ] || exit 0
    $GH issue view "$newest" --repo "$repo" --json body --jq .body
    ;;

  issue)
    need_issue_args
    if [ -z "$title" ] || [ -z "$body_file" ] || [ ! -f "$body_file" ]; then
      echo "issue needs --title and an existing --body-file" >&2
      exit 2
    fi
    week=${week:-$(date -u +%G-W%V)}
    marker="<!-- appgoat:competitor-digest app=$app week=$week -->"
    body=$(mktemp)
    trap 'rm -f "$body"' EXIT
    { printf '%s\n\n' "$marker"; cat "$body_file"; } >"$body"

    digests=$(list_digests)
    this_week=$(printf '%s\n' "$digests" | awk -v w="$week" '$3 == w { print $1; exit }')
    if [ -n "$this_week" ]; then
      run $GH issue edit "$this_week" --repo "$repo" --title "$title" --body-file "$body" >/dev/null
      run $GH issue reopen "$this_week" --repo "$repo" >/dev/null 2>&1 || true
      number=$this_week
    else
      run $GH label create "$LABEL" --repo "$repo" --color 5319e7 \
        --description "AppGoat weekly competitor digest" >/dev/null 2>&1 || true
      if [ "$dry" = 1 ]; then
        run $GH issue create --repo "$repo" --label "$LABEL" --title "$title" --body-file "$body"
        number=NEW
      else
        url=$($GH issue create --repo "$repo" --label "$LABEL" --title "$title" --body-file "$body")
        number=${url##*/}
      fi
      # Close last weeks' open digests of this app
      printf '%s\n' "$digests" | awk '$2 == "OPEN" { print $1 }' | while read -r old; do
        [ -n "$old" ] || continue
        run $GH issue close "$old" --repo "$repo" --comment "Superseded by #$number." >/dev/null
      done
    fi
    if [ "$dry" = 1 ]; then
      echo "issue #$number"
    else
      $GH issue view "$number" --repo "$repo" --json url --jq .url
    fi
    ;;

  slack)
    if [ -z "$file" ] || [ ! -f "$file" ]; then
      echo "slack needs an existing --file" >&2
      exit 2
    fi
    payload=$(jq -Rs '{text: (if length > 39000 then .[0:39000] + "\n…(cut)" else . end), mrkdwn: true}' "$file")
    if [ "$dry" = 1 ]; then
      printf 'dry-run: POST $SLACK_WEBHOOK_URL %s\n' "$payload"
    else
      : "${SLACK_WEBHOOK_URL:?set SLACK_WEBHOOK_URL (a Slack incoming webhook)}"
      $CURL -sS -f -X POST -H 'content-type: application/json' --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null
      echo "posted to Slack"
    fi
    ;;

  *)
    echo "usage: post_digest.sh previous|issue|slack [...] (see the header of this file)" >&2
    exit 2
    ;;
esac
