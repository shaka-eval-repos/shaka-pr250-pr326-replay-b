# frozen_string_literal: true

require 'json'
require_relative '../error'
require_relative 'evidence'
require_relative 'finding'
require_relative 'ledger_transaction'
require_relative 'ledger_guards'

module Shaka
  # Private record of a local review loop: each round's commit, reviewer settings, report, and
  # what became of its findings. It stays outside the checkout until `review publish` renders it,
  # and it has the same shape as that command's content file.
  class LocalReviewLedger
    include LocalReviewLedgerTransaction
    include LocalReviewLedgerGuards

    attr_reader :path

    # Only `review run` can start a ledger, so only it needs the checkout to keep the ledger out of.
    def initialize(path, root: nil)
      @path = File.expand_path(path)
      directory = File.realpath(File.dirname(@path))
      raise Error, '--ledger must be outside the candidate checkout' if
        root && (directory == root || directory.start_with?("#{root}/"))
    end

    def rounds = data.fetch('rounds')

    def previous_rounds(head) = rounds.reject { |round| round['head'] == head }

    def previous_head(head) = previous_rounds(head).last&.fetch('head')

    def fixes_before(head)
      previous = previous_rounds(head)
      batch = previous.select { |round| round['head'] == previous.last&.fetch('head') }
      batch.flat_map { |round| LocalReviewFinding.list(round['findings'], 'finding').select(&:fixed?).map(&:commit) }
    end

    def last_head = rounds.last&.fetch('head')

    # Peers may join the current head; advancing waits for every completion and disposition.
    def check_next!(base:, head:, reviewer:, own: nil)
      check_base!(base)
      check_duplicate!(head, reviewer, own)
      check_batch!(head)
      check_dispositions!(head)
    end

    # The newest disposition of every finding so far, keyed by the id rounds share.
    def prior_finding_lines(head)
      latest = previous_rounds(head).each_with_index.with_object({}) do |(round, index), findings|
        LocalReviewFinding.list(round['findings'], "round #{index + 1} finding").each do |finding|
          findings[[round.fetch('reviewer').downcase, finding.id]] = finding
        end
      end
      latest.map { |(reviewer, _id), finding| "#{finding.prompt_line} [reviewer #{reviewer}]" }
    end

    private

    def data
      @data ||= if File.exist?(@path)
                  parsed = JSON.parse(File.read(@path, encoding: 'UTF-8'))
                  raise Error, "#{@path} is not a review ledger." unless
                    parsed.is_a?(Hash) && parsed['rounds'].is_a?(Array)

                  parsed
                else
                  { 'rounds' => [] }
                end
    end

    def same_reviewer?(round, reviewer) = round.fetch('reviewer').downcase == reviewer.downcase

    def recorded?(round) = round.key?('findings') || reported_count(round).zero?

    # The count check keeps a finding from dropping out between the report and the comment.
    def check_findings!(round, number)
      findings = LocalReviewFinding.list(round['findings'], "round #{number} finding")
      reported = reported_count(round)
      return if findings.size == reported

      raise Error, "Round #{number}'s report counts #{reported} findings; #{findings.size} were recorded."
    end

    def reported_count(round)
      match = File.read(round.fetch('report'), encoding: 'UTF-8').match(LocalReviewEvidence::CLOSING)
      raise Error, "Round report #{round['report']} has no FINDINGS count." unless match

      match[2].to_i
    end
  end
end
