RSpec.describe 'HTML input' do
  def render(source, **options)
    @renderer = Caracal::Md::Renderer.new(image_loader: ->(src) { png unless src.include?('missing') }, **options)
    @docx = @renderer.render(source)
    document_xml(@docx)
  end

  # Paragraphs and tables of the body: style, list level and runs (text and
  # formatting, neighbours with the same formatting joined), header rows,
  # and the targets of hyperlinks.
  def structure(docx)
    pkg = package(docx)
    doc = pkg.xml('word/document.xml')
    blocks = doc.xpath('//w:body/w:p | //w:body/w:tbl', NS).map do |node|
      if node.name == 'tbl'
        [:table, node.xpath('w:tr[w:trPr/w:tblHeader]', NS).size, node.xpath('w:tr', NS).map { |tr| tr.xpath('w:tc', NS).map { |tc| runs(tc) } }]
      else
        [node.at_xpath('w:pPr/w:pStyle/@w:val', NS)&.value, node.at_xpath('w:pPr/w:numPr/w:ilvl/@w:val', NS)&.value, runs(node)]
      end
    end
    links = doc.xpath('//w:hyperlink/@r:id', NS).map { |id| pkg.relationship('word/document.xml', id.value)[:target] }
    [blocks, links]
  end

  def runs(node)
    node.xpath('.//w:r[w:t or w:br]', NS).map do |r|
      format = r.xpath('w:rPr/*', NS).map { |el| [el.name, el['w:val']].compact.join('=') }.sort
      [r.at_xpath('w:br', NS) ? "\n" : r.xpath('w:t', NS).map(&:content).join, format]
    end.chunk_while { |a, b| a[1] == b[1] }.map { |chunk| [chunk.map(&:first).join, chunk.first[1]] }
  end

  def texts(doc)
    doc.xpath('//w:body/w:p', NS).map { |p| p.xpath('.//w:t', NS).map(&:content).join }.reject(&:empty?)
  end

  def expect_like_markdown(html, markdown, **options)
    expected = structure(Caracal::Md.render(markdown, **options))
    renderer = Caracal::Md::Renderer.new(input: :html, **options)
    expect(structure(renderer.render(html))).to eq(expected)
    expect(renderer.warnings).to be_empty
  end

  it 'renders Trix-like markup like the equivalent Markdown' do
    html = <<~HTML
      <div class="trix-content">
        <h1>Report</h1>
        <div>First <strong>bold</strong>, <em>italic</em>, <del>gone</del> and <a href="https://example.com/?a=1&amp;b=2">a link</a>.<br>Second line<br><br>Next paragraph<br></div>
        <ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul>
        <ol><li>First</li><li>Second</li></ol>
        <blockquote>Quoted<br><br>Again</blockquote>
        <pre>code line 1
        code line 2</pre>
      </div>
    HTML
    markdown = <<~MD
      # Report

      First **bold**, *italic*, ~~gone~~ and [a link](https://example.com/?a=1&b=2).\\\\
      Second line

      Next paragraph

      - One
      - Two
        - Nested

      1. First
      2. Second

      > Quoted
      >
      > Again

      ```
      code line 1
        code line 2
      ```
    MD
    expect_like_markdown(html, markdown)
  end

  it 'renders Tiptap-like markup like the equivalent Markdown' do
    html = <<~HTML
      <h2>Title</h2>
      <p>Text with <mark>highlight</mark>, <u>under</u>, <s>strike</s>, <code>code</code>, H<sub>2</sub>O and x<sup>2</sup>.<br>Hard break</p>
      <p></p>
      <ul><li><p>Item</p></li><li><p>Item two</p><ul><li><p>Deeper</p></li></ul></li></ul>
      <ol start="4"><li><p>Four</p></li><li><p>Five</p></li></ol>
      <table><tbody><tr><th colspan="1" rowspan="1"><p>Name</p></th><th><p>Value</p></th></tr><tr><td><p>a</p></td><td><p>1</p><p>2</p></td></tr></tbody></table>
      <blockquote><p>Quote</p></blockquote>
      <hr>
      <pre><code class="language-ruby">puts 1</code></pre>
      <ul data-type="taskList"><li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Done</p></div></li></ul>
    HTML
    markdown = <<~MD
      ## Title

      Text with ==highlight==, <u>under</u>, ~~strike~~, `code`, H<sub>2</sub>O and x<sup>2</sup>.\\\\
      Hard break

      - Item
      - Item two
        - Deeper

      4. Four
      5. Five

      | Name | Value |
      |------|-------|
      | a | 1<br>2 |

      > Quote

      ---

      ```ruby
      puts 1
      ```

      - [x] Done
    MD
    expect_like_markdown(html, markdown)
  end

  it 'joins a task checkbox to the paragraph after it, and nothing else' do
    doc = render(%(<ul><li><input type="checkbox"><p>Task</p></li><li><p>input</p><p>more</p></li></ul>), input: :html)
    expect(texts(doc)).to eq(['☐ Task', 'inputmore'])
    expect(doc.xpath('//w:body/w:p[2]//w:br', NS).size).to eq(2)
  end

  it 'keeps text that reads as Markdown as it is' do
    doc = render('Loose *text* <p># not a heading</p><p>1. no list, [no](link), ==no== highlight</p>', input: :html)
    expect(texts(doc)).to eq(['Loose *text*', '# not a heading', '1. no list, [no](link), ==no== highlight'])
  end

  it 'captions a figure from its figcaption, numbered with an id' do
    doc = render(%(<figure><img src="a.png" alt="Plan"><figcaption>The <b>site</b> plan</figcaption></figure>), input: :html)
    expect(doc.xpath('//w:drawing', NS).size).to eq(1)
    expect(texts(doc)).to eq(['The site plan'])

    html = %(<figure id="fig-plan"><img src="a.png"><figcaption>Plan</figcaption></figure><p>See <a href="#fig-plan"></a>.</p>)
    expect(texts(render(html, input: :html))).to eq(['Figure 1: Plan', 'See Figure 1.'])
  end

  it 'captions images in Action Text attachments' do
    html = <<~HTML
      <div class="trix-content"><div>Look:</div><action-text-attachment sgid="x" content-type="image/png" filename="a.png"><figure class="attachment attachment--preview"><img src="/rails/active_storage/blobs/a.png" width="300" height="200"><figcaption class="attachment__caption">Site plan</figcaption></figure></action-text-attachment></div>
    HTML
    doc = render(html, input: :html)
    expect(texts(doc)).to eq(['Look:', 'Site plan'])
    expect(doc.at_xpath('//wp:extent/@cx', NS).value.to_i).to eq(225 * 12_700) # 300 px
  end

  it 'captions tables from caption and figcaption, and shows other figures as they are' do
    html = %(<table id="tbl-a"><caption>Values</caption><tr><th>A</th></tr><tr><td>1</td></tr></table>) +
           %(<figure><table><tr><td>x</td></tr></table><figcaption>Second</figcaption></figure>) +
           %(<figure><p>Text</p><img src="a.png"><figcaption>Mixed</figcaption></figure>)
    doc = render(html, input: :html, number_captions: true)
    expect(doc.xpath("//w:body/w:p[w:pPr/w:pStyle/@w:val='Caption']", NS).map { |p| p.xpath('.//w:t', NS).map(&:content).join })
      .to eq(['Table 1: Values', 'Table 2: Second'])
    expect(texts(doc)).to include('Text', 'Mixed')
  end

  it 'makes header rows of thead or leading th rows, and pads colspan' do
    doc = render(%(<table><tr><th>A</th><th>B</th></tr><tr><td colspan="2">wide</td></tr><tr><th>Row</th><td>1</td></tr></table>), input: :html)
    rows = doc.xpath('//w:tbl/w:tr', NS)
    expect(rows.map { |tr| tr.xpath('w:tc', NS).size }).to eq([2, 2, 2])
    expect(rows.map { |tr| tr.at_xpath('w:trPr/w:tblHeader', NS) ? :head : :body }).to eq(%i[head body body])
    expect(rows.last.at_xpath('w:tc[1]//w:r[w:rPr/w:b]/w:t', NS).content).to eq('Row')
  end

  it 'drops the contents of script, style, template and head' do
    html = %(<!DOCTYPE html><html><head><title>Mail</title><style>p { color: red }</style></head>) +
           %(<body><p>Hello<script>alert(1)</script></p><style>.x {}</style><template><p>Hidden</p></template></body></html>)
    expect(texts(render(html, input: :html))).to eq(['Hello'])
  end

  it 'keeps the text of other elements' do
    html = %(<p><font color="red">font</font> <span>span</span> <a name="x">anchor</a> <abbr title="x">abbr</abbr></p><custom-box>custom</custom-box>)
    expect(texts(render(html, input: :html))).to eq(['font span anchor abbr', 'custom'])
    expect(@renderer.warnings).to be_empty
  end

  it 'nests lists given without li, and starts ordered lists at start' do
    doc = render(%(<ol start="3"><li>c</li><ul><li>stray</li></ul></ol>), input: :html)
    expect(paragraph_styles(doc)).to eq(%w[ListNumber ListBullet2])
    expect(texts(doc)).to eq(%w[c stray])
    num_id = doc.at_xpath('//w:numPr/w:numId/@w:val', NS).value
    numbering = package(@docx).xml('word/numbering.xml')
    expect(numbering.at_xpath("//w:num[@w:numId='#{num_id}']//w:startOverride/@w:val", NS).value).to eq('3')
  end

  it 'loads images with the rules of Markdown images' do
    doc = render(%(<p><img src="missing.png" alt="gone"> and <img src="a.png" width="60" title="T"></p>), input: :html)
    expect(texts(doc)).to eq(['gone and', 'T'])
    expect(@renderer.warnings).to eq(['missing.png: image not loaded'])
  end

  it 'hands pre blocks with a language to code handlers' do
    seen = nil
    handler = lambda { |block| seen = block; png }
    html = %(<pre id="fig-g" title="Graph" data-theme="dark"><code class="language-dot">a -&gt; b</code></pre>)
    doc = render(html, input: :html, code_handlers: { 'dot' => handler })
    expect(seen.to_h).to eq(language: 'dot', source: 'a -> b', attributes: { 'id' => 'fig-g', 'title' => 'Graph', 'data-theme' => 'dark' })
    expect(texts(doc)).to eq(['Figure 1: Graph'])
  end

  it 'spells no markers, and fills written placeholders as Markdown does' do
    open, close = Caracal::Md::Converter::MARKER_OPEN, Caracal::Md::Converter::MARKER_CLOSE
    html = %(<p>#{open}ref:1#{close}</p><p>&#57344;fn-start:1&#57345;</p><p>Secret</p>) +
           %(<p><a href="#x" title="#{open}">a</a> <code>#{open}char:123#{close}</code></p><p>{{title}} &#123;&#123;title}}</p>)
    doc = render("#{html}", input: :html, template: TemplateBuilder.build, variables: { 'title' => 'Offer' })
    expect(texts(doc)).to include("\u{FFFD}ref:1\u{FFFD}", "\u{FFFD}fn-start:1\u{FFFD}", 'Secret', "a \u{FFFD}char:123\u{FFFD}", 'Offer Offer')
    expect(doc.to_xml).not_to include(open, close)
  end

  it 'refuses HTML nested deeper than 256 levels' do
    expect { render(('<div>' * 300) + 'x', input: :html) }.to raise_error(Caracal::Md::Error, /depth/)
  end

  it 'takes :markdown and :html only' do
    expect { Caracal::Md::Renderer.new(input: :rtf) }.to raise_error(ArgumentError, /neither :markdown nor :html/)
    expect(texts(render('<p>x</p>', input: 'HTML'))).to eq(['x'])
  end

  it 'works in #markdown' do
    docx = Caracal::Document.new
    docx.markdown '<p><strong>bold</strong> cell</p><ul><li>item</li></ul>', input: :html
    doc = document_xml(docx.render.string)
    expect(doc.at_xpath('//w:r[w:rPr/w:b]/w:t', NS).content).to eq('bold')
    expect(paragraph_styles(doc)).to eq(%w[Normal ListBullet])
  end

  it 'converts .html files' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'post.html')
      File.write(path, '<h1>Post</h1><p>Body</p>')
      Caracal::Md.convert_file(path)
      expect(paragraph_styles(document_xml(File.binread(File.join(dir, 'post.docx'))))).to eq(%w[Heading1 Normal])
    end
  end

  describe 'caracal-md' do
    it 'reads .html files as HTML, and others with --input html' do
      expect(paragraph_styles(document_xml(cli('<h1>Post</h1>', file: 'post.html')))).to eq(%w[Heading1])
      expect(paragraph_styles(document_xml(cli('<h1>Post</h1>', '--input', 'html', file: 'post.md')))).to eq(%w[Heading1])
    end
  end
end
