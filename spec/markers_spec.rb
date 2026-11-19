RSpec.describe Caracal::Md::Markers do
  let(:open)  { Caracal::Md::Markers::OPEN }
  let(:close) { Caracal::Md::Markers::CLOSE }

  def texts(docx)
    document_xml(docx).xpath('//w:body//w:p', NS).map { |p| p.xpath('.//w:t', NS).map(&:content).join }.reject(&:empty?)
  end

  describe 'typed into a document' do
    it "renders the issue's examples as text, every paragraph in place" do
      {
        "#{open}ref:1#{close}\n"                                                 => ["#{open}ref:1#{close}"],
        "Before\n\n#{open}fn-start:1#{close}\n\nSecret paragraph\n\nAfter\n"     => ['Before', "#{open}fn-start:1#{close}", 'Secret paragraph', 'After'],
        "#{open}ol-start:7#{close}\n\ntext\n"                                    => ["#{open}ol-start:7#{close}", 'text'],
        "#{open}caption-figure:1#{close}\n"                                      => ["#{open}caption-figure:1#{close}"],
        %(---\ntitle: "\\uE000ref:1\\uE001"\n---\nBody\n)                        => ["#{open}ref:1#{close}", 'Body'],
      }.each do |markdown, expected|
        docx = Caracal::Md.render(markdown)
        expect(texts(docx)).to eq(expected), markdown.inspect
        expect(document_xml(docx).xpath('//w:fldChar | //w:footnoteReference', NS)).to be_empty
        expect(package(docx).include?('word/footnotes.xml')).to be(false)
      end
    end

    it 'keeps markers in variables and in the text of fields as text' do
      template = TemplateBuilder.build
      docx = Caracal::Md.render("---\ntitle: T\n---\n![A](a.png \"#{open}caption-figure:0#{close}\"){: #fig-a}\n\nSee [](#fig-a).\n",
                                template: template, image_loader: ->(_) { png }, variables: { 'author' => "#{open}fn:1#{close}" })
      expect(texts(docx)).to include("Prepared by #{open}fn:1#{close}", "Figure 1: #{open}caption-figure:0#{close}", 'See Figure 1.')
      expect(document_xml(docx).xpath('//w:footnoteReference', NS)).to be_empty
    end

    it 'leaves the markers the converter writes working' do
      docx = Caracal::Md.render("3. three\n\nNote[^1]\n\n![A](a.png){: #fig-a}\n\nSee [](#fig-a).\n\n[^1]: The note.\n", image_loader: ->(_) { png })
      expect(texts(docx)).to eq(['three', 'Note', 'Figure 1: A', 'See Figure 1.'])
      expect(document_xml(docx).xpath('//w:footnoteReference', NS).size).to eq(1)
      expect(package(docx).xml('word/numbering.xml').xpath('//w:startOverride/@w:val', NS).map(&:value)).to include('3')
      expect(package(docx).xml('word/footnotes.xml').xpath('//w:footnote[@w:id="1"]//w:t', NS).map(&:content).join).to include('The note.')
      expect(package(docx)['word/document.xml'].dup.force_encoding('UTF-8')).not_to include(open)
    end
  end

  it 'differ from render to render, and parse only their own' do
    one = described_class.new
    two = described_class.new
    expect(one.prefix).not_to eq(two.prefix)
    expect(one.parse(one.marker('fn', 3))).to eq(['fn', 3])
    expect(two.parse(one.marker('fn', 3))).to be_nil
    expect(one.parse("x#{one.marker('fn', 3)}")).to be_nil
    expect("a #{one.marker('ref', 2)} b"[one.pattern, 1]).to eq('ref')
  end

  it 'are none in #markdown, which runs no PostProcessor' do
    docx = Caracal::Document.new
    docx.markdown "3. three\n4. four\n"
    expect(texts(docx.render.string)).to eq(%w[three four])
    expect(docx.markdown_warnings).to eq(['an ordered list starts at 1 instead of 3; Caracal::Md.render sets start numbers'])
  end
end
