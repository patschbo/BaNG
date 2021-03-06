BaNG on macOS
=============

BaNG can be installed on a macOS computer allowing to back up Mac clients to a native HFS+ file system for full support of extended attributes. Given that the HFS+ file system lacks a snapshotting feature, incremental backups are made with hardlinks using the `--link-dest` option of rsync. Note that BaNG is primarily meant for backups of user data. If you need to be able to restore a full system you should use TimeMachine instead.


Rsync command for restore
-------------------------

```sh
/opt/local/bin/rsync -axHXv --no-D --delete --rsync-path=/opt/local/bin/rsync --stats ORIGIN DESTINATION
```

Whenever possible restore only specific files or folders. If you restore the full home, all local copies of emails and other caches will have to be regenerated (as they are typically excluded from the backup).


Installation
------------

### Client-side

```sh
sudo port install rsync
```

### Server-side

```sh
sudo port install rsync coreutils p5-timedate p5-file-find-rule p5-yaml-tiny p5-dbd-mysql p5-mime-lite p5-template-toolkit p5-text-diff p5-json
```

The perl `forks` package is not available through MacPorts and has to be installed for instance with `cpanm`:

```sh
curl -L http://cpanmin.us > cpanm
chmod u+x cpanm
./cpanm install forks
```

#### OS X specific BaNG configuration

The path for the `rsync` and `date` commands has to point to the MacPorts installation:

`etc/servers/macserver_defaults.yaml`

```yaml
path_date:              "/opt/local/bin/gdate"
path_rsync:             "/opt/local/bin/rsync"
```

Use hardlinks for incremental backups and also transfer extended attributes, but exclude special device files.

`etc/groups/mac-workstation.yaml`

```yaml
BKP_RSYNC_RSHELL_PATH:  "/opt/local/bin/rsync"
BKP_STORE_MODUS:        "links"
BKP_RSYNC_XATTRS:       1
BKP_RSYNC_NODEVICES:    1
```
