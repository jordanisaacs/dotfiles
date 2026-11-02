{ identifiers }:
{
  rsyncNet.network = {
    requested = false;
    inherit (identifiers.network) nodeName tailnetSuffix;
    # Durable secret state allocation, tagged policy and actual service users
    # must be reviewed before enrollment or any live daemon changes.
  };
}
