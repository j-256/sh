# sh

A mixed collection of small shell utilities I've written over the years to make my own life easier. Some are broadly useful; plenty are niche to my own workflow. Every script has a test and a doc.

- Browse the catalog: [INDEX.md](INDEX.md) — rendered at <https://toolio.sh>
- Rendered docs: `https://toolio.sh/<script>.md.html` (e.g. [tsd](https://toolio.sh/tsd.md.html))
- Conventions: [CONVENTIONS.md](CONVENTIONS.md), [DOCS.md](DOCS.md), [TESTING.md](TESTING.md)

## Some picks

A few that might be worth a look before you scroll the catalog. These are mostly the ones where the script does something non-obvious or solves a recurring annoyance. The rest of the catalog is a mix — some broadly useful, plenty that are niche.

- [`prompt`](docs/prompt.md?html) ([script](prompt)) — sourced interactive prompt with default value, placeholder, and Ctrl-C safety
- [`tsd`](docs/tsd.md?html) ([script](tsd)) — paste any number, get back a timestamp or a duration
- [`inflate`](docs/inflate.md?html) ([script](inflate)) — historical USD amounts adjusted for inflation
- [`curl-timing`](docs/curl-timing.md?html) ([script](curl-timing)) — time HTTP requests and compare URLs head-to-head
- [`pin-dns`](docs/pin-dns.md?html) ([script](pin-dns)) — curl wrapper that overrides DNS without touching `/etc/hosts`
- [`explode`](docs/explode.md?html) ([script](explode)) — move a directory's contents up one level after a nested-folder unzip

## Installation
#### 3 options:
1. To run from any folder, make the utility executable and move it to a folder in your `$PATH`:
```sh
$ chmod +x ~/Downloads/utility
$ mv -v ~/Downloads/utility /usr/local/bin
$ utility
Utility output!
```

2. Otherwise, make it executable, put it where you want, then call it by path:
```sh
$ chmod +x ~/Downloads/utility
$ mv -v ~/Downloads/utility /my/special/path/utility
$ /my/special/path/utility
Utility output!
```

3. If you don't want to make it executable or move it into your `$PATH`, you could just `source` it.  
This may not be a viable option in the future, so using an executable is preferred.
```sh
# `.` == `source`, use either
$ . /my/special/path/utility
Utility output!
```

## Notes
macOS ships with an ancient (2007) version of Bash, but every script in this repo targets Bash 3.2, so they run on stock macOS without [Homebrew](https://brew.sh) or a shebang swap. The reason it's that old: Bash moved from GPLv2 to a license that demands more openness from distributors – _"GPLv3 is to Silicon Valley as garlic is to vampires"_. Without opening up their own software, Apple cannot distribute Bash 4.0+ with their OS, which is also why recent versions of macOS have `zsh` as the default interpreter/shell.  

Fun fact: `/bin/sh` is effectively a symlink to run `/bin/bash --posix` – it doesn't actually run the [Bourne shell](https://en.wikipedia.org/wiki/Bourne_shell).  
```sh
$ /bin/sh --version
GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin23)
Copyright (C) 2007 Free Software Foundation, Inc.
```
