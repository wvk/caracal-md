# caracal-md

Markdown in, Word out. caracal-md parses Markdown with [kramdown](https://kramdown.gettalong.org/) (GitHub-flavoured, plus kramdown's extensions) and builds the document with [caracal](https://github.com/wvk/caracal) 2. The result uses either the built-in style set or **your own Word template**: its styles, page setup, headers, footers and, optionally, a cover page around the content.

```ruby
require 'caracal/md'

Caracal::Md.convert_file 'notes.md'                                  # => notes.docx, default styles
Caracal::Md.convert_file 'notes.md', 'notes.docx', template: 'corporate.dotx'

docx = Caracal::Md.render(markdown, template: 'corporate.dotx')       # => DOCX bytes
```

```sh
caracal-md notes.md                         # writes notes.docx
caracal-md notes.md -t corporate.dotx -o report.docx --toc
caracal-md --print-reference-doc reference.docx
```

[README.docx](README.docx) is this file after `caracal-md README.md`.


## Installation

caracal-md needs Ruby 3.3 or later. caracal 2 is installed from GitHub, so add both to your Gemfile:

```ruby
gem 'caracal', github: 'wvk/caracal', tag: 'v2.0.0'
gem 'caracal-md', github: 'wvk/caracal-md'
gem 'rouge' # optional: syntax highlighting of fenced code
```

SVG images need caracal's `master` (`branch: 'master'` in place of the tag) until its next release; with 2.0.0 they need a rasterizer, see [SVG](#svg).


## What converts to what

| Markdown | Word |
|---|---|
| `# Heading` … `######` | Heading 1–6, with a bookmark so `[link](#heading)` jumps there |
| paragraphs, `**strong**`, `*em*`, `~~strike~~`, `==highlight==`, `` `code` `` | Normal, bold, italic, strikethrough, highlight, *Verbatim Char* |
| `<sup>`, `<sub>`, `<u>`, `<mark>`, `<kbd>` | superscript, subscript, underline, highlight, *Verbatim Char* |
| links, autolinks | hyperlinks (*Hyperlink*); `javascript:` and other unknown schemes stay text; see [Links](#links) |
| `"quotes"`, `--`, `...` | typographic quotes (English, German or French), dashes, ellipsis |
| `> quote` | *Quote* |
| `> [!NOTE]` … `> [!CAUTION]` (GitHub alerts) | *Note*, *Tip*, *Important*, *Warning*, *Caution*, with a label |
| fenced and indented code | *Source Code*, highlighted by Rouge when installed |
| ```` ```dot ````, ```` ```mermaid ````, … with a code handler | an image rendered from the block (see [Diagrams](#diagrams)) |
| lists, nested lists, `3.` start numbers, `- [ ]` tasks | *List Bullet*, *List Number*, *List Bullet 2* … *5* and *List Number 2* … *5* for nested levels (*List Paragraph* below), with Word numbering; ☐ / ☒ |
| GFM tables with alignment, `Table: caption` after the table | *Markdown Table* with a repeating header row, *Table Text* |
| definition lists (kramdown) | *Definition Term*, *Definition* |
| `![alt](img.png "Title")` | the image, scaled to the text width, with the title as *caption*; PNG, JPEG, GIF and SVG (see [SVG](#svg)) |
| `![alt](img.png){: width="50%"}` | width/height in `%`, `px`, `pt`, `cm`, `mm`, `in` |
| `{: #fig-x}` or `{#fig:x}` after an image, `{: #tbl-x}` under a table, `Table: caption {#tbl:x}` | numbered caption: **Figure 1:** caption (see below) |
| `[](#id)`, `@fig:x`, `[@fig:x; @tbl:y]`, `[-@fig:x]` | cross-reference: *Figure 1*, a heading's text, or the number alone |
| footnotes `[^1]` | real Word footnotes (*footnote text*, *footnote reference*) |
| `---` | horizontal rule |
| `{: custom-style="Name"}` after a block or span | the paragraph, character or table style *Name* |
| `<!-- pagebreak -->`, `\newpage` | page break |
| `<!-- toc -->`, `[TOC]`, `[[_TOC_]]`, or `toc: true` | table of contents (Word fills in page numbers on open) |
| `<!-- list-of-figures -->`, `\listoffigures`, or `lof: true`; the same for tables with `list-of-tables`, `\listoftables`, `lot: true` | list of figures or tables (*table of figures*) |
| `$$math$$` | the TeX source as code |
| ```` ```{=openxml} ```` | passed through as raw OOXML, only with `allow_raw_openxml: true` |

Front matter feeds the title block, document properties, template placeholders and some options:

```yaml
---
title: Quarterly *Report*
subtitle: Q3 2026
author: [Ada Lovelace, Grace Hopper]
date: 2026-11-17
abstract: |
  One paragraph or more, in Markdown.
lang: de          # German quotes, spelling language de-DE, "Inhalt" as TOC title
toc: true
toc-depth: 2
toc-title: Inhalt
heading-offset: auto    # the highest heading level in use becomes Heading 1, e.g. ## when # is the title
number-captions: true   # every caption numbered; "chapter" numbers per level-1 heading
lof: true               # list of figures after the table of contents
---
```


## Numbered captions and cross-references

Captions are numbered the way Word numbers them, with fields: **Figure 1:** caption below an image, **Table 1:** caption above a table. Figures and tables with an id get a number; `number-captions: true` numbers every caption, and `number-captions: chapter` restarts the count at each level-1 heading (**Figure 2.1:**). Labels follow `lang` (Figure/Table, Abbildung/Tabelle, …) unless `figure-label:` and `table-label:` name others.

```markdown
![Architecture](arch.png "System architecture"){: #fig-arch}

See [](#fig-arch) and @tbl:revenue.

| Quarter | Revenue |
|---------|--------:|
| Q1      |      10 |

Table: Revenue by quarter {#tbl:revenue}
```

The paragraph reads "See Figure 1 and Table 1." Both kramdown and pandoc-crossref syntax work:

* An image takes an id from `{: #fig-arch}` right after it or on the line below, or from pandoc's `{#fig:arch}`; a pandoc figure without title takes its caption from the alt text. A table takes `{: #tbl-x}` on the line below it, or `{#tbl:x}` at the end of its caption.
* A link without text, `[](#id)`, shows the label and number, or a heading's text. `@fig:id`, `[@fig:id]` and `[@fig:a; @tbl:b]` do the same; `[-@fig:id]` shows the number alone. A link with text, `[the diagram](#fig-arch)`, stays a link.
* References are `REF` fields with their text filled in; Word updates them with the other fields.
* `<!-- list-of-figures -->` or `lof: true` (placed after the table of contents) adds Word's table of figures, `<!-- list-of-tables -->` or `lot: true` the list of tables. Either numbers every caption, and Word fills in the page numbers on open.


## Links

Links to local files, such as `[the tiers](tiers.md)` in notes from a wiki or an Obsidian vault, become hyperlinks with relative targets, which lead nowhere once the document travels. `link:` receives each link's target and returns the target to use, or `nil` to keep only the link's text:

```ruby
# links with a scheme (https:, mailto:, …) and in-document anchors stay, local files become text
Caracal::Md.render(markdown, link: ->(href) { href.match?(/\A([a-z][a-z0-9+.-]*:|#)/i) ? href : nil })

# notes point to the wiki
Caracal::Md.render(markdown, link: ->(href) { href.end_with?('.md') ? "https://wiki.example.com/#{href.delete_suffix('.md')}" : href })
```

```sh
caracal-md notes.md --local-links text      # the first of the two
```

The targets it returns pass the same checks as the document's own: `javascript:` and other unknown schemes stay text. Cross-references (`[](#id)`, `@fig:id`) stay cross-references.


## Values in Markdown

Markdown built from data, in ERB views or string templates, interpolates values such as names and comments, and Markdown syntax inside them takes effect: emphasis, links, images read from `base_dir`, footnotes, HTML, the template's `{{placeholders}}`. `Caracal::Md.escape` returns Markdown that renders as the value itself:

```ruby
markdown = <<~MD
  # Offer for #{Caracal::Md.escape(customer.name)}

  | Item | Note |
  |------|------|
  #{items.map { |item| "| #{Caracal::Md.escape(item.name)} | #{Caracal::Md.escape(item.note)} |" }.join("\n")}
MD
Caracal::Md.render(markdown, template: 'offer.dotx')
```

Line breaks in the value become line breaks in the document (`<br>`), so the escaped value is one line of Markdown and fits paragraphs, list items, table cells and headings alike. Inside code spans, fenced code, image titles and alt texts it shows its escapes. It writes braces as `&#123;`, which stay braces through the template merge; `{{key}}` written in the Markdown itself is filled as before. U+E000 and U+E001, two private-use characters that caracal-md keeps for its own markers, come out as U+FFFD.

Front matter is YAML, where `:`, `#`, `[`, `{`, `@` and words such as `yes` have a meaning of their own. Write an escaped value there as a JSON string (`to_json`, from Ruby's `json`), which YAML reads as a quoted scalar:

```ruby
front_matter = "---\ntitle: #{Caracal::Md.escape(report.title).to_json}\n---\n"
```


## Diagrams

A code handler turns a fenced block into an image: a Graphviz, PlantUML or Mermaid diagram, a formula, anything a program or a service can render. Handlers are keyed by the fence's language; `math` also receives `$$` blocks.

```ruby
Caracal::Md.render(markdown, code_handlers: {
  'dot'      => Caracal::Md::CommandHandler.new(%w[dot -Tpng]),
  'plantuml' => Caracal::Md::CommandHandler.new('plantuml -tpng -pipe', timeout: 60),
  'mermaid'  => ->(block) { MyDiagramService.png(block.source) },
})
```

```sh
caracal-md notes.md --code-handler 'dot=dot -Tpng' --code-handler 'plantuml=plantuml -tpng -pipe'
```

The image takes the place of the block, like a Markdown image. Attributes on the line after the fence give it an id, a caption (`title`), alt text and a size:

````markdown
```dot
digraph { Markdown -> caracal -> Word }
```
{: #fig-pipeline title="From Markdown to Word" width="60%"}
````

A handler is anything that responds to `call(block)` and returns PNG, JPEG, GIF or SVG bytes (SVG goes through the [SVG](#svg) path). `block` is a `Caracal::Md::CodeBlock` with `language`, `source` and `attributes` (every attribute of the block as a String, so a handler can read its own, e.g. `theme="dark"`). `CommandHandler` is one such handler: it runs a program with the source on stdin and reads the image from stdout. Handlers for rendering services or other tools can come from any gem.

**Untrusted documents.** Source and attributes come from whoever wrote the Markdown, and what a handler returns counts as untrusted, like an image from the web:

* Only a non-empty String of at most 20 MB holding a PNG, JPEG or GIF with readable dimensions, or an SVG, gets any further; SVG is then cleaned (see [SVG](#svg)). Anything else, an exception included, leaves the block as code and adds a warning.
* At most 50 blocks run per document, and identical blocks run once. `Caracal::Md::CodeHandlers.new(handlers, max_calls: 50, max_bytes: 20 * 1024 * 1024)` sets other limits; pass it as `code_handlers:`.
* `CommandHandler` takes the command as an argument list and never starts a shell; the source reaches the program on stdin only. The program runs in an empty temporary directory and in a process group of its own, which is killed when the program ends, after `timeout:` (30 seconds) or beyond `max_bytes:` of output.
* Diagram tools read files. Graphviz embeds any image the process can read when a node says `image="/path/to/file.png"`, and Graphviz 14 has no setting against it; PlantUML has `!include`; mermaid-cli runs a headless browser. The empty working directory stops relative paths only. For untrusted Markdown, run the tool in a sandbox, e.g. bubblewrap on Linux; this command (tested with Graphviz 14 on Debian) gives `dot` read-only system files and no network, home or project files:

```sh
caracal-md notes.md --code-handler 'dot=bwrap --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/bin /bin --ro-bind /etc/fonts /etc/fonts --proc /proc --dev /dev --tmpfs /tmp --unshare-all --die-with-parent --new-session dot -Tpng'
```


## SVG

SVG images (`![plan](plan.svg)`, `data:image/svg+xml` URIs) and SVG from code handlers (e.g. `dot -Tsvg`) go into the document as SVG, cleaned, at the size the SVG declares. Word 2016 and later and LibreOffice show the SVG; older Word and other readers show a PNG fallback, which an SVG rasterizer makes. Without a rasterizer the fallback is blank.

With caracal 2.0.0, which embeds no SVG (SVG support came after it), SVG goes in as the rasterizer's PNG alone; without a rasterizer it shows as its alt text (code blocks as code), with a warning.

```ruby
inkscape = 'inkscape --pipe --export-type=png --export-filename=- --export-dpi=192'
Caracal::Md.render(markdown, svg_rasterizer: Caracal::Md::CommandHandler.new(inkscape))
```

```sh
caracal-md notes.md --svg-rasterizer 'inkscape --pipe --export-type=png --export-filename=- --export-dpi=192'
```

A rasterizer is a code handler for the language `svg`: it receives a `CodeBlock` whose `source` is the cleaned SVG and returns PNG, JPEG or GIF bytes, checked like any handler's output. When it fails, the fallback is blank and a warning says so.

**Cleaning.** Every SVG is cleaned before it goes into the document or to the rasterizer, because SVG renderers follow references: Inkscape, given `<image xlink:href="file:///…">`, draws whatever local image that names (tested with Inkscape 1.4). caracal-md parses the SVG without DTD, entities or network access and keeps an allowlist of SVG elements and attributes:

* removed: scripts, event handlers (`onclick` …), `foreignObject`, animation (`set`, `animate` …), processing instructions, comments, elements and attributes of other namespaces (editor data), `xml:base`;
* references: only `#id` and inline PNG, JPEG or GIF (`data:image/png;base64,…`) stay; `http:`, `file:`, `javascript:`, relative paths and other data are removed, and `use`, `image`, `feImage` and `textPath` without a reference with them;
* CSS: `style` elements and declarations that load anything (`url()` other than `url(#id)`, `@import`, `image-set()`, escapes) are removed;
* refused, the image then showing as alt text: entity declarations or an internal DTD, malformed XML or another root element than `svg`, more than 100,000 nodes, reference cycles, and `<use>` trees that expand beyond a million nodes.

The warnings name what was removed. Run the rasterizer in a sandbox all the same (see [Diagrams](#diagrams)): the cleaning keeps it from reading files through the SVG, not from its own bugs.


## Templates

Pass any `.docx`, `.dotx`, `.docm` or `.dotm` as `template:` (a path, an IO, the bytes or a `Caracal::Md::Template`). The output keeps the template's styles, theme, fonts, settings, numbering, headers, footers and page setup; caracal-md fills in the body.

**Styles are matched by name.** Word saves localized style ids (German Word writes `berschrift1` for *heading 1* and `Standard` for *Normal*) but keeps the English names of built-in styles, so a German template works without configuration. Styles the template lacks (e.g. *Source Code*) come from the default set, based on the template's own *Normal*. To use a different template style, map it:

```ruby
Caracal::Md.render(markdown, template: 'corporate.dotx',
                   style_map: { 'Quote' => 'Intense Quote', 'MarkdownTable' => 'Grid Table 4 Accent 1' })
```

```sh
caracal-md notes.md -t corporate.dotx -s "Quote=Intense Quote" -s "MarkdownTable=Grid Table 4 Accent 1"
```

Keys are the style ids or names in the table above; values are style names or ids in the template.

**Lists.** Where the template gives *List Bullet*, *List Number* and their nested-level styles (*List Bullet 2* … *5*, *List Number 2* … *5*) a bullet or number, lists take the template's bullets, numbers and indentation, and every numbered list starts at its own first number. Levels without such a style keep caracal-md's numbering. Corporate list styles with other names work through the style map, e.g. `style_map: { 'List Bullet' => 'Aufzählung' }`. In Word, a style gets its numbering under Modify Style → Format → Numbering.

**Where the content goes.** A paragraph reading `{{content}}` (configurable with `placeholder:`) receives the content, and everything else in the template body stays, e.g. a cover page and a closing page. Without that paragraph the content replaces the template's body.

**Placeholders.** `{{title}}`, `{{author}}`, `{{date}}` and any other front matter key are replaced in the template body, headers and footers, also where Word has split the text across several runs, and in the Markdown content; values escaped with `Caracal::Md.escape` keep their braces. `variables: { 'client' => 'ACME' }` (or `--var client=ACME`) adds more. When the template shows `{{title}}`, caracal-md leaves out its own title block.

**Making a template.** `caracal-md --print-reference-doc reference.docx` writes a document using every style of the default set. Change the styles (and page setup, headers, footers) in Word, save it as a template and pass it back.


## Options

| Option | Default | |
|---|---|---|
| `template:` | none | Word template, see above |
| `style_map:` | `{}` | style id or name ⇒ template style name or id |
| `placeholder:` | `'{{content}}'` | template paragraph that receives the content |
| `variables:` | `{}` | extra placeholder values |
| `lang:` | none | language of documents whose front matter names none (`'de'`, `'de-CH'`, `I18n.locale`): quotes, caption labels, list and TOC titles, spelling language; front matter `lang` wins |
| `base_dir:` | `Dir.pwd` | relative image paths resolve here (`convert_file`: the file's directory) |
| `image_loader:` | built in | `->(src) { bytes or nil }`, e.g. for ActiveStorage |
| `allow_remote_images:` | `false` | fetch http(s) images |
| `allow_raw_openxml:` | `false` | pass ```` ```{=openxml} ```` blocks through |
| `link:` | none | `->(href) { href to use, or nil }`: rewrites link targets, or keeps a link's text alone, see [Links](#links) |
| `toc:`, `toc_title:`, `toc_depth:` | front matter, else off, *Contents*, 3 | table of contents |
| `heading_offset:` | front matter, else `0` | levels added to every heading's, within 1–6: `-1` turns `##` into Heading 1, `:auto` makes the highest level in use Heading 1; `toc_depth` and chapter numbers count the shifted levels |
| `title_block:` | `:auto` | title, subtitle, authors, date and abstract from front matter; `:auto` skips it when the template shows `{{title}}` |
| `quotes:` | from the language, else `:en` | `:en`, `:de`, `:fr` or four kramdown entity names |
| `highlight:` | `true` | syntax highlighting, when Rouge is installed |
| `figure_captions:` | `:title` | caption from the image title, `:alt` or `:none` |
| `code_handlers:` | `{}` | language ⇒ handler, or a `CodeHandlers` with limits: fenced blocks as images, see [Diagrams](#diagrams) |
| `svg_rasterizer:` | none | handler turning cleaned SVG into the PNG fallback, see [SVG](#svg); without it the fallback is blank |
| `number_captions:` | front matter, else `false` | `true` numbers every caption, `:chapter` per level-1 heading; figures and tables with an id are numbered either way |
| `figure_label:`, `table_label:` | from the language | caption labels |
| `lof:`, `lot:`, `lof_title:`, `lot_title:` | front matter, else off, *List of Figures*, *List of Tables* | lists of figures and tables |
| `page_size:`, `margins:` | `:a4`, `1440` | without a template; margins in twips |
| `styles:` | none | `->(docx) { docx.style id: 'Normal', font: 'Georgia' }` to adjust the default styles |
| `document:` | none | `->(docx) { docx.footer { p 'Draft' } }` to add caracal content before rendering |

`Caracal::Md::Renderer.new(**options)` renders several documents with the same options; its `warnings` list what it couldn't convert (unloadable images, raw HTML, …).


## Inside caracal

`#markdown` works on documents, headers, footers and table cells:

```ruby
Caracal::Document.save 'report.docx' do |docx|
  docx.h1 'Report'
  docx.markdown File.read('summary.md'), base_dir: 'docs'
  docx.table [[Caracal::Core::Models::TableCellModel.new { |c| c.markdown '**bold** cell' }]]
end
```

Here footnotes become a numbered list after the content, captions stay unnumbered and `[](#id)` stays a plain link: Word footnotes and fields need the finished package, which `Caracal::Md.render` builds.

`Caracal::Md.document` builds that package around caracal commands. Inside its block, `docx.markdown` converts with the state of one render: Word footnotes numbered across the calls, caption numbers and cross-references across them, and the template, language and document properties of `Caracal::Md.render`, with the same options. It returns the DOCX bytes.

```ruby
Caracal::Md.document(template: 'offer.dotx', lang: 'de') do |docx|
  docx.markdown "# Angebot\n\nWie besprochen[^1].\n\n[^1]: Telefonat am 3. November."
  docx.table offer.rows, border_size: 4
  docx.markdown "Gültig bis Jahresende[^2].\n\n[^2]: Preise netto."
end
```

* The options set up the whole document: language, caption numbering, template, and the table of contents and lists of figures, which go at its start. There is no title block.
* Front matter in a `markdown` call adds to the template's placeholders and the document properties, a later call's keys winning, and gives that call its `heading-offset`. Front matter naming a setting of the whole document (`lang`, `toc`, `lof`, `number-captions`, …) adds a warning.
* `docx.markdown` takes `heading_offset:` alone here; `docx.markdown_warnings` lists what the last call couldn't convert, `Renderer#warnings` everything.
* In headers, footers and table cells, `#markdown` works as outside the block.


## Security

Treat Markdown from users like any other input:

* Local images are read only inside `base_dir`, symlinks resolved; paths outside it fall back to their alt text.
* Remote images are off unless `allow_remote_images: true`. Turning them on lets the document's author make your server fetch URLs, internal ones included; consider an `image_loader` with an allowlist instead.
* Raw OOXML is off unless `allow_raw_openxml: true`.
* Values interpolated into Markdown go through `Caracal::Md.escape`, see [Values in Markdown](#values-in-markdown).
* Code handlers get the block's source from the document and run what you configure; their output is checked like an image. See [Diagrams](#diagrams) for the limits and for sandboxing diagram tools.
* SVG is cleaned before the rasterizer sees it, see [SVG](#svg).
* Templates are read with a size limit per entry (`Caracal::Md::Package.max_entry_size`, 50 MB).


## How it works

1. `FrontMatter` splits off the YAML; kramdown parses the rest.
2. `Converter` walks the syntax tree and issues caracal commands, referring to styles by the ids in `Styles`; `CodeHandlers` turn fenced blocks into checked image bytes, `Svg` cleans SVG for the rasterizer. What caracal has no command for (footnotes, list start numbers, caption numbers, cross-references, lists of figures) it marks with private-use characters.
3. caracal renders a complete package.
4. With a template, `TemplateMerger` moves the body into a copy of the template: it resolves styles by name, numbers lists through the template's list styles where they have numbering (renumbering caracal's elsewhere), copies images and links, and fills the placeholders.
5. `PostProcessor` turns the markers into footnotes, start numbers and fields (`SEQ`, `REF`, table of figures) with their results filled in, numbered in the final document order; `Language` and `CoreProperties` write `lang` and the document properties.


## Development

```sh
bundle install
bundle exec rspec
```

`bin/caracal-md` runs from a checkout in any directory: it switches to the Ruby in `.ruby-version` (through rbenv) and loads the project's bundle.

To work on caracal alongside, point Bundler at a checkout: `bundle config set --local local.caracal ../caracal`.


## License

MIT
