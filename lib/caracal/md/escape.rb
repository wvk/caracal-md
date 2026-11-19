module Caracal
  module Md
    # Markdown that renders as a given text, for values interpolated into
    # Markdown (see Caracal::Md.escape).
    #
    # Punctuation kramdown reads as syntax gets a backslash. Characters the
    # converter would still interpret in the text kramdown leaves become
    # numeric entities, which it emits as runs of their own: [ and \ (the
    # directives [TOC] and \newpage), @ (cross-references), ^ (kramdown's
    # end-of-block line), { (attribute lists and template {{placeholders}},
    # see Converter#entity_char), & (entities) and the marker characters,
    # which the converter shows as U+FFFD. So do spaces and tabs at the start
    # and end of a line, which Markdown would read as indentation or drop.
    # Line breaks become <br>, so the result is one line of Markdown and fits
    # table cells and headings as well. The result is UTF-8.
    module Escape
      BACKSLASHED = %(.*_+`<>()]}#!:|"'$=~-).chars.freeze
      ENTITIES    = ['[', '\\', '@', '^', '{', '&', Converter::MARKER_OPEN, Converter::MARKER_CLOSE].freeze
      PATTERN     = /[#{Regexp.escape((BACKSLASHED + ENTITIES).join)}]/
      LINE_BREAK  = '<br>'.freeze

      def self.markdown(text)
        text.to_s.gsub(/\r\n?/, "\n").split("\n", -1).map { |line| line(line) }.join(LINE_BREAK).encode(Encoding::UTF_8)
      end

      def self.line(line)
        lead  = line[/\A[ \t]*/]
        trail = line[lead.length..][/[ \t]*\z/]
        body  = line[lead.length...(line.length - trail.length)]
        entities(lead) + body.gsub(PATTERN) { |char| BACKSLASHED.include?(char) ? "\\#{char}" : entities(char) } + entities(trail)
      end

      def self.entities(chars)
        chars.each_char.map { |char| "&##{char.ord};" }.join
      end
    end
  end
end
