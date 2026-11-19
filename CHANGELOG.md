# Changelog

## 0.1.0 (unreleased)

First release.

* Markdown (GFM and kramdown) to DOCX through caracal 2: headings with bookmarks, inline formatting (`==highlight==` included), typographic quotes per language, lists with start numbers and task boxes, tables with alignment and captions, definition lists, images scaled to the page, highlighted code, GitHub alerts, page breaks, table of contents.
* Word footnotes.
* `link:` rewrites link targets or keeps a link's text alone; `--local-links text` does so for links to local files.
* Numbered captions for figures and tables (opt-in, per chapter on request), cross-references in kramdown (`[](#id)`) and pandoc-crossref (`@fig:id`) syntax, lists of figures and tables.
* Code handlers: fenced blocks (Graphviz, PlantUML, Mermaid, `$$` math, …) rendered to images by any callable, with `CommandHandler` for external programs and `--code-handler` on the command line; handler output is checked like an untrusted image.
* `code_cache:` (`--code-cache DIR`) keeps code handler and rasterizer output across renders, keyed by block and handler (`CommandHandler` with `version:`), with cached bytes checked like fresh ones.
* SVG images and SVG from code handlers, cleaned (allowlist, no external references, no DTD) and embedded as SVG with a PNG fallback from a pluggable `svg_rasterizer` (`--svg-rasterizer`), blank without one; `data:image/svg+xml` URIs. With caracal 2.0.0, the rasterizer's PNG alone.
* Default style set named after Word's built-in styles, and `--print-reference-doc` to restyle it in Word.
* Word templates (.docx, .dotx, .docm, .dotm): styles matched by name, `style_map`, content at `{{content}}`, `{{placeholders}}` from front matter.
* Lists styled *List Bullet* / *List Number* (2–5 for nested levels); with a template whose list styles carry numbering, lists take the template's bullets, numbers and indentation.
* Front matter for the title block, document properties, language and table of contents.
* `lang:` (`--lang`) sets the language of documents whose front matter names none.
* `heading_offset:` (front matter `heading-offset`, `--heading-offset`) shifts heading levels; `auto` makes the highest level in use Heading 1.
* `custom-style` attributes for paragraphs, spans and tables.
* `Caracal::Md.escape` for values interpolated into Markdown.
* `#markdown` on caracal documents, headers, footers and table cells.
* `caracal-md` command line tool.
