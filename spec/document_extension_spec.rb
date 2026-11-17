RSpec.describe Caracal::Md::DocumentExtension do
  it 'adds Markdown to a caracal document, footnotes as a list' do
    docx = Caracal::Document.new
    docx.h1 'Report'
    docx.markdown "Some *text*.[^1]\n\n- a\n- b\n\n[^1]: A note."
    doc = document_xml(Caracal::Md::Package.read(docx.render.string).to_s)
    expect(body_text(doc)).to include('Report', 'Some text.1', 'A note.')
    expect(paragraph_styles(doc)).to include('FootnoteText')
    expect(docx.find_style('SourceCode')).not_to be_nil
  end

  it 'works in table cells' do
    cell = Caracal::Core::Models::TableCellModel.new { |c| c.markdown('**bold** cell') }
    docx = Caracal::Document.new
    docx.table [[cell]]
    doc = document_xml(docx.render.string)
    expect(doc.at_xpath('//w:tc//w:r[w:rPr/w:b]/w:t', DocxHelpers::NS).content).to eq('bold')
  end
end
