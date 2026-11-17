require 'caracal'

module Caracal
  module Md
    # Markdown in, DOCX bytes out.
    #
    #   Caracal::Md::Renderer.new(template: 'corporate.dotx').render(markdown)
    class Renderer
      PAGE_SIZES = { a4: [11906, 16838], letter: [12240, 15840] }.freeze

      DEFAULTS = {
        template:            nil,       # .docx/.dotx path, IO, bytes or Template; nil uses Styles
        style_map:           {},        # Styles id or name => template style id or name
        placeholder:         '{{content}}',
        variables:           {},        # extra {{key}} values for the template
        base_dir:            nil,       # where relative image paths resolve; defaults to Dir.pwd
        image_loader:        nil,       # callable(src) => bytes or nil, replaces the default loader
        allow_remote_images: false,
        allow_raw_openxml:   false,
        toc:                 nil,       # nil: front matter decides
        toc_title:           nil,
        toc_depth:           nil,
        title_block:         :auto,     # :auto renders it unless the template has {{title}}
        quotes:              nil,       # :en, :de, :fr or four kramdown entity names; nil: from lang
        highlight:           true,
        figure_captions:     :title,
        page_size:           :a4,       # without template
        margins:             1440,      # twips, without template
        styles:              nil,       # callable(docx): adjust the default styles
        document:            nil,       # callable(docx): add headers, footers etc. before rendering
      }.freeze

      attr_reader :warnings

      def initialize(**options)
        unknown = options.keys - DEFAULTS.keys
        raise ArgumentError, "unknown option(s): #{unknown.join(', ')}" if unknown.any?

        @options  = DEFAULTS.merge(options)
        @warnings = []
      end

      def render(markdown)
        meta, body = FrontMatter.split(markdown.to_s)
        template   = @options[:template] && Template.load(@options[:template])
        variables  = FrontMatter.to_variables(meta).merge(@options[:variables].transform_keys(&:to_s))

        docx = Caracal::Document.new
        setup_page(docx, template)
        Styles.install(docx)
        @options[:styles]&.call(docx)

        converter = Converter.new(converter_options(meta, template, docx))
        converter.convert(body, docx, meta: meta)
        converter.define_custom_styles(docx)
        @options[:document]&.call(docx)

        package = Package.read(docx.render.string)
        @warnings = converter.warnings.dup
        if template
          merger  = TemplateMerger.new(template, package, style_map: @options[:style_map],
                                       placeholder: @options[:placeholder], variables: variables)
          package = merger.merge
          @warnings.concat merger.warnings
        end
        PostProcessor.new(package).apply
        Language.apply(package, meta['lang']) if meta['lang']
        CoreProperties.apply(package, meta)
        package.to_s
      end

      private

      def setup_page(docx, template)
        if template
          margins = template.margins
          docx.page_size width: template.page_width, height: template.page_height
          docx.page_margins top: margins[:top], bottom: margins[:bottom], left: margins[:left], right: margins[:right]
        else
          width, height = PAGE_SIZES.fetch(@options[:page_size].to_sym)
          margin = @options[:margins]
          docx.page_size width: width, height: height
          docx.page_margins top: margin, bottom: margin, left: margin, right: margin
        end
      end

      def converter_options(meta, template, docx)
        lang = meta['lang'].to_s
        {
          text_width:          template ? template.text_width : docx.page_width - docx.page_margin_left - docx.page_margin_right,
          text_height:         template ? template.text_height : docx.page_height - docx.page_margin_top - docx.page_margin_bottom,
          footnotes:           :native,
          toc:                 option_or_meta(:toc, meta['toc'], false),
          toc_title:           option_or_meta(:toc_title, meta['toc-title'], nil),
          toc_depth:           option_or_meta(:toc_depth, meta['toc-depth'], 3),
          title_block:         title_block?(meta, template),
          quotes:              @options[:quotes] || (lang.start_with?('de') ? :de : lang.start_with?('fr') ? :fr : :en),
          highlight:           @options[:highlight],
          allow_raw_openxml:   @options[:allow_raw_openxml],
          figure_captions:     @options[:figure_captions],
          image_loader:        @options[:image_loader],
          base_dir:            @options[:base_dir],
          allow_remote_images: @options[:allow_remote_images],
          lang:                lang,
        }
      end

      def option_or_meta(key, meta_value, default)
        return @options[key] unless @options[key].nil?
        return meta_value unless meta_value.nil?

        default
      end

      def title_block?(meta, template)
        return @options[:title_block] unless @options[:title_block] == :auto

        !(template and template.placeholder?('title'))
      end
    end
  end
end
