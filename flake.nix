{
  description = "Vellvm, a formal specification and interpreter for LLVM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
  };

  outputs = { self, nixpkgs, flake-utils, nix-filter }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;
        coq = pkgs.coq_8_15;
        ocamlPkgs = coq.ocamlPackages;
        coqPkgs = pkgs.coqPackages_8_15.overrideScope'
          (self: super:
            { simple-io = super.simple-io.overrideAttrs
              (s : rec
                { version = "1.7.0";
                  name = "coq8.15-simple-io-${version}";
                  src = fetchTarball {
                    url = "https://github.com/Lysxia/coq-simple-io/archive/refs/tags/1.7.0.zip";
                    sha256 = "1a1q9x2abx71hqvjdai3n12jxzd49mhf3nqqh3ya2ssl2lj609ci";
                  };
                  meta.broken = false;
                });

              ITree = super.ITree.overrideAttrs
                (s : rec
                  { version = "5.0.0";
                    name = "coq8.15-InteractionTrees-${version}";
                    src = fetchTarball {
                      # Version with rutt theory and mrec rutt theory.
                      url = "https://github.com/DeepSpec/InteractionTrees/archive/9c1637ea57d1afcef587eb438438c73247639c0e.zip";
                      sha256 = "sha256:0hcwplpaj2gx6c2abyp3w4g83hzvjnzfsh1sl9kfhd0r3pb9biar";
                    };
                    meta.broken = false;
                  });

              flocq = super.flocq.overrideAttrs
                (s : rec
                  { version = "3.4.3";
                    name = "coq8.15-flocq-${version}";
                    src = fetchTarball {
                      url = "https://gitlab.inria.fr/flocq/flocq/-/archive/flocq-3.4.3/flocq-flocq-3.4.3.tar.gz";
                      sha256 = "sha256:1489kbqa2z5dpcw9d900g9ssmcc2iqsfwy293sf309l596a5cdv1";
                    };
                    meta.broken = false;
                  });
            });

        version = "vellvm:master";
      in rec {
        packages = {
          default = (pkgs.callPackage ./release.nix (ocamlPkgs // coqPkgs // { nix-filter = nix-filter.lib; perl = pkgs.perl; inherit coq version; })).vellvm;
        };

        defaultPackage = packages.default;

        app.default = flake-utils.lib.mkApp { drv = packages.default; };

        checks = {
          vellvm-test-suite =
            pkgs.stdenv.mkDerivation {
              name = "vellvm-test-suite";
              src = ./.;
              meta = {
                description = "Run the simple suite of vellvm tests";
              };
              buildInputs = [packages.default];
              installPhase = ''
              cd src
              ${packages.default}/bin/vellvm -test-suite
              if [[ $? == 0 ]]; then
                mkdir $out
              fi
              '';
            };
            
          org-lint =
            pkgs.stdenv.mkDerivation {
              name = "org-linting";
              src = ./.;
              meta = {
                description = "Ensure that links are still valid within some important org files for artifact submissions :).";
              };
              buildInputs = [pkgs.emacs];
              installPhase = ''
 ${pkgs.emacs}/bin/emacs --batch -f package-initialize --eval "(add-hook 'org-mode-hook  
      (lambda ()
          (let* ((file-name (current-buffer))
            (Col1 'Line)
            (Col2 'Trust)
            (Col3 'Warning)
            (lint-report (org-lint))
          )
          (princ (format \"file: %s\n%6s%6s%8s\n\" file-name Col1 Col2 Col3))
          (dolist (element lint-report)
           (setq report (car (cdr element)))
           (princ (format \"%6s%6s %7s\n\" (seq-elt report 0) (seq-elt report 1) (seq-elt report 2)))
          )
          (if (not (null lint-report))
            (kill-emacs 1))
          )))" MemoryTour.org

          if [[ $? == 0 ]]; then
             mkdir $out
          fi
              '';
            };
        };

        devShells = {
          # Include a fixed version of clang in the development environment for testing.
          default = pkgs.mkShell {
            inputsFrom = [ packages.default ];
            buildInputs = [ pkgs.clang_13 ];
          };
        };

        devShell = devShells.default;
      });
}
