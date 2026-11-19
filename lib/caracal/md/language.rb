module Caracal
  module Md
    # Sets the document language (spelling, hyphenation) from front matter
    # "lang" in the default run properties of styles.xml.
    module Language
      NS = Package::NS

      REGIONS = {
        'de' => 'de-DE', 'en' => 'en-US', 'fr' => 'fr-FR', 'nl' => 'nl-NL', 'es' => 'es-ES',
        'it' => 'it-IT', 'pt' => 'pt-PT', 'da' => 'da-DK', 'sv' => 'sv-SE', 'pl' => 'pl-PL',
      }.freeze

      # Elements that follow w:lang in w:rPr.
      AFTER_LANG = %w[eastAsianLayout specVanish oMath].freeze

      # The language tag of a lang value, or nil for none: stripped, _ as -,
      # the language subtag in lower case ("DE" => "de", "DE-ch" => "de-ch").
      #
      # From front matter, YAML's false is Norwegian ("no", which YAML 1.1
      # reads as a boolean), a list gives its first entry, and other values
      # (numbers, true) none; the last two yield a message. As an option
      # (+option+), false means none and anything but a String or Symbol
      # raises ArgumentError.
      def self.normalize(value, option: false, &warn)
        case value
        when String, Symbol
          tag = value.to_s.strip.tr('_', '-')
          return if tag.empty?

          language, rest = tag.split('-', 2)
          [language.downcase, rest].compact.join('-')
        when nil then nil
        when false then (option ? nil : 'no')
        else
          raise ArgumentError, "lang: #{value.inspect} is no language tag; pass a String or Symbol" if option

          if value.is_a?(Array) and value.any?
            warn&.call("front matter lang lists #{value.size} languages; the document takes the first") if value.size > 1
            normalize(value.first, &warn)
          else
            warn&.call("front matter lang #{value.inspect} is no language tag; the document has no language")
            nil
          end
        end
      end

      def self.tag(lang)
        lang = lang.to_s.strip.tr('_', '-')
        return if lang.empty?

        lang.include?('-') ? lang : REGIONS.fetch(lang.downcase, lang)
      end

      def self.apply(package, lang)
        tag  = tag(lang) or return
        part = package.related_part(package.main_part, :styles) or return
        doc  = package.xml(part)
        root = doc.root

        defaults = root.at_xpath('w:docDefaults', NS) || prepend(root, '<w:docDefaults/>')
        rpr_default = defaults.at_xpath('w:rPrDefault', NS) || prepend(defaults, '<w:rPrDefault/>')
        rpr = rpr_default.at_xpath('w:rPr', NS) || rpr_default.add_child('<w:rPr/>').first

        node = rpr.at_xpath('w:lang', NS)
        unless node
          anchor = rpr.element_children.find { |el| AFTER_LANG.include?(el.name) }
          node = anchor ? anchor.add_previous_sibling('<w:lang/>').first : rpr.add_child('<w:lang/>').first
        end
        node['w:val'] = tag
      end

      def self.prepend(parent, xml)
        first = parent.element_children.first
        first ? first.add_previous_sibling(xml).first : parent.add_child(xml).first
      end
    end
  end
end
