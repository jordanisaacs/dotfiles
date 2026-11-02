# rsync.net backups

Using a zfs-send capable server. It is on
freebsd.

## Setup

### Initial config

Install vim

```
pkg install vim
```

### sshd config

First scp my ssh key to the root user:

```
scp ~/.ssh/id_ed25519.pub root@my-server.rsync.net:.ssh/authorized_keys
```

Set the following to disable password logins after
confirming ssh works:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
```

### Users

To ensure I don't ssh as root unnecessarily, I will create a bunch of users for each use case.

A user can write/delete to it's volume and take snapshots manually. However, it cannot delete existing snapshots or the volume. This ensures if a computer is hacked, I can still recover to the last snapshot.  All users are public key authenticated.

To allow users to create child datasets under the selected parent dataset, need `vfs.usermount=1`. Also user needs to own the mountpoint. https://docs.freebsd.org/en/books/handbook/zfs/#zfs-zfs-allow-create

```
echo "vfs.usermount=1" >> /etc/sysctl.conf
```

Creating a user:

```
useradd # follow prompts [archiver:archiver]
zfs allow create,mount,snapshot archiver
chown archiver:archiver /mnt/data1/archiver

# To allow SSH into archiver
cp -R ~/.ssh /home/archiver/
chown -R archiver:archiver /home/archiver/.ssh
```

### Volumes

There are two types of backups: archival & continual.

* Archival backups are one time backups done manually, e.g. by me.
* Continual backups should be performed by automatically, e.g. by a machine.

#### Archival volume

There is an `archive` user in the `data1/archive` volume. It follows the access pattern laid out above. It is accessed by users (not machines) and is a spot for manually backing random archival data. Generally, when doing an archive, the user would manually snapshot, but a weekly snapshot can be taken in case a user forgets.

#### Continual volumes

##### Machines

These would have a bunch of users that machines access. E.g. `laptop`, `server`, etc. Each machine would have an SSH key to back up its own data. Either through borg, zfs-send/recv, etc.

These take snapshots more often since the data is continually changing.

#### Applications

These would be things like git mirroring. So users such as `git`. There can be machines with access to this and users.



