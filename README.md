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
