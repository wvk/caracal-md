require 'kramdown'
require 'kramdown-parser-gfm'

module Caracal
  module Md
    # kramdown's GFM parser, plus highlighting: ==text== becomes a <mark>
    # element, as in Obsidian and pandoc's mark extension.
    #
    # The signs touch the text they enclose, so a == between spaces stays
    # text, as does an opening == without its partner. The text inside is
    # parsed like any other, so code spans keep their == signs; brackets in
    # it without a link definition stay text, without kramdown's warning.
    class Parser < Kramdown::Parser::GFM
      HIGHLIGHT = /==/

      def initialize(source, options)
        super
        @span_parsers << :caracal_md_highlight
        @highlighting = false
        @highlight_failed = {}.compare_by_identity # element => true
      end

      def warning(text)
        super unless @highlighting and text.start_with?('No link definition')
      end

      private

      # A failed attempt has scanned the rest of the source: every later
      # == in the same element fails as well, so it stays text at once.
      def parse_highlight
        line = @src.current_line_number
        @src.pos += 2
        if @highlighting or @highlight_failed[@tree] or @src.eos? or @src.match?(/[\s=]/)
          return add_text('==')
        end

        saved    = @src.save_pos
        warnings = @warnings.size
        el = Element.new(:html_element, 'mark', nil, category: :span, location: line)
        found = begin
          @highlighting = true
          parse_spans(el, HIGHLIGHT) { not @src.string.byteslice(@src.pos - 1, 1).match?(/\s/) }
        ensure
          @highlighting = false
        end

        if found
          @src.pos += 2
          @tree.children << el
        else
          @warnings.slice!(warnings..)
          @src.revert_pos(saved)
          @highlight_failed[@tree] = true
          add_text('==')
        end
      end
      define_parser(:caracal_md_highlight, HIGHLIGHT, '==', :parse_highlight)
    end
  end
end
