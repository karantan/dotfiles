{
  description = "karantan's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, nix-darwin, home-manager }:
  let
    secrets = import /Users/karantan/.dotfiles/secrets.nix;

    homeconfig = { pkgs, lib, config, ... }:
    let
      # Bundle the Warcraft peon .ogg sounds into the Nix store so hooks can
      # reference a stable path.
      peonSounds = pkgs.stdenvNoCC.mkDerivation {
        name = "peon-sounds";
        src = ./sounds;
        installPhase = ''
          mkdir -p $out
          cp *.ogg $out/
        '';
      };
    in {
      # Home Manager configuration
      # https://nix-community.github.io/home-manager/
      # Options:
      # https://nix-community.github.io/home-manager/options.xhtml
      home.homeDirectory = lib.mkForce "/Users/karantan";
      home.stateVersion = "25.05";

      # Put ~/.local/bin on PATH so the `zed` symlink (see home.file below) is
      # picked up by the shell. Home Manager writes this into hm-session-vars.sh,
      # which ~/.zshenv sources for every shell.
      home.sessionPath = [ "$HOME/.local/bin" ];

      programs.home-manager.enable = true;
      manual.manpages.enable = false;
      manual.html.enable = false;
      manual.json.enable = false;
      programs.htop.enable = true;
      programs.bat.enable = true;

      # Software I can't live without
      home.packages = with pkgs; [
        (import nixpkgs-unstable { system = "aarch64-darwin"; config.allowUnfree = true; }).claude-code
        (import nixpkgs-unstable { system = "aarch64-darwin"; config.allowUnfree = true; }).codex
        pkgs.devenv
        pkgs.heroku
        pkgs.go
        pkgs.cachix
        pkgs.python3
        pkgs.redis
        pkgs.nixfmt
        pkgs.pdsh # High-performance, parallel remote shell utility
        pkgs.gh # github cli
        pkgs.texliveSmall # latex support
        pkgs.pgcli # postgres cli
      ];

      programs.direnv = {
        package=(import nixpkgs-unstable { system = "aarch64-darwin"; }).direnv;
        enable = true;
        nix-direnv.enable = true;
      };
      programs.zellij = {
        enable = true;
        settings = {
          copy_command = "pbcopy";
          scrollback_editor = "zed";
        };
      };

      programs.fzf = {
        enable = true;
        tmux.enableShellIntegration = true;
        enableZshIntegration = true;
      };

      # NOTE: when ghostty is available on macos
      # programs.ghostty = {
      #   enable = true;
      #   settings = {
      #     theme = "Catppuccin Frappe";
      #     keybind = [
      #       "ctrl+`=toggle_quick_terminal"
      #       "super+right=goto_window:next"
      #       "super+left=goto_window:previous"
      #     ];
      #   };
      # };

      programs.git = {
        enable = true;
        # diff-so-fancy.enable = true;
        settings = {
          user = {
            name = "Gasper Vozel";
            email = secrets.email;
          };
          core = {
            editor = "vim";
          };
          diff = {
            tool = "diffmerge";
          };
          github = {
            user = "karantan";
            token = secrets.github.token;
          };
        };
        ignores = [
          # Packages: it's better to unpack these files and commit the raw source
          # git has its own built in compression methods
          "*.7z"
          "*.dmg"
          "*.gz"
          "*.iso"
          "*.jar"
          "*.rar"
          "*.tar"
          "*.zip"

          # OS generated files
          ".DS_Store"
          ".DS_Store?"
          "ehthumbs.db"
          "Icon?"
          "Thumbs.db"

          # Sublime
          "sublime/*.cache"
          "sublime/oscrypto-ca-bundle.crt"
          "sublime/Package Control.last-run"
          "sublime/Package Control.merged-ca-bundle"
          "sublime/Package Control.user-ca-bundle"

          # VS Code
          "vscode/History/"
          "vscode/globalStorage/"
          "vscode/workspaceStorage/"

          # Secrets
          "ssh_config_private"
        ];
      };

      programs.zsh = {
        enable = true;
        autosuggestion.enable = true;
        enableCompletion = true;
        oh-my-zsh = {
          enable = true;
          theme = "robbyrussell";
          plugins = ["git" "python" "sudo" "direnv"];
        };
        sessionVariables = {
          LC_ALL = "en_US.UTF-8";
          LANG = "en_US.UTF-8";
          EDITOR = "~/.editor";

          # Enable a few neat OMZ features
          HYPHEN_INSENSITIVE = "true";
          COMPLETION_WAITING_DOTS = "true";

          # Disable generation of .pyc files
          # https://docs.python-guide.org/writing/gotchas/#disabling-bytecode-pyc-files
          PYTHONDONTWRITEBYTECODE = "0";
        };
        shellAliases = {
          penv = "cd $HOME/py3122 && source .devenv/state/venv/bin/activate";
          cat = "bat";
          nixre = "sudo darwin-rebuild switch --flake ~/.dotfiles#MacBook-Air --impure";
          nixcfg = "zed ~/.dotfiles";
          nixgc = "nix-collect-garbage -d";
          nixdu = "du -shx /nix/store ";
          c = "zed .";
          e = "zellij attach ebn || zellij -s ebn";
          ee = "zellij attach ebn-nixos || zellij -s ebn-nixos";
          eee = "zellij attach misc || zellij -s misc";
          zls = "zellij list-sessions";
          ga = "git add -p";
          cruncher = "zed ssh://cruncher/home/karantan/ebn-nixos";
          pgcli = "pgcli --auto-vertical-output";
        };
        history = {
          append = true;
          share = true;
        };
        initContent = ''
          function edithosts {
              export EDITOR="zed --wait"
              sudo -e /etc/hosts
              echo "* Successfully edited /etc/hosts"
              sudo dscacheutil -flushcache && echo "* Flushed local DNS cache"
          }   
          # Clear terminal after 3 consecutive empty commands
          export EMPTY_ENTER_COUNT=0

          precmd() {
            if [[ -z $LAST_COMMAND ]]; then
              ((EMPTY_ENTER_COUNT++))
            else
              EMPTY_ENTER_COUNT=0
            fi

            if [[ $EMPTY_ENTER_COUNT -ge 3 ]]; then
              clear
              EMPTY_ENTER_COUNT=0
            fi

            LAST_COMMAND=""
          }

          preexec() {
            LAST_COMMAND=$1
          }
        '';
      };

      # Don't show the "Last login" message for every new terminal.
      home.file.".hushlogin" = {
        text = "";
      };

      # Home Manager is pretty good at managing dotfiles. The primary way to manage
      # plain files is through 'home.file'.
      home.file = {
        # Building this configuration will create a copy of 'dotfiles/screenrc' in
        # the Nix store. Activating the configuration will then make '~/.screenrc' a
        # symlink to the Nix store copy.
        # ".screenrc".source = .dotfiles/screenrc;

        # You can also set the file content immediately.
        ".editor" = {
          executable = true;
          text = ''
            #!/bin/bash
            zed --wait "$@"
          '';
        };
        # Expose the `zed` command from the manually-installed Zed.app.
        ".local/bin/zed".source =
          config.lib.file.mkOutOfStoreSymlink "/Applications/Zed.app/Contents/MacOS/cli";
        ".config/ghostty/config" = {
          text = ''
            theme = Catppuccin Frappe
            keybind = ctrl+`=toggle_quick_terminal
            keybind = super+right=goto_window:next
            keybind = super+left=goto_window:previous
            working-directory = home
            window-inherit-working-directory = false
          '';
        };

        # Claude Code settings. Play a random Warcraft peon sound whenever Claude
        # stops and is waiting for input (i.e. done with work).
        ".claude/settings.json" = {
          text = builtins.toJSON {
            hooks.Stop = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "afplay $(ls ${peonSounds}/*.ogg | sort -R | head -1) &";
                  }
                ];
              }
            ];
          };
        };
      };

    };
    configuration = { pkgs, ... }: {
      # Determinate uses its own daemon to manage the Nix installation that
      # conflicts with nix-darwin’s native Nix management.
      # To turn off nix-darwin’s management of the Nix installation, set:
      nix.enable = false;

      # Save disk space
      # Can't be used with nix.enable = false
      # nix.optimise.automatic = true;

      # Use nix from pinned nixpkgs
      # services.nix-daemon.enable = true;
      nix.settings.trusted-users = [ "@admin" ];
      nix.package = pkgs.nix;

      # Using flakes instead of channels
      nix.settings.nix-path = ["nixpkgs=flake:nixpkgs"];

      # Allow licensed binaries
      nixpkgs.config.allowUnfree = true;

      # Longer log output on errors
      nix.settings.log-lines = 25;

      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [ 
        ];

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Configure Cachix
      nix.settings.substituters = [
        "https://cache.nixos.org"
        "https://devenv.cachix.org"
        "https://niteo.cachix.org"
      ];
      nix.settings.trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "niteo.cachix.org-1:GUFNjJDCE199FDtgkG3ECLrAInFZEDJW2jq2BUQBFYY="
      ];

      # set netrc for automatic login processes (e.g. for cachix)
      nix.settings.netrc-file = "/Users/karantan/.config/nix/netrc";

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";

      #
      # My personal settings
      #
      system.primaryUser = "karantan";
      system.defaults.screencapture.location = "~/Downloads";
      # Enable touch ID authentication for sudo.
      security.pam.services.sudo_local.touchIdAuth = true;
      #
      # End of my personal settings
      #
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#MacBook-Air
    darwinConfigurations."MacBook-Air" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        home-manager.darwinModules.home-manager  {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.karantan = homeconfig;
            home-manager.backupFileExtension = ".backup";
        }
      ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."MacBook-Air".pkgs;

    # Support using parts of the config elsewhere
    homeconfig = homeconfig;
  };
}
