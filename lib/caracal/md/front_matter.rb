require 'date'
require 'yaml'

module Caracal
  module Md
    # YAML front matter: a mapping between `---` lines at the very start.
    module FrontMatter
      PATTERN = /\A(?:﻿)?---[ \t]*\r?\n(.*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|\z)/m

      # Returns [metadata (string keys), markdown body]. Text that merely looks
      # like front matter (e.g. a rule followed by a setext heading) stays body.
      def self.split(text)
        match = PATTERN.match(text)
        return [{}, text] unless match

        data = YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: false)
        return [{}, text] unless data.is_a?(Hash)

        [data.transform_keys(&:to_s), match.post_match]
      rescue Psych::Exception
        [{}, text]
      end

      # Flattens metadata into plain strings for placeholders and document
      # properties; Markdown in string values is reduced to its text.
      def self.to_variables(meta)
        quotes = meta['lang'].to_s.start_with?('de') ? :de : :en
        plain  = ->(value) { value.is_a?(String) ? Converter.plain_text(value, quotes: quotes) : value.to_s }
        meta.each_with_object({}) do |(key, value), vars|
          case value
          when Array        then vars[key] = value.map(&plain).join(', ')
          when Hash, nil    then next
          else                   vars[key] = plain.call(value)
          end
        end
      end
    end
  end
end
