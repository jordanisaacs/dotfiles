"""Control default PulseAudio devices, with unity gain as the ordinary ceiling."""

import argparse
import json
import subprocess

NORMAL_VOLUME = 65536


def pactl(*arguments, capture=False):
    result = subprocess.run(
        [CONFIG["pactl"], *arguments],
        check=True,
        capture_output=capture,
        text=True,
    )
    return result.stdout.strip() if capture else None


def nonnegative(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("expected a nonnegative number")
    return number


def default_sink():
    name = pactl("get-default-sink", capture=True)
    sinks = json.loads(pactl("--format=json", "list", "sinks", capture=True))
    for sink in sinks:
        if sink["name"] == name:
            return name, [channel["value"] for channel in sink["volume"].values()]
    raise RuntimeError("The default audio output is unavailable")


def set_volume(name, values, target):
    maximum = max(values)
    channels = [
        (value * target + maximum // 2) // maximum if maximum else target
        for value in values
    ]
    pactl("set-sink-volume", name, *map(str, channels))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    groups = parser.add_subparsers(dest="group", required=True)
    volume = groups.add_parser("vol", help="control default output volume")
    commands = volume.add_subparsers(dest="action", required=True)
    commands.add_parser("get")
    up = commands.add_parser("up")
    up.add_argument("step", type=nonnegative, nargs="?", default=2)
    up.add_argument(
        "maximum",
        type=nonnegative,
        nargs="?",
        default=100,
        help="explicit amplification override; ordinary controls stop at 100%%",
    )
    down = commands.add_parser("down")
    down.add_argument("step", type=nonnegative, nargs="?", default=2)
    direct = commands.add_parser("set", help="explicitly set volume, including boost")
    direct.add_argument("percent", type=nonnegative)
    commands.add_parser("toggle")
    microphone = groups.add_parser("mic", help="control default microphone mute")
    microphone.add_subparsers(dest="action", required=True).add_parser("toggle")
    arguments = parser.parse_args()
    if arguments.group == "mic":
        pactl("set-source-mute", "@DEFAULT_SOURCE@", "toggle")
    elif arguments.action == "toggle":
        pactl("set-sink-mute", "@DEFAULT_SINK@", "toggle")
    else:
        name, channels = default_sink()
        maximum = max(channels)
        if arguments.action == "get":
            print(f"{(maximum * 100 + NORMAL_VOLUME // 2) // NORMAL_VOLUME}%")
            return
        if arguments.action == "up":
            limit = arguments.maximum * NORMAL_VOLUME // 100
            target = min(maximum + arguments.step * NORMAL_VOLUME // 100, limit)
        elif arguments.action == "down":
            target = max(0, maximum - arguments.step * NORMAL_VOLUME // 100)
        else:
            target = arguments.percent * NORMAL_VOLUME // 100
        set_volume(name, channels, target)


if __name__ == "__main__":
    main()
