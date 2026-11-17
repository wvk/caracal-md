require 'kramdown'
require 'kramdown-parser-gfm'

module Caracal
  module Md
    # Walks kramdown's syntax tree and issues caracal commands on a target: a
    # Caracal::Document, a header or footer, or a table cell.
    #
    # Styles are referred to by the ids in Styles. Footnotes and ordered-list
    # start numbers are emitted as markers (see Markers) that PostProcessor
    # turns into OOXML caracal has no command for.
    class Converter
      MARKER_OPEN  = "\u{E000}".freeze
      MARKER_CLOSE = "\u{E001}".freeze
      MARKER       = /#{MARKER_OPEN}([a-z-]+):(\d+)#{MARKER_CLOSE}/o

      def self.marker(kind, number)
        "#{MARKER_OPEN}#{kind}:#{number}#{MARKER_CLOSE}"
      end

      QUOTES = {
        en: %w[lsquo rsquo ldquo rdquo],
        de: %w[sbquo lsquo bdquo ldquo],
        fr: %w[lsaquo rsaquo laquo raquo],
      }.freeze

      SMART_QUOTE_INDEX = { lsquo: 0, rsquo: 1, ldquo: 2, rdquo: 3 }.freeze

      TYPOGRAPHIC = {
        hellip: '…', mdash: '—', ndash: '–', laquo: '«', raquo: '»',
        laquo_space: "« ", raquo_space: " »",
      }.freeze

      INLINE_HTML = {
        'b' => { bold: true }, 'strong' => { bold: true },
        'i' => { italic: true }, 'em' => { italic: true }, 'cite' => { italic: true }, 'var' => { italic: true },
        'u' => { underline: true }, 'ins' => { underline: true },
        's' => { strike: true }, 'del' => { strike: true }, 'strike' => { strike: true },
        'sup' => { vertical_align: :superscript }, 'sub' => { vertical_align: :subscript },
        'mark' => { highlight_color: 'yellow' },
        'code' => { style: 'VerbatimChar' }, 'kbd' => { style: 'VerbatimChar' },
        'samp' => { style: 'VerbatimChar' }, 'tt' => { style: 'VerbatimChar' },
      }.freeze

      BLOCK_HTML = %w[div section article aside main header footer nav details summary figure figcaption center blockquote].freeze

      ALIGN = { left: :left, center: :center, right: :right }.freeze

      MAX_LIST_LEVEL = 8 # zero-based

      ALERT = /\A\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\n?/i
      ALERT_STYLES = {
        'note' => 'AlertNote', 'tip' => 'AlertTip', 'important' => 'AlertImportant',
        'warning' => 'AlertWarning', 'caution' => 'AlertCaution',
      }.freeze
      ALERT_LABELS = {
        'en' => { 'note' => 'Note', 'tip' => 'Tip', 'important' => 'Important', 'warning' => 'Warning', 'caution' => 'Caution' },
        'de' => { 'note' => 'Hinweis', 'tip' => 'Tipp', 'important' => 'Wichtig', 'warning' => 'Warnung', 'caution' => 'Vorsicht' },
      }.freeze

      LINK_SCHEMES = %w[http https mailto tel ftp ftps news].freeze

      TOC_TITLES = { 'de' => 'Inhalt', 'en' => 'Contents', 'fr' => 'Sommaire', 'nl' => 'Inhoud', 'es' => 'Índice', 'it' => 'Indice' }.freeze

      DEFAULTS = {
        text_width:        9026,            # twips; A4 with 1in margins
        text_height:       13958,
        footnotes:         :native,         # :native (Word footnotes, needs PostProcessor) or :list
        toc:               false,
        toc_title:         nil,
        toc_depth:         3,
        heading_offset:    0,               # levels added to every heading's, or :auto: the highest level in use becomes 1
        title_block:       true,
        quotes:            :en,
        highlight:         true,
        highlight_theme:   Highlighter::THEME,
        allow_raw_openxml: false,
        link:              nil,             # call(href) => the href to use, or nil for the link's text alone
        figure_captions:   :title,          # :title, :alt or :none
        image_loader:      nil,
        base_dir:          nil,
        allow_remote_images: false,
        lang:              nil,
        captions:          nil,             # Captions: numbered captions and cross-references (need PostProcessor)
        lof:               false,           # list of figures after the table of contents
        lot:               false,           # list of tables after the table of contents
        code_handlers:     nil,             # { language => handler } or CodeHandlers: fenced blocks as images
        svg_rasterizer:    nil,             # call(CodeBlock with the cleaned SVG) => PNG/JPEG/GIF fallback
      }.freeze

      # Raster image bytes with their natural size in points, and the
      # cleaned SVG they stand in for, if any.
      Picture = Struct.new(:data, :width, :height, :svg)

      # pandoc-crossref references: @fig:id, [@fig:id], [-@fig:id] (number
      # only), [@fig:a; @tbl:b].
      CROSS_REF_LABEL = /[Ff]ig:[\w.:-]*\w|[Tt]bl:[\w.:-]*\w/
      CROSS_REF = /\[(-?@(?:#{CROSS_REF_LABEL})(?:\s*;\s*-?@(?:#{CROSS_REF_LABEL}))*)\]|(?<![\w@])@(#{CROSS_REF_LABEL})/

      # A pandoc attribute right after an image: {#id}.
      PANDOC_ID = /\A\{#([^\s{}]+)\}/

      attr_reader :warnings, :custom_styles

      # The text of a Markdown snippet, without formatting.
      def self.plain_text(markdown, quotes: :en)
        converter = new(quotes: quotes, highlight: false, image_loader: ->(_) {})
        root = converter.send(:parse, markdown)
        root.children.reject { |el| el.type == :blank }.map { |el| converter.send(:plain_text, el) }.join("\n").strip
      end

      def initialize(options = {})
        unknown = options.keys - DEFAULTS.keys
        raise ArgumentError, "unknown option(s): #{unknown.join(', ')}" if unknown.any?

        @options       = DEFAULTS.merge(options)
        @warnings      = []
        @custom_styles = {}  # id => { name:, type: }
        @bookmarks     = {}  # markdown id => bookmark name
        @footnotes     = []  # [number, definition element]
        @captions      = @options[:captions]
        @targets       = []  # ids with a bookmark: headings and numbered captions
        @referenced    = []  # ids cross-references point to
        @caption_count = 0
        @code_handlers = code_handlers(@options[:code_handlers])
        @svg_rasterizer = (CodeHandlers.new({ 'svg' => @options[:svg_rasterizer] }, raster_only: true) if @options[:svg_rasterizer])
        @image_loader  = @options[:image_loader] ||
          ImageLoader.new(base_dir: @options[:base_dir] || Dir.pwd, allow_remote: @options[:allow_remote_images])
        @highlighter   = Highlighter.new(theme: @options[:highlight_theme]) if @options[:highlight] and Highlighter.available?
      end

      # Converts +markdown+ onto +target+. +meta+ is the front matter, used for
      # the title block.
      def convert(markdown, target, meta: {})
        root = parse(markdown)
        @heading_offset = heading_offset(root)
        lof = (@options[:lof] and not contains_directive?(root, :lof))
        lot = (@options[:lot] and not contains_directive?(root, :lot))
        # a list of figures or tables lists numbered captions, so it numbers all
        @number_all = (@captions and (@captions.number_all? or @options[:lof] or @options[:lot] or
                                      contains_directive?(root, :lof) or contains_directive?(root, :lot)))

        title_block(meta, target) if @options[:title_block]
        toc(target) if @options[:toc] and not contains_directive?(root, :toc)
        list_of_captions(:figure, target) if lof
        list_of_captions(:table, target) if lot
        blocks(root.children, target, {})
        footnote_section(target)
        (@referenced.uniq - @targets).each { |id| warn "cross-reference to ##{id}: no heading, figure or table has this id" }
        target
      end

      # Defines the styles named by custom-style attributes that +docx+ lacks.
      def define_custom_styles(docx)
        normal = docx.find_style('Normal')
        @custom_styles.each do |id, style|
          next if docx.find_style(id)

          options = { id: id, name: style[:name], type: style[:type] }
          if style[:type] == :paragraph and normal
            options.merge!(line: normal.style_line, line_rule: normal.style_line_rule, align: normal.style_align)
          elsif style[:type] == :table
            options[:base] = Styles::TABLE_STYLE[:id]
          end
          docx.style options
        end
      end

      private

      #========== PARSING =====================================

      def parse(markdown)
        options = Kramdown::Options.merge(kramdown_options)
        root, warnings = Parser.parse(markdown.to_s, options)
        @smart_quotes = options[:smart_quotes]
        @warnings.concat(warnings.reject { |message| crossref_link_warning?(message) })
        root
      end

      # kramdown reads [@fig:id] as a reference link without definition.
      def crossref_link_warning?(message)
        id = message[/\ANo link definition for link ID '(.*)' found/, 1]
        (@captions and id and "[#{id}]".match?(/\A#{CROSS_REF}\z/))
      end

      def kramdown_options
        quotes = @options[:quotes]
        quotes = QUOTES.fetch(quotes.to_sym) { QUOTES[:en] } unless quotes.is_a?(Array)
        {
          hard_wrap:    false,
          auto_ids:     true,
          smart_quotes: quotes,
          syntax_highlighter: nil,
          math_engine:  nil,
        }
      end

      def warn(message)
        @warnings << message
      end

      #========== BLOCKS ======================================

      def blocks(elements, target, ctx)
        elements = elements.reject { |el| el.type == :blank }
        elements.each_with_index do |el, index|
          next if el.equal?(@consumed)

          if el.type == :table and (caption = table_caption(elements[index + 1]))
            @consumed = elements[index + 1]
            table(el, target, ctx, caption: caption[:text], caption_id: caption[:id])
          else
            block(el, target, ctx)
          end
        end
      end

      def block(el, target, ctx)
        case el.type
        when :p            then paragraph(el, target, ctx)
        when :header       then heading(el, target, ctx)
        when :blockquote   then blockquote(el, target, ctx)
        when :codeblock    then code_block(el, target, ctx)
        when :ul, :ol      then list(el, target, ctx)
        when :dl           then definition_list(el, target, ctx)
        when :table        then table(el, target, ctx)
        when :hr           then target.hr
        when :math         then code_block(el, target, ctx, language: 'tex', handler: 'math')
        when :html_element then html_block(el, target, ctx)
        when :xml_comment  then directive(comment_directive(el.value), target)
        when :raw          then raw_block(el, target)
        when :text         then blocks(parse(el.value).children, target, ctx) unless el.value.strip.empty?
        when :blank, :eob, :comment, :abbrev_def, :footnote_def then nil
        else
          warn "unsupported block element #{el.type}"
          blocks(el.children, target, ctx)
        end
      end

      def paragraph(el, target, ctx)
        if (kind = paragraph_directive(el))
          return directive(kind, target)
        end

        style = paragraph_style(el, ctx[:style] || 'Normal')
        inline_blocks(el.children, target, ctx, style: style, align: ctx[:align], figure_id: figure_id(el))
      end

      # The id of a paragraph holding only an image belongs to the image.
      def figure_id(el)
        return unless el.attr['id']

        kids = el.children.reject { |child| whitespace?(child) }
        el.attr['id'] if kids.size == 1 and image_element(kids.first)
      end

      # Emits inline content as paragraphs, splitting it at images and
      # directives, which caracal places between paragraphs.
      def inline_blocks(children, target, ctx, style:, align: nil, empty: false, figure_id: nil)
        children = pandoc_ids(children)
        emitted = false
        buffer  = []
        flush = lambda do
          runs = strip_whitespace(buffer)
          if runs.any?
            emit_paragraph(target, runs, style: style, align: align)
            emitted = true
          end
          buffer = []
        end

        children.each do |child|
          image = image_element(child)
          data  = image && load_image(image)
          if data
            flush.call
            image(image, target, ctx, data, id: image.attr['id'] || figure_id)
            emitted = true
          elsif child.type == :xml_comment and (kind = comment_directive(child.value))
            flush.call
            directive(kind, target)
          else
            buffer << child
          end
        end
        flush.call
        emit_paragraph(target, [], style: style, align: align) if empty and not emitted
      end

      # A pandoc attribute {#id} right after an image gives the image its id
      # and leaves the text.
      def pandoc_ids(children)
        children.each_with_index.map do |child, index|
          image = (index.positive? and image_element(children[index - 1]))
          match = child.value.match(PANDOC_ID) if image and child.type == :text
          next child unless match

          image.attr['id'] ||= match[1]
          Kramdown::Element.new(:text, match.post_match)
        end
      end

      def emit_paragraph(target, children, style:, align: nil, fmt: {})
        options = { style: style }
        options[:align] = align if align
        target.p(options) { |p| inlines(children, p, fmt) }
      end

      def heading(el, target, ctx)
        level = (el.options[:level].to_i + @heading_offset).clamp(1, 6)
        style = paragraph_style(el, "Heading#{level}")
        id    = el.attr['id'].to_s

        target.p(style: style) do |p|
          if id.empty?
            inlines(el.children, p, {})
          else
            @targets << id
            name = bookmark_name(id)
            p.bookmark_start id: name, name: name
            inlines(el.children, p, {})
            p.bookmark_end id: name
          end
        end
      end

      # The levels the heading_offset option adds to every heading's: an
      # integer as it is, or for :auto those that make the highest level in
      # +root+ level 1.
      def heading_offset(root)
        offset = @options[:heading_offset]
        return 0 if offset.nil?
        return 1 - (heading_levels(root).min || 1) if offset.to_s == 'auto'

        Integer(offset)
      rescue ArgumentError, TypeError
        warn "heading offset #{offset.inspect} is ignored; it takes an integer or auto"
        0
      end

      def heading_levels(el)
        own = (el.type == :header ? [el.options[:level].to_i] : [])
        own + el.children.flat_map { |child| heading_levels(child) }
      end

      # A quote, or a GitHub alert (> [!NOTE]) with a label paragraph.
      def blockquote(el, target, ctx)
        children = el.children.reject { |child| child.type == :blank }
        first    = children.first
        lead     = first.children.first if first&.type == :p
        kind     = lead.value[ALERT, 1]&.downcase if lead&.type == :text

        unless kind and ALERT_STYLES.key?(kind)
          style = paragraph_style(el, 'Quote')
          return blocks(el.children, target, ctx.merge(style: style, list_style: style))
        end

        style = ALERT_STYLES[kind]
        label = ALERT_LABELS.fetch(@options[:lang].to_s[0, 2], ALERT_LABELS['en'])[kind]
        target.p(style: style, keep_next: true) { |p| p.text label, bold: true }
        rest = Kramdown::Element.new(:text, lead.value.sub(ALERT, ''))
        first = Kramdown::Element.new(:p, nil, first.attr, first.options).tap do |p|
          p.children.replace([rest, *first.children.drop(1)])
        end
        blocks([first, *children.drop(1)], target, ctx.merge(style: style, list_style: style))
      end

      def code_block(el, target, ctx, language: nil, handler: nil)
        language ||= el.options[:lang] || el.attr['class'].to_s[/\blanguage-(\S+)/, 1]
        return raw_openxml(el.value, target) if language == '{=openxml}'
        return if handled_code_block(el, target, ctx, handler || language)

        source = expand_tabs(el.value.to_s.chomp)
        lines  = @highlighter&.lines(source, language) || source.split("\n", -1).map { |line| [[line, {}]] }
        style  = paragraph_style(el, 'SourceCode')

        target.p(style: style) do |p|
          lines.each_with_index do |runs, index|
            p.br if index.positive?
            runs.each { |text, options| p.text text, options.dup unless text.empty? }
          end
        end
      end

      #========== CODE HANDLERS ===============================

      def code_handlers(handlers)
        return if handlers.nil? or handlers.empty?

        handlers = CodeHandlers.new(handlers) unless handlers.is_a?(CodeHandlers)
        handlers.for_render
      end

      # Hands the block to the code handler for +language+ and shows the image
      # it returns like a Markdown image: id, title (as caption), alt, width
      # and height come from the block's attributes. Returns nil, leaving the
      # block to be shown as code, when there is no handler or no image.
      def handled_code_block(el, target, ctx, language)
        return unless @code_handlers and language and @code_handlers.handles?(language)

        attributes = el.attr.except('class').to_h { |key, value| [key.to_s.freeze, value.to_s.freeze] }.freeze
        block = CodeBlock.new(language: language.dup.freeze, source: el.value.to_s.chomp.freeze, attributes: attributes)
        data  = @code_handlers.render(block) { |message| warn "#{message}; shown as code" }
        shown = (picture(data, "#{language} block") if data)
        return unless shown

        attrs = attributes.slice('id', 'title', 'width', 'height')
        attrs['src'] = 'image'
        attrs['alt'] = attributes['alt'] || "#{language} diagram"
        image(Kramdown::Element.new(:img, nil, attrs), target, ctx, shown)
        true
      end

      def list(el, target, ctx)
        return toc(target) if toc_ial?(el)

        start = el.options[:first_list_marker].to_s[/\A\d+/].to_i if el.type == :ol
        target.public_send(el.type) do |list|
          el.children.each_with_index do |li, index|
            next unless li.type == :li

            marker = Converter.marker('ol-start', start) if index.zero? and start and start != 1 and list.list_level.zero?
            list_item(li, list, ctx, marker: marker)
          end
        end
      end

      def list_item(li, list, ctx, marker: nil)
        children = li.children.reject { |child| child.type == :blank }
        first    = children.first&.type == :p ? children.shift : nil

        list.li(style: ctx[:list_style] || Styles.list_style(list.list_type, list.list_level)) do |item|
          item.text marker if marker
          inlines(strip_whitespace(first.children), item, {}) if first
          children.each { |child| list_item_block(child, item, ctx) }
        end
      end

      # Content after an item's first paragraph. Caracal items hold runs and
      # nested lists, so other blocks are approximated as runs.
      def list_item_block(el, item, ctx)
        case el.type
        when :ul, :ol
          return flatten_list(el, item, ctx) if item.list_item_level >= MAX_LIST_LEVEL

          start = el.options[:first_list_marker].to_s[/\A\d+/].to_i if el.type == :ol
          warn "a nested ordered list starts at 1 instead of #{start}" if start and start > 1
          item.public_send(el.type) do |list|
            el.children.each { |li| list_item(li, list, ctx) if li.type == :li }
          end
        when :p
          paragraph_break(item)
          inlines(strip_whitespace(el.children), item, {})
        when :codeblock
          paragraph_break(item)
          expand_tabs(el.value.to_s.chomp).split("\n", -1).each_with_index do |line, index|
            item.br if index.positive?
            item.text line, style: 'VerbatimChar' unless line.empty?
          end
        when :blockquote, :dl, :html_element
          el.children.each { |child| list_item_block(child, item, ctx) }
        when :dt, :dd
          paragraph_break(item)
          inlines(strip_whitespace(el.children), item, el.type == :dt ? { bold: true } : {})
        when :table
          paragraph_break(item)
          el.children.flat_map(&:children).select { |tr| tr.type == :tr }.each_with_index do |tr, index|
            item.br if index.positive?
            item.text tr.children.map { |td| plain_text(td).strip }.join(' | '), bold: (index.zero? and el.children.first&.type == :thead)
          end
          warn 'a table inside a list item is rendered as lines of text'
        when :math
          paragraph_break(item)
          item.text el.value.to_s, style: 'VerbatimChar'
        when :blank, :xml_comment then nil
        else
          paragraph_break(item)
          item.text plain_text(el)
        end
      end

      # Word lists have nine levels; deeper items continue the ninth level's
      # item, one line each.
      def flatten_list(el, item, ctx)
        warn 'lists nest nine levels deep at most; deeper items are flattened' unless @flattened
        @flattened = true
        el.children.each do |li|
          next unless li.type == :li

          item.br
          item.text "\u2013 "
          li.children.reject { |child| child.type == :blank }.each_with_index do |child, index|
            if child.type == :p and index.zero?
              inlines(strip_whitespace(child.children), item, {})
            else
              list_item_block(child, item, ctx)
            end
          end
        end
      end

      # Starts a new paragraph inside a list item: text following a nested
      # list does so by itself, other text gets a blank line.
      def paragraph_break(item)
        after_list = (item.nested_lists.any? and item.nested_lists.last.first == item.runs.size)
        2.times { item.br } unless after_list or item.runs.empty?
      end

      def definition_list(el, target, ctx)
        el.children.each do |child|
          case child.type
          when :dt
            emit_paragraph(target, child.children, style: paragraph_style(child, 'DefinitionTerm'))
          when :dd
            blocks(child.children, target, ctx.merge(style: paragraph_style(child, 'Definition')))
          end
        end
      end

      def table(el, target, ctx, caption: nil, caption_id: nil)
        alignments  = el.options[:alignment] || []
        header_rows = 0
        source_rows = []

        el.children.each do |section|
          section.children.each do |tr|
            next unless tr.type == :tr

            header_rows += 1 if section.type == :thead
            source_rows << tr.children.select { |td| td.type == :td }
          end
        end
        return if source_rows.empty?

        columns = source_rows.map(&:size).max
        widths  = column_widths(source_rows, columns, ctx[:width] || @options[:text_width])
        rows = source_rows.map do |cells|
          Array.new(columns) do |col|
            td    = cells[col]
            align = ALIGN[alignments[col]]
            cell_ctx = ctx.merge(width: widths[col] - 200, style: 'TableText', align: align)
            Caracal::Core::Models::TableCellModel.new do |cell|
              inline_blocks(td ? td.children : [], cell, cell_ctx, style: 'TableText', align: align, empty: true)
            end
          end
        end

        options = { style: el.attr['custom-style'] ? custom_style(el.attr['custom-style'], :table) : 'MarkdownTable', column_widths: widths }
        options[:repeat_header] = header_rows if header_rows.positive?
        id = el.attr['id'] || caption_id
        if numbered_caption?(caption, id)
          numbered_caption(target, :table, caption.to_s, id, keep_next: true)
        elsif caption and not caption.empty?
          options[:caption] = caption
        end
        target.table(rows, options) do |t|
          t.look first_row: header_rows.positive?
        end
      end

      # Column widths proportional to each column's longest text, within limits.
      def column_widths(rows, columns, total)
        weights = Array.new(columns) do |col|
          longest = rows.map { |cells| cells[col] ? plain_text(cells[col]).length : 0 }.max.to_i
          longest.clamp(6, 40)
        end
        sum    = weights.sum.to_f
        widths = weights.map { |w| (total * w / sum).floor }
        widths[-1] += total - widths.sum
        widths
      end

      # A paragraph right after a table reading "Table: ..." captions it; a
      # trailing {#id} gives the table its id. Returns { text:, id: }.
      def table_caption(el)
        return unless el&.type == :p

        text = plain_text(el)
        return unless text.match?(/\A(?:Table)?:\s+\S/)

        text = text.sub(/\A(?:Table)?:\s+/, '')
        id   = text[/\s*\{#([^\s{}]+)\}\s*\z/, 1]
        { text: id ? text.sub(/\s*\{#[^\s{}]+\}\s*\z/, '') : text, id: id }
      end

      #========== NUMBERED CAPTIONS, CROSS-REFERENCES =========

      # Captions are numbered for figures and tables with an id, and all of
      # them with number_captions or a list of figures or tables.
      def numbered_caption?(caption, id)
        return false unless @captions

        id ? true : (@number_all and not caption.to_s.strip.empty?)
      end

      # "Figure N: text" in the Caption style, N being a marker PostProcessor
      # turns into a SEQ field. A bookmark spans label and number, the target
      # of cross-references and of the list of figures; with an id, a second
      # one spans the number alone.
      def numbered_caption(target, kind, text, id, keep_next: false)
        @targets << id if id
        name    = id ? bookmark_name(id) : "_Cap#{@caption_count += 1}"
        options = { style: 'Caption' }
        options[:keep_next] = true if keep_next

        target.p(options) do |p|
          p.bookmark_start id: name, name: name
          p.text "#{@captions.label(kind)} ", bold: true
          p.bookmark_start id: number_bookmark(name), name: number_bookmark(name) if id
          p.text Converter.marker("caption-#{kind}", 0), bold: true
          p.bookmark_end id: number_bookmark(name) if id
          p.bookmark_end id: name
          unless text.empty?
            p.text ':', bold: true
            p.text " #{text}"
          end
        end
      end

      def number_bookmark(name)
        "_N#{name}"
      end

      # A ref marker PostProcessor turns into a REF field showing the
      # bookmarked label and number (or heading text), or the number alone.
      def reference(p, id, fmt, source:, number_only: false)
        @referenced << id
        name = bookmark_name(id)
        name = number_bookmark(name) if number_only
        text(p, Converter.marker('ref', @captions.reference(name, source)), fmt)
      end

      # Text with pandoc-crossref references turned into ref markers.
      def text_with_references(p, content, fmt)
        return text(p, content, fmt) unless @captions

        last = 0
        content.scan(CROSS_REF) do
          match = Regexp.last_match
          text(p, content[last...match.begin(0)], fmt)
          if match[1]
            items = match[1].split(/\s*;\s*/)
            items.each_with_index do |item, index|
              text(p, ', ', fmt) if index.positive?
              label = item.sub(/\A-?@/, '')
              source = items.size == 1 ? match[0] : item
              reference(p, crossref_id(label), fmt, source: source, number_only: item.start_with?('-'))
            end
          else
            reference(p, crossref_id(match[2]), fmt, source: match[0])
          end
          last = match.end(0)
        end
        text(p, content[last..], fmt)
      end

      # @Fig:x refers to fig:x.
      def crossref_id(label)
        label.sub(/\A[FT]/) { |c| c.downcase }
      end

      def list_of_captions(kind, target)
        return warn('a list of figures or tables needs the Renderer') unless @captions
        return warn('a list of figures or tables fits in the document body only') unless target.respond_to?(:toc)

        target.p @captions.list_title(kind), style: 'TOCHeading'
        # the style passes the template merge with the marker, for the entries
        target.p Converter.marker("list-#{kind}", 0), style: 'TableofFigures'
      end

      def html_block(el, target, ctx)
        case el.value
        when 'hr' then target.hr
        when 'br' then target.p
        when 'img' then image(el, target, ctx)
        when 'summary' then inline_blocks(el.children, target, ctx, style: 'DefinitionTerm')
        when 'pre' then code_block(Kramdown::Element.new(:codeblock, plain_text(el)), target, ctx)
        when 'p' then inline_blocks(el.children, target, ctx, style: paragraph_style(el, ctx[:style] || 'Normal'))
        when *BLOCK_HTML then blocks(el.children, target, ctx)
        else
          if el.children.any? { |child| block_element?(child) }
            blocks(el.children, target, ctx)
          else
            warn "HTML element <#{el.value}> is rendered as text" unless el.children.empty?
            inline_blocks(el.children, target, ctx, style: ctx[:style] || 'Normal')
          end
        end
      end

      def raw_block(el, target)
        types = Array(el.options[:type]).flat_map { |t| t.to_s.split(/[\s,]+/) }
        raw_openxml(el.value, target) if types.include?('openxml')
      end

      def raw_openxml(xml, target)
        if @options[:allow_raw_openxml]
          target.raw_xml xml
        else
          warn 'raw OpenXML is ignored; enable allow_raw_openxml to pass it through'
        end
      end

      #========== IMAGES ======================================

      # The image an element shows by itself: an img, or a link around one.
      def image_element(el)
        return el if el.type == :img or (el.type == :html_element and el.value == 'img')

        if el.type == :a
          kids = el.children.reject { |c| c.type == :text and c.value.strip.empty? }
          kids.first if kids.size == 1 and kids.first.type == :img
        end
      end

      # The picture of an image element when it loads, else nil (with a
      # warning), so the image shows as its alt text.
      def load_image(el)
        src  = el.attr['src'].to_s
        data = @image_loader.call(src)
        return picture(data, src) if data

        warn "#{src}: image not loaded"
        nil
      end

      # The picture for image bytes from anywhere: a PNG, JPEG or GIF as it
      # is, an SVG cleaned and rasterized; else nil with a warning.
      def picture(data, name)
        return svg_picture(data, name) if Svg.svg?(data)

        size = Caracal::ImageSize.read(data)
        unless size
          warn "#{name}: unsupported image format, PNG, JPEG, GIF and SVG work"
          return
        end

        dpi_x, dpi_y = Caracal::ImageSize.density(data) || [96, 96]
        Picture.new(data, size[0] * 72.0 / dpi_x, size[1] * 72.0 / dpi_y)
      end

      # The cleaned SVG at its own size, with a raster fallback for readers
      # without SVG support: the svg_rasterizer's PNG, else a blank one.
      # caracal 2.0.0 embeds no SVG; there the rasterizer's PNG is all.
      def svg_picture(data, name)
        clean = Svg.clean(data)
        warn "#{name}: removed from the SVG: #{clean.removed.join(', ')}" if clean.removed.any?

        if Svg.embeddable?
          raster = (rasterize(clean, name, 'the fallback image is blank') if @svg_rasterizer)
          Picture.new(raster || Svg.blank_png(clean.width, clean.height), clean.width, clean.height, clean.svg)
        elsif @svg_rasterizer
          raster = rasterize(clean, name, 'shown as its alt text')
          Picture.new(raster, clean.width, clean.height) if raster
        else
          warn "#{name}: SVG needs an svg_rasterizer, or caracal with SVG support"
          nil
        end
      rescue Svg::Error => e
        warn "#{name}: SVG refused, it #{e.message}"
        nil
      end

      def rasterize(clean, name, consequence)
        block = CodeBlock.new(language: 'svg', source: clean.svg.freeze, attributes: {}.freeze)
        @svg_rasterizer.render(block) { |message| warn "#{name}: #{message}; #{consequence}" }
      end

      def image(el, target, ctx, picture = load_image(el), id: el.attr['id'])
        src = el.attr['src'].to_s
        alt = el.attr['alt'].to_s
        return emit_paragraph(target, [Kramdown::Element.new(:text, alt.empty? ? src : alt)], style: ctx[:style] || 'Normal', fmt: { italic: true }) unless picture

        width, height = image_size(picture, el.attr, ctx)
        options = { data: picture.data, width: width, height: height, ppi: 72, align: ctx[:align] || :center }
        options[:svg] = picture.svg if picture.svg
        target.img(src.start_with?('data:') ? 'image' : src, options)

        caption = case @options[:figure_captions]
                  when :title then el.attr['title']
                  when :alt   then alt
                  end
        return if @options[:figure_captions] == :none

        # a figure with an id takes its caption from the alt text, as in pandoc
        caption = alt if id and caption.to_s.strip.empty?
        if numbered_caption?(caption, id)
          numbered_caption(target, :figure, caption.to_s.strip, id)
        elsif not caption.to_s.strip.empty?
          target.p(caption, style: 'Caption')
        end
      end

      # Size in points: the picture's own size, or width/height attributes,
      # scaled down to fit the text area.
      def image_size(picture, attrs, ctx)
        width  = picture.width
        height = picture.height
        max_width  = (ctx[:width] || @options[:text_width]) / 20.0
        max_height = @options[:text_height] / 20.0 * 0.9

        w = length_in_points(attrs['width'], max_width)
        h = length_in_points(attrs['height'], max_height)
        if w and h then width, height = w, h
        elsif w    then height, width = height * w / width, w
        elsif h    then width, height = width * h / height, h
        end

        scale = [1.0, max_width / width, max_height / height].min
        [(width * scale).round.clamp(1, nil), (height * scale).round.clamp(1, nil)]
      end

      UNITS = { 'pt' => 1.0, 'px' => 0.75, 'in' => 72.0, 'cm' => 72 / 2.54, 'mm' => 72 / 25.4, '' => 0.75 }.freeze

      def length_in_points(value, reference)
        match = value.to_s.strip.match(/\A(\d+(?:\.\d+)?)\s*(%|pt|px|in|cm|mm)?\z/)
        return unless match

        number = match[1].to_f
        match[2] == '%' ? reference * number / 100 : number * UNITS.fetch(match[2].to_s)
      end

      #========== INLINES =====================================

      def inlines(children, p, fmt)
        previous = nil
        children.each do |el|
          # a line break's newline belongs to the break
          el = Kramdown::Element.new(:text, el.value.delete_prefix("\n")) if previous&.type == :br and el.type == :text
          inline(el, p, fmt)
          previous = el
        end
      end

      def inline(el, p, fmt)
        if (name = el.attr['custom-style'])
          fmt = fmt.merge(style: custom_style(name, :character))
        end

        case el.type
        when :text            then text_with_references(p, el.value.tr("\n", ' '), fmt)
        when :strong          then inlines(el.children, p, fmt.merge(bold: true))
        when :em              then inlines(el.children, p, fmt.merge(italic: true))
        when :codespan        then text(p, el.value, fmt.merge(style: 'VerbatimChar'))
        when :a               then link(el, p, fmt)
        when :br              then p.br
        when :smart_quote     then text(p, smart_quote(el.value), fmt)
        when :typographic_sym then text(p, TYPOGRAPHIC.fetch(el.value, ''), fmt)
        when :entity          then text(p, el.value.char, fmt)
        when :footnote        then footnote_reference(el, p, fmt)
        when :html_element    then inline_html(el, p, fmt)
        when :img             then text(p, el.attr['alt'].to_s, fmt.merge(italic: true))
        when :math            then text(p, el.value, fmt.merge(style: 'VerbatimChar'))
        when :abbreviation    then text(p, el.value, fmt)
        when :xml_comment, :comment, :raw then nil
        else inlines(el.children, p, fmt)
        end
      end

      def text(p, content, fmt)
        p.text content, fmt.dup unless content.empty?
      end

      def inline_html(el, p, fmt)
        case el.value
        when 'br' then p.br
        when 'input'
          checked = el.attr.key?('checked')
          text(p, checked ? "☒ " : "☐ ", fmt) if el.attr['type'] == 'checkbox'
        when 'a'
          link(el, p, fmt)
        when 'span'
          inlines(el.children, p, fmt)
        else
          inlines(el.children, p, fmt.merge(INLINE_HTML.fetch(el.value, {})))
        end
      end

      def link(el, p, fmt)
        href    = el.attr['href'].to_s.strip
        content = plain_text(el)
        # [](#id) shows the target's label and number, or its heading text
        if @captions and content.empty? and href.start_with?('#') and href.length > 1
          return reference(p, href[1..], fmt, source: href)
        end

        target = link_target(href)
        return link_text(el, p, fmt, href) unless target

        content = target if content.empty?
        options = fmt.merge(link_format(el)).merge(style: 'Hyperlink')

        if target.start_with?('#') and target.length > 1
          p.link content, bookmark_name(target[1..]), options.merge(internal: true)
        elsif safe_link?(target)
          p.link content, target, options
        else
          warn "link to #{target.inspect} is rendered as text"
          link_text(el, p, fmt, target)
        end
      end

      # The target the link option gives +href+, or nil for the link's text
      # alone; +href+ itself without the option.
      def link_target(href)
        return href unless @options[:link]

        target = @options[:link].call(href.dup.freeze)
        (target.to_s.strip if target)
      end

      # A link's content without the hyperlink, or +href+ when it has none.
      def link_text(el, p, fmt, href)
        plain_text(el).empty? ? text(p, href, fmt) : inlines(el.children, p, fmt)
      end

      # Formatting a link's content applies to all of it.
      def link_format(el)
        kids = el.children
        return {} unless kids.size == 1

        case kids.first.type
        when :strong   then { bold: true }.merge(link_format(kids.first))
        when :em       then { italic: true }.merge(link_format(kids.first))
        when :codespan then { font: Styles::MONO_FONT }
        else {}
        end
      end

      def safe_link?(href)
        scheme = href[/\A([a-z][a-z0-9+.-]*):/i, 1]
        scheme.nil? ? !href.empty? : LINK_SCHEMES.include?(scheme.downcase)
      end

      def smart_quote(kind)
        entity = @smart_quotes[SMART_QUOTE_INDEX.fetch(kind)]
        Kramdown::Utils::Entities.entity(entity.to_s).char
      rescue StandardError
        { lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”' }.fetch(kind, '"')
      end

      #========== FOOTNOTES ===================================

      def footnote_reference(el, p, fmt)
        number = @footnotes.size + 1
        @footnotes << [number, el.value]
        if @options[:footnotes] == :native
          p.text Converter.marker('fn', number), style: 'FootnoteReference'
        else
          p.text number.to_s, fmt.merge(vertical_align: :superscript)
        end
      end

      def footnote_section(target)
        return if @footnotes.empty?

        target.hr unless @options[:footnotes] == :native
        @footnotes.each do |number, definition|
          if @options[:footnotes] == :native
            target.p Converter.marker('fn-start', number), style: 'FootnoteText'
            blocks(definition&.children || [], target, { style: 'FootnoteText', list_style: 'FootnoteText' })
            target.p Converter.marker('fn-end', number), style: 'FootnoteText'
          else
            first, *rest = (definition&.children || []).reject { |c| c.type == :blank }
            target.p(style: 'FootnoteText') do |p|
              p.text number.to_s, vertical_align: :superscript
              p.text ' '
              inlines(strip_whitespace(first.children), p, {}) if first&.type == :p
            end
            rest.unshift(first) if first and first.type != :p
            blocks(rest, target, { style: 'FootnoteText' })
          end
        end
      end

      #========== TITLE BLOCK, TOC, DIRECTIVES ================

      def title_block(meta, target)
        { 'title' => 'Title', 'subtitle' => 'Subtitle' }.each do |key, style|
          inline_markdown(meta[key], target, style) if meta[key]
        end
        Array(meta['author']).each { |author| inline_markdown(author, target, 'Author') }
        inline_markdown(meta['date'], target, 'Date') if meta['date']
        return unless meta['abstract']

        blocks(parse(meta['abstract'].to_s).children, target, { style: 'Abstract' })
      end

      def inline_markdown(value, target, style)
        first = parse(value.to_s).children.find { |el| el.type == :p }
        first ? emit_paragraph(target, first.children, style: style) : target.p(value.to_s, style: style)
      end

      def toc(target)
        return warn('a table of contents fits in the document body only') unless target.respond_to?(:toc)

        lang  = @options[:lang].to_s[0, 2]
        title = @options[:toc_title] || TOC_TITLES.fetch(lang, TOC_TITLES['en'])
        target.toc legend: title, start_level: 1, end_level: @options[:toc_depth].to_i.clamp(1, 6)
      end

      def directive(kind, target)
        case kind
        when :toc then toc(target)
        when :pagebreak
          target.respond_to?(:page) ? target.page : warn('page breaks fit in the document body only')
        when :lof then list_of_captions(:figure, target)
        when :lot then list_of_captions(:table, target)
        end
      end

      DIRECTIVE_TEXT = {
        '\\newpage' => :pagebreak, '\\pagebreak' => :pagebreak,
        '[TOC]' => :toc, '[[_TOC_]]' => :toc, '[[TOC]]' => :toc, '${toc}' => :toc,
        '\\listoffigures' => :lof, '\\listoftables' => :lot,
      }.freeze

      def paragraph_directive(el)
        return unless el.children.size == 1 and el.children.first.type == :text

        DIRECTIVE_TEXT[el.children.first.value.strip]
      end

      def comment_directive(value)
        case value.to_s.sub(/\A<!--/, '').sub(/-->\z/, '').strip.downcase
        when 'pagebreak', 'newpage', 'page-break', 'new-page' then :pagebreak
        when 'toc', 'table-of-contents' then :toc
        when 'lof', 'list-of-figures' then :lof
        when 'lot', 'list-of-tables' then :lot
        end
      end

      def toc_ial?(el)
        Array(el.options.dig(:ial, :refs)).include?('toc')
      end

      def contains_directive?(el, kind)
        return true if el.type == :p and paragraph_directive(el) == kind
        return true if el.type == :xml_comment and comment_directive(el.value) == kind
        return true if kind == :toc and %i[ul ol].include?(el.type) and toc_ial?(el)

        el.children.any? { |child| contains_directive?(child, kind) }
      end

      #========== HELPERS =====================================

      def paragraph_style(el, default)
        name = el.attr['custom-style']
        name ? custom_style(name, :paragraph) : default
      end

      def custom_style(name, type)
        id = name.to_s.gsub(/[^A-Za-z0-9]/, '')
        id = "Custom#{name.to_s.unpack1('H*')[0, 8]}" if id.empty?
        @custom_styles[id] ||= { name: name.to_s, type: type }
        id
      end

      # Word bookmark names start with a letter, hold letters, digits and
      # underscores, and are at most 40 characters long.
      def bookmark_name(id)
        @bookmarks[id] ||= begin
          name = id.gsub(/[^A-Za-z0-9_]/, '_')
          name = "h_#{name}" unless name.match?(/\A[A-Za-z]/)
          name = name[0, 36]
          taken = @bookmarks.values
          candidate = name
          candidate = "#{name[0, 33]}_#{taken.size}" if taken.include?(candidate)
          candidate
        end
      end

      def strip_whitespace(children)
        children = children.dup
        children.shift while children.first and whitespace?(children.first)
        children.pop while children.last and whitespace?(children.last)
        if children.first&.type == :text
          children[0] = Kramdown::Element.new(:text, children.first.value.lstrip)
        end
        if children.last&.type == :text
          children[-1] = Kramdown::Element.new(:text, children.last.value.rstrip)
        end
        children
      end

      def whitespace?(el)
        (el.type == :text and el.value.strip.empty?) or el.type == :xml_comment
      end

      def block_element?(el)
        %i[p header blockquote codeblock ul ol dl table hr math].include?(el.type) or
          (el.type == :html_element and el.options[:category] == :block)
      end

      def plain_text(el)
        case el.type
        when :text, :codespan, :math, :abbreviation then el.value.to_s
        when :smart_quote     then smart_quote(el.value)
        when :typographic_sym then TYPOGRAPHIC.fetch(el.value, '')
        when :entity          then el.value.char
        when :img             then el.attr['alt'].to_s
        when :br              then "\n"
        when :footnote, :xml_comment, :comment then ''
        else el.children.map { |child| plain_text(child) }.join
        end
      end

      def expand_tabs(text, width = 4)
        text.gsub(/([^\n]*?)\t/) { |_| "#{Regexp.last_match(1)}#{' ' * (width - Regexp.last_match(1).length % width)}" }
      end
    end
  end
end
