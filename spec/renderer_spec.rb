RSpec.describe Caracal::Md::Renderer do
  let(:sample) { File.read(File.expand_path('fixtures/sample.md', __dir__)) }
  let(:docx)   { Caracal::Md.render(sample) }
  let(:doc)    { document_xml(docx) }

  it 'writes well-formed parts' do
    expect_well_formed(docx)
  end

  it 'renders the title block from front matter' do
    expect(paragraph_styles(doc).first(4)).to eq(%w[Title Author Author Date])
  end

  it 'maps headings to heading styles with bookmarks for internal links' do
    expect(paragraph_styles(doc)).to include('Heading1', 'Heading2')
    expect(doc.at_xpath("//w:bookmarkStart[@w:name='second_section']", NS)).not_to be_nil
    expect(doc.at_xpath("//w:hyperlink[@w:anchor='second_section']", NS)).not_to be_nil
  end

  it 'formats inline text' do
    bold = doc.xpath('//w:r[w:rPr/w:b]/w:t', NS).map(&:content)
    expect(bold).to include('bold')
    expect(doc.at_xpath("//w:r[w:rPr/w:strike]/w:t", NS).content).to eq('gone')
    expect(doc.at_xpath("//w:r[w:rPr/w:vertAlign[@w:val='subscript']]/w:t", NS).content).to eq('2')
    expect(doc.at_xpath("//w:r[w:rPr/w:rStyle[@w:val='VerbatimChar']]/w:t", NS).content).to eq('code')
    expect(body_text(doc)).to include('Hello “World”')
  end

  it 'moves footnotes into the footnotes part' do
    pkg = package(docx)
    expect(doc.at_xpath('//w:footnoteReference', NS)['w:id']).to eq('1')
    expect(body_text(doc)).not_to include(Caracal::Md::Converter::MARKER_OPEN)
    notes = pkg.xml('word/footnotes.xml')
    expect(notes.at_xpath("//w:footnote[@w:id='1']//w:footnoteRef", NS)).not_to be_nil
    expect(notes.xpath("//w:footnote[@w:id='1']//w:t", NS).map(&:content).join).to include('The note with a link.')
    link_id = notes.at_xpath('//w:hyperlink/@r:id', NS).value
    expect(pkg.relationship('word/footnotes.xml', link_id)[:target]).to eq('https://example.org')
    expect(pkg.xml('word/settings.xml').at_xpath('//w:footnotePr', NS)).not_to be_nil
  end

  it 'starts an ordered list at its first number' do
    numbering = package(docx).xml('word/numbering.xml')
    expect(numbering.at_xpath("//w:num/w:lvlOverride/w:startOverride[@w:val='3']", NS)).not_to be_nil
  end

  it 'styles list items by type and level, numbered by caracal' do
    doc = document_xml(Caracal::Md.render("- a\n  1. b\n     - c\n       - d\n         - e\n           - f\n"))
    items = doc.xpath('//w:body/w:p[w:pPr/w:numPr/w:numId]', NS)
    expect(items.map { |p| p.at_xpath('w:pPr/w:pStyle/@w:val', NS).value })
      .to eq(%w[ListBullet ListNumber2 ListBullet3 ListBullet4 ListBullet5 ListParagraph])
    expect(items.map { |p| p.at_xpath('w:pPr/w:numPr/w:ilvl/@w:val', NS).value }).to eq(%w[0 1 2 3 4 5])
  end

  it 'names the list styles like Word and bases them on List Paragraph' do
    styles = package(docx).xml('word/styles.xml')
    { 'ListBullet' => 'List Bullet', 'ListNumber3' => 'List Number 3' }.each do |id, name|
      style = styles.at_xpath("//w:style[@w:styleId='#{id}']", NS)
      expect(style.at_xpath('w:name/@w:val', NS).value).to eq(name)
      expect(style.at_xpath('w:basedOn/@w:val', NS).value).to eq('ListParagraph')
    end
  end

  it 'renders task lists, code, tables, definition lists and custom styles' do
    text = body_text(doc)
    expect(text).to include("☐ open", "☒ done")
    expect(paragraph_styles(doc)).to include('SourceCode', 'DefinitionTerm', 'Definition', 'Poetry')
    table = doc.at_xpath('//w:tbl', NS)
    expect(table.at_xpath('w:tblPr/w:tblStyle/@w:val', NS).value).to eq('MarkdownTable')
    expect(table.at_xpath('w:tblPr/w:tblCaption/@w:val', NS).value).to eq('Numbers')
    expect(table.xpath('w:tr', NS).size).to eq(3)
    expect(package(docx).style_id_by_name('Poetry')).to eq('Poetry')
  end

  it 'highlights code with Rouge' do
    colors = doc.xpath("//w:p[w:pPr/w:pStyle/@w:val='SourceCode']//w:color/@w:val", NS).map(&:value)
    expect(colors).to include('D73A49')
  end

  it 'adds a page break for <!-- pagebreak -->' do
    expect(doc.at_xpath("//w:br[@w:type='page']", NS)).not_to be_nil
  end

  it 'writes document properties' do
    core = package(docx).xml('docProps/core.xml')
    expect(core.at_xpath('//dc:title', NS).content).to eq('Smoke test')
    expect(core.at_xpath('//dc:creator', NS).content).to eq('Ada, Grace')
  end

  it 'adds a table of contents on request' do
    doc = document_xml(Caracal::Md.render("# One\n\n## Two\n", toc: true, toc_title: 'Inhalt'))
    expect(doc.xpath('//w:instrText', NS).map(&:content).join).to include('TOC \o "1-3"')
    expect(body_text(doc)).to include('Inhalt')
  end

  it 'uses German quotes for lang: de' do
    doc = document_xml(Caracal::Md.render(%(---\nlang: de\n---\nSie sagte "Hallo" und 'tschüss'.)))
    expect(body_text(doc)).to include('„Hallo“', '‚tschüss‘')
  end

  it 'embeds images scaled to the text width, with a caption from the title' do
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, 'wide.png'), png(2000, 100))
      docx = Caracal::Md.render(%(![Wide](wide.png "A wide one")), base_dir: dir)
      doc  = document_xml(docx)
      extent = doc.at_xpath('//wp:extent', NS)
      expect(extent['cx'].to_i).to eq((9026 / 20) * 12_700)
      expect(paragraph_styles(doc)).to include('Caption')
      expect(package(docx).entry_names.grep(%r{\Aword/media/.+\.png\z})).not_to be_empty
    end
  end

  it 'falls back to alt text for images it does not load' do
    renderer = described_class.new
    doc = document_xml(renderer.render('![Secret](../../etc/passwd)'))
    expect(body_text(doc)).to eq('Secret')
    expect(renderer.warnings.join).to include('image not loaded')
  end

  it 'ignores raw OpenXML unless allowed' do
    md = "```{=openxml}\n<w:p><w:r><w:t>RAW</w:t></w:r></w:p>\n```\n"
    expect(body_text(document_xml(Caracal::Md.render(md)))).not_to include('RAW')
    expect(body_text(document_xml(Caracal::Md.render(md, allow_raw_openxml: true)))).to include('RAW')
  end

  it 'renders links with unsafe schemes as text' do
    doc = document_xml(Caracal::Md.render('[click](javascript:alert(1))'))
    expect(doc.at_xpath('//w:hyperlink', NS)).to be_nil
    expect(body_text(doc)).to eq('click')

    doc = document_xml(Caracal::Md.render("[click](<java\tscript:alert(1)>)"))
    expect(doc.at_xpath('//w:hyperlink', NS)).to be_nil
    expect(body_text(doc)).to eq('click')
  end

  it 'rejects unknown options' do
    expect { described_class.new(colour: 'red') }.to raise_error(ArgumentError, /colour/)
  end
end

RSpec.describe 'Markdown extras' do
  it 'turns GitHub alerts into labelled, styled paragraphs' do
    doc = document_xml(Caracal::Md.render("---\nlang: de\n---\n> [!WARNING]\n> Careful *now*.\n"))
    expect(paragraph_styles(doc)).to eq(%w[AlertWarning AlertWarning])
    expect(body_text(doc)).to eq('WarnungCareful now.')
  end

  it 'gives a table the style named by custom-style' do
    docx = Caracal::Md.render("| a |\n|---|\n| 1 |\n{: custom-style=\"Grid Table 4\"}\n")
    expect(document_xml(docx).at_xpath('//w:tblStyle/@w:val', NS).value).to eq('GridTable4')
    expect(package(docx).style_id_by_name('Grid Table 4')).to eq('GridTable4')
  end

  it 'sets the document language from front matter' do
    pkg = package(Caracal::Md.render("---\nlang: de\n---\nHallo"))
    expect(pkg.xml('word/styles.xml').at_xpath('//w:docDefaults/w:rPrDefault/w:rPr/w:lang/@w:val', NS).value).to eq('de-DE')
  end
end
