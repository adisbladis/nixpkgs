MD_TARGETS=$(addsuffix .xml, $(basename $(wildcard ./*.md ./**/*.md)))

.PHONY: all
all: out/html/index.html out/epub/manual.epub

.PHONY: fix-misc-xml
fix-misc-xml:
	find . -iname '*.xml' -type f \
		-exec ../nixos/doc/varlistentry-fixer.rb {} ';'

.PHONY: clean
clean:
	rm -f ${MD_TARGETS} doc-support/result .version manual-full.adoc functions/library/locations.xml functions/library/generated
	rm -rf ./out/ ./highlightjs

.PHONY: validate
validate: manual-full.adoc doc-support/result
	jing doc-support/result/docbook.rng manual-full.adoc

out/html/index.html: # doc-support/result manual-full.adoc style.css highlightjs
	mkdir -p out/html
	asciidoctor --doctype book -o out/html/index.html -a source-highlighter=rouge -b html5 -vvv --trace manual.adoc

out/epub/manual.epub:
	mkdir -p out/epub
	asciidoctor-epub3 --doctype book -o out/epub/manual.epub -a source-highlighter=rouge -vvv --trace manual.adoc

highlightjs: doc-support/result
	mkdir -p highlightjs
	cp -r doc-support/result/highlightjs/highlight.pack.js highlightjs/
	cp -r doc-support/result/highlightjs/LICENSE highlightjs/
	cp -r doc-support/result/highlightjs/mono-blue.css highlightjs/
	cp -r doc-support/result/highlightjs/loader.js highlightjs/

.version: doc-support/result
	ln -rfs ./doc-support/result/version .version

doc-support/result: doc-support/default.nix
	# Nixdoc does not yet have support for any other output than docbook
	# (cd doc-support; nix-build)
