module Caracal
  module Md
    # Turns the converter's markers into OOXML caracal has no command for:
    #
    # * fn:N runs become footnote references, and the paragraphs between
    #   fn-start:N and fn-end:N move into word/footnotes.xml;
    # * an ol-start:N run sets the start number of its list.
    class PostProcessor
      NS = Package::NS
      W  = NS['w']

      FOOTNOTES_XML = <<~XML.freeze
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="#{W}" xmlns:r="#{NS['r']}">
          <w:footnote w:type="separator" w:id="-1"><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:separator/></w:r></w:p></w:footnote>
          <w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
        </w:footnotes>
      XML

      def initialize(package)
        @package = package
        @main    = package.main_part
        @doc     = package.xml(@main)
      end

      def apply
        markers = collect_markers
        list_starts(markers['ol-start'] || [])
        footnotes(markers) if markers['fn-start']
        @package
      end

      private

      # { kind => [[number, w:t node]] } for every text node that is a marker.
      def collect_markers
        @doc.xpath('//w:t', NS).each_with_object({}) do |t, markers|
          match = Converter::MARKER.match(t.content)
          next unless match and match[0] == t.content

          (markers[match[1]] ||= []) << [match[2].to_i, t]
        end
      end

      def list_starts(markers)
        markers.each do |start, t|
          run       = t.parent
          paragraph = paragraph_of(run)
          run.remove
          num_id = paragraph&.at_xpath('w:pPr/w:numPr/w:numId/@w:val', NS)&.value
          next unless num_id

          numbering = @package.related_part(@main, :numbering) or next
          num = @package.xml(numbering).at_xpath("/w:numbering/w:num[@w:numId='#{num_id}']", NS) or next
          num.add_child %(<w:lvlOverride w:ilvl="0"><w:startOverride w:val="#{start}"/></w:lvlOverride>)
        end
      end

      def footnotes(markers)
        part    = footnotes_part
        fn_doc  = @package.xml(part)
        next_id = [fn_doc.xpath('//w:footnote/@w:id', NS).map { |a| a.value.to_i }.max.to_i, 0].max + 1
        ref_style = @package.style_id_by_name('footnote reference') || 'FootnoteReference'
        ends   = (markers['fn-end'] || []).to_h { |number, t| [number, paragraph_of(t)] }
        ids    = {}

        markers['fn-start'].each do |number, t|
          start_p = paragraph_of(t)
          end_p   = ends[number]
          nodes   = []
          node    = start_p.next_element
          while node and not node.equal?(end_p)
            nodes << node
            node = node.next_element
          end

          id = ids[number] = next_id
          next_id += 1
          move_relationships(nodes, part)

          footnote = fn_doc.root.add_child(%(<w:footnote w:id="#{id}"/>)).first
          footnote.add_child footnote.parse(nodes.map(&:to_xml).join) unless nodes.empty?
          first_p = footnote.at_xpath('w:p', NS) || footnote.add_child('<w:p/>').first
          ref = %(<w:r><w:rPr><w:rStyle w:val="#{ref_style}"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> </w:t></w:r>)
          (ppr = first_p.at_xpath('w:pPr', NS)) ? ppr.add_next_sibling(ref) : first_p.prepend_child(ref)

          ([start_p, end_p] + nodes).compact.each(&:remove)
        end

        (markers['fn'] || []).each do |number, t|
          id = ids[number]
          id ? t.replace(%(<w:footnoteReference w:id="#{id}"/>)) : t.parent.remove
        end
      end

      def footnotes_part
        existing = @package.related_part(@main, :footnotes)
        return existing if existing

        part = 'word/footnotes.xml'
        @package[part] = FOOTNOTES_XML
        @package.add_relationship(@main, Package::REL_TYPES[:footnotes], 'footnotes.xml')
        @package.set_override(part, Package::CONTENT_TYPES[:footnotes])

        settings = @package.related_part(@main, :settings)
        if settings
          Settings.ensure(@package.xml(settings), 'footnotePr',
                          '<w:footnotePr><w:footnote w:id="-1"/><w:footnote w:id="0"/></w:footnotePr>')
        end
        part
      end

      # Hyperlinks and images in moved content need relationships from the
      # footnotes part.
      def move_relationships(nodes, part)
        map = {}
        nodes.each do |node|
          node.xpath('.//@r:id | .//@r:embed | .//@r:link', NS).each do |attr|
            map[attr.value] ||= begin
              rel = @package.relationship(@main, attr.value)
              if rel
                target = rel[:mode] == 'External' ? rel[:target] : relative_target(@package.resolve(@main, rel[:target]), part)
                @package.add_relationship(part, rel[:type], target, mode: rel[:mode])
              end
            end
            attr.value = map[attr.value] if map[attr.value]
          end
        end
      end

      def paragraph_of(node)
        node.ancestors.find { |a| a.name == 'p' and a.namespace&.href == W }
      end

      def relative_target(path, part)
        dir = File.dirname(part)
        path.start_with?("#{dir}/") ? path.delete_prefix("#{dir}/") : "/#{path}"
      end
    end
  end
end
