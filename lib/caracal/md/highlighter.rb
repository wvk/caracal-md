module Caracal
  module Md
    # Splits source code into colored runs with Rouge, when Rouge is installed.
    class Highlighter
      # GitHub-like colors, looked up by token name and then its parents.
      THEME = {
        'Comment'               => { color: '6A737D', italic: true },
        'Comment.Preproc'       => { color: 'D73A49', italic: false },
        'Keyword'               => { color: 'D73A49' },
        'Keyword.Constant'      => { color: '005CC5' },
        'Keyword.Type'          => { color: '6F42C1' },
        'Operator.Word'         => { color: 'D73A49' },
        'Literal.String'        => { color: '032F62' },
        'Literal.String.Symbol' => { color: '005CC5' },
        'Literal.String.Regex'  => { color: '22863A' },
        'Literal.Number'        => { color: '005CC5' },
        'Name.Builtin'          => { color: '005CC5' },
        'Name.Class'            => { color: '6F42C1' },
        'Name.Constant'         => { color: '005CC5' },
        'Name.Decorator'        => { color: '6F42C1' },
        'Name.Function'         => { color: '6F42C1' },
        'Name.Namespace'        => { color: '6F42C1' },
        'Name.Variable'         => { color: 'E36209' },
        'Name.Tag'              => { color: '22863A' },
        'Name.Attribute'        => { color: '6F42C1' },
        'Name.Label'            => { color: '005CC5' },
        'Generic.Deleted'       => { color: 'B31D28' },
        'Generic.Inserted'      => { color: '22863A' },
        'Generic.Heading'       => { color: '005CC5', bold: true },
        'Generic.Subheading'    => { color: '6F42C1', bold: true },
        'Generic.Emph'          => { italic: true },
        'Generic.Strong'        => { bold: true },
        'Error'                 => { color: 'B31D28' },
      }.freeze

      def self.available?
        return @available unless @available.nil?

        @available = begin
          require 'rouge'
          true
        rescue LoadError
          false
        end
      end

      def initialize(theme: THEME)
        @theme = theme
        @cache = {}
      end

      # Returns the source's lines, each a list of [text, run options], or nil
      # when no lexer knows the language.
      def lines(source, language)
        lexer = Rouge::Lexer.find_fancy(language.to_s, source) if language and not language.empty?
        return unless lexer

        lines = [[]]
        lexer.lex(source).each do |token, value|
          options = run_options(token)
          value.split("\n", -1).each_with_index do |part, index|
            lines << [] if index.positive?
            lines.last << [part, options] unless part.empty?
          end
        end
        lines
      rescue StandardError
        nil
      end

      private

      def run_options(token)
        @cache[token.qualname] ||= begin
          name = token.qualname
          name = name.rpartition('.').first until name.empty? or @theme.key?(name)
          @theme.fetch(name, {})
        end
      end
    end
  end
end
