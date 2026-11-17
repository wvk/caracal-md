RSpec.describe Caracal::Md::Placeholders do
  let(:doc) do
    Nokogiri::XML(<<~XML)
      <w:document xmlns:w="#{Caracal::Md::Package::NS['w']}"><w:body>
        <w:p><w:r><w:t>Dear {{fir</w:t></w:r><w:r><w:t>st}} and {{ last }}, {{unknown}}</w:t></w:r></w:p>
      </w:body></w:document>
    XML
  end

  it 'replaces placeholders split across runs and keeps unknown ones' do
    described_class.replace(doc, 'first' => 'Ada', 'last' => 'Lovelace')
    texts = doc.xpath('//w:t', DocxHelpers::NS).map(&:content)
    expect(texts.join).to eq('Dear Ada and Lovelace, {{unknown}}')
    expect(texts.first).to eq('Dear Ada')
  end

  it 'lists the keys' do
    expect(described_class.keys(doc)).to eq(%w[first last unknown])
  end
end
