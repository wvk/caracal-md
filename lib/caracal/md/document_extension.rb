module Caracal
  module Md
    # Adds #markdown to caracal documents, headers, footers and table cells:
    #
    #   docx.markdown "Some **bold** text", base_dir: 'docs'
    #
    # Content goes in as it is converted; footnotes become a numbered list
    # after it, since Word footnotes need the whole package (see Renderer).
    # In the block of Caracal::Md.document, the document's #markdown
    # converts with that render's state instead (see Renderer#document).
    module DocumentExtension
      # Set by Renderer#document for the time of its block.
      attr_accessor :markdown_session

      def markdown(text, **options)
        if markdown_session
          @markdown_warnings = markdown_session.markdown(self, text, **options)
          return self
        end

        if is_a?(Caracal::Document)
          Styles.install(self, only_missing: true)
          options = { text_width: page_width - page_margin_left - page_margin_right,
                      text_height: page_height - page_margin_top - page_margin_bottom }.merge(options)
        end
        meta, body = FrontMatter.split(text.to_s)
        converter = Converter.new({ footnotes: :list, title_block: false }.merge(options))
        converter.convert(body, self, meta: meta)
        owner = is_a?(Caracal::Document) ? self : (document if respond_to?(:document))
        converter.define_custom_styles(owner) if owner
        @markdown_warnings = converter.warnings
        self
      end

      def markdown_warnings
        @markdown_warnings || []
      end
    end
  end
end

Caracal::Document.include Caracal::Md::DocumentExtension
Caracal::AbstractHeaderAndFooter.include Caracal::Md::DocumentExtension
Caracal::Core::Models::TableCellModel.include Caracal::Md::DocumentExtension
