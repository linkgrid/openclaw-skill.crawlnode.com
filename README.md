# openclaw-skills

Central repository for OpenClaw agent skills, per-agent prompts (`AGENTS.md`), config overlay, and the one-command deploy script for each Claw machine.

**Deployment status (Aug 24 2026):** live on Claw2. Claw1 pending (machine offline in the office).

> See [DESIGN.md](DESIGN.md) for the full architecture, quirks we hit, and the current list of open bugs. That doc is the single source of truth if you're new to this repo.

## Architecture at a glance

OpenClaw runs a **classifier + specialists** pattern on each Claw machine:

```
                         User Request
                              │
                              ▼
                    ┌───────────────────┐
                    │   main agent      │
                    │  (classifier)     │
                    │  gpt-5.6-luna     │
                    │                   │
                    │ Reads SKILLS.json │
                    │ Picks specialist  │
                    │ Never does work   │
                    │ itself            │
                    └──────┬────────────┘
                           │  sessions_spawn
              ┌────────────┴────────────┐
              ▼                         ▼
     ┌──────────────────┐      ┌──────────────────┐
     │  browser-agent   │      │ crawlnode-agent  │
     │  gpt-5.4         │      │  gpt-5.4         │
     │                  │      │                  │
     │ browser-         │      │ crawlnode +      │
     │  automation +    │      │  passimagein     │
     │  passimagein     │      │                  │
     └──────────────────┘      └──────────────────┘
```

Only the classifier reads `SKILLS.json`. Each specialist sees only the skills it needs. Every specialist that produces files uses the `passimagein` skill (via `exec curl`, or the helper script — see DESIGN.md §6) to upload and return a public URL.

## Folder layout

```
openclaw-skills/
├── DESIGN.md                              read this first
├── README.md                              this file
├── SKILLS.json                            classifier's dispatch table
│
├── browser-automation/SKILL.md            skill loaded into browser-agent
├── crawlnode/                             skill loaded into crawlnode-agent
│   ├── SKILL.md
│   ├── docs/CRAWLNODE-API-DOCUMENTATION.md
│   └── scripts/test-crawlnode.sh
├── passimagein/SKILL.md                   skill loaded into every specialist
│
├── agents/                                per-agent system prompts
│   ├── main/
│   │   ├── AGENTS.md                      classifier prompt
│   │   └── WORKSPACE                      "$HOME/.openclaw/workspace"
│   ├── browser-agent/
│   │   ├── AGENTS.md
│   │   └── WORKSPACE                      "$HOME/.openclaw/workspace-browser"
│   └── crawlnode-agent/
│       ├── AGENTS.md
│       └── WORKSPACE                      "$HOME/.openclaw/workspace-crawlnode"
│
└── openclaw-config/
    ├── multi-agent-overlay.json5          config merged into openclaw.json
    └── scripts/
        ├── refresh-openclaw.sh            the one-command deploy
        └── upload-latest-screenshot.sh    helper called by browser-agent via exec
```

Each `agents/<name>/WORKSPACE` file contains a single line: the absolute path (with `$HOME` allowed) where that agent's `AGENTS.md` should land on the Claw. The refresh script reads it — no hardcoded mappings.

## Deployment (one command per machine)

On each Claw:

```bash
~/scripts/refresh-openclaw.sh
```

That script:

1. Clones this repo.
2. Copies each skill folder into `~/.openclaw/skills/` and updates `SKILLS.json`.
3. Copies each `agents/<name>/AGENTS.md` into the path listed in its sibling `WORKSPACE` file (backing up the previous version).
4. Installs helper scripts from `openclaw-config/scripts/` (except itself) into `~/.openclaw/scripts/`.
5. Applies `openclaw-config/multi-agent-overlay.json5` via `openclaw config patch --file` (dry-run validated first).
6. Self-updates: replaces `~/scripts/refresh-openclaw.sh` with the freshest version from the repo so future runs pick up any changes.
7. Restarts the OpenClaw gateway.

Idempotent. Safe to re-run. Exits non-zero on the first failure. Full log of the config patch step at `/tmp/openclaw-refresh-overlay.log`.

**Bootstrapping onto a new Claw** (or after a factory reset):

```bash
# Once, to install the script itself
mkdir -p ~/scripts && curl -sSL \
  https://raw.githubusercontent.com/linkgrid/openclaw-skill.crawlnode.com/main/openclaw-config/scripts/refresh-openclaw.sh \
  -o ~/scripts/refresh-openclaw.sh && chmod +x ~/scripts/refresh-openclaw.sh

# Then every subsequent update:
~/scripts/refresh-openclaw.sh
```

Both Claws should end up on the same commit — the refresh script pulls `main`.

## Change workflow

Anything that touches a Claw's behaviour is a change to this repo:

1. Edit the relevant file (a `SKILL.md`, an `AGENTS.md`, `SKILLS.json`, the overlay, a helper script).
2. Commit and push to `main`.
3. SSH into each Claw and run `~/scripts/refresh-openclaw.sh`.
4. Test the changed path (Slack for user-facing flows; CLI for internal ones).

## Adding a new skill

1. Create `<my-skill>/SKILL.md` with YAML front-matter (`name`, `description`, optionally `version`).
2. Add a row for it in `SKILLS.json` with `capabilities`, `requires_env`, and `collaborates_with`.
3. Add the skill's name to the specialist's `skills: [...]` array in `openclaw-config/multi-agent-overlay.json5`.
4. Push and run the refresh script.

## Adding a new specialist agent

1. Add a new object to `agents.list[]` in `openclaw-config/multi-agent-overlay.json5` with `id`, `name`, `workspace`, `model`, `skills`, `tools`.
2. Create `agents/<new-agent-id>/AGENTS.md` (the system prompt) and `agents/<new-agent-id>/WORKSPACE` (one line, the workspace path).
3. Update `agents/main/AGENTS.md` with a routing rule for when the classifier should spawn this new specialist.
4. Push and run the refresh script.

## Related repos

| Repo | Purpose |
|------|---------|
| [asa-cf-worker.autoscale.team](https://github.com/linkgrid/asa-cf-worker.autoscale.team) | Cloudflare Worker that connects Slack to the OpenClaw gateways. |

## Known issues

See [DESIGN.md §11](DESIGN.md) for the current list, including the open Slack-path bug (`_No response._` after `sessions_yield`) that CLI tests do not reproduce.
