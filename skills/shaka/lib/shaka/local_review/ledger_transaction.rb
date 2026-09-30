# frozen_string_literal: true

require 'securerandom'
require 'tempfile'

module Shaka
  # Locks only ledger mutations; reviewer processes run independently outside the lock.
  module LocalReviewLedgerTransaction
    def start!(base:, head:, reviewer:)
      locked do
        check_next!(base:, head:, reviewer:)
        @baseline = rounds.reject { |round| round['head'] == head }
        @reservation = { 'id' => SecureRandom.hex(16), 'head' => head, 'reviewer' => reviewer }
        write(data.merge('base' => base, 'pending' => pending + [@reservation]))
      end
    end

    def cancel!
      return unless @reservation

      locked { write(data.merge('pending' => pending.reject { |item| item['id'] == @reservation['id'] })) }
      @reservation = nil
    end

    def append!(base:, round:)
      locked do
        check_snapshot!(base, round)

        check_next!(base:, head: round.fetch('head'), reviewer: round.fetch('reviewer'), own: @reservation)
        number = rounds.size + 1
        write(data.merge('rounds' => rounds + [round], 'pending' => pending - [@reservation]))
        @reservation = nil
        number
      end
    end

    # Without an explicit round, retain the single-reviewer last-round behavior.
    def record!(content, number: nil)
      raise Error, 'Record content must be an object.' unless content.is_a?(Hash)

      locked do
        number = record_number(number)

        round = recorded_round(content, number)
        updated = rounds.dup
        updated[number - 1] = round
        write(data.merge(content.slice('fallback'), 'rounds' => updated))
      end
    end

    private

    def recorded_round(content, number)
      round = rounds.fetch(number - 1).merge(content.slice('findings', 'model', 'tokens', 'cost', 'estimate'))
      check_findings!(round, number)
      round
    end

    def record_number(number)
      number ||= rounds.size
      raise Error, 'Round must identify an existing review.' unless
        number.is_a?(Integer) && number.positive? && number <= rounds.size

      number
    end

    def check_snapshot!(base, round)
      current = rounds.reject { |item| item['head'] == round['head'] }
      return if pending.include?(@reservation) && data['base'] == base && current == @baseline

      raise Error, 'The ledger changed while the reviewer ran; result is stale.'
    end

    def pending = data.fetch('pending', [])

    def locked
      File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        @data = nil
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    def write(content)
      Tempfile.create(['shaka-ledger-', '.json'], File.dirname(@path)) do |file|
        file.write("#{JSON.pretty_generate(content)}\n")
        file.flush
        File.rename(file.path, @path)
      end
      @data = content
    end
  end
end
