module Caracal
  module Md
    # {{key}} placeholders in WordprocessingML. Word often splits typed text
    # across several runs, so matching works on each paragraph's whole text.
    module Placeholders
      PATTERN = /\{\{\s*([\w.-]+)\s*\}\}/
      NS = Package::NS

      # The text nodes of a paragraph's own runs, in order (text boxes nested
      # in the paragraph are paragraphs of their own).
      def self.text_nodes(paragraph)
        paragraph.xpath('./w:r/w:t | ./w:hyperlink/w:r/w:t | ./w:ins/w:r/w:t | ./w:smartTag/w:r/w:t | ' \
                        './w:fldSimple/w:r/w:t | ./w:sdt/w:sdtContent/w:r/w:t', NS)
      end

      def self.text(paragraph)
        text_nodes(paragraph).map(&:content).join
      end

      # The keys of all placeholders in +doc+.
      def self.keys(doc)
        doc.xpath('//w:p', NS).flat_map { |p| text(p).scan(PATTERN).flatten }.uniq
      end

      # The first paragraph whose whole text is +placeholder+.
      def self.find_paragraph(doc, placeholder)
        doc.xpath('//w:body//w:p', NS).find { |p| text(p).strip == placeholder }
      end

      # Replaces each {{key}} with values[key]; unknown keys stay.
      def self.replace(doc, values)
        return if values.empty?

        doc.xpath('//w:p', NS).each do |paragraph|
          nodes = text_nodes(paragraph).to_a
          full  = nodes.map(&:content).join
          next unless full.match?(PATTERN)

          matches = full.to_enum(:scan, PATTERN).map { Regexp.last_match }
          matches.reverse_each do |match|
            value = values[match[1]]
            next if value.nil?

            splice(nodes, match.begin(0), match.end(0), value.to_s)
          end
        end
      end

      # Replaces the characters [from, to) of the nodes' joint text.
      def self.splice(nodes, from, to, replacement)
        offset = 0
        first  = true
        nodes.each do |node|
          content = node.content
          node_start = offset
          node_end   = offset + content.length
          offset     = node_end
          next if node_end <= from or node_start >= to

          local_from = [from - node_start, 0].max
          local_to   = [to - node_start, content.length].min
          node.content = content[0...local_from] + (first ? replacement : '') + content[local_to..]
          node['xml:space'] = 'preserve'
          first = false
        end
      end
    end
  end
end
