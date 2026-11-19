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
        lang:                nil,       # language of documents whose front matter names none ('de', 'de-CH', :en, …)
        input:               :markdown, # or :html: rich text from web editors, without front matter
        base_dir:            nil,       # where relative image paths resolve; defaults to Dir.pwd
        image_loader:        nil,       # callable(src) => bytes or nil, replaces the default loader
        allow_remote_images: false,
        allow_raw_openxml:   false,
        link:                nil,       # callable(href) => the href to use, or nil to keep the link's text alone
        toc:                 nil,       # nil: front matter decides
        toc_title:           nil,
        toc_depth:           nil,
        heading_offset:      nil,       # nil: front matter decides; levels added to every heading's, or :auto (highest level in use becomes Heading 1)
        title_block:         :auto,     # :auto renders it unless the template has {{title}}
        quotes:              nil,       # :en, :de, :fr or four kramdown entity names; nil: from lang
        highlight:           true,
        figure_captions:     :title,
        number_captions:     nil,       # nil: front matter decides; true numbers every caption, :chapter per level-1 heading
        figure_label:        nil,       # nil: from lang ("Figure", "Abbildung", …)
        table_label:         nil,
        lof:                 nil,       # list of figures after the table of contents; nil: front matter decides
        lot:                 nil,       # list of tables
        lof_title:           nil,
        lot_title:           nil,
        code_handlers:       {},        # { language => handler } or CodeHandlers: fenced blocks as images
        svg_rasterizer:      nil,       # call(CodeBlock with cleaned SVG) => PNG fallback; without it the fallback is blank
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
        @input    = Converter.input(@options[:input])
        @warnings = []
      end

      # DOCX bytes for +markdown+, or for HTML with input: :html.
      def render(markdown)
        meta, body = (@input == :html ? [{}, markdown.to_s] : FrontMatter.split(markdown.to_s))
        meta       = with_lang(meta)
        template   = @options[:template] && Template.load(@options[:template])
        variables  = FrontMatter.to_variables(meta).merge(@options[:variables].transform_keys(&:to_s))

        docx = Caracal::Document.new
        setup_page(docx, template)
        Styles.install(docx)
        @options[:styles]&.call(docx)

        captions  = captions(meta)
        converter = Converter.new(converter_options(meta, template, docx).merge(captions: captions))
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
        PostProcessor.new(package, captions: captions).apply
        Language.apply(package, meta['lang']) if meta['lang']
        CoreProperties.apply(package, meta)
        package.to_s
      end

      private

      # Front matter with the lang option as its "lang" when it names none:
      # the language decides quotes, caption labels, list titles, the
      # spelling language and the document property.
      def with_lang(meta)
        lang = @options[:lang].to_s.strip
        return meta if lang.empty? or not meta['lang'].to_s.strip.empty?

        meta.merge('lang' => lang)
      end

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
          heading_offset:      option_or_meta(:heading_offset, meta['heading-offset'], 0),
          title_block:         title_block?(meta, template),
          quotes:              @options[:quotes] || (lang.start_with?('de') ? :de : lang.start_with?('fr') ? :fr : :en),
          highlight:           @options[:highlight],
          allow_raw_openxml:   @options[:allow_raw_openxml],
          link:                @options[:link],
          figure_captions:     @options[:figure_captions],
          image_loader:        @options[:image_loader],
          base_dir:            @options[:base_dir],
          allow_remote_images: @options[:allow_remote_images],
          lang:                lang,
          input:               @input,
          code_handlers:       @options[:code_handlers],
          svg_rasterizer:      @options[:svg_rasterizer],
          literal_braces:      true,
          lof:                 option_or_meta(:lof, meta['lof'], false),
          lot:                 option_or_meta(:lot, meta['lot'], false),
        }
      end

      def captions(meta)
        Captions.new(
          mode:        option_or_meta(:number_captions, meta['number-captions'], false),
          lang:        meta['lang'],
          labels:      { figure: option_or_meta(:figure_label, meta['figure-label'], nil),
                         table:  option_or_meta(:table_label, meta['table-label'], nil) },
          list_titles: { figure: option_or_meta(:lof_title, meta['lof-title'], nil),
                         table:  option_or_meta(:lot_title, meta['lot-title'], nil) },
        )
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
