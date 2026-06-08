# GitHub Push Event Ingestor

A small service that polls GitHub's public events feed, keeps the PushEvents,
stores them in Postgres (raw payload plus the fields you'd actually query on),
and enriches them with actor and repository details. It runs without a GitHub
token, so most of the work is staying inside the 60 requests/hour limit.

Built with Rails (API-only), Sidekiq, Redis and PostgreSQL. See
[DESIGN_BRIEF.md](DESIGN_BRIEF.md) for the reasoning behind the design.

## Running it

You'll need Docker. To bring up Postgres, Redis, the API and the Sidekiq worker:

```
docker compose up --build
```

The API listens on http://localhost:3000. The database is created and migrated
automatically the first time the web container starts.

Ingestion runs as a separate command so you can start/stop it independently:

```
docker compose run --rm ingest
```

That starts the poller and keeps it running until you stop it. There are also
`rake ingest:once` and `rake ingest:cycles CYCLES=5` if you just want a fixed
number of cycles, e.g.:

```
docker compose run --rm ingest bundle exec rake ingest:once
```

## Tests

```
docker compose run --rm test
```

The GitHub API is stubbed with WebMock, so the suite doesn't touch the network.

## Checking it's working

Follow the logs with `docker compose logs -f` (or `-f ingest` / `-f worker`).
The poller prints a line each cycle with how many events it saw, how many were
PushEvents, and the current rate-limit budget. The worker logs each event it
saves and enriches. When the budget runs low you'll see it back off and defer
rather than error.

The quickest way to see data is the read API:

```
curl -s localhost:3000/api/stats
curl -s localhost:3000/api/push_events
curl -s localhost:3000/api/push_events/<id>     # includes the raw payload
```

Or go straight to the database:

```
docker compose exec db psql -U postgres -d github_ingestor_development \
  -c "select github_event_id, repository_name, ref, enriched_at from push_events order by event_created_at desc limit 10;"
```

The tables are `push_events`, `actors` and `repositories`. PushEvents show up a
few seconds after you start ingestion; enrichment (`enriched_at` and the
`fetched_at` columns on actors/repos) follows shortly after, until the rate
limit is reached, at which point it resumes after the window resets.

Sidekiq's dashboard is at http://localhost:3000/sidekiq.

## Config

A few environment variables (defaults in `docker-compose.yml`):

- `MIN_POLL_INTERVAL_SECONDS` (60): shortest gap between polls
- `ENRICHMENT_RATE_RESERVE` (15): requests kept aside for the poller
- `ENRICHMENT_TTL_HOURS` (24): skip re-fetching an actor/repo seen this recently
- `SIDEKIQ_CONCURRENCY` (2): caps parallel outbound calls
