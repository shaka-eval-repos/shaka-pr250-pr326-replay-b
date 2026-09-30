# frozen_string_literal: true

require_relative 'local_review_batch_test'

class LocalReviewBatchFailureTest < Minitest::Test
  COMMAND = LocalReviewCodexTest::COMMAND
  include LocalReviewFixture
  include LocalReviewLoopSteps
  include LocalReviewBatchHelpers

  def teardown
    Array(@results).each { |result| cleanup_artifacts(result) }
  end

  def test_same_reviewer_is_rejected_after_a_peer_completes
    in_loop do |head|
      loop_round(head, findings: 0)
      fake_claude(@bin, head)
      peer_round(head)
      assert_refused(head, 'Round 1 already reviewed')
      other_base = Shaka::LocalReviewLedger.new(@ledger)
      assert_error('measure the change against') do
        other_base.start!(base: 'e' * 40, head:, reviewer: 'xai/grok')
      end
    end
  end

  def test_concurrent_disposition_updates_keep_each_target_round
    in_loop do |head|
      fake_batch(head)
      concurrent_rounds(head)
      [Thread.new { record_peer(1, 'first peer') }, Thread.new { record_peer(2, 'second peer') }].each(&:value)
      assert_equal(['first peer', 'second peer'], ledger_rounds.map do |round|
        round.fetch('findings').first.fetch('summary')
      end)
    end
  end

  def test_modified_prior_evidence_rejects_completion_without_losing_it
    in_loop do |head|
      loop_round(head, findings: 0)
      ledger = Shaka::LocalReviewLedger.new(@ledger)
      new_head = fix_commit
      ledger.start!(base: @base, head: new_head, reviewer: 'anthropic/claude')
      assert_stale_prior(ledger, new_head)
      assert_equal '100', ledger_rounds.first.fetch('tokens')
      ledger.cancel!
    end
  end

  def test_moved_checkout_rejects_a_late_process_result
    in_loop do |head|
      fake_batch(head)
      thread = Thread.new { batch_process(head, 'openai/codex', 0) }
      wait_for_process
      fix_commit
      File.write("#{@trace}-1", 'release')
      assert_moved_head_result(thread.value)
      assert_empty ledger_rounds
    end
  end

  private

  def assert_stale_prior(ledger, head)
    ledger.record!({ 'findings' => [], 'tokens' => '100' }, number: 1)
    round = ledger_rounds.first.merge('head' => head, 'reviewer' => 'anthropic/claude')
    assert_error('stale') { ledger.append!(base: @base, round:) }
  end

  def assert_moved_head_result(result)
    output, _, status = result
    refute_predicate status, :success?
    assert_includes JSON.parse(output).fetch('reason'), 'Checkout HEAD is'
  end

  def wait_for_process
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until File.exist?("#{@trace}-0")
      raise 'fake reviewer did not start' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end
