# Wrapper around the GitHub REST API used without a token. Sends conditional
# requests, records rate-limit headers, and maps responses to results/errors.
class GithubClient
  USER_AGENT = ENV.fetch("GITHUB_USER_AGENT", "github-events-ingestor")
  ACCEPT = "application/vnd.github+json".freeze
  API_VERSION = "2022-11-28".freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  Result = Struct.new(:status, :data, :headers, :etag, keyword_init: true) do
    def not_modified? = status == 304
    def ok? = status == 200
  end

  # Raised when the window is spent; carries seconds until reset.
  class RateLimitError < StandardError
    attr_reader :retry_after

    def initialize(message, retry_after:)
      super(message)
      @retry_after = retry_after
    end
  end

  class ServerError < StandardError; end # retryable
  class ClientError < StandardError; end # not retryable

  def initialize(rate_limiter: RateLimiter.new, logger: Rails.logger, connection: nil)
    @rate_limiter = rate_limiter
    @logger = logger
    @connection = connection || build_connection
  end

  def get(url, conditional: true)
    etag = conditional ? @rate_limiter.etag_for(url) : nil

    response =
      begin
        @connection.get(url) do |req|
          req.headers["If-None-Match"] = etag if etag.present?
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise ServerError, "network error for #{url}: #{e.class}: #{e.message}"
      end

    @rate_limiter.record(response.headers)
    handle(url, response, conditional)
  end

  private

  def handle(url, response, conditional)
    case response.status
    when 200
      new_etag = response.headers["etag"]
      @rate_limiter.store_etag(url, new_etag) if conditional && new_etag.present?
      Result.new(status: 200, data: parse(response.body), headers: response.headers, etag: new_etag)
    when 304
      Result.new(status: 304, data: nil, headers: response.headers, etag: response.headers["etag"])
    when 403, 429
      raise_if_rate_limited(url, response)
      raise ClientError, "forbidden for #{url} (status #{response.status})"
    when 404
      raise ClientError, "not found: #{url}"
    when 400..499
      raise ClientError, "client error #{response.status} for #{url}"
    else
      raise ServerError, "server error #{response.status} for #{url}"
    end
  end

  # GitHub signals exhaustion via remaining: 0 or a Retry-After header.
  def raise_if_rate_limited(url, response)
    remaining = response.headers["x-ratelimit-remaining"]
    retry_after = response.headers["retry-after"]

    return unless remaining.to_s == "0" || retry_after.present?

    seconds = retry_after.present? ? retry_after.to_i : @rate_limiter.seconds_until_reset
    raise RateLimitError.new("rate limited on #{url}", retry_after: [seconds, 1].max)
  end

  def parse(body)
    return body if body.is_a?(Array) || body.is_a?(Hash)

    JSON.parse(body)
  rescue JSON::ParserError => e
    raise ClientError, "unparseable JSON response: #{e.message}"
  end

  def build_connection
    Faraday.new(url: "https://api.github.com") do |f|
      f.headers["User-Agent"] = USER_AGENT
      f.headers["Accept"] = ACCEPT
      f.headers["X-GitHub-Api-Version"] = API_VERSION
      f.options.open_timeout = OPEN_TIMEOUT
      f.options.timeout = READ_TIMEOUT
      f.adapter Faraday.default_adapter
    end
  end
end
