module Caracal
  module Md
    # Turns the converter's caption markers into Word fields, each with its
    # result filled in, so Word shows the numbers without updating fields:
    #
    # * caption-figure / caption-table become SEQ fields numbered in document
    #   order; in chapter mode "C.N", N restarting at each level-1 heading,
    #   which gets a hidden SEQ Chapter field;
    # * ref:N becomes a REF field showing the bookmarked text;
    # * list-figure / list-table paragraphs become a TOC \c field listing the
    #   captions, page numbers filled in by Word on open.
    class CaptionFields
      NS = Package::NS
      W  = NS['w']

      # Hidden text, for the chapter field LibreOffice would show despite \h.
      HIDDEN = '<w:rPr><w:vanish/></w:rPr>'.freeze

      def initialize(package, captions, markers)
        @package  = package
        @captions = captions
        @markers  = markers
        @main     = package.main_part
        @doc      = package.xml(@main)
        @numbered = Hash.new { |hash, kind| hash[kind] = [] } # kind => caption paragraphs
      end

      # +markers+: { kind => [[number, w:t node]] }, as PostProcessor collects them.
      def apply(markers)
        number_captions(markers)
        references(markers['ref'] || [])
        Captions::KINDS.each do |kind|
          (markers["list-#{kind}"] || []).each { |_, t| list(kind, paragraph_of(t)) }
        end
      end

      private

      #========== NUMBERS =====================================

      def number_captions(markers)
        captions = {}.compare_by_identity
        Captions::KINDS.each do |kind|
          (markers["caption-#{kind}"] || []).each { |_, t| captions[paragraph_of(t)] = [kind, t] }
        end
        return if captions.empty?

        heading = (@package.style_id_by_name('heading 1') if @captions.chapters?)
        chapter = 0
        counts  = Hash.new(0)
        @doc.xpath('/w:document/w:body//w:p', NS).each do |p|
          if heading and p.at_xpath('w:pPr/w:pStyle/@w:val', NS)&.value == heading
            chapter += 1
            counts.clear
            insert_after_properties(p, field(" SEQ #{Captions::CHAPTER_SEQUENCE} \\h ", nil, HIDDEN))
          end
          kind, t = captions[p]
          next unless kind

          counts[kind] += 1
          number(t.parent, kind, chapter, counts[kind])
          @numbered[kind] << p
          describe_table(p) if kind == :table
        end
      end

      # In chapter mode the first caption of a chapter also resets its
      # sequence with \r 1, for LibreOffice, which ignores \s.
      def number(run, kind, chapter, count)
        rpr = run.at_xpath('w:rPr', NS)&.to_xml.to_s
        sequence = @captions.sequence(kind)
        xml = if @captions.chapters?
                reset = count == 1 ? '\\r 1 ' : ''
                field(" SEQ #{Captions::CHAPTER_SEQUENCE} \\c ", chapter, rpr) + text_run('.', rpr) +
                  field(" SEQ #{sequence} \\* ARABIC #{reset}\\s 1 ", count, rpr)
              else
                field(" SEQ #{sequence} \\* ARABIC ", count, rpr)
              end
        run.replace(xml)
      end

      # The caption, as caracal gives it, describes the table that follows.
      def describe_table(p)
        table = p.next_element
        return unless table and table.name == 'tbl' and table.namespace&.href == W

        properties = table.at_xpath('w:tblPr', NS)
        return if properties.nil? or properties.at_xpath('w:tblCaption', NS)

        properties.add_child('<w:tblCaption/>').first['w:val'] = text_of(p)
      end

      #========== REFERENCES ==================================

      def references(markers)
        return if markers.empty?

        texts = bookmark_texts
        markers.each do |index, t|
          reference = @captions.references[index]
          run  = t.parent
          text = texts[reference[:bookmark]]
          if text.to_s.empty?
            t.content = reference[:source]
          else
            rpr = run.at_xpath('w:rPr', NS)&.to_xml.to_s
            run.replace(field(" REF #{reference[:bookmark]} \\h \\* CHARFORMAT ", text, rpr))
          end
        end
      end

      # { bookmark name => text between its start and end }.
      def bookmark_texts
        texts = {}
        open  = {}
        @doc.xpath('//w:bookmarkStart | //w:bookmarkEnd | //w:t', NS).each do |node|
          case node.name
          when 'bookmarkStart'
            open[node['w:id']] = node['w:name']
            texts[node['w:name']] = +''
          when 'bookmarkEnd'
            open.delete(node['w:id'])
          else
            open.each_value { |name| texts[name] << node.content }
          end
        end
        texts.transform_values { |text| text.gsub(@markers.pattern, '').strip }
      end

      #========== LISTS =======================================

      def list(kind, placeholder)
        return unless placeholder

        style = placeholder.at_xpath('w:pPr/w:pStyle/@w:val', NS)&.value || 'TableofFigures'
        start = field_start(%( TOC \\h \\z \\c "#{@captions.sequence(kind)}" ))
        entries = @numbered[kind].map do |p|
          name = p.at_xpath('w:bookmarkStart/@w:name', NS)&.value
          [name, text_of(p)] if name
        end.compact

        xml = entries.each_with_index.map do |(name, text), index|
          %(<w:p><w:pPr><w:pStyle w:val="#{style}"/><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="#{text_width}"/></w:tabs></w:pPr>) +
            (index.zero? ? start : '') +
            %(<w:hyperlink w:anchor="#{name}" w:history="1">#{text_run(text, '')}<w:r><w:tab/></w:r>) +
            field(" PAGEREF #{name} \\h ", '#', '') + '</w:hyperlink></w:p>'
        end.join
        xml += %(<w:p>#{entries.empty? ? start : ''}<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>)

        placeholder.add_previous_sibling(xml)
        placeholder.remove
        settings = @package.related_part(@main, :settings)
        Settings.ensure(@package.xml(settings), 'updateFields', '<w:updateFields w:val="true"/>') if settings
      end

      # The width between the margins of the body's last section.
      def text_width
        section = @doc.xpath('/w:document/w:body/w:sectPr', NS).last
        width   = section&.at_xpath('w:pgSz/@w:w', NS)&.value.to_i
        margins = %w[left right].sum { |side| section&.at_xpath("w:pgMar/@w:#{side}", NS)&.value.to_i }
        width.to_i.positive? ? width - margins : 9026
      end

      #========== OOXML =======================================

      # A complex field: begin, instruction, separate, result, end.
      def field(instruction, result, rpr = '')
        field_start(instruction, rpr) +
          (result.to_s.empty? ? '' : text_run(result.to_s, rpr)) +
          %(<w:r>#{rpr}<w:fldChar w:fldCharType="end"/></w:r>)
      end

      def field_start(instruction, rpr = '')
        %(<w:r>#{rpr}<w:fldChar w:fldCharType="begin"/></w:r>) +
          %(<w:r>#{rpr}<w:instrText xml:space="preserve">#{instruction.encode(xml: :text)}</w:instrText></w:r>) +
          %(<w:r>#{rpr}<w:fldChar w:fldCharType="separate"/></w:r>)
      end

      def text_run(text, rpr)
        %(<w:r>#{rpr}<w:t xml:space="preserve">#{text.encode(xml: :text)}</w:t></w:r>)
      end

      def insert_after_properties(p, xml)
        properties = p.at_xpath('w:pPr', NS)
        properties ? properties.add_next_sibling(xml) : p.prepend_child(xml)
      end

      def text_of(p)
        p.xpath('.//w:t', NS).map(&:content).join
      end

      def paragraph_of(node)
        node.ancestors.find { |a| a.name == 'p' and a.namespace&.href == W }
      end
    end
  end
end
