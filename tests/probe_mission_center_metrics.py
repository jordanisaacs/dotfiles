"""Read actual Magpie IPC using its production protobuf descriptors."""

import argparse
import json
import os
import time
from pathlib import Path

import pynng
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expect", choices=["allowed", "denied"])
    parser.add_argument("--traffic-pid", type=int)
    args = parser.parse_args()
    descriptors = descriptor_pb2.FileDescriptorSet.FromString(
        Path(os.environ["MAGPIE_DESCRIPTORS"]).read_bytes()
    )
    pool = descriptor_pool.DescriptorPool()
    for item in descriptors.file:
        pool.Add(item)
    request_type = message_factory.GetMessageClass(
        pool.FindMessageTypeByName("magpie.ipc.Request")
    )
    response_type = message_factory.GetMessageClass(
        pool.FindMessageTypeByName("magpie.ipc.Response")
    )
    addr = "ipc://" + os.environ["XDG_RUNTIME_DIR"] + "/mission-center-metrics.sock"
    last = {}
    with pynng.Req0(dial=addr, send_timeout=5000, recv_timeout=5000) as connection:
        for _ in range(40):
            request = request_type()
            request.get_processes.process_map.SetInParent()
            connection.send(request.SerializeToString())
            processes = response_type.FromString(connection.recv()).processes.processes
            request = request_type()
            request.get_cpu.SetInParent()
            connection.send(request.SerializeToString())
            cpu = response_type.FromString(connection.recv()).cpu.cpu
            error = processes.WhichOneof("network_stats_error")
            power = cpu.power_draw_w if cpu.HasField("power_draw_w") else None
            traffic = (
                processes.processes.get(args.traffic_pid) if args.traffic_pid else None
            )
            usage = traffic.usage_stats.network_usage if traffic else 0
            last = {
                "network_error": error,
                "cpu_watts": power,
                "network_bytes_sec": usage,
            }
            if args.expect == "allowed":
                if error is None and power is not None and 9 < power < 11 and usage > 0:
                    print(json.dumps(last))
                    return
            elif error == "permissions_error" and power is None:
                print(json.dumps(last))
                return
            time.sleep(1)
    raise AssertionError(last)


if __name__ == "__main__":
    main()
