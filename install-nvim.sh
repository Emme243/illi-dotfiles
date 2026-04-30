#!/bin/sh
# Downloads custom dotfiles, and stows nvim dotfiles

sudo pacman -S neovim
rm -rf ~/dotfiles
git clone git@github.com:Emme243/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow nvim

echo "Nvim Dotfiles installation complete!"
