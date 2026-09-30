# frozen_string_literal: true

require_relative 'reviewer_command_test'
require_relative 'review_policy_test'
require_relative 'reviewer_selection_test'

class ReviewerBatchSelectionTest < ReviewerSelectionTest
  def test_additional_reviewers_follow_configuration_after_the_preferred_first
    result = batch(['anthropic/claude'], count: 3)
    assert_equal %w[openai/codex anthropic/claude xai/grok], result.fetch('reviewers')
    assert_equal 'different_provider', result.fetch('outcome')
    assert_equal result.fetch('reviewer'), result.fetch('reviewers').first
  end

  def test_unavailable_and_duplicate_identities_do_not_fill_extra_slots
    roster = ROSTER + [{ 'provider' => 'Anthropic', 'model_family' => 'Claude' }]
    result = batch(['openai/codex'], count: 5, reviewers: roster, unavailable: ['xai/grok'])
    assert_equal %w[anthropic/claude openai/codex], result.fetch('reviewers')
  end

  def test_fresh_host_fallback_remains_one_identity_when_all_clis_are_unavailable
    result = batch(['openai/codex'], count: 3, unavailable: ROSTER.map { |row| row.values.join('/') })
    assert_equal ['openai/codex'], result.fetch('reviewers')
    assert_equal 'same_model', result.fetch('outcome')
  end

  private

  def batch(implementers, **options)
    Shaka::ReviewerSelection.new(reviewers: options.fetch(:reviewers, ROSTER),
                                 implementers: implementers.map { |id| Shaka::ReviewerSelection.parse(id) },
                                 unavailable: options.fetch(:unavailable, []).map do |id|
                                   Shaka::ReviewerSelection.parse(id)
                                 end, count: options.fetch(:count)).call
  end
end

class ReviewerBatchCommandTest < ReviewerCommandTest
  def test_configured_count_and_override_use_the_trusted_settings
    with_repository do |root|
      configure_count(root, 2)
      commit_repository(root)
      configure_count(root, 3)
      result = reviewer(root, '--ref', 'HEAD', '--implementer', 'openai/codex')
      assert_equal %w[anthropic/claude openai/codex], result.fetch('reviewers')
      override = reviewer(root, '--ref', 'HEAD', '--implementer', 'openai/codex', '--count', '1')
      assert_equal ['anthropic/claude'], override.fetch('reviewers')
    end
  end

  def test_rejects_invalid_count_overrides
    with_repository do |root|
      %w[0 -1 1.5 two].each do |value|
        _, error, status = Open3.capture3(COMMAND, 'reviewer', '--root', root,
                                          '--implementer', 'openai/codex', '--count', value)
        refute_predicate status, :success?
        assert_includes error, 'positive integer'
      end
    end
  end

  private

  def configure_count(root, count)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.safe_load_file(path)
    data['review']['local_review_count'] = count
    File.write(path, YAML.dump(data))
  end
end

class ReviewerBatchPolicyTest < ReviewPolicyTest
  def test_rejects_non_positive_or_non_integer_configuration
    [0, -1, 1.5, '2', true, nil].each do |count|
      with_repository('review' => review_policy('local_review_count' => count)) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }
        assert_includes error.message, 'review.local_review_count must be a positive integer'
      end
    end
  end
end
