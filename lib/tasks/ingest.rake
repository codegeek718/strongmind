namespace :ingest do
  desc "Continuously poll the GitHub public events feed and ingest PushEvents"
  task run: :environment do
    EventsPoller.new.run(continuous: true)
  end

  desc "Run a single ingestion cycle (useful for verification/CI)"
  task once: :environment do
    EventsPoller.new.run(continuous: false, cycles: 1)
  end

  desc "Run N ingestion cycles (CYCLES=5)"
  task cycles: :environment do
    n = Integer(ENV.fetch("CYCLES", "5"))
    EventsPoller.new.run(continuous: true, cycles: n)
  end
end
