module Caracal
  module Md
    # A Word document or template (.docx, .dotx, .docm, .dotm) whose styles,
    # numbering, page setup, headers and footers the output takes over.
    class Template
      NS = Package::NS

      attr_reader :package

      def self.load(source)
        case source
        when Template then source
        when Package  then new(source)
        else new(Package.read(source))
        end
      end

      def initialize(package)
        @package = package
        package.main_part # raises unless this is a Word package
      end

      def main_part
        package.main_part
      end

      # The section properties that apply to the end of the document.
      def section
        package.xml(main_part).at_xpath('/w:document/w:body/w:sectPr', NS)
      end

      def page_width  = section_value('w:pgSz/@w:w', 11906)
      def page_height = section_value('w:pgSz/@w:h', 16838)

      def margins
        %w[top right bottom left gutter].to_h do |side|
          [side.to_sym, section_value("w:pgMar/@w:#{side}", side == 'gutter' ? 0 : 1440).abs]
        end
      end

      def text_width
        page_width - margins[:left] - margins[:right] - margins[:gutter]
      end

      def text_height
        page_height - margins[:top] - margins[:bottom]
      end

      # The parts placeholders may appear in: the document, its headers and footers.
      def text_parts
        [main_part] + package.related_parts(main_part, :header) + package.related_parts(main_part, :footer)
      end

      def placeholder?(key)
        text_parts.any? { |part| Placeholders.keys(package.xml(part)).include?(key) }
      end

      private

      def section_value(xpath, default)
        value = section&.at_xpath(xpath, NS)&.value
        value ? value.to_i : default
      end
    end
  end
end
