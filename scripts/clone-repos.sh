#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")/.."
REPOS_DIR="repos"
mkdir -p "$REPOS_DIR"

REPOS=(
  "GreenCityUser|https://github.com/GreenCity-UA-4823-4826/GreenCityUser.git"
  "GreenCityMVP|https://github.com/GreenCity-UA-4823-4826/GreenCityMVP.git"
  "GreenCityClient|https://github.com/ita-social-projects/GreenCityClient.git"
)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

for entry in "${REPOS[@]}"; do
  name="${entry%%|*}"
  url="${entry##*|}"
  dest="${REPOS_DIR}/${name}"
  if [ -d "${dest}/.git" ]; then
    echo -e "${YELLOW}[exists]${NC} ${name} already cloned — leaving it as-is."
  else
    echo -e "${GREEN}[clone ]${NC} ${name} ..."
    git clone "$url" "$dest"
  fi
done

echo
echo -e "${GREEN}Done.${NC} Your working clones are in ./repos/."
echo "Edit code there, then 'git commit' to trigger the Jenkins quality gate."
