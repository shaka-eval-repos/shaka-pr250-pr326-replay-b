# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'error'
require_relative 'repository_config'
require_relative 'reviewer_selection'
require_relative 'configuration'

module Shaka
  # Answers which listed reviewer satisfies the alternate-review gate for one change.
  class Reviewer
    def self.run(arguments)
      new(arguments).run
    rescue OptionParser::ParseError, SystemCallError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def initialize(arguments)
      @arguments = arguments.dup
      @options = {}
    end

    def run
      parser = option_parser
      parser.parse!(@arguments)
      return help(parser) if @options[:help]
      raise OptionParser::InvalidArgument, parser.to_s unless @arguments.empty?

      puts JSON.pretty_generate(selection)
      0
    end

    private

    def selection
      ReviewerSelection.new(reviewers: config.review[RepositoryConfig::ReviewSchema::LOCAL_REVIEW_AGENTS],
                            implementers: identities(:implementers, required: true),
                            unavailable: identities(:unavailable),
                            count: @options.fetch(:count) { config.review.fetch('local_review_count', 1) }).call
    end

    def identities(key, required: false)
      values = @options.fetch(key, [])
      raise OptionParser::MissingArgument, '--implementer is required' if required && values.empty?

      values.map { |value| ReviewerSelection.parse(value) }
    end

    def config
      Configuration.trusted(root:, ref: @options[:ref])
    end

    def option_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka reviewer --implementer PROVIDER/FAMILY [options]'
        flags.on('--root DIR', 'Repository root (default: current directory)') { |v| @options[:root] = v }
        flags.on('--ref REF', 'Read policy from this trusted Git commit') { |v| @options[:ref] = v }
        flags.on('--count N', 'Positive reviewer count (default: configured count or 1)') { |v| parse_count(v) }
        add_identity_options(flags)
        flags.on('-h', '--help', 'Show usage') { @options[:help] = true }
      end
    end

    def parse_count(value)
      raise OptionParser::InvalidArgument, '--count must be a positive integer' unless
        value.match?(/\A[0-9]+\z/) && value.to_i.positive?

      @options[:count] = value.to_i
    end

    def add_identity_options(flags)
      flags.on('--implementer ID', 'PROVIDER/FAMILY that produced part of the change; repeatable') do |v|
        (@options[:implementers] ||= []) << v
      end
      flags.on('--unavailable ID', 'PROVIDER/FAMILY shown unavailable on evidence; repeatable') do |v|
        (@options[:unavailable] ||= []) << v
      end
    end

    def help(parser)
      puts parser
      0
    end

    def root = File.realpath(@options.fetch(:root, Dir.pwd))
  end
end
