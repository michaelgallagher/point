#!/bin/zsh
# For the trial on the real vault (plan/live-vault-safety.md, phase 4): a copy of the vault
# kept outside it (and outside iCloud), and what has changed in the vault since.
#
#   scripts/vault-snapshot.sh take      copies the vault to ~/Point vault snapshots/<date time>
#   scripts/vault-snapshot.sh changes   lists what changed since the latest copy, and writes
#                                       the full diff next to the copies
#
# POINT_VAULT is the vault (needed); POINT_SNAPSHOTS changes where the copies go.
set -euo pipefail

vault="${POINT_VAULT:?Set POINT_VAULT to the vault folder}"
store="${POINT_SNAPSHOTS:-$HOME/Point vault snapshots}"
# Files Obsidian rewrites all the time, which say nothing about the notes.
ignored=(--exclude=workspace.json --exclude=workspace-mobile.json --exclude=.DS_Store)

[[ -d "$vault" ]] || { echo "No vault at $vault" >&2; exit 1; }

case "${1:-}" in
take)
    mkdir -p "$store"
    copy="$store/$(date '+%Y-%m-%d %H%M%S')"
    # Reading a note iCloud has evicted downloads it, so the copy is complete.
    rsync -a "$vault/" "$copy/"
    echo "Copied $(find "$copy" -name '*.md' | wc -l | tr -d ' ') notes to $copy"
    ;;
changes)
    latest=$(ls -1d "$store"/*/ 2>/dev/null | tail -1)
    [[ -n "$latest" ]] || { echo "No copies in $store yet: run '$0 take' first." >&2; exit 1; }
    latest=${latest%/}
    report="$store/changes since ${latest:t} at $(date '+%Y-%m-%d %H%M%S').diff"
    diff -ruN "${ignored[@]}" "$latest" "$vault" > "$report" || true
    echo "Since ${latest:t}:"
    diff -rqN "${ignored[@]}" "$latest" "$vault" | sed -e "s|^Files $latest/||" -e 's| and .* differ$||' || true
    echo "Full diff: $report"
    ;;
*)
    echo "Usage: $0 take | changes" >&2
    exit 2
    ;;
esac
