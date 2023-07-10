{
  description = "nixpkgs with the unfree bits enabled";

  inputs = {
    nixpkgs.follows = "nixpkgs-master";

    nixpkgs-master.url = github:NixOS/nixpkgs/master;
    nixpkgs-nixpkgs-unstable.url = github:NixOS/nixpkgs/nixpkgs-unstable;
    nixpkgs-nixos-unstable.url = github:NixOS/nixpkgs/nixos-unstable;
    nixpkgs-release.url = github:NixOS/nixpkgs/nixos-23.05;

    hercules-ci-effects.url = github:hercules-ci/hercules-ci-effects;
  };

  nixConfig = {
    extra-substituters = [
      "https://cuda-maintainers.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  outputs = inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ withSystem, config, ... }:
      {
        imports = [
          inputs.hercules-ci-effects.flakeModule
        ];
        systems = [ "x86_64-linux" ];
        hercules-ci.flake-update = {
          enable = true;
          when = {
            minute = 30;
            hour = [ 2 19 ];
          };
          autoMergeMethod = "rebase";

          # Don't create PRs in flake-update, instead push to master
          createPullRequest = false;
          updateBranch = "develop";
        };
        hercules-ci.github-pages = {
          branch = "develop";
          pushJob = "gh-pages";
        };
        perSystem = { self', pkgs, ... }: {
          packages.website = pkgs.writeTextFile {
            name = "nixpkgs-unfree-gh-pages";
            destination = "/index.html";
            text = ''
              <h1>nixpkgs-unfree</h1>
              <h2>test</h2>
            '';
          };
          hercules-ci.github-pages = {
            settings.contents = self'.packages.website;
          };
        };
        flake =
          let

            inherit (inputs) nixpkgs;
            inherit (nixpkgs) lib;

            systems = [ "x86_64-linux" ];

            eachSystem = lib.genAttrs systems;

            utils = import ./nix/utils.nix;
            inherit (utils) optionalString;

            x = eachSystem (system:
              import ./nix/jobs.nix {
                inherit system nixpkgs lib;
              }
            );
          in
          {
            # Inherit from upstream
            inherit (nixpkgs) lib; # nixosModules htmlDocs;

            # But replace legacyPackages with the unfree version
            legacyPackages = eachSystem (system: x.${system}.legacyPackages);

            # And load all the unfree+redistributable packages as checks
            checks = eachSystem (system: x.${system}.neverBreak);

            # Expose our own unfree overrides
            overlays = import ./nix/overlays.nix;
            overlay = self.overlays.basic;
          };

        herculesCI =
          { ref
          , branch
          , tag
          , rev
          , shortRev
          , primaryRepo
          , herculesCI
          , lib # Because of flake-parts...
          , ...
          }: {

            # To disable the "default" checks:
            # onPush.default.outputs = lib.mkForce { };
            onPush.default.outputs = {
              effects = withSystem "x86_64-linux" ({ hci-effects, pkgs, ... }: {
                releaseBranch = hci-effects.modularEffect {
                  imports = [ ./effects/git-push/effects-fun.nix ];
                  git.push.source.url = "https://github.com/NixOS/nixpkgs.git";
                  git.push.source.ref = inputs.nixpkgs-master.rev;
                  git.push.destination.url = "https://github.com/9d80dba85131ab22/nixpkgs.git";
                  git.push.destination.ref = "buildNixosUnstable80";
                  git.push.destination.tokenSecret = "nixpkgCuda";
                };
              });
            };

            # Cf. https://docs.hercules-ci.com/hercules-ci-agent/evaluation#attributes-herculesCI.onSchedule-when
            onSchedule."master, no overlays, arches: 8_6" = {
              when.hour = [ 0 2 20 22 ];
              outputs =
                let
                  system = "x86_64-linux";
                  cudaCapabilities = [ "8.6" ];
                  input = "nixpkgs-master";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                    extraConfig = { inherit cudaCapabilities; };
                  };
                in
                jobs.neverBreak;
            };
            onSchedule."master, mkl overlay, arches: 8_6" = {
              when.hour = [ 21 ];
              outputs =
                let
                  system = "x86_64-linux";
                  cudaCapabilities = [ "8.6" ];
                  input = "nixpkgs-master";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                    extraConfig = { inherit cudaCapabilities; };
                  };
                in
                jobs.checks;
            };

            # Build pytorch&c with default capabilities, daily
            onSchedule."master, no overlays, arches: all" = {
              when.hour = [ 3 ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-master";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                  };
                in
                jobs.neverBreak;
            };

            onSchedule."master, mkl overlay, arches: all" = {
              when.hour = [ 21 ];
              when.dayOfWeek = [ "Fri" ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-master";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                  };
                in
                jobs.checks;
            };

            # Default cudaCapabilities

            onSchedule."nixpkgs-unstable, mkl overlay, arches: all" = {
              when.dayOfWeek = [ "Sat" ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-nixpkgs-unstable";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                  };
                in
                jobs.checks;
            };
            onSchedule."nixos-unstable, mkl overlay, arches: all" = {
              when.dayOfWeek = [ "Sat" ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-nixos-unstable";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                  };
                in
                jobs.checks;
            };
            onSchedule."nixpkgs-unstable, mkl overlay, arches: 8_6" = {
              when.dayOfWeek = [ "Sat" ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-nixpkgs-unstable";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                    extraConfig.cudaCapabilities = [ "8.6" ];
                  };
                in
                jobs.checks;
            };
            onSchedule."nixos-unstable, mkl overlay, arches: 8_6" = {
              when.dayOfWeek = [ "Fri" ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-nixos-unstable";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                    extraConfig.cudaCapabilities = [ "8.6" ];
                  };
                in
                jobs.checks;
            };
            onSchedule."nixos-unstable, mkl overlay, arches: 8_0" = {
              when.dayOfWeek = [ "Sat" ];
              outputs =
                let
                  system = "x86_64-linux";
                  input = "nixpkgs-nixos-unstable";
                  jobs = import ./nix/jobs.nix {
                    inherit system;
                    nixpkgs = inputs.${input};
                    extraConfig.cudaCapabilities = [ "8.0" ];
                  };
                in
                jobs.checks;
            };
          };
      });
}
