# FeedPug

A self-hosted RSS/Atom feed reader. Subscribe to feeds, organize them into
groups, react to items, and read from the web UI or a JSON API. Feeds are
globally deduped and fetched once no matter how many people follow them.
Phoenix LiveView on top of PostgreSQL, with background fetching via Oban.

## Features

- **Newsfeed** — a unified reading view at `/` (Phoenix LiveView) with
  read / unread tracking.
- **Shared, deduped feeds** — feeds are canonical and deduped by URL, items
  by `{feed_id, guid}`, so a feed followed by many people is fetched and
  stored exactly once.
- **Groups** — organize your subscriptions into groups (`/groups`).
- **Discover & follow** — find and follow new feeds at `/discover`.
- **Reactions** — react to individual items.
- **OPML** — import and export your subscriptions (`/opml/export`).
- **JSON API** — `/api/*` for timelines, items, sources, groups, follows,
  and reactions — handy for companion apps and devices (`/devices`).
- **Background fetching** — Oban workers keep feeds up to date.
- **Accounts** — magic-link login by default, password optional, with
  invite-gated registration (`/users/invites`).
- **Themes** — pick a daisyUI theme; the choice persists.

## Quick start

```sh
# 1. Bring up Postgres (see compose.yml)
podman compose up -d   # or: docker compose up -d

# 2. Install deps, create + migrate the dev DB, build assets
mix setup

# 3. Start the dev server
mix phx.server
```

Then open <http://localhost:4000>.

## Container images

CI publishes a multi-registry image on every push to `master`:

- `ghcr.io/neiam/feedpug`
- `docker.io/neiam/feedpug`
- `quay.io/neiam/feedpug`

Tags: `latest` (default branch), `vX.Y.Z` + `X.Y` (git tags), the branch name,
and the commit SHA.

```sh
docker pull ghcr.io/neiam/feedpug:latest

docker run --rm -p 4000:4000 \
  -e PHX_SERVER=true \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=localhost \
  -e POSTGRES_HOST=host.containers.internal \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=feed_pug \
  ghcr.io/neiam/feedpug:latest
```

Or set `DATABASE_URL=ecto://user:pass@host/db` instead of the discrete
`POSTGRES_*` variables.

## Tests

```sh
mix test
mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, test
```

`mix precommit` is what CI runs and what every change should pass.
