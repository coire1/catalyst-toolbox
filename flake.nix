{
  nixConfig.extra-substituters = [
    "https://vit.cachix.org"
    "https://hydra.iohk.io"
  ];
  nixConfig.extra-trusted-public-keys = [
    "vit.cachix.org-1:tuLYwbnzbxLzQHHN0fvZI2EMpVm/+R7AKUGqukc6eh8="
    "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
  ];

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-compat.flake = false;
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.gitignore.url = "github:hercules-ci/gitignore.nix";
  inputs.gitignore.inputs.nixpkgs.follows = "nixpkgs";
  inputs.pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  inputs.pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  inputs.pre-commit-hooks.inputs.flake-utils.follows = "flake-utils";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.flake-utils.follows = "flake-utils";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  inputs.naersk.url = "github:nix-community/naersk";
  inputs.naersk.inputs.nixpkgs.follows = "nixpkgs";

  outputs = {
    self,
    nixpkgs,
    flake-compat,
    flake-utils,
    gitignore,
    pre-commit-hooks,
    rust-overlay,
    naersk,
  }:
    flake-utils.lib.eachSystem
    [
      flake-utils.lib.system.x86_64-linux
      flake-utils.lib.system.aarch64-linux
    ]
    (
      system: let
        readTOML = file: builtins.fromTOML (builtins.readFile file);
        workspaceCargo = readTOML ./Cargo.toml;

        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };

        mkRust = {channel ? "stable"}: let
          _rust = pkgs.rust-bin.${channel}.latest.default.override {
            extensions = [
              "rust-src"
              "rust-analysis"
              "rls-preview"
              "rustfmt-preview"
              "clippy-preview"
            ];
          };
        in
          pkgs.buildEnv {
            name = _rust.name;
            inherit (_rust) meta;
            buildInputs = [pkgs.makeWrapper pkgs.openssl];
            paths = [_rust];
            pathsToLink = ["/" "/bin"];
            # XXX: This is needed because cargo and clippy commands need to
            # also be aware of other binaries in order to work properly.
            # https://github.com/cachix/pre-commit-hooks.nix/issues/126
            postBuild = ''
              for i in $out/bin/*; do
                wrapProgram "$i" --prefix PATH : "$out/bin"
              done
            '';
          };

        rust-stable = mkRust {channel = "stable";};
        rust-nightly = mkRust {channel = "nightly";};

        naersk-lib = naersk.lib."${system}".override {
          cargo = rust-stable;
          rustc = rust-stable;
        };

        mkPackage = name: let
          pkgCargo = readTOML ./${name}/Cargo.toml;
          cargoOptions = [
            "--package"
            "file://$PWD/\"${name}\""
          ];
        in
          naersk-lib.buildPackage {
            inherit (pkgCargo.package) name version;

            root = gitignore.lib.gitignoreSource self;

            cargoBuildOptions = x: x ++ cargoOptions;
            cargoTestOptions = x: x ++ cargoOptions;

            PROTOC = "${pkgs.protobuf}/bin/protoc";
            PROTOC_INCLUDE = "${pkgs.protobuf}/include";

            nativeBuildInputs = with pkgs; [
              pkg-config
              protobuf
              rustfmt
            ];

            buildInputs = with pkgs; [
              openssl
            ];
          };

        workspace =
          builtins.listToAttrs
          (
            builtins.map
            (name: {
              inherit name;
              value = mkPackage name;
            })
            workspaceCargo.workspace.members
          );

        pre-commit = pre-commit-hooks.lib.${system}.run {
          src = self;
          hooks = {
            alejandra = {
              enable = true;
            };
            rustfmt = {
              enable = true;
              entry = pkgs.lib.mkForce "${rust-nightly}/bin/cargo-fmt fmt -- --check --color always";
            };
          };
        };

        warnToUpdateNix = pkgs.lib.warn "Consider updating to Nix > 2.7 to remove this warning!";
      in rec {
        packages =
          workspace
          // {
            default = workspace.catalyst-toolbox;
          };

        devShells.default = pkgs.mkShell {
          PROTOC = "${pkgs.protobuf}/bin/protoc";
          PROTOC_INCLUDE = "${pkgs.protobuf}/include";
          buildInputs =
            [rust-stable]
            ++ (with pkgs; [
              pkg-config
              openssl
              protobuf
            ]);
          shellHook =
            pre-commit.shellHook
            + ''
              echo "=== Catalyst toolbox development shell ==="
              echo "Info: Git hooks can be installed using \`pre-commit install\`"
            '';
        };

        checks.pre-commit = pre-commit;

        hydraJobs = packages;

        defaultPackage = warnToUpdateNix packages.default;
        devShell = warnToUpdateNix devShells.default;
      }
    );
}
