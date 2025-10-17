{
  description = "Manage system config using nix on any distro";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );
      nix-vm-test-lib =
        let
          rev = "e34870b8dd2c2d203c05b4f931b8c33eaaf43b81";
          sha256 = "sha256:1qp1fq96kv9i1nj20m25057pfcs1b1c9bj4502xy7gnw8caqr30d";
        in
        "${
          builtins.fetchTarball {
            url = "https://github.com/numtide/nix-vm-test/archive/${rev}.tar.gz";
            inherit sha256;
          }
        }/lib.nix";
    in
    {
      lib = import ./nix/lib.nix { inherit nixpkgs; };

      packages = eachSystem (
        { pkgs, system }:
        {
          default = pkgs.callPackage ./package.nix { };
        }
      );

      overlays = {
        default = final: _prev: {
          system-manager = final.callPackage ./package.nix { };
        };
      };

      # Only useful for quick tests
      systemConfigs.default = self.lib.makeSystemConfig {
        modules = [ ./examples/example.nix ];
      };

      formatter = eachSystem ({ pkgs, ... }: pkgs.treefmt);

      devShells = eachSystem (
        { pkgs, ... }:
        {
          default = pkgs.mkShellNoCC {
            shellHook = ''
              ${pkgs.pre-commit}/bin/pre-commit install --install-hooks --overwrite
              export PKG_CONFIG_PATH="${
                pkgs.lib.makeSearchPath "lib/pkgconfig" [
                  pkgs.dbus.dev
                  pkgs.systemdMinimal.dev
                ]
              }"
              export LIBCLANG_PATH="${pkgs.llvmPackages_latest.libclang}/lib"
              # for rust-analyzer
              export RUST_SRC_PATH="${pkgs.rustPlatform.rustLibSrc}"
              export RUST_BACKTRACE=1
              export RUSTFLAGS="${
                pkgs.lib.concatStringsSep " " [
                  "-L${pkgs.lib.getLib pkgs.systemdMinimal}/lib"
                  "-lsystemd"
                ]
              }"
            '';

            buildInputs = with pkgs; [
              dbus
            ];

            nativeBuildInputs = with pkgs; [
              pkgs.llvmPackages_latest.clang
              pkg-config
              rustc
              cargo
              # Formatting
              pre-commit
              treefmt
              nixfmt-rfc-style
              rustfmt
              clippy
              mdbook
              mdformat
            ];
          };
        }
      );

      checks = (
        nixpkgs.lib.recursiveUpdate
          (eachSystem (
            { system, ... }:
            {
              system-manager = self.packages.${system}.default;
            }
          ))
          {
            x86_64-linux =
              let
                system = "x86_64-linux";
              in
              (import ./test/nix/modules {
                inherit system;
                inherit (nixpkgs) lib;
                nix-vm-test = import nix-vm-test-lib {
                  inherit nixpkgs;
                  inherit system;
                };
                system-manager = self;
              });
          }
      );
    };
}
