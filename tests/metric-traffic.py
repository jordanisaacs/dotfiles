"""Synthetic TCP traffic confined to the activity-monitor test VMs."""

import argparse
import socket
import time


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["server", "client"])
    parser.add_argument("host", nargs="?", default="0.0.0.0")
    args = parser.parse_args()
    with socket.socket() as sock:
        if args.mode == "server":
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((args.host, 8765))
            sock.listen()
            while True:
                connection, _ = sock.accept()
                with connection:
                    try:
                        while True:
                            connection.sendall(bytes(32768))
                            time.sleep(0.02)
                    except BrokenPipeError, ConnectionResetError:
                        pass
        else:
            sock.connect((args.host, 8765))
            while sock.recv(65536):
                pass


if __name__ == "__main__":
    main()
