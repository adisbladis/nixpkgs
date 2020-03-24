{ pkgs, options, config, version, revision, extraSources ? [] }:

with pkgs;

let
  lib = pkgs.lib;

  # We need to strip references to /nix/store/* from options,
  # including any `extraSources` if some modules came from elsewhere,
  # or else the build will fail.
  #
  # E.g. if some `options` came from modules in ${pkgs.customModules}/nix,
  # you'd need to include `extraSources = [ pkgs.customModules ]`
  prefixesToStrip = map (p: "${toString p}/") ([ ../../.. ] ++ extraSources);
  stripAnyPrefixes = lib.flip (lib.fold lib.removePrefix) prefixesToStrip;

  optionsDoc = buildPackages.nixosOptionsDoc {
    inherit options revision;
    transformOptions = opt: opt // {
      # Clean up declaration sites to not refer to the NixOS source tree.
      declarations = map stripAnyPrefixes opt.declarations;
    };
  };

  sources = lib.sourceFilesBySuffices ./. [".adoc"];

  modulesDoc = builtins.toFile "modules.xml" ''
    <section xmlns:xi="http://www.w3.org/2001/XInclude" id="modules">
    ${(lib.concatMapStrings (path: ''
      <xi:include href="${path}" />
    '') (lib.catAttrs "value" config.meta.doc))}
    </section>
  '';

  generatedSources = runCommand "generated-docbook" {} ''
    mkdir $out
    ln -s ${modulesDoc} $out/modules.xml
    ln -s ${optionsDoc.optionsDocBook} $out/options-db.xml
    printf "%s" "${version}" > $out/version
  '';

  copySources =
    ''
      cp -prd $sources/* . # */
      ln -s ${generatedSources} ./generated
      chmod -R u+w .
    '';

  toc = builtins.toFile "toc.xml"
    ''
      <toc role="chunk-toc">
        <d:tocentry xmlns:d="http://docbook.org/ns/docbook" linkend="book-nixos-manual"><?dbhtml filename="index.html"?>
          <d:tocentry linkend="ch-options"><?dbhtml filename="options.html"?></d:tocentry>
          <d:tocentry linkend="ch-release-notes"><?dbhtml filename="release-notes.html"?></d:tocentry>
        </d:tocentry>
      </toc>
    '';

  manualXsltprocOptions = toString [
    "--param section.autolabel 1"
    "--param section.label.includes.component.label 1"
    "--stringparam html.stylesheet 'style.css overrides.css highlightjs/mono-blue.css'"
    "--stringparam html.script './highlightjs/highlight.pack.js ./highlightjs/loader.js'"
    "--param xref.with.number.and.title 1"
    "--param toc.section.depth 0"
    "--stringparam admon.style ''"
    "--stringparam callout.graphics.extension .svg"
    "--stringparam current.docid manual"
    "--param chunk.section.depth 0"
    "--param chunk.first.sections 1"
    "--param use.id.as.filename 1"
    "--stringparam chunk.toc ${toc}"
  ];

  olinkDB = runCommand "manual-olinkdb"
    { inherit sources;
      nativeBuildInputs = [ buildPackages.libxml2.bin buildPackages.libxslt.bin ];
    }
    ''
      xsltproc \
        ${manualXsltprocOptions} \
        --stringparam collect.xref.targets only \
        --stringparam targets.filename "$out/manual.db" \
        --nonet \
        ${docbook_xsl_ns}/xml/xsl/docbook/xhtml/chunktoc.xsl \
        ${manual-combined}/manual-combined.xml

      cat > "$out/olinkdb.xml" <<EOF
      <?xml version="1.0" encoding="utf-8"?>
      <!DOCTYPE targetset SYSTEM
        "file://${docbook_xsl_ns}/xml/xsl/docbook/common/targetdatabase.dtd" [
        <!ENTITY manualtargets SYSTEM "file://$out/manual.db">
      ]>
      <targetset>
        <targetsetinfo>
            Allows for cross-referencing olinks between the manpages
            and manual.
        </targetsetinfo>

        <document targetdoc="manual">&manualtargets;</document>
      </targetset>
      EOF
    '';

  mkDocs = {
    docType
    , outFile
  }: runCommand "nixos-manual-${docType}"
    { inherit sources;
      nativeBuildInputs = [ buildPackages.asciidoctor ];
      meta.description = "The NixOS manual in HTML format";
      allowedReferences = ["out"];
    }
    ''
      dst=$out/share/doc/nixos
      mkdir -p $dst

      type -p asciidoctor
      asciidoctor --doctype book -o $dst/${outFile} -a source-highlighter=rouge -b ${docType} -vvv --trace ${sources}/manual.adoc

      mkdir -p $out/nix-support
      echo "nix-build out $out" >> $out/nix-support/hydra-build-products
      echo "doc manual $dst" >> $out/nix-support/hydra-build-products
    ''; # */


in rec {
  inherit generatedSources;

  inherit (optionsDoc) optionsJSON optionsXML optionsDocBook;

  # Generate the NixOS manual.
  manualHTML = mkDocs {
    docType = "html5";
    outFile = "index.html";
  };

  # Alias for backward compatibility. TODO(@oxij): remove eventually.
  manual = manualHTML;

  # Index page of the NixOS manual.
  manualHTMLIndex = "${manualHTML}/share/doc/nixos/index.html";

  # TODO: Currently fails with:
  # asciidoctor: FAILED: missing converter for backend 'epub'
  manualEpub = mkDocs {
    docType = "epub";
    outFile = "nixos-manual.epub";
  };

  # Generate the NixOS manpages.
  manpages = runCommand "nixos-manpages"
    { inherit sources;
      nativeBuildInputs = [ buildPackages.asciidoctor ];
      allowedReferences = ["out"];
    }
    ''
      cp $sources/man-*.adoc .
      rm man-nixos-generate-config.adoc # Has problems, needs fixup
      rm man-pages.adoc # Has problems, needs fixup
      asciidoctor --failure-level=INFO -b manpage *.adoc

      find . -maxdepth 1 -regex '.*\.[0-9]' | while read man; do
        level=$(echo $man | grep -Po '[0-9]$')
        outd=$out/share/man/man$level
        mkdir -p $outd
        cp $man $outd/
      done
    '';

}
