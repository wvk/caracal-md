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

  it "numbers captions with the template's caption and table of figures styles" do
    markdown = <<~MD
      ---
      lang: de
      number-captions: chapter
      lof: true
      ---
      # Eins

      ![A](a.png "Erste"){: #fig-a}

      Siehe [](#fig-a).
    MD
    docx = Caracal::Md.render(markdown, template: TemplateBuilder.build(captions: true).to_s, image_loader: ->(_) { png })
    doc  = document_xml(docx)
    expect_well_formed(docx)

    texts = ->(style) { doc.xpath("//w:body/w:p[w:pPr/w:pStyle/@w:val='#{style}']", NS).map { |p| p.xpath('.//w:t', NS).map(&:content).join } }
    expect(texts.call('Beschriftung')).to eq(['Abbildung 1.1: Erste'])
    expect(texts.call('Abbildungsverzeichnis')).to eq(['Abbildung 1.1: Erste#'])
    expect(body_text(doc)).to include('Siehe Abbildung 1.1.')

    heading = doc.at_xpath("//w:body/w:p[w:pPr/w:pStyle/@w:val='berschrift1']", NS)
    expect(heading.xpath('.//w:instrText', NS).map { |i| i.content.strip }).to eq(['SEQ Chapter \h'])
    expect(doc.xpath('//w:instrText', NS).map(&:content).join).to include('SEQ Abbildung', 'TOC \h \z \c "Abbildung"')
  end

  describe 'lists' do
    let(:markdown) do
      <<~MD
        - one
        - two
          - two a

          after nested
          - two b
            - deep

        1. first
        2. second
           1. nested one
        3. third
           1. nested again

        Between.

        3. three
        4. four

        > - quoted
      MD
    end
    let(:template)  { TemplateBuilder.build(lists: true) }
    let(:docx)      { Caracal::Md.render(markdown, template: template.to_s) }
    let(:numbering) { pkg.xml('word/numbering.xml') }

    it 'writes well-formed parts' do
      expect_well_formed(docx)
    end

    it 'gives bullets the template styles by level and their numbering' do
      expect(style_of('one')).to eq('Aufzhlungszeichen')
      expect(style_of('two a')).to eq('Aufzhlungszeichen2')
      %w[one two\ a two\ b].each do |text|
        expect(paragraph(text).at_xpath('w:pPr/w:numPr | w:pPr/w:ind | w:pPr/w:contextualSpacing', NS)).to be_nil
      end
    end

    it 'gives every numbered list its own numbering on the template definition' do
      first, third, three = %w[first third three].map { |text| num_pr(text) }
      expect(style_of('first')).to eq('Listennummer')
      expect(first).to eq(third)
      expect(three).not_to eq(first)
      [first, three].each do |ilvl, num_id|
        expect(ilvl).to eq('0')
        expect(abstract_of(num_id)).to eq('91')
      end
      expect(start_overrides(first.last)).to eq('0' => '1')
      expect(start_overrides(three.last)).to eq('0' => '3')
    end

    it 'keeps caracal numbering for levels the template lacks, restarting each list' do
      expect(pkg.style_id_by_name('List Bullet 3')).to eq(style_of('deep'))
      expect(pkg.style_id_by_name('List Number 2')).to eq(style_of('nested one'))
      expect(num_pr('deep').first).to eq('2')
      nested, again = num_pr('nested one'), num_pr('nested again')
      expect(nested.first).to eq('1')
      expect(nested.last).not_to eq(again.last)
      expect(start_overrides(again.last)).to eq('1' => '1')
      expect(paragraph('nested one').at_xpath('w:pPr/w:ind', NS)).not_to be_nil
    end

    it 'indents text after a nested list like its item, without a bullet' do
      ppr = paragraph('after nested').at_xpath('w:pPr', NS)
      expect(ppr.at_xpath('w:pStyle/@w:val', NS).value).to eq('Aufzhlungszeichen')
      expect(ppr.at_xpath('w:numPr/w:numId/@w:val', NS).value).to eq('0')
      expect(ppr.element_children.map(&:name).first(2)).to eq(%w[pStyle numPr])
      expect(ppr.at_xpath('w:ind/@w:start', NS).value).to eq('284')
    end

    it 'keeps caracal numbering in quotes' do
      expect(style_of('quoted')).to eq('Quote')
      expect(abstract_of(num_pr('quoted').last)).not_to eq('90')
    end

    it "keeps the template's own list" do
      expect(num_pr('template list')).to eq(%w[0 1])
    end

    it 'drops copies of caracal numbering that no item uses' do
      used = doc.xpath('//w:numId/@w:val', NS).map(&:value)
      expect(numbering.xpath('//w:num/@w:numId', NS).map(&:value) - used).to contain_exactly('90', '91')
      referenced = numbering.xpath('//w:num/w:abstractNumId/@w:val', NS).map(&:value)
      expect(numbering.xpath('//w:abstractNum/@w:abstractNumId', NS).map(&:value) - referenced).to be_empty
    end

    context 'with a style map' do
      let(:docx) { Caracal::Md.render("1. first\n", template: template.to_s, style_map: { 'List Number' => 'List Bullet' }) }

      it 'uses the mapped style and its numbering' do
        expect(style_of('first')).to eq('Aufzhlungszeichen')
        expect(paragraph('first').at_xpath('w:pPr/w:numPr', NS)).to be_nil
      end
    end

    def paragraph(text)
      doc.xpath('//w:body/w:p', NS).find { |p| p.xpath('.//w:t', NS).map(&:content).join == text }
    end

    def style_of(text)
      paragraph(text).at_xpath('w:pPr/w:pStyle/@w:val', NS).value
    end

    def num_pr(text)
      %w[ilvl numId].map { |name| paragraph(text).at_xpath("w:pPr/w:numPr/w:#{name}/@w:val", NS).value }
    end

    def abstract_of(num_id)
      numbering.at_xpath("//w:num[@w:numId='#{num_id}']/w:abstractNumId/@w:val", NS).value
    end

    def start_overrides(num_id)
      numbering.xpath("//w:num[@w:numId='#{num_id}']/w:lvlOverride", NS).to_h do |override|
        [override['w:ilvl'], override.at_xpath('w:startOverride/@w:val', NS).value]
      end
    end
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
