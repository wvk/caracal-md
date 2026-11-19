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
    %("quoted" 'single' -- --- ... << >>), 'C#', 'Ende #', '    indented', "\ttab", ' padded ', 'a | b', "x\u{E000}fn:1\u{E001}",
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
  end

  it 'works in #markdown' do
    docx = Caracal::Document.new
    docx.markdown "Hi #{escape('{{x}} *y* [TOC]')}"
    expect(texts(document_xml(docx.render.string))).to eq(['Hi {{x}} *y* [TOC]'])
  end

  it 'takes nil and other objects' do
    expect(escape(nil)).to eq('')
    expect(escape(3.5)).to eq('3\.5')
  end
end
