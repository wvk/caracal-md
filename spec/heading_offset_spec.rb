RSpec.describe 'Heading offset' do
  def headings(docx)
    paragraph_styles(document_xml(docx)).grep(/\AHeading\d\z/)
  end

  let(:markdown) { "## Section\n\n### Subsection\n" }

  it 'takes heading levels as written by default' do
    expect(headings(Caracal::Md.render(markdown))).to eq(%w[Heading2 Heading3])
  end

  it 'makes the highest level in use Heading 1 with :auto' do
    expect(headings(Caracal::Md.render(markdown, heading_offset: :auto))).to eq(%w[Heading1 Heading2])
    expect(headings(Caracal::Md.render("# Title\n\n## Section\n", heading_offset: :auto))).to eq(%w[Heading1 Heading2])
    expect(headings(Caracal::Md.render("> ### Quoted\n\n#### Deeper\n", heading_offset: :auto))).to eq(%w[Heading1 Heading2])
  end

  it 'shifts every heading by an integer, clamped to 1 to 6' do
    expect(headings(Caracal::Md.render(markdown, heading_offset: -1))).to eq(%w[Heading1 Heading2])
    expect(headings(Caracal::Md.render(markdown, heading_offset: -2))).to eq(%w[Heading1 Heading1])
    expect(headings(Caracal::Md.render("# A\n\n##### E\n", heading_offset: 2))).to eq(%w[Heading3 Heading6])
  end

  it 'reads heading-offset from front matter, the option taking precedence' do
    expect(headings(Caracal::Md.render("---\nheading-offset: auto\n---\n#{markdown}"))).to eq(%w[Heading1 Heading2])
    expect(headings(Caracal::Md.render("---\nheading-offset: -1\n---\n#{markdown}"))).to eq(%w[Heading1 Heading2])
    expect(headings(Caracal::Md.render("---\nheading-offset: auto\n---\n#{markdown}", heading_offset: 0))).to eq(%w[Heading2 Heading3])
  end

  it 'ignores other values with a warning' do
    renderer = Caracal::Md::Renderer.new(heading_offset: 'up')
    expect(headings(renderer.render(markdown))).to eq(%w[Heading2 Heading3])
    expect(renderer.warnings).to eq(['heading offset "up" is ignored; it takes an integer or auto'])
  end

  it 'counts the shifted levels for toc_depth' do
    doc = document_xml(Caracal::Md.render("## A\n\n### B\n\n#### C\n", toc: true, toc_depth: 2, heading_offset: :auto))
    entries = doc.xpath('//w:p[w:pPr/w:pStyle]', NS).filter_map do |p|
      style = p.at_xpath('w:pPr/w:pStyle/@w:val', NS).value
      [style, p.at_xpath('.//w:hyperlink/w:r/w:t', NS).content] if style.match?(/\ATOC\d\z/)
    end
    expect(entries).to eq([%w[TOC1 A], %w[TOC2 B]])
  end

  it 'counts the shifted levels for chapter numbers' do
    md = "## One\n\n| a |\n|---|\n| 1 |\n\nTable: First {#tbl:a}\n\n## Two\n\n| b |\n|---|\n| 2 |\n\nTable: Second {#tbl:b}\n"
    doc = document_xml(Caracal::Md.render(md, number_captions: :chapter, heading_offset: :auto))
    captions = doc.xpath("//w:p[w:pPr/w:pStyle/@w:val='Caption']", NS).map { |p| p.xpath('.//w:t', NS).map(&:content).join }
    expect(captions).to eq(['Table 1.1: First', 'Table 2.1: Second'])
  end

  it 'works in #markdown' do
    docx = Caracal::Document.new
    docx.markdown markdown, heading_offset: :auto
    expect(headings(docx.render.string)).to eq(%w[Heading1 Heading2])
  end

  describe 'caracal-md --heading-offset' do
    it 'takes auto and integers' do
      expect(headings(cli(markdown, '--heading-offset', 'auto'))).to eq(%w[Heading1 Heading2])
      expect(headings(cli(markdown, '--heading-offset', '-1'))).to eq(%w[Heading1 Heading2])
    end
  end
end
