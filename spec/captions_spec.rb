RSpec.describe 'numbered captions and cross-references' do
  def render(markdown, **options)
    @renderer = Caracal::Md::Renderer.new(image_loader: ->(_) { png }, **options)
    @docx = @renderer.render(markdown)
    document_xml(@docx)
  end

  def paragraphs(doc, style)
    doc.xpath("//w:body//w:p[w:pPr/w:pStyle/@w:val='#{style}']", NS).map { |p| text_of(p) }
  end

  def text_of(node)
    node.xpath('.//w:t', NS).map(&:content).join
  end

  def instructions(doc)
    doc.xpath('//w:instrText', NS).map { |i| i.content.strip }
  end

  def paragraph_with(doc, text)
    doc.xpath('//w:body//w:p', NS).find { |p| text_of(p).include?(text) }
  end

  it 'leaves captions unnumbered by default' do
    doc = render(%(![A](a.png "One")\n\n| a |\n|---|\n| 1 |\n\nTable: Rev\n))
    expect(paragraphs(doc, 'Caption')).to eq(%w[One Rev])
    expect(instructions(doc).grep(/SEQ/)).to be_empty
  end

  it 'numbers every caption with number-captions, in document order' do
    doc = render(<<~MD)
      ---
      number-captions: true
      ---
      ![A](a.png "One")

      | a |
      |---|
      | 1 |

      Table: Rev

      ![B](a.png "Two")

      ![C](a.png)
    MD
    expect_well_formed(@docx)
    expect(paragraphs(doc, 'Caption')).to eq(['Figure 1: One', 'Table 1: Rev', 'Figure 2: Two'])
    expect(instructions(doc).grep(/SEQ/)).to eq(['SEQ Figure \* ARABIC', 'SEQ Table \* ARABIC', 'SEQ Figure \* ARABIC'])

    caption = paragraph_with(doc, 'Figure 1')
    bold = caption.xpath('w:r[w:rPr/w:b]/w:t', NS).map(&:content).join
    expect(bold).to eq('Figure 1:')
    expect(caption.at_xpath('w:bookmarkStart/@w:name', NS).value).to start_with('_Cap')
  end

  it 'puts a table caption above the table and describes the table with it' do
    doc = render(%(| a |\n|---|\n| 1 |\n\nTable: Rev\n), number_captions: true)
    caption = paragraph_with(doc, 'Table 1: Rev')
    expect(caption.next_element.name).to eq('tbl')
    expect(caption.at_xpath('w:pPr/w:keepNext', NS)).not_to be_nil
    expect(doc.at_xpath('//w:tblPr/w:tblCaption/@w:val', NS).value).to eq('Table 1: Rev')
  end

  it 'numbers figures and tables with an id without number-captions' do
    doc = render(<<~MD)
      ![A](a.png "With id"){: #fig-a}

      ![B](a.png "Without id")

      ![Alt text](a.png){#fig:b}

      | a |
      |---|
      | 1 |

      Table: Rev {#tbl:r}

      | b |
      |---|
      | 2 |
      {: #tbl-s}
    MD
    expect(paragraphs(doc, 'Caption')).to eq(['Figure 1: With id', 'Without id', 'Figure 2: Alt text', 'Table 1: Rev', 'Table 2'])
    expect(body_text(doc)).not_to include('{#')
    expect(doc.xpath('//w:bookmarkStart/@w:name', NS).map(&:value)).to include('fig_a', '_Nfig_a', 'fig_b', 'tbl_r', 'tbl_s')
  end

  it 'takes the id of a paragraph holding only the image' do
    doc = render(%(![A](a.png "One")\n{: #fig-p}\n\nSee [](#fig-p).))
    expect(paragraphs(doc, 'Caption')).to eq(['Figure 1: One'])
    expect(body_text(doc)).to include('See Figure 1.')
  end

  it 'turns empty internal links and pandoc-crossref references into REF fields' do
    doc = render(<<~MD)
      See [](#fig-b), @fig:c, [-@fig:c], [@fig:c; @tbl:r] and [the diagram](#fig-b).

      ![A](a.png "One")

      ![B](a.png "Two"){: #fig-b}

      ![C](a.png "Three"){#fig:c}

      | a |
      |---|
      | 1 |

      Table: Rev {#tbl:r}
    MD
    expect(text_of(paragraph_with(doc, 'See'))).to eq('See Figure 1, Figure 2, 2, Figure 2, Table 1 and the diagram.')
    expect(instructions(doc).grep(/REF/)).to eq(
      ['REF fig_b \h \* CHARFORMAT', 'REF fig_c \h \* CHARFORMAT', 'REF _Nfig_c \h \* CHARFORMAT',
       'REF fig_c \h \* CHARFORMAT', 'REF tbl_r \h \* CHARFORMAT']
    )
    expect(doc.at_xpath("//w:hyperlink[@w:anchor='fig_b']", NS)).not_to be_nil
    expect(@renderer.warnings).to be_empty
  end

  it "shows a heading's text for an empty link to it" do
    doc = render("# Getting started\n\nSee [](#getting-started).")
    expect(text_of(paragraph_with(doc, 'See'))).to eq('See Getting started.')
    expect(instructions(doc)).to include('REF getting_started \h \* CHARFORMAT')
  end

  it 'warns about references to unknown ids and keeps their text' do
    doc = render('See [](#nope), @fig:gone and [-@fig:gone].')
    expect(text_of(paragraph_with(doc, 'See'))).to eq('See #nope, @fig:gone and [-@fig:gone].')
    expect(@renderer.warnings).to include(/#nope/, /#fig:gone/)
  end

  it 'leaves other @ text alone' do
    doc = render('Mail me@fig:x or write @sec:intro.')
    expect(body_text(doc)).to eq('Mail me@fig:x or write @sec:intro.')
  end

  it 'numbers captions per chapter with number-captions: chapter' do
    doc = render(<<~MD)
      ---
      number-captions: chapter
      ---
      # One

      ![A](a.png "A")

      ![B](a.png "B")

      # Two

      ![C](a.png "C"){#fig:c}

      See [-@fig:c].
    MD
    expect(paragraphs(doc, 'Caption')).to eq(['Figure 1.1: A', 'Figure 1.2: B', 'Figure 2.1: C'])
    expect(instructions(doc).grep(/SEQ Figure/)).to eq(
      ['SEQ Figure \* ARABIC \r 1 \s 1', 'SEQ Figure \* ARABIC \s 1', 'SEQ Figure \* ARABIC \r 1 \s 1']
    )
    expect(body_text(doc)).to include('See 2.1.')

    heading = paragraph_with(doc, 'Two')
    expect(heading.xpath('.//w:instrText', NS).map { |i| i.content.strip }).to eq(['SEQ Chapter \h'])
    expect(heading.xpath('w:r[w:rPr/w:vanish]', NS).size).to eq(4)
  end

  it 'labels captions in the document language, or as given' do
    doc = render("---\nlang: de\nnumber-captions: true\n---\n![A](a.png \"Bild\")\n\n| a |\n|---|\n| 1 |\n\nTable: Werte\n")
    expect(paragraphs(doc, 'Caption')).to eq(['Abbildung 1: Bild', 'Tabelle 1: Werte'])

    doc = render(%(![A](a.png "Bild")), number_captions: true, figure_label: 'Abb.')
    expect(paragraphs(doc, 'Caption')).to eq(['Abb. 1: Bild'])
    expect(instructions(doc)).to include('SEQ Abb \* ARABIC')
  end

  it 'lists figures and tables, numbering every caption' do
    doc = render(<<~MD, lof: true)
      ![A](a.png "One")

      | a |
      |---|
      | 1 |

      Table: Rev

      <!-- list-of-tables -->
    MD
    expect(paragraphs(doc, 'TOCHeading')).to eq(['List of Figures', 'List of Tables'])
    expect(paragraphs(doc, 'TableofFigures')).to eq(['Figure 1: One#', 'Table 1: Rev#'])
    expect(instructions(doc)).to include('TOC \h \z \c "Figure"', 'TOC \h \z \c "Table"', 'PAGEREF _Cap1 \h')

    entry = doc.at_xpath("//w:p[w:pPr/w:pStyle/@w:val='TableofFigures']", NS)
    expect(entry.at_xpath('w:hyperlink/@w:anchor', NS).value).to eq('_Cap1')
    expect(entry.at_xpath('w:pPr/w:tabs/w:tab/@w:pos', NS).value).to eq('9026')
    expect(package(@docx).xml('word/settings.xml').at_xpath('//w:updateFields', NS)).not_to be_nil
  end

  it 'accepts \\listoffigures and keeps field begin and end balanced without captions' do
    doc = render("\\listoffigures\n\nNo figures.")
    expect(paragraphs(doc, 'TOCHeading')).to eq(['List of Figures'])
    types = doc.xpath('//w:fldChar/@w:fldCharType', NS).map(&:value)
    expect(types).to eq(%w[begin separate end])
  end

  it 'leaves #markdown output as it was' do
    docx = Caracal::Document.new
    docx.markdown "# Intro\n\nSee [](#intro) and @fig:a.\n\n<!-- list-of-figures -->"
    doc = document_xml(docx.render.string)
    expect(body_text(doc)).to eq('IntroSee #intro and @fig:a.')
    expect(docx.markdown_warnings).to include(/needs the Renderer/)
  end
end
