# frozen_string_literal: true

module Shaka
  # Selects a ledger round for dispositions without relying on completion order.
  module LocalReviewRecordCommand
    private

    def record(parser)
      raise OptionParser::InvalidArgument, parser.to_s unless
        @arguments.empty? && @options[:ledger] && @options[:content_file]

      ledger = LocalReviewLedger.new(@options[:ledger])
      content = record_content
      ledger.record!(content, number: @options[:round])
      puts JSON.pretty_generate('ledger' => ledger.path, 'round' => ledger.rounds.size)
      0
    end

    def record_content = JSON.parse(File.read(@options[:content_file], encoding: 'UTF-8'))

    def record_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka review record --ledger PATH --content-file PATH'
        flags.on('--ledger PATH') { |value| @options[:ledger] = value }
        flags.on('--round N', Integer) { |value| @options[:round] = value }
        flags.on('--content-file PATH') { |value| @options[:content_file] = value }
        flags.on('-h', '--help') { @options[:help] = true }
      end
    end
  end
end
