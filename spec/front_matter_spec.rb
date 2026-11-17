RSpec.describe Caracal::Md::FrontMatter do
  it 'splits YAML front matter from the body' do
    meta, body = described_class.split("---\ntitle: Hi\ntags: [a, b]\n---\n# Body\n")
    expect(meta).to eq('title' => 'Hi', 'tags' => %w[a b])
    expect(body).to eq("# Body\n")
  end

  it 'leaves a rule followed by a setext heading alone' do
    text = "---\nNot front matter\n---\n"
    expect(described_class.split(text)).to eq([{}, text])
  end

  it 'flattens values into plain text' do
    vars = described_class.to_variables('title' => '*Big* "deal"', 'author' => %w[A B], 'date' => Date.new(2026, 1, 2), 'lang' => 'de')
    expect(vars).to include('title' => 'Big „deal“', 'author' => 'A, B', 'date' => '2026-01-02')
  end
end
