# dotfiles

This are my dotfiles. Well actually this is my nix-darwin config which also contains dotfiles.

To install nix-darwin I’ve followed these instructions: Setting up Nix on macOS. Install nix using Determinate System’s shell installer BUT select Nix from the official nixos.org repo and not Determinate Nix.

The idea is to use only nix-darwin to control macos settings and packages. Don’t use homebrew (because with this setup you won’t need it).

Once you’ve installed and configured nix-darwin you should also add home-manager.

For an example of dotfiles look at zupo’s repo.

## Commands

To open and edit .nix config run
```bash
nixcfg
```

To apply the changes run
```bash
nixre
```

These 2 commands are aliases for `code ~/.dotfiles`  and `darwin-rebuild switch --flake ~/.dotfiles#MacBook-Air --impure`. 
