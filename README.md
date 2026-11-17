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


## What converts to what

| Markdown | Word |
|---|---|
| `# Heading` … `######` | Heading 1–6, with a bookmark so `[link](#heading)` jumps there |
| paragraphs, `**strong**`, `*em*`, `~~strike~~`, `` `code` `` | Normal, bold, italic, strikethrough, *Verbatim Char* |
| `<sup>`, `<sub>`, `<u>`, `<mark>`, `<kbd>` | superscript, subscript, underline, highlight, *Verbatim Char* |
| links, autolinks | hyperlinks (*Hyperlink*); `javascript:` and other unknown schemes stay text |
| `"quotes"`, `--`, `...` | typographic quotes (English, German or French), dashes, ellipsis |
| `> quote` | *Quote* |
| `> [!NOTE]` … `> [!CAUTION]` (GitHub alerts) | *Note*, *Tip*, *Important*, *Warning*, *Caution*, with a label |
| fenced and indented code | *Source Code*, highlighted by Rouge when installed |
| lists, nested lists, `3.` start numbers, `- [ ]` tasks | *List Bullet*, *List Number*, *List Bullet 2* … *5* and *List Number 2* … *5* for nested levels (*List Paragraph* below), with Word numbering; ☐ / ☒ |
| GFM tables with alignment, `Table: caption` after the table | *Markdown Table* with a repeating header row, *Table Text* |
| definition lists (kramdown) | *Definition Term*, *Definition* |
| `![alt](img.png "Title")` | the image, scaled to the text width, with the title as *caption* |
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

**Placeholders.** `{{title}}`, `{{author}}`, `{{date}}` and any other front matter key are replaced in the template body, headers and footers, also where Word has split the text across several runs. `variables: { 'client' => 'ACME' }` (or `--var client=ACME`) adds more. When the template shows `{{title}}`, caracal-md leaves out its own title block.

**Making a template.** `caracal-md --print-reference-doc reference.docx` writes a document using every style of the default set. Change the styles (and page setup, headers, footers) in Word, save it as a template and pass it back.


## Options

| Option | Default | |
|---|---|---|
| `template:` | none | Word template, see above |
| `style_map:` | `{}` | style id or name ⇒ template style name or id |
| `placeholder:` | `'{{content}}'` | template paragraph that receives the content |
| `variables:` | `{}` | extra placeholder values |
| `base_dir:` | `Dir.pwd` | relative image paths resolve here (`convert_file`: the file's directory) |
| `image_loader:` | built in | `->(src) { bytes or nil }`, e.g. for ActiveStorage |
| `allow_remote_images:` | `false` | fetch http(s) images |
| `allow_raw_openxml:` | `false` | pass ```` ```{=openxml} ```` blocks through |
| `toc:`, `toc_title:`, `toc_depth:` | front matter, else off, *Contents*, 3 | table of contents |
| `title_block:` | `:auto` | title, subtitle, authors, date and abstract from front matter; `:auto` skips it when the template shows `{{title}}` |
| `quotes:` | from `lang`, else `:en` | `:en`, `:de`, `:fr` or four kramdown entity names |
| `highlight:` | `true` | syntax highlighting, when Rouge is installed |
| `figure_captions:` | `:title` | caption from the image title, `:alt` or `:none` |
| `number_captions:` | front matter, else `false` | `true` numbers every caption, `:chapter` per level-1 heading; figures and tables with an id are numbered either way |
| `figure_label:`, `table_label:` | from `lang` | caption labels |
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


## Security

Treat Markdown from users like any other input:

* Local images are read only inside `base_dir`, symlinks resolved; paths outside it fall back to their alt text.
* Remote images are off unless `allow_remote_images: true`. Turning them on lets the document's author make your server fetch URLs, internal ones included; consider an `image_loader` with an allowlist instead.
* Raw OOXML is off unless `allow_raw_openxml: true`.
* Templates are read with a size limit per entry (`Caracal::Md::Package.max_entry_size`, 50 MB).


## How it works

1. `FrontMatter` splits off the YAML; kramdown parses the rest.
2. `Converter` walks the syntax tree and issues caracal commands, referring to styles by the ids in `Styles`. What caracal has no command for (footnotes, list start numbers, caption numbers, cross-references, lists of figures) it marks with private-use characters.
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
