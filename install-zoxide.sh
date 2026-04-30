#!/bin/bash
# Zoxide Installation Script

sudo pacman -S zoxide

FISH_SETUP_LINE="zoxide init fish | source"
grep -qF "$FISH_SETUP_LINE" ~/.config/fish/config.fish || echo "$FISH_SETUP_LINE" >> ~/.config/fish/config.fish 

ZSH_SETUP_LINE='eval "$(zoxide init zsh)"'
grep -qF "$ZSH_SETUP_LINE" ~/.zshrc || echo "$ZSH_SETUP_LINE" >> ~/.zshrc 


BASH_SETUP_LINE='eval "$(zoxide init bash)"'
grep -qF "$BASH_SETUP_LINE" ~/.bashrc || echo "$BASH_SETUP_LINE" >> ~/.bashrc 

echo "Zoxide installation complete!"
