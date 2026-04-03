# openclaw-skills

Central repository for all [OpenClaw](https://openclaw.org) agent skills. Each folder contains a self-contained skill that OpenClaw can load and use.

## Architecture

OpenClaw uses a **classifier + sub-agent** pattern:

```
                         User Request
                              │
                              ▼
                    ┌───────────────────┐
                    │   Main Agent      │
                    │   (Classifier)    │
                    │                   │
                    │ Reads SKILLS.json │
                    │ to decide which   │
                    │ sub-agent(s) to   │
                    │ activate          │
                    └──────┬────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
     ┌──────────────┐ ┌──────────┐ ┌──────────┐
     │  crawlnode   │ │ passim…  │ │ (future) │
     │              │◄┤►         │ │          │
     │ Browse sites │ │ Upload & │ │ Calendar │
     │ Fill forms   │ │ share    │ │ Slack    │
     │ Screenshots  │ │ files    │ │ etc.     │
     └──────────────┘ └──────────┘ └──────────┘
           ▲                ▲
           └────────────────┘
           Skills collaborate
           with each other
```

1. **Main Agent (Classifier)** — receives every user request, reads `SKILLS.json` to understand what skills are available, then routes the task to the right sub-agent.
2. **Sub-Agents (Skills)** — each skill is a specialist. It handles one type of task really well.
3. **Collaboration** — skills can call on each other mid-task. For example, CrawlNode takes a screenshot and hands it to PassImageIn to upload and get a public URL.

## Skill Registry

`SKILLS.json` at the root of this repo is the central index. It lists every skill, what it can do, what environment variables it needs, and which other skills it can collaborate with. The classifier reads this file to make routing decisions.

## Skills

| Skill | Folder | What it does |
|-------|--------|--------------|
| **CrawlNode** | `crawlnode/` | Remote browser automation — browse websites, interact with pages, capture screenshots |
| **PassImageIn** | `passimagein/` | Upload files to s.passimage.in and return public URLs for sharing |

## Folder Structure

```
openclaw-skills/
  SKILLS.json                         ← skill registry (classifier reads this)
  README.md                           ← this file
  crawlnode/
    SKILL.md                          ← skill definition (loaded by OpenClaw)
    docs/CRAWLNODE-API-DOCUMENTATION.md
    scripts/test-crawlnode.sh
  passimagein/
    SKILL.md                          ← skill definition (loaded by OpenClaw)
  (future-skill)/
    SKILL.md
```

Each skill folder must contain at minimum a `SKILL.md` file with:
- YAML front-matter (`name`, `description`, and optionally `version`, `metadata`)
- Instructions for how the agent should use the skill

## Adding a New Skill

1. Create a new folder: `my-new-skill/`
2. Add a `SKILL.md` with YAML front-matter and usage instructions
3. Register it in `SKILLS.json` — add an entry with name, path, description, capabilities, required env vars, and which skills it can collaborate with
4. Push to GitHub
5. Run the refresh script on Claw1 to pull the update

## Deployment

This repo is the single source of truth for all OpenClaw skills. On the Claw1 server:

```bash
~/scripts/refresh-openclaw.sh
```

This script pulls all skills from this repo into `/home/autoscale/.openclaw/skills/` and restarts the gateway.

## Related Repos

| Repo | Purpose |
|------|---------|
| [asa-cf-worker.autoscale.team](https://github.com/linkgrid/asa-cf-worker.autoscale.team) | ASA — Cloudflare Worker that connects Slack to OpenClaw |
