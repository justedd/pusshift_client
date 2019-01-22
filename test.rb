require 'faraday'
require 'oj'
require 'awesome_print'
require 'oauth2'
require "redis"

client = Faraday.new(url: 'https://www.reddit.com')

# response = client.get('ruby/search.json?q=bundler&restrict_sr=true&limit=100')
# data = response.body

# data = File.read('./ruby_gon_search.json')

# data = Oj.load(data)

# post_fields = %w[title name id created_utc score author num_comments permalink]

# results = data['data']['children'].map do |result|
  # hash = result['data']
  # hash.slice(*post_fields)
# end

# ap results.length

# ap results

# title
# name
# id
# created_utc
# score
# author
# num_comments

# authorizer = Faraday.new(url: 'https://www.reddit.com') do |conn|
  # conn.basic_auth('username', 'password')
# end


# data = File.read('./gon_perfomance_comments.json')
# data = Oj.load(data)

# # ap data.last

# results = data.map do |result|
  # hash = result['data']
  # hash.slice(*post_fields)
# end

# Authorize Connection
class Authorizer
  TOKEN_KEY = 'ossert_reddit_token'.freeze

  def initialize(id, secret)
    @connection = Faraday.new(url: 'https://www.reddit.com')
    @connection.basic_auth(id, secret)
    @redis = Redis.new
  end

  def token
    forget_token
    @token ||= recieve_token_from_redis || recieve_token_from_auth
  end

  def new_token
    forget_token
    token
  end

  private

  def forget_token
    @redis.del(TOKEN_KEY)
    @token = nil
  end

  def recieve_token_from_redis
    @redis.get(TOKEN_KEY)
  end

  def recieve_token_from_auth
    response = @connection.post('api/v1/access_token',
                                grant_type: 'client_credentials')
    throw 'Invalid Credentials' unless response.status == 200

    Oj.load(response.body)['access_token'].tap do |token|
      @redis.set('ossert_reddit_token', token)
    end
  end
end

# Fetch data
class Fetcher
  RATE_LIMIT = 1000

  # Query with Params
  class ParametrizedQuery
    attr_reader :query, :params

    def initialize(query, params)
      @query = query
      @params = params
    end

    def set_param(name, value)
      @params[name] = value
    end
  end

  def initialize(authorizer)
    @authorizer = authorizer
    @connection = Faraday.new(url: 'https://oauth.reddit.com')
    self.authorization_token = @authorizer.token

    @last_query_timestamp = 0
    @last_response = nil
  end

  THREAD_USEFUL_FIELDS = %w[title name id created_utc score author
                            num_comments permalink].freeze

  def threads(topic)
    @results = []
    request = ParametrizedQuery.new('r/ruby/search.json',
                                    q: topic, restrict_sr: true, limit: 100,
                                    sort: :new)
    recursive_fetch(request)
    @results
  end

  private

  attr_reader :authorization_token

  def recursive_fetch(request)
    data = fetch_json(request)
    after_results_anchor = data['data']['after']
    ap data['data']['after']

    @results += data['data']['children'].map do |result|
      hash = result['data']
      hash.slice(*THREAD_USEFUL_FIELDS)
    end

    request.set_param(:after, after_results_anchor)
    recursive_fetch(request) if after_results_anchor
  end

  def fetch_json(request)
    ensure_rate_limits
    response = @connection.get(request.query, request.params)

    if response.status == 401
      fetch_json_with_new_token(request)
    else
      Oj.load(response.body)
    end
  end

  def fetch_json_with_new_token(request)
    refresh_token
    fetch_json(request)
  end

  def refresh_token
    self.authorization_token = new_token
  end

  def authorization_token=(token)
    @connection.authorization :Bearer, token
  end

  def ensure_rate_limits
    current_timestamp = Time.new.to_i
    diff = current_timestamp - @last_query_timestamp

    delay = (RATE_LIMIT - diff) / RATE_LIMIT.to_f
    sleep delay if diff < 1000
    @last_query_timestamp = current_timestamp
  end
end

fetcher = Fetcher.new(authorizer)

ap fetcher.threads('ruby').length
