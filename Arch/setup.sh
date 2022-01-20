## ! Make sure you are logged in as root, and have an internet connection. To do this:
# ip link # ? Identify the network interface, probably the second one on the list
# ip link set <interface> up # ? Set it to UP, by default it is DOWN

## ! Then clone this repository (after setting up git) with:
# git config --global credential.helper store
# git config --global user.email  "brendanjohnharris@gmail.com"
# git config --global user.name "brendanjohnharris"
# git clone --bare https://github.com/brendanjohnharris/Arch.git $HOME/.dotfiles
# git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME checkout

# * Now we assume the bare git repo for our config is in place. We also assume the current shell is bash. 
# ? `config` now takes the place of `git` for config stuff
echo -e 'config () {\n    git --git-dir="$HOME/.dotfiles" --work-tree="$HOME" "$@"\n}' >> ~/.bashrc
source $HOME/.bashrc
cd $HOME/.dotfiles
git config --local status.showUntrackedFiles no
cd $HOME


