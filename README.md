# vim stuff

1. `mkdir ~/.vim && cd ~/.vim`
2. `git clone https://github.com/metacoin/vim-stuff.git .`
3. `mv .vimrc ~/.vimrc`
4. `cd bundle`

Then install the bundles individually:

```
git clone https://github.com/bling/vim-airline \
&& git clone https://github.com/fatih/vim-go.git \
&& git clone https://github.com/plasticboy/vim-markdown.git \
&& git clone git://github.com/tpope/vim-sensible.git
```

## Ubuntu

Ubuntu has some differences. Go to `/plugin/` and make minibuffexpl.vim not a hidden file, and delete all vim-airline stuff.

Also, for go syntax, this is needed:

```bash
sudo apt-get install vim-gocomplete gocode vim-syntax-go
```
