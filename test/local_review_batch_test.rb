# frozen_string_literal: true

require_relative 'local_review_test'
require 'shaka/local_review/ledger'
require 'shaka/local_review/comment'
require_relative 'local_review_batch_helpers'

# Real helper invocations use two fake processes and one private ledger.
class LocalReviewBatchTest < Minitest::Test
  COMMAND = LocalReviewCodexTest::COMMAND
  include LocalReviewFixture
  include LocalReviewLoopSteps
  include LocalReviewBatchHelpers

  def teardown
    Array(@results).each { |result| cleanup_artifacts(result) }
  end

  def test_peer_sees_earlier_findings_but_not_current_head_findings
    in_loop do |head|
      loop_round(head, findings: 1)
      fix = fix_commit
      record_fix(fix)
      loop_round(fix, findings: 1)
      fake_claude(@bin, fix)
      assert_equal 3, peer_round(fix).fetch('round')
      assert_peer_context(head, fix)
      assert_new_head_blocked
    end
  end

  def test_concurrent_completion_and_dispositions_preserve_both_reviews
    in_loop do |head|
      fake_batch(head)
      results = concurrent_rounds(head)
      assert_peer_completions(results)
      fix = fix_commit
      finish_peer_dispositions(fix)
      loop_round(fix, findings: 0)
      assert_includes File.read(@trace), 'first peer'
      assert_includes File.read(@trace), 'second peer'
    end
  end

  def test_pending_peer_blocks_new_heads_and_duplicate_launches
    in_loop do |head|
      ledger = Shaka::LocalReviewLedger.new(@ledger)
      ledger.start!(base: @base, head:, reviewer: 'anthropic/claude')
      other = Shaka::LocalReviewLedger.new(@ledger)
      assert_error('already running') { other.start!(base: @base, head:, reviewer: 'Anthropic/Claude') }
      assert_refused(fix_commit, 'pending review of another head')
      assert_error('pending reviewers') { Shaka::LocalReviewComment.render(JSON.parse(File.read(@ledger))) }
      assert_released(ledger)
    end
  end

  def test_stale_ledger_completion_does_not_overwrite_peer_evidence
    in_loop do |head|
      loop_round(head, findings: 1)
      ledger = Shaka::LocalReviewLedger.new(@ledger)
      ledger.start!(base: @base, head:, reviewer: 'anthropic/claude')
      peer = ledger_rounds.first
      assert_stale_completion(ledger, peer)
      ledger.cancel!
      assert_equal 'f' * 40, JSON.parse(File.read(@ledger)).fetch('base')
    end
  end

  def test_failed_process_releases_its_reservation_and_preserves_completed_peer
    in_loop do |head|
      loop_round(head, findings: 0)
      write_executable(@bin, 'claude', "#!/bin/sh\nexit 42\n")
      output, _, status = run_review(@root, @base, head, @bin, reviewer: 'anthropic/claude', ledger: @ledger)
      refute_predicate status, :success?
      result = JSON.parse(output)
      cleanup_artifacts(result)
      assert_empty JSON.parse(File.read(@ledger)).fetch('pending')
      assert_equal 1, ledger_rounds.size
    end
  end
end
