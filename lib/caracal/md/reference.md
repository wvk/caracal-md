---
title: Reference Document
subtitle: Every style caracal-md uses
author: caracal-md
date: 2026-01-01
abstract: |
  This document shows each style once. Change the styles in Word (not the text:
  only styles, page setup, headers and footers carry over), save it as a
  template and pass it to caracal-md as `template:`.
---

# Heading 1

Body text in the *Normal* style, with **strong**, *emphasis*, `Verbatim Char`,
~~strikethrough~~, a [Hyperlink](https://example.com) and a footnote.[^note]

## Heading 2

### Heading 3

#### Heading 4

##### Heading 5

###### Heading 6

> A paragraph in the *Quote* style.

> [!NOTE]
> GitHub alerts use the styles Note, Tip, Important, Warning and Caution.

```ruby
# Source Code
def greet(name)
  "Hello, #{name}!"
end
```

Lists use *List Bullet* and *List Number*, 2 to 5 for nested levels. Give
these styles a bullet or number in Word (Modify Style, Format, Numbering) and
lists take it over.

- List Bullet
  - List Bullet 2
    - List Bullet 3
      - List Bullet 4
        - List Bullet 5
          - List Paragraph, for deeper levels

1. List Number
   1. List Number 2
      1. List Number 3
         1. List Number 4
            1. List Number 5

| Markdown Table | Value |
|:---------------|------:|
| Table Text     | 1     |
| Header row     | 2     |

Table: Caption

Definition Term
: Definition

![Figure](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAUAAAAB4CAIAAAAMrLyJAAAACXBIWXMAAA7EAAAOxAGVKw4bAAABOklEQVR42u3TMQ0AIAwAwTrBEX4QiwIEsNYAC1shl5yCTz5aH8CjQgIwMGBgwMBgYMDAgIGBi4Hn2kARBgYDAwYGDAwGNjAYGDAwYGAwMGBgwMBgYAODgQEDAwYGAxsYDAwYGDAwGBgwMGBgMLCBwcCAgQEDg4ENDAYGDAwYGAwMGBgwMBjYwGBgwMCAgcHABgYDAwYGAxsYDAwYGDAwGNjAYGDAwICBwcCAgQEDg4ENDAYGDAwYGAxsYDAwYGDAwGBgwMCAgcHABgYDAwYGDAwGNjAYGDAwYGAwMGBgwMBgYAODgQEDAwYGA0sGBgYMDAY2MBgYMDBgYDCwgcHAgIEBA4OBAQMDBgYDGxgMDBgYMDAY2MBgYMDAgIHBwICBAQODgQ0M/w4M1GdgMDBgYMDAYGDAwICBgYMEjDEIxjt7hvcAAAAASUVORK5CYII= "Caption")

[^note]: Footnote Text with its Footnote Reference.
