require 'time'

module Caracal
  module Md
    # Writes front matter into docProps/core.xml: title, author, subject,
    # keywords, description, language and the creation time.
    module CoreProperties
      NS = Package::NS

      FIELDS = {
        'title'       => 'dc:title',
        'author'      => 'dc:creator',
        'subject'     => 'dc:subject',
        'description' => 'dc:description',
        'keywords'    => 'cp:keywords',
        'lang'        => 'dc:language',
      }.freeze

      def self.apply(package, meta, time: Time.now.utc)
        rel = package.relationships('').find { |r| r[:type] == Package::REL_TYPES[:core_properties] }
        return unless rel

        part = package.resolve('', rel[:target])
        return unless package.include?(part)

        doc  = package.xml(part)
        root = doc.root
        %w[cp dc dcterms xsi].each do |prefix|
          root.add_namespace_definition(prefix, NS[prefix]) unless root.namespace_definitions.any? { |d| d.prefix == prefix }
        end

        vars = FrontMatter.to_variables(meta)
        FIELDS.each do |key, qname|
          next if (value = vars[key]).nil?

          set(root, qname, value)
        end
        set(root, 'dc:title', '') if vars['title'].nil? and root.at_xpath('dc:title', NS)&.content.to_s.end_with?('.docx')

        stamp = time.iso8601
        %w[dcterms:created dcterms:modified].each do |qname|
          node = set(root, qname, stamp)
          node['xsi:type'] = 'dcterms:W3CDTF'
        end
      end

      def self.set(root, qname, value)
        node = root.at_xpath(qname, NS) || root.add_child("<#{qname}/>").first
        node.content = value.to_s
        node
      end
    end
  end
end
