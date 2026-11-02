"""Send real Restic HTTP/2 requests over a caller-selected SSH command.

The integration fixture supplies generated device credentials and policy; this
helper owns only the wire protocol and never creates authorization or storage.
"""

import argparse
import base64
import json
import os
import selectors
import subprocess
import time

import h2.config
import h2.connection
import h2.events


def request(command, method, path, body=b"", *, timeout=15):
    """Send an actual HTTP/2 REST request over the forced SSH command."""
    connection = h2.connection.H2Connection(
        config=h2.config.H2Configuration(client_side=True, header_encoding="utf-8")
    )
    connection.initiate_connection()
    stream = connection.get_next_available_stream_id()
    connection.send_headers(
        stream,
        [
            (":method", method),
            (":scheme", "http"),
            (":authority", "fixture"),
            (":path", path),
            ("content-length", str(len(body))),
        ],
        end_stream=not body,
    )
    if body:
        connection.send_data(stream, body, end_stream=True)
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    status = None
    response = bytearray()
    try:
        process.stdin.write(connection.data_to_send())
        process.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                for key, _ in selector.select(timeout=0.5):
                    data = os.read(key.fileobj.fileno(), 65536)
                    assert data, "SSH closed before the HTTP/2 response completed"
                    for event in connection.receive_data(data):
                        if isinstance(event, h2.events.ResponseReceived):
                            status = int(dict(event.headers)[":status"])
                        elif isinstance(event, h2.events.DataReceived):
                            response.extend(event.data)
                            connection.acknowledge_received_data(
                                event.flow_controlled_length, event.stream_id
                            )
                        elif isinstance(event, h2.events.StreamEnded):
                            return status, bytes(response)
                    pending = connection.data_to_send()
                    if pending:
                        process.stdin.write(pending)
                        process.stdin.flush()
        raise AssertionError("HTTP/2 request timed out")
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()
        process.stderr.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--method", required=True)
    parser.add_argument("--path", required=True)
    parser.add_argument("--body", default="")
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    command = arguments.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("an SSH command is required after --")
    status, body = request(
        command,
        arguments.method,
        arguments.path,
        arguments.body.encode(),
        timeout=arguments.timeout,
    )
    print(json.dumps({"status": status, "bodyBase64": base64.b64encode(body).decode()}))


if __name__ == "__main__":
    main()
