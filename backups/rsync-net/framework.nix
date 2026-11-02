{ identifiers }:
{
  rsyncNet = {
    mode = "public";
    connection.host = identifiers.host;
    setup = {
      enable = true;
      backends = [
        "restic"
        "git"
      ];
      snapshotting = true;
      inherit (identifiers) expectedRelease;
    };
    inherit (identifiers) pool;
    recovery = {
      enable = true;
      recipients = identifiers.recoveryRecipients;
    };
    principals.${identifiers.backup.principal} = {
      inherit (identifiers.backup) uid gid dataset;
      backend = "restic";
      devices.${identifiers.backup.device}.publicKey = identifiers.backup.publicKey;
    };
    datasets.${identifiers.backup.principal} = {
      name = identifiers.backup.dataset;
      inherit (identifiers.backup) mountpoint principal;
      purpose = "user";
      # Snapshot-inclusive caps do not reserve space.
      quotaBytes = 1099511627776;
    };
    principals.${identifiers.git.principal} = {
      inherit (identifiers.git)
        uid
        gid
        home
        dataset
        ;
      backend = "git";
      devices.${identifiers.git.device} = {
        inherit (identifiers.git) publicKey gpgFingerprint;
      };
    };
    datasets.${identifiers.git.principal} = {
      name = identifiers.git.dataset;
      inherit (identifiers.git) mountpoint principal;
      purpose = "git";
      quotaBytes = 274877906944;
    };
    # One policy for backup, Git, and future binary cache datasets.
    snapshotSchedules = {
      hourly = {
        schedule = "15 * * * *";
        retention = "48h";
      };
      daily = {
        schedule = "20 0 * * *";
        retention = "30d";
      };
      weekly = {
        schedule = "25 0 * * 0";
        retention = "12w";
      };
      monthly = {
        schedule = "30 0 1 * *";
        retention = "1y";
      };
      yearly = {
        schedule = "35 0 1 1 *";
        retention = "forever";
      };
    };
    # Add the Nix cache principal after its separate IDs, keys and storage
    # allocation are selected; an incomplete principal blocks all setup.
    control = {
      enable = true;
      inherit (identifiers.control) dataset path;
      quotaBytes = 1073741824;
    };
  };
}
