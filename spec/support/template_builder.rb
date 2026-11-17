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

  def self.build(placeholder: true, footnotes: false)
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
    package
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
