{
  description = "dmurko's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, nix-darwin, home-manager }:
  let
    secrets = import /Users/dejanmurko/.dotfiles/secrets.nix;

    homeconfig = { pkgs, lib, ... }: {
      # Home Manager configuration
      # https://nix-community.github.io/home-manager/
      home.homeDirectory = lib.mkForce "/Users/dejanmurko";
      home.stateVersion = "25.05";
      programs.home-manager.enable = true;
      programs.htop.enable = true;
      programs.bat.enable = true;

      # Software I can't live without
      home.packages = with pkgs; [
        (import nixpkgs-unstable { system = "aarch64-darwin"; }).devenv
        (import nixpkgs-unstable { system = "aarch64-darwin"; config.allowUnfree = true; }).claude-code
        cachix
        atuin
        bat
      ];

      programs.vim.enable = true;

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      programs.git = {
        enable = true;
        diff-so-fancy.enable = true;
        userName = "Dejan Murko";
        userEmail = secrets.email;
        aliases = {
          ap = "add -p";
          st = "status";
          ci = "commit";
          co = "checkout";
          df = "diff";
          l = "log";
          ll = "log -p";
          rehab = "reset origin/main --hard";
        };
        extraConfig = {
          branch = {
            autosetuprebase = "always";
          };
          help = {
            autocorrect = 20;
          };
          init = {
            defaultBranch = "main";
          };
          push = {
            default = "simple";
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

          # VS Code
          "vscode/History/"
          "vscode/globalStorage/"
          "vscode/workspaceStorage/"

          # Secrets
          "ssh_config_private"

          # AI tooling
          "**/.claude/settings.local.json"
        ];
      };

      programs.ssh = {
        enable = true;

        extraConfig = ''
          Host *
            IdentityAgent /Users/dejanmurko/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
        '';
      };


      programs.zsh = {
        enable = true;
        autosuggestion.enable = true;
        enableCompletion = true;
        oh-my-zsh = {
          enable = true;
          theme = "robbyrussell";
          plugins = ["git" "sudo" "direnv"];
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
          cat = "bat";
          nixre = "sudo darwin-rebuild switch --flake ~/.dotfiles#Dejans-Air --impure";
          nixcfg = "cursor ~/.dotfiles";
          nixgc = "nix-collect-garbage -d";
          nixdu = "du -shx /nix/store ";
          history = "atuin search -i";
        };
        history = {
          append = true;
          share = true;
        };
        initContent = ''
          eval "$(atuin init zsh --disable-up-arrow)"

          function edithosts {
              export EDITOR="cursor --wait"
              sudo -e /etc/hosts
              echo "* Successfully edited /etc/hosts"
              sudo dscacheutil -flushcache && echo "* Flushed local DNS cache"
          }   
        '';
      };

      # Don't show the "Last login" message for every new terminal.
      home.file.".hushlogin" = {
        text = "";
      };

      # Create config files in ~/
      home.file = {
        ".editor" = {
          executable = true;
          text = ''
            #!/bin/bash
            # https://github.com/microsoft/vscode/issues/68579#issuecomment-463039009
            cursor --wait "$@"
            open -a Terminal
          '';
        };
      };
      
    };
    configuration = { pkgs, ... }: {
      # Enable touch ID authentication for sudo.
      security.pam.services.sudo_local.touchIdAuth = true;

      # make sure firewall is up & running
      system.defaults.alf.globalstate = 1;
      system.defaults.alf.stealthenabled = 1;

        # Personalization
        system.primaryUser = "dejanmurko";
        networking.hostName = "Dejans-Air";
        system.defaults.dock.autohide = true;
        system.defaults.dock.orientation = "left";
        system.defaults.dock.tilesize = 40;
        system.defaults.finder._FXShowPosixPathInTitle = true;
        system.defaults.finder.AppleShowAllExtensions = true;
        system.defaults.finder.AppleShowAllFiles = false;
        system.defaults.finder.ShowPathbar = true;
        system.defaults.finder.ShowStatusBar = true;
        system.defaults.finder.FXPreferredViewStyle = "clmv";
        system.defaults.loginwindow.GuestEnabled = false;
        system.defaults.finder.FXDefaultSearchScope = "SCcf"; # search current folder by default
        system.defaults.NSGlobalDomain.AppleShowScrollBars = "Always";
        system.defaults.NSGlobalDomain.AppleScrollerPagingBehavior = true;
        system.defaults.finder.FXEnableExtensionChangeWarning = false;
        system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
        system.defaults.NSGlobalDomain.KeyRepeat = 2;
        system.defaults.NSGlobalDomain.AppleKeyboardUIMode = 3;
        system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode = true;
        system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 = true;
        system.defaults.NSGlobalDomain.NSTableViewDefaultSizeMode = 2;
        system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint = true;
        system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint2 = true;
        system.defaults.trackpad.FirstClickThreshold = 0;
        system.defaults.trackpad.SecondClickThreshold = 0;
        system.keyboard.enableKeyMapping = true;
        system.keyboard.nonUS.remapTilde = true;
        system.defaults.screencapture.disable-shadow = false;
        system.defaults.screensaver.askForPasswordDelay = 1;

      # Use nix from pinned nixpkgs
      nix.settings.trusted-users = [ "@admin dejanmurko" ];
      nix.package = pkgs.nix;

      # Using flakes instead of channels
      nix.settings.nix-path = ["nixpkgs=flake:nixpkgs"];
      nix.channel.enable = false;

      # Allow licensed binaries
      nixpkgs.config.allowUnfree = true;

      # Save disk space
      nix.optimise.automatic = true;

      # Longer log output on errors
      nix.settings.log-lines = 25;

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
      nix.settings.netrc-file = "/Users/dejanmurko/.config/nix/netrc";

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#Dejans-Air
    darwinConfigurations."Dejans-Air" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        home-manager.darwinModules.home-manager  {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.dejanmurko = homeconfig;
            home-manager.backupFileExtension = ".backup";
        }
      ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."Dejans-Air".pkgs;

    # Support using parts of the config elsewhere
    homeconfig = homeconfig;
  };
}
