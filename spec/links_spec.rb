RSpec.describe 'Links' do
  let(:markdown) { "# Intro\n\nSee [the tiers](tiers.md), [docs](https://example.com/) and [above](#intro).\n" }
  let(:remote_only) { ->(href) { href.match?(/\A([a-z][a-z0-9+.-]*:|#)/i) ? href : nil } }

  # { text => target } of the body's hyperlinks: relationship targets, #anchors.
  def hyperlinks(docx)
    pkg = package(docx)
    pkg.xml('word/document.xml').xpath('//w:body//w:hyperlink', NS).to_h do |link|
      id = link['r:id']
      [link.xpath('.//w:t', NS).map(&:content).join, id ? pkg.relationship('word/document.xml', id)[:target] : "##{link['w:anchor']}"]
    end
  end

  it 'turns every link into a hyperlink by default' do
    expect(hyperlinks(Caracal::Md.render(markdown)))
      .to eq('the tiers' => 'tiers.md', 'docs' => 'https://example.com/', 'above' => '#intro')
  end

  describe 'link:' do
    it 'keeps only the text of links it returns nil for' do
      docx = Caracal::Md.render(markdown, link: remote_only)
      expect(hyperlinks(docx)).to eq('docs' => 'https://example.com/', 'above' => '#intro')
      expect(body_text(document_xml(docx))).to eq('IntroSee the tiers, docs and above.')
      plain = document_xml(docx).xpath("//w:body//w:r[w:t='the tiers']", NS)
      expect(plain.size).to eq(1)
      expect(plain.first.at_xpath('w:rPr/w:rStyle', NS)).to be_nil
    end

    it 'receives each href and links to what it returns' do
      seen = []
      wiki = lambda do |href|
        seen << href
        href.end_with?('.md') ? "https://wiki.example.com/#{href.delete_suffix('.md')}" : href
      end
      docx = Caracal::Md.render(markdown, link: wiki)
      expect(seen).to eq(%w[tiers.md https://example.com/ #intro])
      expect(hyperlinks(docx)['the tiers']).to eq('https://wiki.example.com/tiers')
    end

    it 'keeps the formatting of the text it keeps' do
      doc = document_xml(Caracal::Md.render("[**the** tiers](tiers.md)\n", link: remote_only))
      expect(doc.xpath('//w:r[w:rPr/w:b]/w:t', NS).map(&:content)).to eq(['the'])
      expect(body_text(doc)).to eq('the tiers')
    end

    it 'shows the target of a link without text' do
      doc = document_xml(Caracal::Md.render("<a href=\"tiers.md\"></a>\n", link: remote_only))
      expect(body_text(doc)).to eq('tiers.md')
      expect(doc.at_xpath('//w:hyperlink', NS)).to be_nil
    end

    it 'checks what it returns like any link' do
      renderer = Caracal::Md::Renderer.new(link: ->(_) { 'javascript:alert(1)' })
      doc = document_xml(renderer.render("[click](https://example.com/)\n"))
      expect(doc.at_xpath('//w:hyperlink', NS)).to be_nil
      expect(body_text(doc)).to eq('click')
      expect(renderer.warnings).to eq(['link to "javascript:alert(1)" is rendered as text'])
    end

    it 'leaves cross-references alone' do
      seen = []
      md = "| a |\n|---|\n| 1 |\n\nTable: Numbers {#tbl:n}\n\nSee [](#tbl:n) and @tbl:n.\n"
      doc = document_xml(Caracal::Md.render(md, link: ->(href) { seen << href; nil }))
      expect(seen).to be_empty
      expect(body_text(doc)).to include('See Table 1 and Table 1.')
    end

    it 'applies to links in footnotes' do
      docx = Caracal::Md.render("Text.[^1]\n\n[^1]: See [the tiers](tiers.md).\n", link: remote_only)
      notes = package(docx).xml('word/footnotes.xml')
      expect(notes.at_xpath('//w:hyperlink', NS)).to be_nil
      expect(notes.xpath('//w:t', NS).map(&:content).join).to include('See the tiers.')
    end
  end

  describe 'caracal-md --local-links' do
    it 'keeps only the text of links to local files with "text"' do
      expect(hyperlinks(cli(markdown, '--local-links', 'text')))
        .to eq('docs' => 'https://example.com/', 'above' => '#intro')
    end

    it 'keeps them as links with "link"' do
      expect(hyperlinks(cli(markdown, '--local-links', 'link')).keys).to eq(['the tiers', 'docs', 'above'])
    end
  end
end
