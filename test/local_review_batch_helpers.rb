# frozen_string_literal: true

# Shared fake-process setup and batch assertions.
module LocalReviewBatchHelpers
  private

  def ledger_rounds = JSON.parse(File.read(@ledger)).fetch('rounds')

  def peer_round(head)
    output, error, status = run_review(@root, @base, head, @bin, reviewer: 'anthropic/claude', ledger: @ledger,
                                                                 env: { 'REVIEW_TRACE' => @trace })
    result = assert_successful_review(output, error, status, head, 'anthropic/claude')
    (@results ||= []) << result
    result
  end

  def fake_batch(head)
    %w[codex claude].each { |name| fake_batch_process(head, name) }
  end

  def fake_batch_process(_head, name)
    script = File.read(File.join(__dir__, 'fixtures/local_review_batch_process.rb'))
    write_executable(@bin, name, script)
  end

  def concurrent_rounds(head)
    reviewers = %w[openai/codex anthropic/claude]
    threads = reviewers.map.with_index { |reviewer, index| Thread.new { batch_process(head, reviewer, index) } }
    threads.map.with_index do |thread, index|
      output, error, status = thread.value
      result = assert_successful_review(output, error, status, head, reviewers[index])
      (@results ||= []) << result
      result
    end
  end

  def batch_process(head, reviewer, index)
    environment = { 'REVIEW_TRACE' => "#{@trace}-#{index}", 'REVIEW_PEER' => "#{@trace}-#{1 - index}" }
    run_review(@root, @base, head, @bin, reviewer:, ledger: @ledger, timeout_seconds: 10, env: environment)
  end

  def record_peer(number, summary, kind: 'nit')
    content = { 'findings' => [{ 'id' => 'F1', 'summary' => summary, 'class' => kind,
                                 'disposition' => 'documented' }] }
    Shaka::LocalReviewLedger.new(@ledger).record!(content, number:)
  end

  def assert_peer_context(previous, head)
    prompt = JSON.parse(File.read(@trace)).fetch('prompt')
    assert_prior_round_prompt(prompt, head)
    assert_includes prompt, "Commits since #{previous}"
    assert_ledger_rounds([previous, head, head])
  end

  def assert_new_head_blocked
    commit!(@root, 'another fix', 'Finish repairs')
    assert_refused(git!(@root, 'rev-parse', 'HEAD').strip, 'Record round 2')
  end

  def finish_peer_dispositions(fix)
    assert_refused(fix, 'Record round 1')
    record_peer(1, 'first peer', kind: 'defect')
    assert_refused(fix, 'Record round 2')
    record_peer(2, 'second peer')
    assert_peer_publication
  end

  def assert_released(ledger)
    ledger.cancel!
    assert_empty JSON.parse(File.read(@ledger)).fetch('pending')
  end

  def assert_stale_completion(ledger, peer)
    change_ledger_base
    assert_error('stale') { ledger.append!(base: @base, round: peer.merge('reviewer' => 'anthropic/claude')) }
    assert_equal [peer], ledger_rounds
  end

  def assert_peer_completions(results)
    assert_equal [1, 2], results.map { |result| result.fetch('round') }.sort
    assert_equal %w[anthropic/claude openai/codex], ledger_rounds.map { |round| round.fetch('reviewer') }.sort
  end

  def assert_peer_publication
    body = Shaka::LocalReviewComment.render(JSON.parse(File.read(@ledger)))
    assert_includes body, 'first peer'
    assert_includes body, 'second peer'
    assert_includes body, '1 unfixed defect'
  end

  def change_ledger_base
    data = JSON.parse(File.read(@ledger))
    data['base'] = 'f' * 40
    File.write(@ledger, JSON.generate(data))
  end

  def assert_error(message, &)
    assert_includes assert_raises(Shaka::Error, &).message, message
  end
end
