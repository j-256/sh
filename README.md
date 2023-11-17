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
macOS ships with an ancient (2007) version of Bash, so in order for these scripts to work you might need to get the latest from [Homebrew](https://brew.sh), change the [shebang](https://en.wikipedia.org/wiki/Shebang_(Unix)) to zsh, or run it in the current shell with `source <file>`.  

Recent versions of macOS have `zsh` as the default interpreter/shell because Bash changed from GPLv2 to an even more open license – _"GPLv3 is to Silicon Valley as garlic is to vampires"_. Without opening up their own software, Apple cannot distribute Bash 4.0+ with their OS.  

Fun fact: `/bin/sh` is effectively a symlink to run `/bin/bash --posix` – it doesn't actually run the [Bourne shell](https://en.wikipedia.org/wiki/Bourne_shell).  
```sh
$ /bin/sh --version
GNU bash, version 3.2.57(1)-release (x86_64-apple-darwin23)
Copyright (C) 2007 Free Software Foundation, Inc.
```
