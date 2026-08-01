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
    # Instantiate nixpkgs-unstable exactly once. Every `import nixpkgs-unstable
    # { ... }` is a full, independent nixpkgs evaluation, so per-package imports
    # make each rebuild slower and let allowUnfree drift between call sites.
    pkgsUnstable = import nixpkgs-unstable {
      system = "aarch64-darwin";
      config.allowUnfree = true;
    };

    homeconfig = { pkgs, lib, config, ... }:
    let
      # Bundle the Warcraft peon sounds into the Nix store so hooks can
      # reference a stable path, decoding each clip to WAV with 0.8s of
      # trailing silence appended.
      #
      # The padding is load-bearing, not cosmetic. afplay queues its audio
      # with CoreAudio and exits, and the output device powers down before
      # the final buffers reach the speaker, so the last ~0.3s never plays:
      # "ready to w" instead of "ready to work". Playing clips back to back
      # hides this, because each new afplay holds the device open long
      # enough to flush the previous one's tail -- only the last clip of a
      # burst loses it, and a hook always plays exactly one. Padding inside
      # the file means the dropped tail is silence.
      #
      # It has to be one file: a second afplay of a separate silent clip
      # does not work, because the ~0.7s the device takes to open leaves a
      # gap in which the tail is already gone.
      peonSounds = pkgs.stdenvNoCC.mkDerivation {
        name = "peon-sounds";
        src = ./sounds;
        nativeBuildInputs = [ pkgs.sox ];
        # Accepts ogg/wav/mp3 so replacement clips can be dropped into
        # sounds/ in whatever format they were downloaded in; sox normalises
        # all of them to padded WAV. Fails the build on an unreadable file
        # rather than silently shipping a pool with a missing clip.
        installPhase = ''
          mkdir -p $out
          shopt -s nullglob
          for f in *.ogg *.wav *.mp3; do
            sox "$f" "$out/''${f%.*}.wav" pad 0 0.8
          done
          [ -n "$(ls -A $out)" ] || { echo "no sound files found in src"; exit 1; }
        '';
      };

      # Stage 2 of the Claude Code notifier: the part that has to outlive the
      # hook. Split out from claudeNotify below so stage 1 can hand it off to
      # setsid as a single argv-taking program instead of a quoted blob.
      #   argv: $1 = clip  $2 = title  $3 = subtitle  $4 = body  $5 = group
      claudeNotifyEmit = pkgs.writeShellScript "claude-notify-emit" ''
        ${pkgs.terminal-notifier}/bin/terminal-notifier \
          -title "$2" -subtitle "$3" -message "$4" -group "$5" \
          -activate com.mitchellh.ghostty >/dev/null 2>&1
        exec /usr/bin/afplay "$1"
      '';

      # Stage 1: runs inside the hook, reads the event JSON off stdin and works
      # out what to say. A banner rather than only a sound, because a sound is
      # gone the moment it plays and NotificationCenter still has it waiting
      # when you come back to the desk. Clicking the banner raises Ghostty.
      #   argv: $1 = done | attention | failed
      # Niteo's Grafana MCP server, per https://github.com/teamniteo/claude.
      # The service account token is created at
      # https://niteo.grafana.net/org/serviceaccounts and lives in 1Password.
      #
      # Niteo's own config expects GRAFANA_SERVICE_ACCOUNT_TOKEN in the
      # environment, which only works when Claude Code is started from a
      # shell. The desktop app is launched by the GUI and inherits no zsh
      # environment, so fetch the token from 1Password when the server
      # starts instead. Nothing secret lands in the Nix store.
      mcpGrafana = pkgs.writeShellScript "mcp-grafana-op" ''
        set -euo pipefail
        # Homebrew's op, not nixpkgs': only a 1Password-signed binary in a
        # location the desktop app trusts gets the desktop-app integration
        # (biometric unlock) instead of demanding a session token.
        GRAFANA_SERVICE_ACCOUNT_TOKEN="$(/opt/homebrew/bin/op read --no-newline \
          'op://Niteo Team/GRAFANA_SERVICE_ACCOUNT_TOKEN/credential')"
        export GRAFANA_SERVICE_ACCOUNT_TOKEN
        export GRAFANA_URL="https://niteo.grafana.net"
        exec ${pkgsUnstable.mcp-grafana}/bin/mcp-grafana "$@"
      '';

      # Ship that server as a one-plugin marketplace rather than through
      # `programs.claude-code.mcpServers`. That option delivers its .mcp.json
      # by appending `--plugin-dir` to a wrapper around the `claude` binary,
      # which the desktop app never runs -- it launches its own bundled copy,
      # so the server would exist only in the terminal CLI. A marketplace is
      # registered in settings.json, which both read.
      niteoMcpMarketplace =
        let
          plugin = {
            name = "niteo-grafana";
            description = "Niteo's Grafana (niteo.grafana.net) as an MCP server.";
            version = "1.0.0";
          };
          json = (pkgs.formats.json { }).generate;
        in
        pkgs.runCommand "niteo-mcp-marketplace" { } ''
          install -Dm644 ${
            json "marketplace.json" {
              name = "niteo-mcp";
              owner = {
                name = "Niteo";
                url = "https://github.com/teamniteo";
              };
              plugins = [ (plugin // { source = "./"; }) ];
            }
          } $out/.claude-plugin/marketplace.json
          install -Dm644 ${json "plugin.json" plugin} $out/.claude-plugin/plugin.json
          install -Dm644 ${
            json "mcp.json" { mcpServers.mcp-grafana.command = "${mcpGrafana}"; }
          } $out/.mcp.json
        '';

      claudeNotify = pkgs.writeShellScript "claude-notify" ''
        PATH="${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:/usr/bin:/bin"
        export PATH

        kind="$1"
        payload="$(cat)"
        jqf() { printf '%s' "$payload" | ${pkgs.jq}/bin/jq -r "$1" 2>/dev/null; }

        # Which checkout this fired from — you usually have several sessions up.
        project="$(basename "$(jqf '.cwd // ""')")"
        [ -n "$project" ] || project="claude"
        # Per-session group, so a session replaces its own stale banner while
        # different sessions still stack.
        group="claude-$(jqf '.session_id // "0"')"

        # Distinct clip pools per event, so you can tell "finished" from
        # "blocked on you" by ear without looking. The acknowledgement lines
        # (yes, work-work, right-oh, ...) are deliberately unused: they are
        # peon *accepting* an order, which is not what any of these events are.
        #
        # ready-to-work and ready-to-work2 are held out of the done pool: both
        # rips are clipped mid-word and lose the final /k/ of "work". That is
        # damage in the source files, not the CoreAudio tail drop the padding
        # above fixes, so no amount of padding recovers it -- put them back
        # once the files are replaced.
        case "$kind" in
          done)
            title="Work complete"
            body="$(jqf '.last_assistant_message // ""' | grep -m1 -o '[^[:space:]].*')"
            [ -n "$body" ] || body="Turn finished."
            pool="work-complete"
            ;;
          attention)
            title="Needs your input"
            body="$(jqf '.message // ""' | grep -m1 -o '[^[:space:]].*')"
            [ -n "$body" ] || body="Claude is waiting on you."
            pool="something-need-doing what-do-you-want more-work hmm"
            ;;
          failed)
            title="Turn failed"
            body="$(jqf '.message // ""' | grep -m1 -o '[^[:space:]].*')"
            [ -n "$body" ] || body="The turn ended with an API error."
            pool="hmm"
            ;;
          *)
            exit 0
            ;;
        esac

        # NotificationCenter truncates hard anyway; keep it to one short line.
        body="$(printf '%s' "$body" | cut -c1-140)"
        clip="${peonSounds}/$(printf '%s\n' $pool | sort -R | head -1).wav"

        # A padded clip keeps afplay busy for ~2.5s, most of it silence. Hand
        # stage 2 to perl's setsid so it runs in its own session and the hook
        # returns immediately rather than blocking the turn on audio.
        #
        # Note this is NOT about surviving a killpg, which is what the comment
        # here used to claim (and 1b2a8e5's commit message with it). Measured
        # at a real Stop hook, afplay lives its full 1.82s undisturbed; the
        # truncation everyone was chasing was the CoreAudio tail drop that
        # peonSounds now pads around. perl and afplay are macOS built-ins, so
        # PATH here doesn't matter.
        exec /usr/bin/perl -e 'use POSIX; exit if fork; POSIX::setsid(); exec @ARGV' \
          ${claudeNotifyEmit} "$clip" "$title" "$project" "$body" "$group"
      '';
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
      # (claude-code is installed by programs.claude-code below.)
      home.packages = with pkgs; [
        pkgsUnstable.codex
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
        # rtk ("Rust Token Killer") compresses the output of ~100 common dev
        # commands (git, ls, cat, grep, pytest, ...) before an agent sees it,
        # cutting token use by 60-90%. Track unstable — it releases often.
        pkgsUnstable.rtk
        pkgs.bun # for hakuto
      ];

      programs.direnv = {
        package = pkgsUnstable.direnv;
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

      # Ghostty.app itself is installed manually (nixpkgs marks ghostty broken
      # on macOS), so package = null makes Home Manager manage only the config
      # file at ~/.config/ghostty/config.
      programs.ghostty = {
        enable = true;
        package = null;
        settings = {
          theme = "Catppuccin Frappe";
          keybind = [
            "ctrl+`=toggle_quick_terminal"
            "super+right=goto_window:next"
            "super+left=goto_window:previous"
          ];
          working-directory = "home";
          window-inherit-working-directory = false;
        };
      };

      programs.git = {
        enable = true;
        # diff-so-fancy.enable = true;
        settings = {
          user = {
            name = "Gasper Vozel";
            # Not a secret: this address is in the metadata of every commit.
            email = "gv@niteo.co";
          };
          core = {
            editor = "vim";
          };
          diff = {
            tool = "diffmerge";
          };
          github = {
            user = "karantan";
          };
          # Let gh supply credentials for https remotes. The leading "" resets
          # any helper inherited from the system gitconfig (e.g. osxkeychain).
          credential."https://github.com".helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
          credential."https://gist.github.com".helper = [
            ""
            "!${pkgs.gh}/bin/gh auth git-credential"
          ];
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
          nixre = "sudo darwin-rebuild switch --flake ~/.dotfiles#MacBook-Air";
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
      };

      # Claude Code: the package (tracking unstable — it releases often) plus
      # ~/.claude/settings.json, both managed by the Home Manager module.
      programs.claude-code = {
        enable = true;
        package = pkgsUnstable.claude-code;

        settings = {
          # Route every Bash tool call through rtk, which rewrites e.g.
          # `git status` to `rtk git status` before it runs. This is what
          # `rtk init -g` would install, but that patches settings.json in
          # place and this file is a read-only Nix store symlink.
          hooks.PreToolUse = [
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "${pkgsUnstable.rtk}/bin/rtk hook claude";
                }
              ];
            }
          ];

          # Peon clip + NotificationCenter banner whenever Claude finishes a
          # turn. See claudeNotify above for why this is two stages.
          hooks.Stop = [
            {
              hooks = [
                {
                  type = "command";
                  command = "${claudeNotify} done";
                }
              ];
            }
          ];

          # Same, but for a turn that died on an API error rather than
          # finishing — otherwise the two are indistinguishable from across
          # the room.
          hooks.StopFailure = [
            {
              hooks = [
                {
                  type = "command";
                  command = "${claudeNotify} failed";
                }
              ];
            }
          ];

          # The one that actually saves time: Stop only fires once Claude has
          # given up the turn, so it says nothing while Claude sits blocked on
          # a permission prompt mid-task. The matcher filters on
          # notification_type; the remaining types (auth_success, the
          # elicitation_* pair, agent_completed) are noise or already covered
          # by Stop.
          hooks.Notification = [
            {
              matcher = "permission_prompt|idle_prompt|agent_needs_input";
              hooks = [
                {
                  type = "command";
                  command = "${claudeNotify} attention";
                }
              ];
            }
          ];

          # Register extra plugin marketplaces, so /plugin can install from
          # them without a manual `/plugin marketplace add` first. (The
          # module's `marketplaces` option only supports directory sources,
          # so this github source stays in raw settings. niteo-mcp is a
          # directory and could use the option -- but that option *replaces*
          # settings.extraKnownMarketplaces wholesale, which would drop
          # hakuto, so both are written by hand here.)
          extraKnownMarketplaces = {
            hakuto = {
              source = {
                source = "github";
                repo = "teamniteo/hakuto";
              };
            };
            niteo-mcp = {
              source = {
                source = "directory";
                path = "${niteoMcpMarketplace}";
              };
            };
          };

          # Turn the plugins on. Without this the marketplace is merely known,
          # not installed.
          enabledPlugins = {
            "hakuto@hakuto" = true;
            "niteo-grafana@niteo-mcp" = true;
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
