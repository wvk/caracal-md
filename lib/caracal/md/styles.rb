module Caracal
  module Md
    # The default style set. The converter refers to styles by these ids only;
    # a Word template replaces them by name (see TemplateMerger), so every style
    # carries the name Word uses for its built-in counterpart where there is one.
    module Styles
      BODY_FONT    = 'Calibri'.freeze
      HEADING_FONT = 'Calibri'.freeze
      MONO_FONT    = 'Consolas'.freeze
      TEXT_COLOR   = '222222'.freeze
      ACCENT_COLOR = '1F4E79'.freeze
      MUTED_COLOR  = '595959'.freeze

      HEADING = { font: HEADING_FONT, color: ACCENT_COLOR, keep_next: true, keep_lines: true, line: 240, line_rule: :auto }.freeze

      DEFINITIONS = [
        { id: 'Normal',            name: 'Normal',             font: BODY_FONT, size: 22, color: TEXT_COLOR, line: 276, line_rule: :auto, top: 0, bottom: 160, default: true },
        { id: 'Title',             name: 'Title',              font: HEADING_FONT, size: 52, color: ACCENT_COLOR, bottom: 80, keep_next: true, line: 240, line_rule: :auto },
        { id: 'Subtitle',          name: 'Subtitle',           font: HEADING_FONT, size: 30, color: MUTED_COLOR, bottom: 240, keep_next: true },
        { id: 'Author',            name: 'Author',             size: 22, color: MUTED_COLOR, bottom: 0, keep_next: true },
        { id: 'Date',              name: 'Date',               size: 22, color: MUTED_COLOR, bottom: 240, keep_next: true },
        { id: 'Abstract',          name: 'Abstract',           size: 20, italic: true, indent_left: 567, indent_right: 567, bottom: 240 },
        HEADING.merge(id: 'Heading1', name: 'heading 1', size: 36, top: 480, bottom: 160),
        HEADING.merge(id: 'Heading2', name: 'heading 2', size: 30, top: 360, bottom: 120),
        HEADING.merge(id: 'Heading3', name: 'heading 3', size: 26, top: 280, bottom: 80, bold: true),
        HEADING.merge(id: 'Heading4', name: 'heading 4', size: 24, top: 240, bottom: 80, bold: true, italic: true),
        HEADING.merge(id: 'Heading5', name: 'heading 5', size: 22, top: 200, bottom: 60, bold: true, color: MUTED_COLOR),
        HEADING.merge(id: 'Heading6', name: 'heading 6', size: 22, top: 200, bottom: 60, italic: true, color: MUTED_COLOR),
        { id: 'Quote',             name: 'Quote',              italic: true, color: MUTED_COLOR, indent_left: 284, indent_right: 284,
                                   border_left: { color: 'BFBFBF', size: 18, spacing: 8 } },
        { id: 'SourceCode',        name: 'Source Code',        font: MONO_FONT, size: 19, color: TEXT_COLOR, line: 240, line_rule: :auto, top: 0, bottom: 160,
                                   bgcolor: 'F6F8FA', border_color: 'E1E4E8', border_size: 4, border_spacing: 4, word_wrap: true },
        { id: 'VerbatimChar',      name: 'Verbatim Char',      type: :character, font: MONO_FONT, color: '24292E', bgcolor: 'F0F0F0' },
        *{ 'AlertNote' => ['Note', '0969DA'], 'AlertTip' => ['Tip', '1A7F37'], 'AlertImportant' => ['Important', '8250DF'],
           'AlertWarning' => ['Warning', '9A6700'], 'AlertCaution' => ['Caution', 'CF222E'] }.map do |id, (name, color)|
          { id: id, name: name, indent_left: 284, bottom: 80, border_left: { color: color, size: 18, spacing: 8 } }
        end,
        { id: 'ListParagraph',     name: 'List Paragraph',     bottom: 60 },
        { id: 'TableText',         name: 'Table Text',         size: 20, top: 40, bottom: 40, line: 240, line_rule: :auto },
        { id: 'DefinitionTerm',    name: 'Definition Term',    bold: true, bottom: 0, keep_next: true },
        { id: 'Definition',        name: 'Definition',         indent_left: 567 },
        { id: 'Caption',           name: 'caption',            size: 18, italic: true, color: MUTED_COLOR, align: :center, top: 0, bottom: 240 },
        { id: 'FootnoteText',      name: 'footnote text',      size: 18, top: 0, bottom: 0, line: 240, line_rule: :auto },
        { id: 'FootnoteReference', name: 'footnote reference', type: :character, vertical_align: :superscript },
        { id: 'Hyperlink',         name: 'Hyperlink',          type: :character, color: '0563C1', underline: true },
        { id: 'TOCHeading',        name: 'TOC Heading',        font: HEADING_FONT, size: 30, color: ACCENT_COLOR, top: 240, bottom: 160 },
        *(1..6).map { |level| { id: "TOC#{level}", name: "toc #{level}", size: 22, top: 0, bottom: 60, indent_left: (level - 1) * 220, bold: level == 1 } },
      ].freeze

      TABLE_STYLE = {
        id: 'MarkdownTable', name: 'Markdown Table', type: :table,
        border_color: 'BFBFBF', border_size: 4, top: 60, bottom: 60, left: 100, right: 100,
        line: 240, line_rule: :auto, # caracal copies these onto every cell paragraph
      }.freeze

      TABLE_CONDITIONAL_FORMATS = [
        { type: :firstRow, bold: true, bgcolor: 'F2F2F2' },
      ].freeze

      # caracal gives every paragraph style a minimum line height of 18pt
      # unless it sets one; these styles follow Normal instead.
      LINE_SPACING = { line: 276, line_rule: :auto }.freeze

      # Every style id the converter may use.
      def self.ids
        DEFINITIONS.map { |d| d[:id] } + [TABLE_STYLE[:id]]
      end

      # Defines the style set on a caracal document. With only_missing, styles
      # the document already has are kept.
      def self.install(docx, only_missing: false)
        DEFINITIONS.each do |definition|
          next if only_missing and docx.find_style(definition[:id])

          definition = LINE_SPACING.merge(definition) unless definition[:type] == :character
          docx.style definition.dup
        end

        return if only_missing and docx.find_style(TABLE_STYLE[:id])

        docx.style TABLE_STYLE.dup do |style|
          TABLE_CONDITIONAL_FORMATS.each { |format| style.conditional_format format.dup }
        end
      end
    end
  end
end
