#!/usr/bin/env bash
# Install skills by symlinking them into a target skills directory.
#
# Usage:
#   ./install.sh                       # install all skills
#   ./install.sh <skill> [<skill>...]  # install specific skills
#   ./install.sh -t <dir> ...          # custom target dir
#   ./install.sh -c ...                # copy instead of symlink
#   ./install.sh -l                    # list available skills
#
# Default target: ~/.pi/agent/skills

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SKILLS_TARGET:-$HOME/.pi/agent/skills}"
MODE="link"
LIST=0

usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET="$2"; shift 2 ;;
    -c|--copy)   MODE="copy"; shift ;;
    -l|--list)   LIST=1; shift ;;
    -h|--help)   usage 0 ;;
    --) shift; break ;;
    -*) echo "Unknown flag: $1" >&2; usage 1 ;;
    *) break ;;
  esac
done

# Discover skills (directories with SKILL.md at repo root).
ALL_SKILLS=()
while IFS= read -r line; do
  ALL_SKILLS+=("$line")
done < <(
  find "$REPO_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md \
    -exec dirname {} \; \
    | awk -F/ '{print $NF}' \
    | sort
)

if [[ $LIST -eq 1 ]]; then
  if [[ ${#ALL_SKILLS[@]} -gt 0 ]]; then
    printf '%s\n' "${ALL_SKILLS[@]}"
  fi
  exit 0
fi

if [[ $# -eq 0 ]]; then
  SKILLS=(${ALL_SKILLS[@]+"${ALL_SKILLS[@]}"})
else
  SKILLS=("$@")
fi

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  echo "No skills found in $REPO_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET"

for name in "${SKILLS[@]}"; do
  src="$REPO_DIR/$name"
  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "skip: $name (no SKILL.md at $src)" >&2
    continue
  fi
  dest="$TARGET/$name"
  rm -rf "$dest"
  if [[ "$MODE" == "copy" ]]; then
    cp -R "$src" "$dest"
    echo "copied: $name -> $dest"
  else
    ln -s "$src" "$dest"
    echo "linked: $name -> $dest"
  fi
done

echo "Done. Target: $TARGET"
