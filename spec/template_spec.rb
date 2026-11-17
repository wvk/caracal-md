RSpec.describe 'rendering into a Word template' do
  let(:sample)   { File.read(File.expand_path('fixtures/sample.md', __dir__)) }
  let(:template) { TemplateBuilder.build }
  let(:docx)     { Caracal::Md.render(sample, template: template.to_s, style_map: { 'Quote' => 'Corporate Quote' }) }
  let(:pkg)      { package(docx) }
  let(:doc)      { pkg.xml('word/document.xml') }

  it 'writes well-formed parts' do
    expect_well_formed(docx)
  end

  it 'turns the template into a document' do
    expect(pkg.override_content_type('word/document.xml')).to eq(Caracal::Md::Package::CONTENT_TYPES[:document])
  end

  it 'resolves styles by name, so localized style ids work' do
    styles = paragraph_styles(doc)
    expect(styles).to include('berschrift1', 'berschrift2', 'Standard')
    expect(styles).not_to include('Heading1', 'Normal')
  end

  it 'applies the style map' do
    quote_style = template_style_id('Corporate Quote')
    expect(styles_of_text('Quote with bold')).to eq([quote_style])
  end

  it 'imports styles the template lacks, based on the template styles' do
    styles = pkg.xml('word/styles.xml')
    code = styles.at_xpath("//w:style[@w:styleId='SourceCode']", NS)
    expect(code.at_xpath('w:name/@w:val', NS).value).to eq('Source Code')
    expect(code.at_xpath('w:basedOn/@w:val', NS).value).to eq('Standard')
  end

  it 'puts the content at the {{content}} paragraph and keeps the rest of the template' do
    text = body_text(doc)
    expect(text).not_to include('{{content}}')
    expect(text.index('Prepared by Ada, Grace')).to be < text.index('Hello “World”')
    expect(text.index('Hello “World”')).to be < text.index('Template closing paragraph')
  end

  it 'fills placeholders in body and header from front matter' do
    header = pkg.related_parts('word/document.xml', :header).map { |part| body_text_of(pkg.xml(part)) }.join
    expect(header).to include('Smoke test – Ada, Grace')
    expect(body_text(doc)).to start_with('Smoke test')
  end

  it 'skips the title block when the template shows the title' do
    expect(paragraph_styles(doc)).not_to include('Author')
  end

  it 'keeps the template page setup' do
    expect(doc.at_xpath('//w:body/w:sectPr/w:pgMar/@w:left', NS).value).to eq('2000')
    expect(doc.at_xpath('//w:body/w:sectPr/w:pgSz/@w:w', NS).value).to eq('12240')
  end

  it 'keeps list numbering apart from the template lists' do
    num_ids = doc.xpath('//w:numPr/w:numId/@w:val', NS).map(&:value)
    numbering = pkg.xml('word/numbering.xml')
    expect(num_ids.uniq.size).to be > 1
    num_ids.uniq.each do |id|
      expect(numbering.at_xpath("//w:num[@w:numId='#{id}']", NS)).not_to be_nil
    end
    abstract_ids = numbering.xpath('//w:abstractNum/@w:abstractNumId', NS).map(&:value)
    expect(abstract_ids).to eq(abstract_ids.uniq)
  end

  it 'adds footnotes after those the template has' do
    docx = Caracal::Md.render("Text[^a]\n\n[^a]: Note", template: TemplateBuilder.build(footnotes: true).to_s)
    pkg  = package(docx)
    notes = pkg.xml('word/footnotes.xml')
    expect(notes.xpath('//w:footnote/@w:id', NS).map(&:value)).to eq(%w[-1 0 1 2])
    expect(pkg.xml('word/document.xml').at_xpath('//w:footnoteReference/@w:id', NS).value).to eq('2')
  end

  it 'replaces the template body when there is no placeholder' do
    docx = Caracal::Md.render("# Only this\n", template: TemplateBuilder.build(placeholder: false).to_s)
    doc  = document_xml(docx)
    expect(body_text(doc)).to eq('Only this')
    expect(doc.at_xpath('//w:body/w:sectPr/w:headerReference', NS)).not_to be_nil
  end

  it 'copies images and their relationships' do
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, 'pic.png'), png)
      docx = Caracal::Md.render('![Pic](pic.png)', template: template.to_s, base_dir: dir)
      pkg  = package(docx)
      embed = pkg.xml('word/document.xml').at_xpath('//a:blip/@r:embed', NS.merge('a' => 'http://schemas.openxmlformats.org/drawingml/2006/main'))
      target = pkg.relationship('word/document.xml', embed.value)[:target]
      expect(pkg.include?(pkg.resolve('word/document.xml', target))).to be(true)
      expect(pkg.default_content_type('png')).to eq('image/png')
    end
  end

  it 'drops the macros of a macro-enabled template' do
    tpl = TemplateBuilder.build
    tpl['word/vbaProject.bin'] = 'macros'
    tpl.add_relationship('word/document.xml', Caracal::Md::Package::REL_TYPES[:vba_project], 'vbaProject.bin')
    tpl.set_override('word/vbaProject.bin', 'application/vnd.ms-office.vbaProject')
    tpl.set_override('word/document.xml', 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml')
    pkg = package(Caracal::Md.render('Text', template: tpl.to_s))
    expect(pkg.include?('word/vbaProject.bin')).to be(false)
    expect(pkg.override_content_type('word/vbaProject.bin')).to be_nil
    expect(pkg.relationships('word/document.xml').map { |r| r[:type] }).not_to include(Caracal::Md::Package::REL_TYPES[:vba_project])
    expect(pkg.override_content_type('word/document.xml')).to eq(Caracal::Md::Package::CONTENT_TYPES[:document])
  end

  it 'warns about style map entries the template lacks' do
    renderer = Caracal::Md::Renderer.new(template: template.to_s, style_map: { 'Quote' => 'Nope' })
    renderer.render("> quoted\n")
    expect(renderer.warnings.join).to include('Nope')
  end

  def template_style_id(name)
    pkg.style_id_by_name(name)
  end

  def styles_of_text(text)
    doc.xpath('//w:body/w:p', NS).select { |p| p.xpath('.//w:t', NS).map(&:content).join == text }
       .map { |p| p.at_xpath('w:pPr/w:pStyle/@w:val', NS).value }
  end

  def body_text_of(xml)
    xml.xpath('//w:t', NS).map(&:content).join
  end
end
