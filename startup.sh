#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
REPOS=(
  "GreenCityUser|https://github.com/GreenCity-UA-4823-4826/GreenCityUser.git"
  "GreenCityMVP|https://github.com/GreenCity-UA-4823-4826/GreenCityMVP.git"
  "GreenCityClient|https://github.com/ita-social-projects/GreenCityClient.git"
)
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[startup]${NC} $*"; }
warn() { echo -e "${YELLOW}[startup]${NC} $*"; }
fail() { echo -e "${RED}[startup]${NC} $*" >&2; exit 1; }

command -v git    >/dev/null || fail "git is not installed"
command -v docker >/dev/null || fail "docker is not installed"
docker info >/dev/null 2>&1           || fail "Docker daemon is not running"
docker compose version >/dev/null 2>&1 || fail "'docker compose' (v2 plugin) is required"

[ -f .env ] || warn "no .env file found — compose will fall back to built-in dev defaults"
for entry in "${REPOS[@]}"; do
  dir="${entry%%|*}"
  url="${entry##*|}"
  if [ -d "$dir/.git" ]; then
    info "Pulling latest $dir ..."
    git -C "$dir" pull --ff-only
  else
    info "Cloning $dir ..."
    git clone "$url" "$dir"
  fi
done
info "Building images (first run downloads dependencies — this can take a while) ..."
docker compose build

info "Starting containers ..."
docker compose up -d

echo
docker compose ps
echo
info "Stack is starting (backends need a minute to pass healthchecks). Endpoints:"
echo "  Frontend:     http://localhost:4200"
echo "  Core API:     http://localhost:8080"
echo "  User API:     http://localhost:8060"
echo "  RabbitMQ UI:  http://localhost:15672"
