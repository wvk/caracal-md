# Changelog

## 0.1.0 (unreleased)

First release.

* Markdown (GFM and kramdown) to DOCX through caracal 2: headings with bookmarks, inline formatting, typographic quotes per language, lists with start numbers and task boxes, tables with alignment and captions, definition lists, images scaled to the page, highlighted code, GitHub alerts, page breaks, table of contents.
* Word footnotes.
* Default style set named after Word's built-in styles, and `--print-reference-doc` to restyle it in Word.
* Word templates (.docx, .dotx, .docm, .dotm): styles matched by name, `style_map`, content at `{{content}}`, `{{placeholders}}` from front matter.
* Lists styled *List Bullet* / *List Number* (2–5 for nested levels); with a template whose list styles carry numbering, lists take the template's bullets, numbers and indentation.
* Front matter for the title block, document properties, language and table of contents.
* `custom-style` attributes for paragraphs, spans and tables.
* `#markdown` on caracal documents, headers, footers and table cells.
* `caracal-md` command line tool.
