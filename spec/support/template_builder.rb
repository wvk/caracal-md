require 'caracal/md'

# Builds a Word template the way German Word saves one: localized style ids
# ("Standard", "berschrift1") with English built-in names, a template main
# part, existing numbering, and placeholders in the header and body.
module TemplateBuilder
  W = Caracal::Md::Package::NS['w']

  STYLE_IDS = {
    'Normal'    => 'Standard',
    'Heading1'  => 'berschrift1',
    'Heading2'  => 'berschrift2',
    'Title'     => 'Titel',
    'Hyperlink' => 'Hyperlink',
  }.freeze

  # German ids of List Bullet, List Bullet 2 and List Number with their
  # numbering, as Word writes it: List Bullet and List Bullet 2 share a
  # multi-level definition and name their level; List Number has a
  # definition of its own that links back to the style. There is no List
  # Bullet 3 or List Number 2.
  LIST_STYLES = {
    'Aufzhlungszeichen'  => ['List Bullet', '<w:ilvl w:val="0"/><w:numId w:val="90"/>'],
    'Aufzhlungszeichen2' => ['List Bullet 2', '<w:ilvl w:val="1"/><w:numId w:val="90"/>'],
    'Listennummer'       => ['List Number', '<w:numId w:val="91"/>'],
  }.freeze

  LIST_NUMBERING = <<~XML.freeze
    <w:abstractNum w:abstractNumId="90"><w:multiLevelType w:val="multilevel"/>
      <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:pStyle w:val="Aufzhlungszeichen"/><w:lvlText w:val="–"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="284" w:hanging="284"/></w:pPr></w:lvl>
      <w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:pStyle w:val="Aufzhlungszeichen2"/><w:lvlText w:val="▪"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="568" w:hanging="284"/></w:pPr></w:lvl>
    </w:abstractNum>
    <w:abstractNum w:abstractNumId="91"><w:multiLevelType w:val="singleLevel"/>
      <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:pStyle w:val="Listennummer"/><w:lvlText w:val="%1)"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="284" w:hanging="284"/></w:pPr></w:lvl>
    </w:abstractNum>
  XML

  def self.build(placeholder: true, footnotes: false, lists: false)
    docx = Caracal::Document.new
    docx.page_size width: 12240, height: 15840
    docx.page_margins left: 2000, right: 2000, top: 1440, bottom: 1440
    docx.style id: 'Normal', name: 'Normal', font: 'Georgia', size: 24, color: '000000', default: true
    docx.style id: 'Heading1', name: 'heading 1', font: 'Georgia', size: 40, color: 'C00000', bold: true
    docx.style id: 'Heading2', name: 'heading 2', font: 'Georgia', size: 32, color: 'C00000'
    docx.style id: 'Title', name: 'Title', font: 'Georgia', size: 64, color: 'C00000'
    docx.style id: 'Corporate', name: 'Corporate Quote', font: 'Georgia', italic: true, color: '7F7F7F'
    docx.header { p '{{title}} – {{author}}', align: :right }
    docx.footer { p 'Confidential' }
    docx.p '{{title}}', style: 'Title'
    docx.p 'Prepared by {{author}}'
    docx.ul { li 'template list' }
    docx.page
    docx.p '{{content}}' if placeholder
    docx.p 'Template closing paragraph'

    package = Caracal::Md::Package.read(docx.render.string)
    rename_styles(package)
    package.set_override('word/document.xml',
                         'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml')
    add_footnotes(package) if footnotes
    add_lists(package) if lists
    package
  end

  def self.add_lists(package)
    styles = package.xml('word/styles.xml')
    LIST_STYLES.each do |id, (name, num_pr)|
      styles.root.add_child(%(<w:style w:type="paragraph" w:styleId="#{id}"><w:name w:val="#{name}"/><w:basedOn w:val="Standard"/>) +
                            %(<w:pPr><w:numPr>#{num_pr}</w:numPr><w:spacing w:after="40"/></w:pPr></w:style>))
    end

    root = package.xml('word/numbering.xml').root
    root.at_xpath('w:num', 'w' => W).add_previous_sibling(root.parse(LIST_NUMBERING))
    root.add_child(root.parse(%(<w:num w:numId="90"><w:abstractNumId w:val="90"/></w:num><w:num w:numId="91"><w:abstractNumId w:val="91"/></w:num>)))
  end

  def self.rename_styles(package)
    package.entry_names.grep(/\Aword\/.*\.xml\z/).each do |part|
      doc = package.xml(part)
      doc.xpath('//w:style/@w:styleId | //w:pStyle/@w:val | //w:rStyle/@w:val | //w:basedOn/@w:val | //w:next/@w:val',
                'w' => W).each do |attr|
        attr.value = STYLE_IDS.fetch(attr.value, attr.value)
      end
    end
  end

  def self.add_footnotes(package)
    package['word/footnotes.xml'] = Caracal::Md::PostProcessor::FOOTNOTES_XML.sub(
      '</w:footnotes>', %(<w:footnote w:id="1"><w:p><w:r><w:t>existing</w:t></w:r></w:p></w:footnote></w:footnotes>)
    )
    package.add_relationship('word/document.xml', Caracal::Md::Package::REL_TYPES[:footnotes], 'footnotes.xml')
    package.set_override('word/footnotes.xml', Caracal::Md::Package::CONTENT_TYPES[:footnotes])
  end
end
