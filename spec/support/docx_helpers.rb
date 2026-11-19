require 'open3'
require 'rbconfig'
require 'zlib'

module DocxHelpers
  NS = Caracal::Md::Package::NS

  CLI = File.expand_path('../../bin/caracal-md', __dir__)

  # Runs bin/caracal-md on +markdown+, written to +file+, with +args+;
  # returns the DOCX it writes.
  def cli(markdown, *args, file: 'input.md')
    Dir.mktmpdir do |dir|
      input = File.join(dir, file)
      File.write(input, markdown)
      _, error, status = Open3.capture3(RbConfig.ruby, CLI, *args, input)
      raise "caracal-md failed: #{error}" unless status.success?

      File.binread(File.join(dir, file.sub(/\.[^.]+\z/, '.docx')))
    end
  end

  def package(bytes)
    Caracal::Md::Package.read(bytes)
  end

  def document_xml(bytes)
    package(bytes).xml('word/document.xml')
  end

  def body_text(doc)
    doc.xpath('//w:body//w:t', NS).map(&:content).join
  end

  def paragraph_styles(doc)
    doc.xpath('//w:body/w:p/w:pPr/w:pStyle/@w:val', NS).map(&:value)
  end

  # A solid PNG of the given size, 96 dpi.
  def png(width = 40, height = 20)
    raw   = ([0].pack('C') + ([200, 30, 30].pack('C3') * width)) * height
    chunk = ->(type, data) { [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N') }
    "\x89PNG\r\n\x1a\n".b +
      chunk.call('IHDR', [width, height, 8, 2, 0, 0, 0].pack('NNCCCCC')) +
      chunk.call('pHYs', [3780, 3780, 1].pack('NNC')) +
      chunk.call('IDAT', Zlib::Deflate.deflate(raw)) +
      chunk.call('IEND', '')
  end

  # Every XML part of the package parses strictly.
  def expect_well_formed(bytes)
    pkg = package(bytes)
    pkg.entry_names.grep(/(\.xml|\.rels)\z/).each do |name|
      expect { Nokogiri::XML(pkg[name]) { |c| c.strict } }.not_to raise_error, name
    end
  end
end
