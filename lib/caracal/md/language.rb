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
