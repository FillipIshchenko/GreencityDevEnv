# GreenCity Local Dev Environment

A self-contained, Dockerised dev environment for the GreenCity project:

- **Working clones** of the three GreenCity repos (`GreenCityUser`,
  `GreenCityMVP`, `GreenCityClient`) under `repos/`.
- **Jenkins** that watches those clones and, on every local commit, runs a
  build → **SonarQube quality gate** → image rebuild → app restart.
- **SonarQube** as a real, blocking quality gate for the two Java backends.
- The full **GreenCity app stack** (Postgres, RabbitMQ, user, core, client),
  rebuilt automatically from the dev's edits when the gate passes.
- A background job that **checks upstream every 5 minutes** and tells the dev
  when the source repos have new commits — without ever touching their work.

Everything runs in containers. The only host requirements are Docker + the
Compose v2 plugin(I recommend atleast 8GBs or RAM).

---

## Startup

```bash
git clone <URL>
cd GreencityDevEnv
./setup.sh           # or: make setup
```

Then:

| Service    | URL                     | Default login            |
|------------|-------------------------|--------------------------|
| Jenkins    | http://localhost:8081   | `admin` / `admin`        |
| SonarQube  | http://localhost:9000   | `admin` / `Admin12345!`  |
| App (UI)   | http://localhost:4200   | —                        |
| Core API   | http://localhost:8080   | —                        |
| User API   | http://localhost:8060   | —                        |
| RabbitMQ   | http://localhost:15672  | `guest` / `guest`        |


---

## How it fits together

There are two stacks, kept separate on purpose:

1. CI tooling stack (`docker-compose.yml`) — Jenkins + SonarQube + Sonar's
   DB. This is the "control plane". You start it once and leave it running.

2. App stack (`app/docker-compose.app.yml`) — the actual GreenCity
   application. It is built and run by Jenkins, not started by hand
   (though `make app-up` lets you start it manually too). Its build contexts
   point at `repos/`, so it always builds from the dev's working clones.

Jenkins reaches the host Docker daemon to build and
run the app stack, and reaches SonarQube over the shared `greencity-ci`
network for the quality gate.

---

## The dev workflow

1. **Edit code** in `repos/GreenCityMVP` (or `GreenCityUser` / `GreenCityClient`).

2. **Commit locally** — no push required:
   ```bash
   git -C repos/GreenCityMVP commit -am "tweak something"
   ```

3. Within ~1 minute Jenkins detects the new commit (it polls the local clone)
   and starts the matching job, e.g. `build-GreenCityMVP`:
   - builds the module,
   - runs the SonarQube quality gate (Java backends only),
   - if the gate passes, rebuilds that one service's image and restarts it
     in the app stack,
   - reports whether the service came back healthy.

4. Watch at http://localhost:8081. If the gate fails, the run stops and
   the previously running app is left untouched — open

   http://localhost:9000 (project = the repo name) to see what to fix.
5. **Push when you decide.** Nothing is pushed automatically:

   ```bash
   git -C repos/GreenCityMVP push origin <your-branch>
   ```

### Upstream updates (poll-only, never auto-pull)

Every 5 minutes the `upstream-notify` job runs `scripts/check-upstream.sh`,
which `git fetch`es each repo and reports which are behind. It does not
pull — your local edits are never overwritten. Results go to
`repos/.upstream-status`:

```
[ok   ] GreenCityUser (main): up to date.
[UPDATE AVAILABLE] GreenCityMVP (main): 3 new commit(s) on origin/main.
    To merge them in:  cd repos/GreenCityMVP && git pull --ff-only
```

Merge on your own schedule with `git pull --ff-only` when your tree is clean.

---

## Commands

```bash
make help            # list everything
make setup           # first-time setup
make up / make down  # start / stop the CI tooling
make app-up          # build + start the app stack manually
make app-ps          # app container status
make app-logs        # tail app logs
make check-upstream  # run the upstream check by hand
make clean           # stop everything and delete all volumes (EVERYTHING!)
```
