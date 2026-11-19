RSpec.describe 'a loaded Template' do
  let(:sample) { File.read(File.expand_path('fixtures/sample.md', __dir__)) + "\n![Plan](plan.png){: #fig-plan}\n\nSee [](#fig-plan).\n" }
  let(:bytes)  { TemplateBuilder.build(lists: true, footnotes: true, captions: true).to_s }
  let(:options) { { style_map: { 'Quote' => 'Corporate Quote' }, image_loader: ->(_) { png }, toc: true, lof: true } }

  def parts(docx)
    pkg = package(docx)
    %w[word/document.xml word/styles.xml word/numbering.xml word/footnotes.xml word/_rels/document.xml.rels].to_h { |part| [part, pkg[part]] }
  end

  it 'gives eight threads what renders with separate loads give' do
    expected = parts(Caracal::Md.render(sample, template: bytes, **options))
    expect(parts(Caracal::Md.render(sample, template: Caracal::Md::Template.load(bytes), **options))).to eq(expected)

    template = Caracal::Md::Template.load(bytes)
    entries  = template.package.entry_names.to_h { |name| [name, template.package[name].dup] }
    results  = Array.new(8) do
      Thread.new { Array.new(3) { parts(Caracal::Md.render(sample, template: template, **options)) } }
    end.flat_map(&:value)

    expect(results.size).to eq(24)
    results.each { |result| expect(result).to eq(expected) }
    expect(template.package.entry_names.to_h { |name| [name, template.package[name]] }).to eq(entries)
  end

  it 'raises FrozenError on changes' do
    template = Caracal::Md::Template.load(bytes)
    pkg = template.package
    expect(template).to be_frozen
    expect(pkg).to be_frozen
    expect { pkg['word/document.xml'] = '<x/>' }.to raise_error(FrozenError)
    expect { pkg.delete('word/styles.xml') }.to raise_error(FrozenError)
    expect { pkg['word/document.xml'] << 'x' }.to raise_error(FrozenError)
    expect { pkg.xml('word/document.xml') }.to raise_error(FrozenError, /parse them in a #dup/)
    expect { pkg.add_relationship('word/document.xml', 'type', 'target') }.to raise_error(FrozenError)
    expect { template.margins[:top] = 0 }.to raise_error(FrozenError)
    expect { template.text_parts << 'word/x.xml' }.to raise_error(FrozenError)
    expect { template.instance_variable_set(:@page_width, 1) }.to raise_error(FrozenError)
  end

  it 'reads page setup and placeholders when loaded' do
    template = Caracal::Md::Template.load(bytes)
    expect([template.page_width, template.page_height, template.text_width]).to eq([12240, 15840, 8240])
    expect(template.text_parts).to eq(%w[word/document.xml word/header1.xml word/footer1.xml])
    expect(template.placeholder?('title')).to be(true)
    expect(template.placeholder?('missing')).to be(false)
  end

  it 'loads from a Pathname in binary mode' do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join('corporate.dotx')
      File.binwrite(path, bytes)
      expect(Caracal::Md::Template.load(path).placeholder?('title')).to be(true)
    end
  end

  it 'leaves a package it is loaded from as it was' do
    source = TemplateBuilder.build
    template = Caracal::Md::Template.load(source)
    expect(source).not_to be_frozen
    expect(template.package).not_to equal(source)
    source['word/document.xml'] = source['word/document.xml'].sub('Template closing paragraph', 'Changed')
    expect(body_text(document_xml(Caracal::Md.render('x', template: template)))).to include('Template closing paragraph')
  end

  it 'copies into packages that change on their own' do
    template = Caracal::Md::Template.load(bytes)
    copy = template.package.dup
    expect(copy).not_to be_frozen
    copy.xml('word/document.xml').at_xpath('//w:body', NS).add_child('<w:p/>')
    copy['word/settings.xml'] = '<changed/>'
    expect(template.package['word/settings.xml']).not_to eq('<changed/>')
    expect { template.package.dup }.not_to raise_error
  end

  it 'is what the README shows: one load for every render' do
    template = Caracal::Md::Template.load(bytes)
    docs = %w[One Two].map { |text| body_text(document_xml(Caracal::Md.render("# #{text}", template: template))) }
    expect(docs[0]).to include('One')
    expect(docs[0]).not_to include('Two')
    expect(docs[1]).to include('Two')
    expect(docs[1]).not_to include('One')
  end
end
