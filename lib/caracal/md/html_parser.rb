require 'kramdown'
require 'nokogiri'

module Caracal
  module Md
    # Reads HTML, such as rich text from web editors (Trix, Tiptap) and CMS
    # fields, into the kramdown element tree Converter walks for Markdown.
    #
    # Nokogiri's HTML5 parser builds the DOM, so text and attributes arrive
    # with entities decoded, and broken markup is repaired as a browser
    # repairs it. Elements with a Markdown counterpart become that element;
    # div and the other generic containers pass their blocks on; other
    # elements keep their content; script, style and template contents are
    # dropped, as is everything in head.
    #
    # Text directly inside a container becomes paragraphs, split where two
    # line breaks follow each other (Trix writes paragraphs so). Table cells
    # hold their blocks as lines; a figure with one image or table and a
    # figcaption becomes a captioned image or table.
    #
    # The marker characters (see Converter) become U+FFFD in text and
    # attributes, as entities for them do in Markdown, so HTML spells no
    # markers.
    class HtmlParser
      E = Kramdown::Element

      MAX_DEPTH = 256

      DROPPED    = %w[script style template].freeze
      CONTAINERS = %w[body div section article main header footer nav aside address center hgroup fieldset form figcaption li dd].freeze
      EMPHASIS   = { 'em' => :em, 'i' => :em, 'strong' => :strong, 'b' => :strong }.freeze
      SPAN_HTML  = (Converter::INLINE_HTML.keys - EMPHASIS.keys - %w[code]).freeze
      BLOCK_TYPES = %i[p header blockquote ul ol dl table hr codeblock].freeze
      ALIGNMENTS = %w[left center right].freeze
      WHITESPACE = /[ \t\n\r\f]+/
      MARKERS    = "#{Converter::MARKER_OPEN}#{Converter::MARKER_CLOSE}".freeze
      REPLACED   = "\u{FFFD}\u{FFFD}".freeze

      def self.parse(html)
        new.parse(html)
      end

      # The root element of +html+, a fragment or a whole document.
      def parse(html)
        doc = begin
          Nokogiri::HTML5.parse(html.to_s, max_tree_depth: MAX_DEPTH)
        rescue ArgumentError => e
          raise Error, "HTML not read: #{e.message}"
        end
        root = E.new(:root, nil, nil, encoding: Encoding::UTF_8)
        body = doc.at_css('body')
        root.children.concat(blocks(items(body))) if body
        root
      end

      private

      #========== NODES =======================================

      # The elements for the children of +node+: blocks and inline elements
      # in document order.
      def items(node)
        node.children.flat_map { |child| item(child) }
      end

      def item(node)
        case node
        when Nokogiri::XML::Text    then [E.new(:text, clean(node.content).gsub(WHITESPACE, ' '))]
        when Nokogiri::XML::Comment then [E.new(:xml_comment, "<!--#{node.content}-->", nil, category: :block)]
        when Nokogiri::XML::Element then element(node)
        else []
        end
      end

      def element(node)
        name = node.name.downcase
        case name
        when *DROPPED            then []
        when 'p'                 then paragraph(node)
        when /\Ah[1-6]\z/        then [with(E.new(:header, nil, attrs(node, 'id'), level: name[1].to_i), trim(items(node)))]
        when 'blockquote'        then [with(E.new(:blockquote), blocks(items(node)))]
        when 'ul', 'ol'          then [list(node)].compact
        when 'dl'                then [definition_list(node)]
        when 'pre'               then [code_block(node)]
        when 'table'             then [table(node)]
        when 'hr'                then [E.new(:hr)]
        when 'figure'            then figure(node)
        when 'details'           then [with(E.new(:html_element, 'details', nil, category: :block), blocks(items(node)))]
        when 'summary'           then [with(E.new(:html_element, 'summary', nil, category: :block), trim(items(node)))]
        when *CONTAINERS         then blocks(items(node))
        when 'br'                then [E.new(:br)]
        when 'img'               then [image(node)]
        when 'a'                 then node['href'] ? [with(E.new(:a, nil, attrs(node, 'href', 'title')), items(node))] : items(node)
        when 'code'              then [E.new(:codespan, clean(node.text).gsub(WHITESPACE, ' '))]
        when *EMPHASIS.keys      then [with(E.new(EMPHASIS[name]), items(node))]
        when *SPAN_HTML          then [with(E.new(:html_element, name, nil, category: :span), items(node))]
        when 'input'             then checkbox(node)
        else items(node)
        end
      end

      # A paragraph holds inline content; blocks inside one (from elements
      # HTML lets in, such as a custom element) end it.
      def paragraph(node)
        blocks(items(node), split: false).each_with_index.map do |block, index|
          block.attr['id'] = node['id'] if index.zero? and node['id'] and block.type == :p
          block
        end
      end

      def image(node)
        E.new(:img, nil, attrs(node, 'src', 'alt', 'title', 'width', 'height', 'id'))
      end

      def checkbox(node)
        return [] unless node['type'].to_s.casecmp?('checkbox')

        attr = { 'type' => 'checkbox' }
        attr['checked'] = 'checked' if node.has_attribute?('checked')
        [E.new(:html_element, 'input', attr, category: :span)]
      end

      #========== BLOCKS ======================================

      # Wraps the inline runs among +items+ into paragraphs, with +split+ at
      # two line breaks in a row.
      def blocks(items, split: true)
        result = []
        run = []
        items.each do |item|
          if block?(item)
            result.concat(paragraphs(run, split))
            run = []
            result << item
          else
            run << item
          end
        end
        result.concat(paragraphs(run, split))
      end

      def block?(el)
        BLOCK_TYPES.include?(el.type) or (el.type == :html_element and el.options[:category] == :block)
      end

      def paragraphs(run, split)
        groups = split ? split_run(run) : [run]
        groups.filter_map do |group|
          children = trim(group)
          with(E.new(:p), children) unless children.empty?
        end
      end

      # Splits a run where two or more line breaks follow each other, with
      # nothing but whitespace between them.
      def split_run(run)
        groups  = [[]]
        pending = []
        run.each do |item|
          if item.type == :br or whitespace?(item)
            pending << item
          else
            pending.count { |el| el.type == :br } >= 2 ? groups << [] : groups.last.concat(pending)
            pending = []
            groups.last << item
          end
        end
        groups.last.concat(pending)
        groups
      end

      # Inline children without whitespace or line breaks at either end, or
      # whitespace next to a line break.
      def trim(children)
        children = children.dup
        children.shift while children.first and (children.first.type == :br or whitespace?(children.first))
        children.pop while children.last and (children.last.type == :br or whitespace?(children.last))
        children.each_with_index.filter_map do |el, index|
          next el unless el.type == :text

          value = el.value
          value = value.lstrip if index.zero? or children[index - 1].type == :br
          value = value.rstrip if index == children.size - 1 or children[index + 1]&.type == :br
          E.new(:text, value) unless value.empty?
        end
      end

      def whitespace?(el)
        el.type == :text and el.value.strip.empty?
      end

      #========== LISTS =======================================

      # A list of li elements. Other content, such as a list nested without
      # its li, joins the item before it. A list without items is no list:
      # caracal refuses one.
      def list(node)
        list = E.new(node.name.downcase.to_sym)
        list.attr['start'] = node['start'] if list.type == :ol and node['start']
        node.children.each do |child|
          if child.element? and child.name.casecmp?('li')
            list.children << list_item(child)
          else
            content = blocks(item(child))
            next if content.empty?

            list.children << E.new(:li) if list.children.empty?
            list.children.last.children.concat(content)
          end
        end
        list unless list.children.empty?
      end

      # An item's blocks; a task's checkbox, in a paragraph of its own as
      # Tiptap writes it, joins the paragraph after it.
      def list_item(node)
        children = blocks(items(node))
        first, second = children
        if first&.type == :p and second&.type == :p and first.children.all? { |el| (el.type == :html_element and el.value == 'input') or whitespace?(el) }
          second.children.unshift(*first.children.reject { |el| whitespace?(el) })
          children.shift
        end
        with(E.new(:li), children)
      end

      def definition_list(node)
        list = E.new(:dl)
        node.xpath('./*[local-name()="dt" or local-name()="dd"] | ./div/*[local-name()="dt" or local-name()="dd"]').each do |entry|
          list.children << if entry.name.casecmp?('dt')
            with(E.new(:dt), trim(items(entry)))
          else
            with(E.new(:dd), blocks(items(entry)))
          end
        end
        list
      end

      #========== CODE ========================================

      # A pre, with the language from a language-x class on it or on its
      # code element, and the other attributes for code handlers.
      def code_block(node)
        code = node.element_children.first if node.element_children.size == 1 and node.element_children.first.name.casecmp?('code')
        attr = [code, node].compact.inject({}) { |all, el| all.merge(el.attributes.transform_values { |a| clean(a.value) }) }
        language = [node, code].compact.filter_map { |el| el['class'].to_s[/\blanguage-(\S+)/, 1] }.first
        attr.delete('class')
        attr['class'] = "language-#{language}" if language
        E.new(:codeblock, clean(node.text), attr)
      end

      #========== TABLES ======================================

      # A table with a header row from thead, else from leading rows of th
      # cells. Cells hold their blocks as lines; colspan adds empty cells;
      # rows without cells are left out.
      def table(node)
        rows  = node.xpath('./*[local-name()="thead" or local-name()="tbody" or local-name()="tfoot"]/*[local-name()="tr"] | ./*[local-name()="tr"]')
        rows  = rows.select { |tr| cells(tr).any? }
        heads = rows.take_while { |tr| tr.parent.name.casecmp?('thead') }
        heads = rows.take_while { |tr| cells(tr).any? and cells(tr).all? { |cell| cell.name.casecmp?('th') } } if heads.empty?

        table = E.new(:table, nil, attrs(node, 'id'), alignment: alignment(rows.first))
        thead = E.new(:thead)
        tbody = E.new(:tbody)
        rows.each_with_index do |tr, index|
          header = index < heads.size
          (header ? thead : tbody).children << row(tr, header)
        end
        table.children << thead unless thead.children.empty?
        table.children << tbody
        caption = node.at_xpath('./*[local-name()="caption"]')
        table.options[:caption] = squish(caption.text) if caption
        table
      end

      def cells(tr)
        tr.element_children.select { |cell| %w[td th].include?(cell.name.downcase) }
      end

      def row(tr, header)
        row = E.new(:tr)
        cells(tr).each do |cell|
          content = cell_content(cell)
          content = [with(E.new(:strong), content)] if cell.name.casecmp?('th') and not header and content.any?
          row.children << with(E.new(:td), content)
          (span(cell) - 1).times { row.children << E.new(:td) }
        end
        row
      end

      def span(cell)
        cell['colspan'].to_s[/\A\d+\z/].to_i.clamp(1, 100)
      end

      def alignment(tr)
        return [] unless tr

        cells(tr).flat_map do |cell|
          align = cell['style'].to_s[/text-align\s*:\s*(\w+)/i, 1] || cell['align']
          align = align.to_s.downcase
          [ALIGNMENTS.include?(align) ? align.to_sym : :default] * span(cell)
        end
      end

      # A cell's content as inline elements, its blocks one per line.
      def cell_content(cell)
        blocks(items(cell)).each_with_index.flat_map do |block, index|
          (index.zero? ? [] : [E.new(:br)]) + inline(block)
        end
      end

      def inline(block)
        case block.type
        when :p, :header, :dt then block.children
        when :hr then []
        when :codeblock
          block.value.to_s.chomp.split("\n", -1).each_with_index.flat_map do |line, index|
            (index.zero? ? [] : [E.new(:br)]) + [E.new(:codespan, line)]
          end
        else
          block.children.each_with_index.flat_map do |child, index|
            lines = (block?(child) or %i[li dd dt thead tbody tr td].include?(child.type)) ? inline(child) : [child]
            (index.zero? ? [] : [E.new(:br)]) + lines
          end
        end
      end

      #========== FIGURES =====================================

      # One image, or one table, with a figcaption becomes the image with
      # the caption as its title, or the table with its caption; the
      # figure's id goes to either. Other figures keep their content.
      def figure(node)
        caption = node.at_xpath('.//*[local-name()="figcaption"]')
        text = caption && squish(caption.text)
        outside = node.xpath('.//text()[not(ancestor::*[local-name()="figcaption"])]').map(&:content).join.strip
        images = node.xpath('.//*[local-name()="img"][not(ancestor::*[local-name()="figcaption"])]')
        tables = node.xpath('.//*[local-name()="table"]')

        if images.size == 1 and tables.empty? and outside.empty?
          img = image(images.first)
          img.attr['title'] = text if text and not text.empty?
          img.attr['id'] ||= node['id'] if node['id']
          [with(E.new(:p), [img])]
        elsif tables.size == 1 and images.empty? and text and not text.empty? and
              outside == tables.first.xpath('.//text()').map(&:content).join.strip
          table = table(tables.first)
          table.options[:caption] = text
          table.attr['id'] ||= node['id'] if node['id']
          [table]
        else
          blocks(items(node))
        end
      end

      #========== HELPERS =====================================

      def with(element, children)
        element.children.concat(children)
        element
      end

      def attrs(node, *names)
        names.each_with_object({}) { |name, attr| attr[name] = clean(node[name]) if node[name] }
      end

      def squish(text)
        clean(text).gsub(WHITESPACE, ' ').strip
      end

      def clean(text)
        text.tr(MARKERS, REPLACED)
      end
    end
  end
end
