# frozen_string_literal: true

# Format raw data into metrics
class Formatter
  PREFIX = 'reddit_'
  FIELDS = %w[submissions comments submissioners commenters comment_scores
              submission_comment_numbers submission_scores users].freeze

  attr_accessor(*FIELDS)

  def self.aggregate(*formatters)
    new([], []).tap do |aggregator|
      FIELDS.each do |field|
        values = formatters.reduce { |formatter| formatter.send(field) }
        aggregator.send("#{field}=", values)
      end
    end
  end

  def initialize(submissions, comments)
    @submissioners = Set.new

    @submissions = []
    @submission_comment_numbers = []
    @submission_scores = []

    @commenters = Set.new
    @comments = []
    @comment_scores = []

    @users = Set.new

    parse_data(submissions, comments)
  end

  def to_h
    FIELDS.each_with_object({}) do |field, result|
      result[PREFIX + field] = send(field)
    end
  end

  private

  def parse_data(submissions, comments)
    parse_submissions(submissions)
    parse_comments(comments)
    @users = @submissioners + @commenters
  end

  def parse_submissions(data)
    data.each do |hash|
      @submissions << hash['id']
      @submission_comment_numbers << hash['num_comments']
      @submission_scores << hash['score']
      @submissioners << hash['author']
    end
  end

  def parse_comments(data)
    data.each do |hash|
      @commenters << hash['author']
      @comments << hash['id']
      @comment_scores << hash['score']
    end
  end
end
