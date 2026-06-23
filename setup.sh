#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup]${NC} $*"; }
fail() { echo -e "${RED}[setup]${NC} $*" >&2; exit 1; }

command -v docker >/dev/null            || fail "docker is not installed."
docker info >/dev/null 2>&1             || fail "Docker daemon is not running."
docker compose version >/dev/null 2>&1  || fail "'docker compose' v2 plugin is required."

if [ ! -f .env ]; then
  cp .env.example .env
  info "Created .env from .env.example (edit it to add real secrets later)."
fi

info "Cloning the three GreenCity repos into ./repos ..."
bash scripts/clone-repos.sh

info "Building & starting the CI tooling stack (Jenkins + SonarQube) ..."
docker compose up -d --build

info "Bootstrapping SonarQube (token + Jenkins webhook) ..."
bash scripts/bootstrap-sonar.sh

info "Recreating Jenkins to load the Sonar token ..."
docker compose up -d --force-recreate jenkins

cat <<EOF

$(echo -e "${GREEN}==================================================================${NC}")
 GreenCity dev environment is up.

   Jenkins      http://localhost:8081   (admin / admin by default)
   SonarQube    http://localhost:9000   (admin / set in bootstrap-sonar.sh)

 Your working clones live in ./repos/. Edit code there.

 Workflow:
   1. Edit code in repos/GreenCityMVP (or User / Client).
   2. git -C repos/GreenCityMVP commit -am "my change"
   3. Within ~1 min Jenkins runs build-GreenCityMVP:
        build -> SonarQube quality gate -> rebuild image -> restart app.
   4. Watch it at http://localhost:8081. Gate fails? See http://localhost:9000.
   5. Happy with it? Push upstream when YOU choose:
        git -C repos/GreenCityMVP push origin <branch>

 Upstream updates are checked every 5 min (job 'upstream-notify') and
 reported in repos/.upstream-status — never auto-pulled.

 To start the app stack now without waiting for a commit:  make app-up
$(echo -e "${GREEN}==================================================================${NC}")
EOF
