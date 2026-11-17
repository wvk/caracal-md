RSpec.describe Caracal::Md::Parser do
  # [text, highlighted?] for every run of the body.
  def runs(markdown)
    renderer = Caracal::Md::Renderer.new
    doc = document_xml(renderer.render(markdown))
    @warnings = renderer.warnings
    doc.xpath('//w:body//w:r[w:t]', NS).map do |r|
      [r.xpath('w:t', NS).map(&:content).join, !r.at_xpath('w:rPr/w:highlight', NS).nil?]
    end
  end

  def highlighted(markdown)
    runs(markdown).select(&:last).map(&:first)
  end

  def text(markdown)
    runs(markdown).map(&:first).join
  end

  describe '==highlight==' do
    it 'highlights the text between the signs, brackets included, without a link warning' do
      md = "Due ==[date]==, and ==this== too.\n"
      expect(text(md)).to eq('Due [date], and this too.')
      expect(highlighted(md)).to eq(%w[[date] this])
      expect(@warnings).to be_empty
    end

    it 'highlights in yellow, as <mark> does' do
      doc = document_xml(Caracal::Md.render("==a== <mark>b</mark>\n"))
      expect(doc.xpath('//w:highlight/@w:val', NS).map(&:value)).to eq(%w[yellow yellow])
    end

    it 'keeps a == between spaces as text' do
      expect(runs("a == b == c\n")).to eq([['a == b == c', false]])
      expect(runs("x ==y == z\n")).to eq([['x ==y == z', false]])
    end

    it 'keeps an opening == without its partner as text' do
      expect(runs("==open only\n")).to eq([['==open only', false]])
      expect(runs("===b===\n")).to eq([['===b===', false]])
    end

    it 'keeps escaped signs as text' do
      expect(runs("\\==not==\n")).to eq([['==not==', false]])
    end

    it 'leaves code spans and code blocks alone' do
      expect(highlighted("`a ==b== c`\n")).to be_empty
      expect(text("`a ==b== c`\n")).to eq('a ==b== c')
      expect(text("```\n==x==\n```\n")).to eq('==x==')
      expect(highlighted("    ==x==\n")).to be_empty
    end

    it 'parses the text inside: formatting, code spans and links' do
      expect(highlighted("==**bold** `x==y`==\n")).to eq(['bold', ' ', 'x==y'])
      doc = document_xml(Caracal::Md.render("==[link](https://example.com/?q==1)==\n"))
      expect(doc.at_xpath('//w:hyperlink//w:highlight', NS)).not_to be_nil
    end

    it 'highlights within words and across a line break' do
      expect(runs("a==b==c\n")).to eq([['a', false], ['b', true], ['c', false]])
      expect(highlighted("==one\ntwo==\n")).to eq(['one two'])
    end

    it 'reads unmatched signs in linear time' do
      source  = "#{(['==a'] * 4000).join(' ')}\n"
      options = Kramdown::Options.merge({})
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      root, = described_class.parse(source, options)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
      expect(root.children.first.children.map(&:type)).to eq([:text])
    end

    it 'still warns about brackets without link definition outside a highlight' do
      runs("==[date]== [nope]\n")
      expect(@warnings).to eq(["No link definition for link ID 'nope' found on line 1"])
    end

    it 'reads front matter values as text without the signs' do
      vars = Caracal::Md::FrontMatter.to_variables('title' => 'Due ==soon==')
      expect(vars['title']).to eq('Due soon')
    end
  end
end
