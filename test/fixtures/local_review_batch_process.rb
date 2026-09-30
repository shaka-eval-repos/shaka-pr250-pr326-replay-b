#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

prompt = $stdin.read
head = prompt.match(/pinned commit ([0-9a-f]{40})/)[1]
codex = File.basename($PROGRAM_NAME) == 'codex'
identity, effort = codex ? %w[openai/codex UNKNOWN] : %w[anthropic/claude medium]
File.write(ENV.fetch('REVIEW_TRACE'), 'started')
sleep 0.01 until File.exist?(ENV.fetch('REVIEW_PEER'))
report = "peer finding\nREVIEWED #{head} BY #{identity} EFFORT #{effort} FINDINGS 1\n"
if codex
  File.write(ARGV.fetch(ARGV.index('-o') + 1), report)
else
  puts JSON.generate(is_error: false, result: report)
end
