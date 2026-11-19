require 'securerandom'

module Caracal
  module Md
    # The markers of one render: text runs U+E000 nonce:kind:N U+E001 that
    # the converter writes where caracal has no command, and PostProcessor
    # turns into OOXML once the document is complete (see PostProcessor).
    #
    # The nonce is new for every render and appears in no input, so text
    # from Markdown, front matter, variables or caracal commands spells no
    # marker, whatever characters it holds.
    class Markers
      OPEN  = "\u{E000}".freeze
      CLOSE = "\u{E001}".freeze

      # The start of every marker of this render.
      attr_reader :prefix

      # A marker anywhere in a text: kind and number as groups 1 and 2.
      attr_reader :pattern

      def initialize(nonce = SecureRandom.hex(8))
        @prefix  = "#{OPEN}#{nonce}:".freeze
        @pattern = /#{Regexp.escape(@prefix)}([a-z-]+):(\d+)#{CLOSE}/
        @whole   = /\A#{@pattern}\z/
        freeze
      end

      def marker(kind, number)
        "#{@prefix}#{kind}:#{number}#{CLOSE}"
      end

      # [kind, number] when +text+ is a marker of this render and nothing
      # else, else nil.
      def parse(text)
        match = @whole.match(text)
        [match[1], match[2].to_i] if match
      end
    end
  end
end
