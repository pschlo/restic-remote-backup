# restic-remote-backup
Creates restic backups of rclone remotes. Supports Telegram notifications.

This script fixes a problem in restic: a parent snapshot is only detected if the path is the same. However, when backing up a remote mount, the mount path might change, even though it still points to the same server. Because there is currently no way of changing the path attribute of snapshots, this script uses a kind of `chroot` to create a temporary backup environment for restic. That way, the parent snapshot is found independent of where on the local machine the remote is mounted. Note that the hostname is also used for finding the parent snapshot.

See also https://github.com/restic/restic/issues/2092



## Usage
Rename `config-schema.cfg` to `config.cfg` and edit it. Make sure the config file is in the same folder as `backup` and run

```bash
$ ./backup
```



## Requirements

* restic
* rclone
* [`serve-fuse-mount`](https://github.com/pschlo/serve-fuse-mount)
