module Caracal
  module Md
    # A Word document or template (.docx, .dotx, .docm, .dotm) whose styles,
    # numbering, page setup, headers and footers the output takes over.
    #
    # A Template is frozen, and so is its package: it reads what renders
    # need when it is made, and renders copy the package. Load a template
    # once and pass it to any number of renders, also in parallel threads.
    class Template
      NS = Package::NS

      attr_reader :package, :main_part, :page_width, :page_height, :margins, :text_parts

      def self.load(source)
        case source
        when Template then source
        when Package  then new(source)
        else new(Package.read(source))
        end
      end

      # Takes a copy of +package+, so the caller's package stays as it is.
      def initialize(package)
        @package   = package.dup
        @main_part = @package.main_part.freeze # raises unless this is a Word package

        section      = @package.xml(@main_part).at_xpath('/w:document/w:body/w:sectPr', NS)
        @page_width  = section_value(section, 'w:pgSz/@w:w', 11906)
        @page_height = section_value(section, 'w:pgSz/@w:h', 16838)
        @margins     = %w[top right bottom left gutter].to_h do |side|
          [side.to_sym, section_value(section, "w:pgMar/@w:#{side}", side == 'gutter' ? 0 : 1440).abs]
        end.freeze

        # The parts placeholders may appear in: the document, its headers and footers.
        parts = [@main_part] + @package.related_parts(@main_part, :header) + @package.related_parts(@main_part, :footer)
        @text_parts   = parts.map(&:freeze).freeze
        @placeholders = @text_parts.flat_map { |part| Placeholders.keys(@package.xml(part)) }.uniq.freeze

        @package.freeze
        freeze
      end

      def text_width
        page_width - margins[:left] - margins[:right] - margins[:gutter]
      end

      def text_height
        page_height - margins[:top] - margins[:bottom]
      end

      def placeholder?(key)
        @placeholders.include?(key)
      end

      private

      def section_value(section, xpath, default)
        value = section&.at_xpath(xpath, NS)&.value
        value ? value.to_i : default
      end
    end
  end
end
