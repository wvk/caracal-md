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

  describe 'values' do
    def german?(docx)
      doc = document_xml(docx)
      quotes = body_text(doc).include?('„oben“')
      label  = paragraphs(docx, 'Caption').first.to_s.start_with?('Abbildung')
      title  = paragraphs(docx, 'TOCHeading').include?('Abbildungsverzeichnis')
      alert  = body_text(doc).include?('Warnung')
      [quotes, label, title, alert].uniq
    end

    let(:content) { %(Siehe "oben".\n\n![A](a.png "Bild"){: #fig-a}\n\n> [!WARNING]\n> Achtung\n) }
    let(:options) { { image_loader: ->(_) { png }, lof: true } }

    it 'reads front matter lang: no as Norwegian' do
      docx = Caracal::Md.render("---\nlang: no\n---\n#{quote}")
      expect(spelling(docx)).to eq('no')
      expect(core_language(docx)).to eq('no')
    end

    it 'takes language tags in any case' do
      [Caracal::Md.render("---\nlang: DE\n---\n#{content}", **options), Caracal::Md.render(content, lang: 'DE', **options)].each do |docx|
        expect(german?(docx)).to eq([true])
        expect(spelling(docx)).to eq('de-DE')
        expect(core_language(docx)).to eq('de')
      end
      expect(spelling(Caracal::Md.render(quote, lang: ' DE_ch '))).to eq('de-ch')
    end

    it 'reads the option false as no language, and applies the option beside front matter without one' do
      docx = Caracal::Md.render(quote, lang: false)
      expect(spelling(docx)).to be_nil
      expect(core_language(docx)).to be_nil

      renderer = Caracal::Md::Renderer.new(lang: 'de')
      docx = renderer.render("---\nlang: 5\n---\n#{quote}")
      expect(spelling(docx)).to eq('de-DE')
      expect(renderer.warnings).to eq(['front matter lang 5 is no language tag; the document has no language'])
    end

    it 'takes the first entry of a list in front matter, with a warning' do
      renderer = Caracal::Md::Renderer.new
      docx = renderer.render("---\nlang: [DE, en]\n---\n#{quote}")
      expect(spelling(docx)).to eq('de-DE')
      expect(body_text(document_xml(docx))).to eq('Siehe „oben“.')
      expect(renderer.warnings).to eq(['front matter lang lists 2 languages; the document takes the first'])
    end

    it 'reads other front matter values as no language, with a warning' do
      renderer = Caracal::Md::Renderer.new
      docx = renderer.render("---\nlang: yes\n---\n#{quote}")
      expect(spelling(docx)).to be_nil
      expect(core_language(docx)).to be_nil
      expect(renderer.warnings).to eq(['front matter lang true is no language tag; the document has no language'])
    end

    it 'refuses other option values' do
      [true, 5, %w[de en]].each do |value|
        expect { Caracal::Md::Renderer.new(lang: value) }.to raise_error(ArgumentError, /no language tag/)
      end
    end

    it 'takes any case in #markdown' do
      docx = Caracal::Document.new
      docx.markdown "> [!WARNING]\n> Achtung\n", lang: 'DE'
      expect(body_text(document_xml(docx.render.string))).to start_with('Warnung')
    end
  end

  describe 'caracal-md --lang' do
    it 'sets the language of documents without front matter' do
      docx = cli(quote, '--lang', 'de')
      expect(body_text(document_xml(docx))).to eq('Siehe „oben“.')
      expect(spelling(docx)).to eq('de-DE')
    end
  end
end
