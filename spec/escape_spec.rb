require 'json'

RSpec.describe 'Caracal::Md.escape' do
  def escape(value)
    Caracal::Md.escape(value)
  end

  def render(markdown, **options)
    @renderer = Caracal::Md::Renderer.new(**options)
    @docx = @renderer.render(markdown)
    document_xml(@docx)
  end

  def texts(doc)
    doc.xpath('//w:body//w:p', NS).map { |p| p.xpath('.//w:t | .//w:br', NS).map { |n| n.name == 'br' ? "\n" : n.content }.join }.reject(&:empty?)
  end

  let(:name) { "**Admin** ![x](logo.png) [^1] {{title}} <b>bold</b> &amp; 1. x" }

  it "renders the issue's example as it is" do
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, 'logo.png'), png)
      raw = render("Customer: #{name}\n\n[^1]: note\n", base_dir: dir)
      expect(raw.xpath('//w:drawing', NS)).not_to be_empty

      doc = render("Customer: #{escape(name)}\n\n[^1]: note\n", base_dir: dir)
      expect(texts(doc)).to eq(["Customer: #{name}"])
      expect(doc.xpath('//w:drawing | //w:footnoteReference | //w:r[w:rPr/w:b]', NS)).to be_empty
      expect(package(@docx).include?('word/footnotes.xml')).to be(false)
    end
  end

  values = [
    "**Admin** ![x](logo.png) [^1] {{title}} <b>bold</b> &amp; 1. x",
    '\\', '`', '*', '_', '~~', '|', '$', '==x==', '[x]', '<x>', '&', '{{x}}',
    '*a* _b_ __c__ ~~d~~ `e` $$f$$ [g](h) <https://i.example> j@k.example',
    '# not a heading', '- not a list', '+ x', '1. x', '> not a quote', ': x', '=== x', '---', '***', '~~~', '```',
    '[TOC]', '[[_TOC_]]', '${toc}', '\\newpage', '\\listoffigures', '<!-- pagebreak -->', '@fig:a', '[@fig:a; @tbl:b]', '[-@fig:a]',
    '^', '{: .class}', '{::comment}x{:/}', '{#id}', '[!NOTE] x', '*[HTML]: Hyper', '[x]: https://example.com',
    %("quoted" 'single' -- --- ... << >>), 'C#', 'Ende #', '    indented', "\ttab", ' padded ', 'a | b',
  ]

  {
    'a paragraph' => ->(e) { "Before\n\n#{e}\n\nAfter\n" },
    'a list item' => ->(e) { "- #{e}\n- after\n" },
    'a table cell' => ->(e) { "| head |\n|------|\n| #{e} |\n" },
    'a heading' => ->(e) { "## #{e}\n" },
  }.each do |context, markdown|
    it "renders each value as it is in #{context}" do
      values.each do |value|
        doc = render(markdown.call(escape(value)), number_captions: true)
        expect(texts(doc)).to include(value), "#{value.inspect} as #{escape(value).inspect}: #{texts(doc).inspect}"
        expect(doc.xpath('//w:hyperlink | //w:drawing | //w:footnoteReference | //w:fldChar | //w:r[(w:rPr/w:b or w:rPr/w:i or w:rPr/w:strike or w:rPr/w:highlight) and not(w:t="head")]', NS)).to be_empty, value.inspect
      end
    end
  end

  it 'keeps line breaks, on one line of Markdown' do
    value = "First\r\n- second\n\n  third\n"
    expect(escape(value)).not_to include("\n")
    expect(texts(render("Note: #{escape(value)}\n"))).to eq(["Note: First\n- second\n\n  third\n"])
    expect(texts(render("| head |\n|---|\n| #{escape(value)} |\n"))).to eq(['head', "First\n- second\n\n  third\n"])
  end

  it 'keeps escaped braces out of template placeholders, and fills written ones' do
    markdown = "---\ntitle: Offer\n---\nCustomer: #{escape('{{title}} {{author}}')}\n\nWritten: {{title}}\n"
    doc = render(markdown, template: TemplateBuilder.build)
    expect(texts(doc)).to include('Customer: {{title}} {{author}}', 'Written: Offer')
    expect(body_text(doc)).not_to include(Caracal::Md::Converter::MARKER_OPEN)
  end

  it 'keeps escaped braces in link texts, table captions and the table of contents' do
    value = escape('{{title}}')
    markdown = "---\ntitle: Offer\n---\n# #{value}\n\n[#{value}](https://example.com)\n\n| a |\n|---|\n| 1 |\n\nTable: #{value}\n"
    doc = render(markdown, template: TemplateBuilder.build, toc: true)
    expect(doc.xpath('//w:hyperlink[@r:id]//w:t', NS).map(&:content)).to eq(['{{title}}'])
    expect(texts(doc).count('{{title}}')).to eq(3)
    expect(texts(doc).grep(/\A\{\{title\}\}#\z/)).not_to be_empty # the TOC entry and its page number
    expect(body_text(doc)).not_to include(Caracal::Md::Converter::MARKER_OPEN)
    # attributes too: caracal writes a table's caption into w:tblCaption
    expect(doc.at_xpath('//w:tblCaption/@w:val', NS).value).to eq('{{title}}')
    expect(package(@docx)['word/document.xml'].dup.force_encoding('UTF-8')).not_to include(Caracal::Md::Converter::MARKER_OPEN)
  end

  # Link texts, captions and the table of contents join the text of their
  # elements into one run, where a value could spell a marker: ref:1 without
  # a caption raised, fn-start:1 moved what follows into the footnotes.
  describe 'with the marker characters in a value' do
    open_char  = Caracal::Md::Converter::MARKER_OPEN
    close_char = Caracal::Md::Converter::MARKER_CLOSE

    {
      'a paragraph'     => ->(e) { "#{e}\n\nAfter\n" },
      'a list item'     => ->(e) { "- #{e}\n\nAfter\n" },
      'a table cell'    => ->(e) { "| head |\n|------|\n| #{e} |\n\nAfter\n" },
      'a heading'       => ->(e) { "# #{e}\n\nAfter\n" },
      'a link text'     => ->(e) { "[#{e}](https://example.com)\n\nAfter\n" },
      'a table caption' => ->(e) { "| a |\n|---|\n| 1 |\n\nTable: #{e}\n\nAfter\n" },
    }.each do |context, markdown|
      it "shows them as U+FFFD in #{context}, and no marker takes effect" do
        %w[fn:1 fn-start:1 ref:1 ol-start:7 caption-figure:1 list-figure:1 char:60 char:0 char:55296].each do |marker|
          value = "#{open_char}#{marker}#{close_char}"
          doc   = render(markdown.call(escape(value)), toc: true, number_captions: true)
          expect(texts(doc).join("\n")).to include("\u{FFFD}#{marker}\u{FFFD}"), "#{marker}: #{texts(doc).inspect}"
          expect(texts(doc)).to include('After'), "#{marker}: #{texts(doc).inspect}"
          expect(package(@docx)['word/document.xml'].dup.force_encoding('UTF-8')).not_to include(open_char), marker
          expect(package(@docx).include?('word/footnotes.xml')).to be(false), marker
        end
      end
    end

    it 'turns char markers typed into the Markdown into braces alone' do
      doc = render("A #{open_char}char:123#{close_char} B #{open_char}char:60#{close_char} C #{open_char}char:0#{close_char} D\n")
      expect(texts(doc)).to eq(["A { B #{open_char}char:60#{close_char} C #{open_char}char:0#{close_char} D"])
    end
  end

  it 'fits front matter as a JSON string' do
    ['2024: Q3', 'a #b', '[x]', '{x}', '@home', '% x', 'yes', '*x* "q"', "it's"].each do |value|
      docx = Caracal::Md.render("---\ntitle: #{escape(value).to_json}\n---\nBody\n")
      expect(texts(document_xml(docx))).to eq([value, 'Body']), value
      expect(package(docx).xml('docProps/core.xml').at_xpath('//dc:title', NS).content).to eq(value)
    end
  end

  it 'works in #markdown' do
    docx = Caracal::Document.new
    docx.markdown "Hi #{escape('{{x}} *y* [TOC]')}"
    expect(texts(document_xml(docx.render.string))).to eq(['Hi {{x}} *y* [TOC]'])
  end

  it 'takes nil and other objects, and returns UTF-8' do
    expect(escape(nil)).to eq('')
    expect(escape(3.5)).to eq('3\.5')
    expect([nil, 'x', '*x*', 'Grüße'].map { |value| escape(value).encoding }.uniq).to eq([Encoding::UTF_8])
  end
end
