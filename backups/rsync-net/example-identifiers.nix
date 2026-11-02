# Synthetic identifiers for examples and isolated regression checks.
{
  host = "storage.example.invalid";
  publicHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4";
  expectedRelease = "14.4-RELEASE";
  pool = {
    name = "data1";
    guid = "123456";
  };
  recoveryRecipients = [ "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ];
  backup = {
    principal = "backup-user";
    uid = 2001;
    gid = 2001;
    dataset = "data1/backups/user/example";
    mountpoint = "/mnt/data1/backups/user/example";
    device = "workstation";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4";
    identityFile = "/home/example/.local/state/rsync-net/keys/backup";
  };
  git = {
    binding = "shared";
    principal = "git-host";
    uid = 2002;
    gid = 2002;
    home = "/home/git-host";
    dataset = "data1/git/shared";
    mountpoint = "/mnt/data1/git/shared";
    device = "workstation";
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4";
    gpgFingerprint = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
    identityFile = "/home/example/.local/state/rsync-net/keys/git";
  };
  control = {
    dataset = "data1/control";
    path = "/mnt/data1/control";
  };
  network = {
    nodeName = "storage";
    tailnetSuffix = "example.ts.net";
  };
}
