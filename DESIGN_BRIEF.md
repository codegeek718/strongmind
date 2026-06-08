# Design notes

## The problem

The task is to pull PushEvents off GitHub's public events feed, keep both the raw
payloads and a structured version I can query, and enrich each event with the
actor and repository behind it. It has to run unattended and not fall over when
things go wrong.

The constraint that actually shapes everything is the rate limit: without a token
GitHub gives you about 60 requests an hour per IP. A naive "fetch the feed, then
fetch every actor and every repo" approach burns through that almost immediately.
So the interesting part isn't ingesting events, it's spending a tiny request
budget carefully while still staying durable and observable.

## How it's put together

There are a few processes, each doing one thing:

- The **poller** (`rake ingest:run`) hits `/events`, filters to PushEvents, and
  enqueues a job per event. It deliberately doesn't write to the database; it
  stays a fast network loop and lets the workers do the slow part.
- The **worker** (Sidekiq) runs two jobs. `ProcessPushEventJob` saves the raw
  event, the structured columns, and the actor/repo data that's already in the
  payload. `EnrichEventJob` is the only thing that spends extra API calls; it
  fetches the actor and repo URLs, and it's careful about it.
- The **web** process is a small read-only API for checking what's been stored.
- Postgres is the source of truth; Redis backs the Sidekiq queue and holds the
  shared rate-limit state and ETags.

I went with Rails in API mode because it was the suggested stack and ActiveRecord's
`upsert` makes the "don't store the same thing twice" logic trivial. Sidekiq gives
me durable queues, retries with backoff, and a concurrency cap without writing any
of that myself.

### Data model

Three tables, all keyed on GitHub's own ids:

- `push_events` holds `github_event_id` (unique) as the dedupe key, the structured
  columns the brief asks to be queryable (`repository_id`, `push_id`, `ref`,
  `head`, `before`, plus actor and timestamps), and the full `raw_payload` as
  jsonb so nothing is lost.
- `actors` and `repositories` are separate because the same actor and repo turn up
  across many events; pulling them out is what makes enrichment affordable, since
  I only fetch each one once. Each has the cheap fields from the payload, the
  richer fields from enrichment, a `raw` blob, an ETag, and a `fetched_at`.

Events link to actors/repos by GitHub id rather than a foreign key, because an
event gets stored before its actor/repo is enriched and I didn't want write order
to matter.

## Rate limits and durability

This is where most of the thought went:

- **Conditional requests.** The poller stores the `/events` ETag and sends it back.
  If nothing changed GitHub returns a 304 with no body and it doesn't cost a
  request, so polling stays cheap when the feed is quiet.
- **Use what's free.** The events payload already carries the basic actor and repo
  info, so that gets saved at no API cost. Only the deeper details need a fetch.
- **Don't re-fetch.** Before enriching an actor or repo I check `fetched_at`; if
  it was fetched within the TTL (default 24h) I skip it. Busy accounts and repos
  recur constantly, so this removes most of the would-be calls.
- **Keep budget for the poller.** Enrichment only spends when there are more than
  `ENRICHMENT_RATE_RESERVE` requests left, so ingestion never gets starved.
- **Back off, don't fail.** When GitHub says the window is spent, the poller sleeps
  until reset and the enrichment job reschedules itself instead of burning retries.

For durability, every event is upserted on `github_event_id`, so re-running or
restarting can't create duplicates and `enriched_at` is never clobbered by a
re-ingest. Actors and repos upsert on their ids too. Malformed events are logged
and skipped rather than raised, transient errors get Sidekiq's retry/backoff, and
the poll loop has a catch-all so an unexpected error turns into a wait instead of
killing the process. Everything logs as JSON to stdout.

## Tradeoffs and assumptions

- The poller enqueues to Redis before the event reaches Postgres, so there's a
  brief window where it only lives in the queue. Redis is running with append-only
  on, which I considered good enough here.
- `enriched_at` is set per event even if a deep fetch was skipped for budget. That
  keeps work bounded and avoids retry storms; the cost is that a one-off actor seen
  exactly when the budget was empty might not get fully enriched (a recurring one
  will, on a later event). Given 60/hour, I'd rather guarantee ingestion than
  enrichment, and the reserve/TTL are tunable.
- Runs in development mode by default for readable logs; it also boots in
  production mode (a dummy secret is provided).

## What I left out

- Anything that needs a token, or pagination/backfill of the feed; it's a rolling
  window and continuous polling is the intended pattern.
- Object storage for avatars/raw events, and a dedicated rate-limit middleware;
  the reserve/ETag/backoff approach covers the limit without it.
- Auth on the read API; it's just there to inspect data.
- Heavy test coverage; the specs focus on the parts with real logic (dedup,
  rate-limit handling, the jobs and the poller) rather than everything.
