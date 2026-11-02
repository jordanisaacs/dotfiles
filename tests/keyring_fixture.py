"""Initialize and inspect only a disposable VM's encrypted keyring fixture."""

import argparse
import json

import secretstorage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("initialize", "lock", "status"))
    args = parser.parse_args()
    connection = secretstorage.dbus_init()
    collection = secretstorage.get_default_collection(connection)
    if args.operation == "initialize":
        assert not collection.is_locked()
        collection.create_item(
            "Boot keyring fixture",
            {"fixture": "boot-keyring"},
            b"KeyringFixtureCanary-2026",
        )
    elif args.operation == "lock":
        collection.lock()
    locked = collection.is_locked()
    print(
        json.dumps(
            {
                "locked": locked,
                "canary": False
                if locked
                else any(
                    item.get_secret() == b"KeyringFixtureCanary-2026"
                    for item in collection.search_items({"fixture": "boot-keyring"})
                ),
            }
        )
    )


if __name__ == "__main__":
    main()
