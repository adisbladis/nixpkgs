### Introduction
Asciidoc is a [lightweight markup language](https://en.wikipedia.org/wiki/Lightweight_markup_language).
Unlike most of these other lightweight formats Asciidoc supports structural elements necessary for writing technical documentation.

### Notes

I started this effort using [Pandoc](https://pandoc.org/) but it turns out it's woefully inadequate at converting either from Docbook, to Asciidoc or both.

So we've packaged [DocBookRx](https://github.com/asciidoctor/docbookrx) & [Kramdown AsciiDoc](https://github.com/asciidoctor/kramdown-asciidoc/) which in combination gets us pretty close to a workable conversion, though even these tools are _not_ able to fully automatically do the conversion so we have a custom post-processor that touches up some of the shortcomings in the documentation generator.

This Python script should be dropped (via `git rebase`) before merging this work.

### The good
- Building nixpkgs docs takes well under a second - even on my laptop

- The documentation's build closure size is now ~120M (thanks to work by @qyliss to reduce asciidoctor closure size)

- The build machinery is much simplified

- Asciidoc is more intuitive than DocBook
This is more of a personal preference than anything else

- Asciidoctor has good support for syntax highlighting
Asciidoctor has support for a wide variety of highlighters:
  - [Rouge](https://github.com/rouge-ruby/rouge) - My current choice, "just works" and has good support for Nix
  - [Pygments](https://pygments.org/) - One of the widest language support highlighters out there, in Python though so we may want to steer clear for closure size reasons.
  - coderay, prettify, highlight.js - Also supported but dont feel we need to get into these.

- Has first-class support for epub

- Composes nicely via includes

- Supported & rendered nicely by Github

### The bad

- While converting the docs I've noticed a huge value in the old docs being XML (or some other well-understood format)
It's trivial to parse an XML file using custom tooling, the same cannot be said for asciidoc (or other "human-friendly" formats).

- Custom conversion tooling may have missed something
As most data loss I've seen in doc conversion so far has been silent it's possible we're losing something important.
Care needs to be taken and things manually checked.

- No support for inline Markdown
Unlike in DocBook where we can import Markdown files pretty seamlessly we have to convert Markdown to asciidoc.
This can be seen both as a positive & a negative depending on your perspective.

### Conclusions
As you can see from my lists weighing pros & cons I have mostly positive things to say about asciidoc.
It's is a fantastic format that I think will serve us very well going forward with about the same level of intuition that Markdown has.

While there are some small question marks around what tooling supports the format `asciidoctor` itself is enough for our requirements.

I see very little downside & a lot of potential upsides with Asciidoc, it has my strongest possible recommendation as a DocBook replacement for Nixpkgs/NixOS.


### Samples

Pre rendered samples can be found at:
- https://f001.backblazeb2.com/file/asciidoc/nixpkgs-manual.html
- https://f001.backblazeb2.com/file/asciidoc/nixpkgs-manual.epub

- https://f001.backblazeb2.com/file/asciidoc/nixos-manual.html
