# frozen_string_literal: true

require 'faraday'
require 'oj'
require 'awesome_print'
require 'redis'
require 'forwardable'

require './time_range'
require './query_builder'

# Fetch data
class Fetcher
  BASE_URI = 'https://api.pushshift.io'
  # maximum amount of items possible for single response
  RESPONSE_LIMIT = 1000
  SUBREDDITS = %w[ruby rails learn_ruby].freeze
  COMMENT_FIELDS = %w[id created_utc score author link_id].freeze
  SUBMISSION_FIELDS = %w[title name id created_utc score author
                         num_comments full_link author].freeze

  # Sometimes it's not possible to get all data in a single request
  class ResponsePortion
    attr_reader :data

    def initialize(data, fields)
      @data = data.map { |item| item.slice(*fields) }
    end

    def exhaustive_for?(query)
      @data.length < query.limit
    end

    def last_item_creation_time
      raise 'slice is empty' if @data.empty?

      @data.last['created_utc']
    end
  end

  def initialize
    @connection = Faraday.new(BASE_URI)
    @query_builder = QueryBuilder.new(subreddits: SUBREDDITS,
                                      response_limit: RESPONSE_LIMIT)
  end

  def submissions(topic, time_range)
    query = @query_builder.submission_search(topic, time_range)
    fetch_data(query, SUBMISSION_FIELDS)
  end

  def comments(topic, time_range)
    query = @query_builder.comment_search(topic, time_range)
    fetch_data(query, COMMENT_FIELDS)
  end

  def submission_comments(id, time_range)
    query = @query_builder.submission_comment_list(id, time_range)
    fetch_data(query, COMMENT_FIELDS)
  end

  private

  def fetch_data(query, fields)
    fetch_all_portions(query, fields).map(&:data).flatten
  end

  # keep fetching reducing the range until we get all of results
  def fetch_all_portions(query, fields)
    slices = []
    loop do
      slice = ResponsePortion.new(fetch_json(query), fields)
      slices << slice
      return slices if slice.exhaustive_for?(query)

      query.set_param(:before, slice.last_item_creation_time)
    end
  end

  def fetch_json(query)
    # TODO: ensure rate-limits
    response = @connection.get(*query.to_faraday_param_list)
    Oj.load(response.body)['data']
  end
end

fetcher = Fetcher.new
time_range = TimeRange.new(Time.new(2017, 1, 1), Time.new(2018, 1, 1))
# time_range = TimeRange.exhaustive

submissions = fetcher.submissions('rubocop', time_range)
submission_ids = submissions.map { |submission| submission['id'] }

# ap gon_submissions

ap submissions.length
ap submissions.first
ap fetcher.submission_comments(submission_ids.first, time_range).length

# ap fetcher.submission_comments(gon_submission_ids, time_range)
