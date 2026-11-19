require 'nokogiri'
require 'stringio'
require 'zip'

module Caracal
  module Md
    # An OPC package (.docx, .dotx) held in memory: its raw entries plus the
    # XML parts parsed so far. Parsed parts are written back on #to_s.
    #
    # A frozen package (see Template) keeps its entries as they are: it
    # writes, copies (#dup) and serializes them, and parses no parts.
    class Package
      NS = {
        'w'       => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        'r'       => 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
        'wp'      => 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
        'rel'     => 'http://schemas.openxmlformats.org/package/2006/relationships',
        'ct'      => 'http://schemas.openxmlformats.org/package/2006/content-types',
        'cp'      => 'http://schemas.openxmlformats.org/package/2006/metadata/core-properties',
        'dc'      => 'http://purl.org/dc/elements/1.1/',
        'dcterms' => 'http://purl.org/dc/terms/',
        'xsi'     => 'http://www.w3.org/2001/XMLSchema-instance',
      }.freeze

      OFFICE_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'.freeze
      REL_TYPES = {
        office_document: "#{OFFICE_REL}/officeDocument",
        core_properties: 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
        styles:          "#{OFFICE_REL}/styles",
        numbering:       "#{OFFICE_REL}/numbering",
        settings:        "#{OFFICE_REL}/settings",
        footnotes:       "#{OFFICE_REL}/footnotes",
        header:          "#{OFFICE_REL}/header",
        footer:          "#{OFFICE_REL}/footer",
        hyperlink:       "#{OFFICE_REL}/hyperlink",
        image:           "#{OFFICE_REL}/image",
        vba_project:     'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
      }.freeze

      WML = 'application/vnd.openxmlformats-officedocument.wordprocessingml'.freeze
      CONTENT_TYPES = {
        document:  "#{WML}.document.main+xml",
        numbering: "#{WML}.numbering+xml",
        footnotes: "#{WML}.footnotes+xml",
      }.freeze

      CONTENT_TYPES_PART = '[Content_Types].xml'.freeze

      class << self
        # Entries larger than this many bytes are refused when reading, so a
        # small crafted archive can't expand into a huge one in memory.
        attr_accessor :max_entry_size
      end
      self.max_entry_size = 50 * 1024 * 1024

      # Reads a package from a path (String or Pathname), an IO or a String
      # of bytes.
      def self.read(source)
        bytes = if defined?(Pathname) and source.is_a?(Pathname)
          File.binread(source)
        elsif source.respond_to?(:read)
          source.read
        elsif source.is_a?(String) and source.b.start_with?("PK\x03\x04".b)
          source
        else
          File.binread(source.to_s)
        end

        entries = {}
        zip = ::Zip::File.open_buffer(StringIO.new(bytes.b))
        zip.each do |entry|
          next if entry.name.end_with?('/')
          if entry.size.to_i > max_entry_size
            raise Error, "#{entry.name} is larger than #{max_entry_size} bytes"
          end
          data = entry.get_input_stream.read(max_entry_size + 1).to_s
          raise Error, "#{entry.name} is larger than #{max_entry_size} bytes" if data.bytesize > max_entry_size
          entries[entry.name] = data
        end
        new entries
      rescue ::Zip::Error => e
        raise Error, "not a Word package: #{e.message}"
      end

      def initialize(entries)
        @entries = entries
        @xml     = {}
      end

      def entry_names
        @entries.keys
      end

      def include?(name)
        @entries.key?(name)
      end

      def [](name)
        flush name
        @entries[name]
      end

      def []=(name, content)
        @xml.delete name
        @entries[name] = content
      end

      def delete(name)
        @xml.delete name
        @entries.delete name
      end

      # The parsed XML of a part; changes to it are kept.
      def xml(name)
        @xml.fetch(name) do
          raise FrozenError.new("#{name}: a frozen package parses no parts; parse them in a #dup", receiver: self) if frozen?

          content = @entries.fetch(name) { raise Error, "package has no part #{name}" }
          @xml[name] = Nokogiri::XML(content) { |config| config.strict.nonet }
        end
      end

      # A copy whose parts can change independently of this package. It
      # reads this package only, and shares the entries frozen ones.
      def dup
        entries = @entries.transform_values { |content| content.frozen? ? content : content.dup }
        @xml.each { |name, doc| entries[name] = serialize(doc) }
        Package.new entries
      end

      # Writes parsed parts back and freezes the entries; #xml raises
      # FrozenError from then on.
      def freeze
        return self if frozen?

        begin
          main_part
        rescue Error
          nil
        end
        flush
        @xml = {}.freeze
        @entries.each_value(&:freeze)
        @entries.freeze
        super
      end

      # The package as zip bytes.
      def to_s
        flush
        names = entry_names.sort_by { |name| name == CONTENT_TYPES_PART ? 0 : 1 }
        buffer = ::Zip::OutputStream.write_buffer do |zip|
          names.each do |name|
            content = @entries[name].to_s
            entry = ::Zip::Entry.new('', name)
            entry.size = content.bytesize
            zip.put_next_entry entry
            zip.write content
          end
        end
        buffer.string
      end

      #========== RELATIONSHIPS ===============================

      def main_part
        @main_part ||= begin
          rel = relationships('').find { |r| r[:type] == REL_TYPES[:office_document] }
          raise Error, 'package has no main document' unless rel
          rel[:target].delete_prefix('/')
        end
      end

      def rels_name(part)
        dir  = File.dirname(part)
        base = File.basename(part)
        dir == '.' || part.empty? ? "_rels/#{base}.rels" : "#{dir}/_rels/#{base}.rels"
      end

      def rels(part)
        name = rels_name(part)
        unless include?(name)
          self[name] = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n) +
            %(<Relationships xmlns="#{NS['rel']}"></Relationships>)
        end
        xml name
      end

      def relationships(part)
        name = rels_name(part)
        return [] unless include?(name)

        xml(name).xpath('/rel:Relationships/rel:Relationship', NS).map do |node|
          { id: node['Id'], type: node['Type'], target: node['Target'], mode: node['TargetMode'] }
        end
      end

      def relationship(part, id)
        relationships(part).find { |r| r[:id] == id }
      end

      def add_relationship(part, type, target, mode: nil)
        doc = rels(part)
        ids = doc.xpath('//rel:Relationship/@Id', NS).map(&:value)
        id  = "rIdMd#{ids.size + 1}"
        id  = id.succ while ids.include?(id)

        node = doc.create_element('Relationship', 'Id' => id, 'Type' => type, 'Target' => target)
        node['TargetMode'] = mode if mode
        doc.root.add_child node
        id
      end

      def remove_relationship(part, id)
        rels(part).xpath("//rel:Relationship[@Id='#{id}']", NS).each(&:remove)
      end

      # The package path of the first part related to +part+ by +type+.
      def related_part(part, type)
        type = REL_TYPES.fetch(type) if type.is_a?(Symbol)
        rel  = relationships(part).find { |r| r[:type] == type and r[:mode] != 'External' }
        resolve(part, rel[:target]) if rel
      end

      def related_parts(part, type)
        type = REL_TYPES.fetch(type) if type.is_a?(Symbol)
        relationships(part).select { |r| r[:type] == type and r[:mode] != 'External' }.map { |r| resolve(part, r[:target]) }
      end

      # The package path of a relationship target given relative to +part+.
      def resolve(part, target)
        return target.delete_prefix('/') if target.start_with?('/')

        dir = File.dirname(part)
        path = dir == '.' ? target : File.join(dir, target)
        segments = []
        path.split('/').each do |segment|
          case segment
          when '..' then segments.pop
          when '.', '' then next
          else segments << segment
          end
        end
        segments.join('/')
      end

      #========== CONTENT TYPES ===============================

      def content_types
        xml CONTENT_TYPES_PART
      end

      def override_content_type(part)
        node = content_types.at_xpath("/ct:Types/ct:Override[@PartName='/#{part}']", NS)
        node && node['ContentType']
      end

      def set_override(part, type)
        doc  = content_types
        node = doc.at_xpath("/ct:Types/ct:Override[@PartName='/#{part}']", NS)
        if node
          node['ContentType'] = type
        else
          doc.root.add_child doc.create_element('Override', 'PartName' => "/#{part}", 'ContentType' => type)
        end
      end

      def remove_override(part)
        content_types.xpath("/ct:Types/ct:Override[@PartName='/#{part}']", NS).each(&:remove)
      end

      def default_content_type(extension)
        node = content_types.xpath('/ct:Types/ct:Default', NS).find { |n| n['Extension'].to_s.casecmp?(extension) }
        node && node['ContentType']
      end

      def ensure_default(extension, type)
        return if default_content_type(extension)

        doc = content_types
        node = doc.create_element('Default', 'Extension' => extension, 'ContentType' => type)
        first_override = doc.at_xpath('/ct:Types/ct:Override', NS)
        first_override ? first_override.add_previous_sibling(node) : doc.root.add_child(node)
      end

      #========== STYLES ======================================

      # The style id named +name+ (case-insensitive), or nil.
      def style_id_by_name(name)
        part = related_part(main_part, :styles)
        return unless part

        node = xml(part).xpath('/w:styles/w:style', NS).find do |style|
          style.at_xpath('w:name/@w:val', NS)&.value.to_s.casecmp?(name)
        end
        node && node['w:styleId']
      end

      private

      def flush(name = nil)
        names = name ? [name] : @xml.keys
        names.each do |n|
          doc = @xml[n] or next
          @entries[n] = serialize(doc)
        end
      end

      def serialize(doc)
        doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
      end
    end
  end
end
