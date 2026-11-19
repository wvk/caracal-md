RSpec.describe 'Caracal::Md.document' do
  def texts(doc)
    doc.xpath('//w:body/w:p | //w:body/w:tbl', NS).map { |node| node.xpath('.//w:t', NS).map(&:content).join }.reject(&:empty?)
  end

  def footnotes(bytes)
    package(bytes).xml('word/footnotes.xml').xpath('//w:footnote[not(@w:type)]', NS).to_h do |note|
      [note['w:id'], note.xpath('.//w:t', NS).map(&:content).join.strip]
    end
  end

  def captions(doc)
    doc.xpath("//w:body/w:p[w:pPr/w:pStyle/@w:val='Caption' or w:pPr/w:pStyle/@w:val='Beschriftung']", NS).map { |p| p.xpath('.//w:t', NS).map(&:content).join }
  end

  let(:rows) { [%w[Pos Preis], ['Beratung', '1.200 €']] }

  it "renders the issue's example with Word footnotes, merged into the template" do
    template = TemplateBuilder.build
    renderer = Caracal::Md::Renderer.new(template: template, lang: 'de')
    rows = self.rows
    bytes = renderer.document do |docx|
      docx.markdown "# Angebot\n\nWie besprochen[^1].\n\n[^1]: Telefonat am 3. November."
      docx.table rows, border_size: 4
      docx.markdown "Gültig bis Jahresende[^2].\n\n[^2]: Preise netto."
    end
    expect_well_formed(bytes)
    expect(footnotes(bytes)).to eq('1' => 'Telefonat am 3. November.', '2' => 'Preise netto.')

    doc = document_xml(bytes)
    expect(doc.xpath('//w:footnoteReference/@w:id', NS).map(&:value)).to eq(%w[1 2])
    expect(texts(doc)).to eq(['{{title}}', 'Prepared by {{author}}', 'template list', 'Angebot', 'Wie besprochen.',
                              'PosPreisBeratung1.200 €', 'Gültig bis Jahresende.', 'Template closing paragraph'])
    expect(paragraph_styles(doc)).to include('berschrift1', 'Standard')
    expect(package(bytes).xml('word/styles.xml').at_xpath('//w:docDefaults//w:lang/@w:val', NS).value).to eq('de-DE')
    expect(renderer.warnings).to be_empty
  end

  it 'numbers captions and resolves cross-references across calls' do
    renderer = Caracal::Md::Renderer.new(number_captions: true)
    bytes = renderer.document do |docx|
      docx.markdown "See @tbl:b and [](#tbl:a).\n\n| a |\n|---|\n| 1 |\n\nTable: First {#tbl:a}\n"
      docx.p 'Between'
      docx.markdown "| b |\n|---|\n| 2 |\n\nTable: Second {#tbl:b}\n"
    end
    doc = document_xml(bytes)
    expect(captions(doc)).to eq(['Table 1: First', 'Table 2: Second'])
    expect(texts(doc).first).to eq('See Table 2 and Table 1.')
    expect(renderer.warnings).to be_empty
  end

  it 'starts with the table of contents and lists of figures the options ask for' do
    bytes = Caracal::Md.document(toc: true, lof: true, image_loader: ->(_) { png }) do |docx|
      docx.markdown "# One\n\n![A](a.png \"Plan\")\n"
      docx.h1 'Two'
      docx.markdown "# Three\n"
    end
    doc = document_xml(bytes)
    expect(texts(doc).first(5)).to eq(['Contents', 'One#', 'Two#', 'Three#', 'List of Figures'])
    expect(captions(doc)).to eq(['Figure 1: Plan'])
  end

  it 'takes front matter of the calls for placeholders and properties, and warns about document settings' do
    template = TemplateBuilder.build
    renderer = Caracal::Md::Renderer.new(template: template, variables: { 'author' => 'Sales' })
    bytes = renderer.document do |docx|
      docx.markdown "---\ntitle: First\nsubject: Offer\ntoc: true\nlang: fr\n---\nOne \"quote\"\n"
      docx.markdown "---\ntitle: Second\n---\nTwo\n"
    end
    doc = document_xml(bytes)
    expect(texts(doc).first(2)).to eq(['Second', 'Prepared by Sales'])
    expect(texts(doc)).to include('One “quote”', 'Two')
    core = package(bytes).xml('docProps/core.xml')
    expect(core.xpath('//dc:title | //dc:subject | //dc:language', NS).map(&:content)).to eq(%w[Second Offer])
    expect(renderer.warnings).to eq([
      'front matter toc in #markdown is ignored; Caracal::Md.document takes it as an option',
      'front matter lang in #markdown is ignored; Caracal::Md.document takes it as an option',
    ])
  end

  it 'shifts headings per call, by option or front matter' do
    bytes = Caracal::Md.document(heading_offset: 1) do |docx|
      docx.markdown "# A\n"
      docx.markdown "### B\n", heading_offset: :auto
      docx.markdown "---\nheading-offset: auto\n---\n## C\n"
    end
    expect(paragraph_styles(document_xml(bytes))).to eq(%w[Heading2 Heading1 Heading1])
  end

  it 'returns the warnings of each call from markdown_warnings' do
    seen = []
    renderer = Caracal::Md::Renderer.new
    renderer.document do |docx|
      docx.markdown '![x](missing.png)'
      seen << docx.markdown_warnings
      docx.markdown 'fine'
      seen << docx.markdown_warnings
    end
    expect(seen).to eq([['missing.png: image not loaded'], []])
    expect(renderer.warnings).to eq(['missing.png: image not loaded'])
  end

  it 'leaves #markdown outside the block, and in cells, headers and footers, as it is' do
    kept = nil
    Caracal::Md.document do |docx|
      cell = Caracal::Core::Models::TableCellModel.new { |c| c.markdown "cell[^1]\n\n[^1]: in the cell" }
      docx.table [[cell]]
      kept = docx
    end
    expect(kept.markdown_session).to be_nil

    docx = Caracal::Document.new
    docx.markdown "Some text.[^1]\n\n[^1]: A note."
    expect(paragraph_styles(document_xml(docx.render.string))).to include('FootnoteText')
  end

  it 'refuses what it cannot do' do
    expect { Caracal::Md.document }.to raise_error(ArgumentError, /needs a block/)
    expect { Caracal::Md.document(title_block: true) { nil } }.to raise_error(ArgumentError, /title block/)
    expect { Caracal::Md.document { |docx| docx.markdown 'x', base_dir: '.' } }.to raise_error(ArgumentError, /base_dir/)
  end
end
