#!/usr/bin/env bash

set -uo pipefail

REPOS_DIR="${REPOS_DIR:-/workspace/repos}"
STATUS_FILE="${REPOS_DIR}/.upstream-status"
REPOS=(GreenCityUser GreenCityMVP GreenCityClient)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

{
  echo "Upstream check — $(date '+%Y-%m-%d %H:%M:%S')"
  echo "-----------------------------------------------"
} > "$STATUS_FILE"

behind_any=0

for name in "${REPOS[@]}"; do
  dir="${REPOS_DIR}/${name}"

  if [ ! -d "${dir}/.git" ]; then
    echo -e "${YELLOW}[skip]${NC} ${name}: not cloned yet."
    echo "[skip] ${name}: not cloned yet." >> "$STATUS_FILE"
    continue
  fi

  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

  if ! git -C "$dir" fetch --quiet origin 2>/dev/null; then
    echo -e "${RED}[err ]${NC} ${name}: git fetch failed."
    echo "[err ] ${name}: git fetch failed." >> "$STATUS_FILE"
    continue
  fi

  upstream="$(git -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -z "$upstream" ]; then
    if git -C "$dir" rev-parse --verify --quiet origin/main >/dev/null; then
      upstream="origin/main"
    elif git -C "$dir" rev-parse --verify --quiet origin/master >/dev/null; then
      upstream="origin/master"
    fi
  fi

  if [ -z "$upstream" ]; then
    echo -e "${YELLOW}[skip]${NC} ${name}: no upstream branch to compare."
    echo "[skip] ${name} (${branch}): no upstream to compare." >> "$STATUS_FILE"
    continue
  fi

  behind="$(git -C "$dir" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)"

  if [ "$behind" -gt 0 ]; then
    behind_any=1
    echo -e "${YELLOW}[update]${NC} ${name} (${branch}): ${behind} new commit(s) on ${upstream}."
    {
      echo "[UPDATE AVAILABLE] ${name} (${branch}): ${behind} new commit(s) on ${upstream}."
      echo "    To merge them in:  cd repos/${name} && git pull --ff-only"
    } >> "$STATUS_FILE"
  else
    echo -e "${GREEN}[ok  ]${NC} ${name} (${branch}): up to date with ${upstream}."
    echo "[ok   ] ${name} (${branch}): up to date." >> "$STATUS_FILE"
  fi
done

echo "-----------------------------------------------" >> "$STATUS_FILE"
if [ "$behind_any" -eq 1 ]; then
  echo "One or more repos have upstream updates. Review repos/.upstream-status." >> "$STATUS_FILE"
  echo ""
  echo -e "${YELLOW}One or more repos have upstream updates (not pulled). See repos/.upstream-status.${NC}"
else
  echo "All repos are up to date." >> "$STATUS_FILE"
fi

exit 0
