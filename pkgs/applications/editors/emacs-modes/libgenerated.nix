lib: self:

let

    fetcherGenerators = { repo ? null
                        , url ? null
                        , ... }:
                        { sha256
                        , commit
                        , ...}: {
      github = self.callPackage ({ fetchFromGitHub }:
        fetchFromGitHub {
          owner = lib.head (lib.splitString "/" repo);
          repo = lib.head (lib.tail (lib.splitString "/" repo));
          rev = commit;
          inherit sha256;
        }
      ) {};
      gitlab = self.callPackage ({ fetchFromGitLab }:
        fetchFromGitLab {
          owner = lib.head (lib.splitString "/" repo);
          repo = lib.head (lib.tail (lib.splitString "/" repo));
          rev = commit;
          inherit sha256;
        }
      ) {};
      git = self.callPackage ({ fetchgit }:
        fetchgit {
          rev = commit;
          inherit sha256 url;
        }
      ) {};
      bitbucket = self.callPackage ({ fetchhg }:
        fetchhg {
          rev = commit;
          url = "https://bitbucket.com/${repo}";
          inherit sha256;
        }
      ) {};
      hg = self.callPackage ({ fetchhg }:
        fetchhg {
          rev = commit;
          inherit sha256 url;
        }
      ) {};
    };

in {

    melpaDerivation = variant:
                      { ename, fetcher
                      , commit ? null
                      , sha256 ? null
                      , ... }@args:
      let
        sourceArgs = args."${variant}";
        version = sourceArgs.version or null;
        deps = sourceArgs.deps or null;
        error = sourceArgs.error or args.error or null;
      in
      lib.nameValuePair ename (
        self.callPackage ({ melpaBuild, fetchurl, ... }@pkgargs:
          melpaBuild {
            pname = ename; # todo: sanitize
            ename = ename;
            version = if isNull version then "" else
              lib.concatStringsSep "." (map toString version);
            src = if isNull sha256 then null else
              lib.getAttr fetcher (fetcherGenerators args sourceArgs);
            recipe = if isNull commit then null else
              fetchurl {
                name = ename + "-recipe";
                url = "https://raw.githubusercontent.com/melpa/melpa/${commit}/recipes/${ename}";
                inherit sha256;
              };
            packageRequires = lib.optional (! isNull deps)
              (map (dep: pkgargs."${dep}" or self."${dep}" or null)
                   deps);
            meta = (sourceArgs.meta or {}) // {
              broken = ! isNull error;
              reasonBroken = error;
            };
          }
        ) {}
      );

}
