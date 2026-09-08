# mise

Automated weekly meal planning & grocery list generator.

Self-hosted n8n workflow that suggests weekly recipes via Telegram,
tracks ratings, generates a scaled shopping list, and manages recipes
through Mealie.

See [PLAN.md](PLAN.md) for the implementation roadmap.

## Stack
- n8n (workflow orchestration)
- Mealie (recipe DB, meal plan, shopping list)
- PostgreSQL
- Telegram Bot API
- NVIDIA Nemotron 3 Super (via OpenRouter) for recipe extraction
- Caddy (reverse proxy, automatic TLS)

## Architecture

Three separate Compose stacks on a single VPS:

| Stack | Contents | Repo |
|---|---|---|
| `~/proxy` | Caddy — owns ports 80/443 | shared infrastructure |
| `~/n8n` | n8n, searxng, sandbox | separate |
| `~/mise` | PostgreSQL 17, Mealie | this one |

Two Docker networks connect them:

- **`edge`** — Caddy ↔ n8n, Caddy ↔ Mealie. Also Mealie's only route to
  the internet (needed for recipe URL imports).
- **`mise_data`** — `internal`, no internet access. PostgreSQL ↔ Mealie,
  PostgreSQL ↔ n8n.

Neither network is owned by a Compose project. Both are created manually
and referenced as `external: true` everywhere, so that tearing down one
stack cannot break another. See setup below.

Only Caddy publishes ports to the host. Everything else is reachable
solely through the Docker networks.

## Setup

### 1. Networks

Create these **before** starting any stack:

```bash
docker network create edge --subnet 172.30.0.0/16
docker network create mise_data --internal
```

`--internal` is what keeps PostgreSQL off the internet — omitting it
fails silently. The explicit subnet for `edge` avoids collisions with
leftover iptables rules from previously deleted networks.

Verify:

```bash
docker network inspect mise_data --format '{{.Internal}}'   # must print: true
```

### 2. Environment

```bash
cp .env.example .env
```

Fill in every value. `.env` is gitignored and must stay that way — this
repo is public. Run `git status` before every `git add`.

Note that `DEFAULT_EMAIL` and `DEFAULT_PASSWORD` are only read on
Mealie's **very first** start, while the database is still empty. Setting
them later has no effect; change credentials through the UI instead.

### 3. Start

```bash
docker compose up -d
```

Then start `~/n8n` and `~/proxy`. Order matters only in that Caddy should
come last, so it resolves its backends while they are already up.

### 4. DNS

Point `mealie.<domain>` and `n8n.<domain>` at the VPS. Caddy obtains
certificates automatically on first request.

## Mealie

- Users live in group `Home`, household `Family`. Meal plans and shopping
  lists are **per household** — anyone outside it sees an empty plan.
- The n8n workflow authenticates as a dedicated non-admin user holding
  only the "manage foods, tags, and categories" permission, which it
  needs to create ingredients during recipe import.
- API tokens inherit their user's household context. Generate them while
  logged in as that user, not as admin.
- No SMTP configured, so invites and password resets are unavailable.
  Create users directly with a password.

## n8n

n8n runs in a separate stack and does **not** read this repo's `.env`.
Secrets are therefore split, deliberately:

| Secret | Lives in |
|---|---|
| DB passwords | `.env`, passed to the Postgres container |
| Telegram bot token | n8n's own credential store (encrypted) |
| Allowed chat IDs | hardcoded in the `Allowlist` code node |

The `.env` entries for the Telegram values remain useful for `curl`
tests and as documentation, but they are not the source of truth for
n8n. Changing them there has no effect on the running bot.

Credentials, both pointing at host `mise-postgres`, port 5432, SSL
disabled:

| Name | Database | User |
|---|---|---|
| `mise einkauf (rw)` | `einkauf` | `einkauf` |
| `mise mealie (ro)` | `mealie` | `mise_reader` |

SSL is off on purpose: traffic never leaves the internal `mise_data`
network, and the server has no TLS configured — `Require` would simply
fail.

`bot_state` lives in `einkauf`, so even read-only queries against it use
the **rw** credential. `mise_reader` has no `CONNECT` on that database.

**The host is a container name, and that couples this stack to n8n's
credentials.** It works because `docker-compose.yml` sets
`container_name: mise-postgres` explicitly. Drop that line and Compose
names the container `mise-postgres-1`; n8n then fails to resolve it,
without anything in the n8n stack having changed.

Also required in the n8n stack: `WEBHOOK_URL=https://n8n.<domain>/`.

### Troubleshooting

The n8n image is minimal — no `getent`, no `psql`. Test connectivity
from inside it with Node instead:

```bash
docker exec n8n-n8n-1 node -e "require('net').connect(5432,'mise-postgres').on('connect',()=>{console.log('port open');process.exit(0)}).on('error',e=>{console.log(e.message);process.exit(1)})"
```

If the bot goes silent, check the `Allowlist` node first: it drops
unknown senders without replying, so a misconfiguration looks exactly
like a stranger being blocked.

## Security

- Public repo. No credentials in tracked files — everything lives in
  `.env`, only `.env.example` with placeholders is versioned.
- PostgreSQL is not exposed to the host and has no internet access.
- Mealie and n8n are reachable only via Caddy over TLS.

## Status

Work in progress. Phase 1 of [PLAN.md](PLAN.md) mostly complete.