RSpec.describe 'lang option' do
  def spelling(docx)
    package(docx).xml('word/styles.xml').at_xpath('//w:docDefaults/w:rPrDefault/w:rPr/w:lang/@w:val', NS)&.value
  end

  def core_language(docx)
    package(docx).xml('docProps/core.xml').at_xpath('//dc:language', NS)&.content
  end

  def paragraphs(docx, style)
    document_xml(docx).xpath("//w:body//w:p[w:pPr/w:pStyle/@w:val='#{style}']", NS).map do |p|
      p.xpath('.//w:t', NS).map(&:content).join
    end
  end

  let(:quote) { %(Siehe "oben".\n) }
  let(:figures) { "![A](a.png \"Bild\")\n\n| a |\n|---|\n| 1 |\n\nTable: Werte\n" }

  it 'leaves documents without front matter English by default' do
    docx = Caracal::Md.render(quote)
    expect(body_text(document_xml(docx))).to eq('Siehe “oben”.')
    expect(spelling(docx)).to be_nil
  end

  it 'renders like front matter lang' do
    docx = Caracal::Md.render(quote, lang: 'de')
    expect(body_text(document_xml(docx))).to eq('Siehe „oben“.')
    expect(spelling(docx)).to eq('de-DE')
    expect(core_language(docx)).to eq('de')

    options = { image_loader: ->(_) { png }, number_captions: true, toc: true, lof: true }
    by_option = Caracal::Md.render(figures, lang: 'de', **options)
    by_meta   = Caracal::Md.render("---\nlang: de\n---\n#{figures}", **options)
    expect(paragraphs(by_option, 'Caption')).to eq(['Abbildung 1: Bild', 'Tabelle 1: Werte'])
    expect(paragraphs(by_option, 'TOCHeading')).to eq(%w[Inhalt Abbildungsverzeichnis])
    %w[Caption TOCHeading].each { |style| expect(paragraphs(by_option, style)).to eq(paragraphs(by_meta, style)) }
  end

  it 'takes symbols and regional tags, as I18n.locale gives them' do
    expect(spelling(Caracal::Md.render(quote, lang: :de))).to eq('de-DE')
    docx = Caracal::Md.render(quote, lang: :'de-CH')
    expect(spelling(docx)).to eq('de-CH')
    expect(body_text(document_xml(docx))).to eq('Siehe „oben“.')
  end

  it 'gives way to front matter lang' do
    docx = Caracal::Md.render("---\nlang: en\n---\n#{quote}", lang: 'de')
    expect(body_text(document_xml(docx))).to eq('Siehe “oben”.')
    expect(spelling(docx)).to eq('en-US')
  end

  it 'applies when front matter names no language' do
    docx = Caracal::Md.render("---\ntitle: Notiz\nlang:\n---\n#{quote}", lang: 'de')
    expect(body_text(document_xml(docx))).to end_with('Siehe „oben“.')
    expect(spelling(docx)).to eq('de-DE')
  end

  it 'fills {{lang}} in a template' do
    template = Caracal::Document.new
    template.p 'Sprache: {{lang}}'
    template.p '{{content}}'
    docx = Caracal::Md.render(quote, lang: 'de', template: template.render.string)
    expect(body_text(document_xml(docx))).to eq('Sprache: deSiehe „oben“.')
  end

  describe 'caracal-md --lang' do
    it 'sets the language of documents without front matter' do
      docx = cli(quote, '--lang', 'de')
      expect(body_text(document_xml(docx))).to eq('Siehe „oben“.')
      expect(spelling(docx)).to eq('de-DE')
    end
  end
end
