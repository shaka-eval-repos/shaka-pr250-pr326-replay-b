# frozen_string_literal: true

module Shaka
  # Batch boundaries and duplicate identity checks shared by start and completion.
  module LocalReviewLedgerGuards
    private

    def check_base!(base)
      return unless data['base'] && data['base'] != base

      raise Error, "The ledger's rounds measure the change against #{data['base']}; use a new ledger."
    end

    def check_duplicate!(head, reviewer, own)
      duplicate = rounds.index { |round| round['head'] == head && same_reviewer?(round, reviewer) }
      raise Error, "Round #{duplicate + 1} already reviewed #{head}; commit the fix first." if duplicate
      return unless (pending - [own]).any? { |item| item['head'] == head && same_reviewer?(item, reviewer) }

      raise Error, 'This reviewer is already running for this head.'
    end

    def check_batch!(head)
      raise Error, 'The ledger has a pending review of another head; finish the batch first.' if
        pending.any? { |item| item['head'] != head }
      return unless rounds.any? { |round| round['head'] == head } && last_head != head

      raise Error, 'An earlier batch already reviewed this head; commit the fix first.'
    end

    def check_dispositions!(head)
      rounds.each_with_index do |round, index|
        next if round['head'] == head || recorded?(round)

        raise Error, "Record round #{index + 1}'s findings with `shaka review record` before the next round."
      end
    end
  end
end
