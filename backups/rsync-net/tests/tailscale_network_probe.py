"""Exercise real isolated Headscale/Tailscale transport and scoped OpenSSH.

Executed by the native NixOS test driver, never on production machines.
All keys, identities and control-plane state are synthetic VM fixtures.
"""

import ipaddress
import json
import shlex
import tempfile
import time
from datetime import timedelta


def command(*arguments):
    return shlex.join(arguments)


def write(machine, path, text, mode=0o600):
    """Copy test input without embedding private fixture material in commands."""
    with tempfile.NamedTemporaryFile(mode="w") as fixture:
        fixture.write(text)
        fixture.flush()
        machine.copy_from_host(fixture.name, path)
    machine.succeed(command("chmod", oct(mode)[2:], path))


def ssh_arguments(address, user="backup", port=22):
    return [
        "ssh",
        "-F",
        "/dev/null",
        "-i",
        "/run/device-key",
        "-o",
        "IdentityAgent=none",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "UserKnownHostsFile=/run/provider-known-hosts",
        "-o",
        "ConnectTimeout=4",
        "-o",
        "ConnectionAttempts=1",
        "-p",
        str(port),
        f"{user}@{address}",
        "id -un" if user == "root" else "ignored-client-command",
    ]


def ssh(machine, address, user="backup", port=22):
    argv = ssh_arguments(address, user, port)
    result = json.loads(
        machine.succeed(
            command(
                "python3",
                "-c",
                "import json,subprocess,sys; p=subprocess.run(['timeout','6',*json.loads(sys.argv[1])],capture_output=True,text=True,timeout=10); print(json.dumps([p.returncode,p.stdout+p.stderr]))",
                json.dumps(argv),
            ),
            timeout=timedelta(seconds=15),
        )
    )
    return result


def set_policy(control, policy):
    # Only the disposable control VM's explicit fixture file is replaced.
    control.succeed(command("rm", "/etc/headscale/test-policy.json"))
    write(control, "/etc/headscale/test-policy.json", json.dumps(policy), mode=0o644)
    control.succeed("systemctl kill --kill-whom=main --signal=HUP headscale.service")


def wait_for_denied(machine, address):
    deadline = time.monotonic() + 30
    while True:
        code, output = ssh(machine, address)
        if code != 0:
            return
        assert time.monotonic() < deadline, (
            "policy update did not deny client",
            output,
        )
        time.sleep(0.2)


def outbound_probe(address, *, allowed):
    expectation = (
        "rc == 0 and line.startswith(b'HTTP/')"
        if allowed
        else "rc != 0 and not line.startswith(b'HTTP/')"
    )
    # tailscale nc ends its copy loop when stdin closes, so subprocess.run(input)
    # can discard a successful response. Keep stdin open until its first line.
    script = (
        "import subprocess; p=subprocess.Popen(['timeout','6','tailscale','nc',"
        + repr(address)
        + ",'9999'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE); "
        + "p.stdin.write(b'GET / HTTP/1.0\\r\\n\\r\\n'); p.stdin.flush(); "
        + "line=p.stdout.readline(); p.stdin.close(); rc=p.wait(timeout=10); assert "
        + expectation
        + ", (rc,line,p.stderr.read())"
    )
    return command(
        "python3",
        "-c",
        script,
    )


def run(*, control, provider, allowed, denied, private_config_path):
    users = {}
    for name in ["storage", "allowed", "denied"]:
        data = json.loads(
            control.succeed(
                command("headscale", "users", "create", name, "--output", "json")
            )
        )
        users[name] = data["id"]

    for machine, user in [
        (provider, "storage"),
        (allowed, "allowed"),
        (denied, "denied"),
    ]:
        arguments = [
            "headscale",
            "preauthkeys",
            "create",
            "--user",
            str(users[user]),
            "--output",
            "json",
        ]
        if machine is provider:
            arguments += ["--tags", "tag:storage"]
        key = json.loads(control.succeed(command(*arguments)))["key"]
        write(machine, "/run/fixture-authkey", key)
        machine.succeed(
            command(
                "tailscale",
                "up",
                "--login-server=https://control",
                "--auth-key=file:/run/fixture-authkey",
                "--accept-dns=false",
                "--accept-routes=false",
                "--ssh=false",
                "--hostname=" + machine.name,
            ),
            timeout=timedelta(seconds=60),
        )
        machine.succeed(command("rm", "/run/fixture-authkey"))

    provider_ip = str(ipaddress.ip_address(provider.succeed("tailscale ip -4").strip()))
    provider_dns = json.loads(provider.succeed("tailscale status --json"))["Self"][
        "DNSName"
    ].rstrip(".")
    allowed_ip = str(ipaddress.ip_address(allowed.succeed("tailscale ip -4").strip()))
    # QEMU's separate user-mode NIC gives every guest the same 10.0.2.15;
    # exercise the shared provider/client network through the native test VLAN.
    addresses = json.loads(provider.succeed("ip -j -4 address show dev eth1"))
    provider_public = str(ipaddress.ip_address(addresses[0]["addr_info"][0]["local"]))
    host_key = provider.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub").split()[:2]
    hosts = f"{provider_ip},{provider_public},[127.0.0.1]:2222"
    public_keys = []
    for machine in [allowed, denied]:
        machine.succeed(
            command(
                "ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", "/run/device-key"
            )
        )
        public_keys.append(machine.succeed("cat /run/device-key.pub").strip())
        write(
            machine,
            "/run/provider-known-hosts",
            hosts + " " + " ".join(host_key) + "\n",
        )

    provider.succeed(
        "mkdir -p /usr/local/etc/rsync-net/authorized_keys /etc/ssh/public-authorized /srv/cache"
    )
    write(
        provider,
        "/usr/local/etc/rsync-net/authorized_keys/backup",
        "".join(
            'restrict,command="/run/current-system/sw/bin/id -un" ' + key + "\n"
            for key in public_keys
        ),
        mode=0o644,
    )
    # Root administrative access uses a different key than either routine user.
    control.succeed(
        command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", "/run/device-key")
    )
    admin_key = control.succeed("cat /run/device-key.pub").strip()
    write(provider, "/etc/ssh/public-authorized/root", admin_key + "\n", mode=0o644)
    write(control, "/run/provider-known-hosts", hosts + " " + " ".join(host_key) + "\n")
    provider.succeed(
        command(
            "systemd-run",
            "--unit=private-sshd",
            "/run/current-system/sw/bin/sshd",
            "-D",
            "-e",
            "-f",
            private_config_path,
        )
    )
    provider.wait_for_open_port(2222)
    write(provider, "/srv/cache/fixture", "private-cache-over-tailnet\n", mode=0o644)
    provider.succeed(
        command(
            "systemd-run",
            "--unit=cache-http",
            "/run/current-system/sw/bin/python3",
            "-m",
            "http.server",
            "--bind",
            "127.0.0.1",
            "--directory",
            "/srv/cache",
            "8080",
        )
    )
    provider.wait_for_open_port(8080)
    provider.succeed("tailscale serve --bg --tcp=22 tcp://127.0.0.1:2222")
    provider.succeed("tailscale serve --bg --http=80 http://127.0.0.1:8080")

    code, output = ssh(control, provider_public, user="root")
    assert code == 0, ("public administrative access broken", output)
    for machine in [allowed, denied]:
        code, output = ssh(machine, provider_public)
        assert code != 0 and "Permission denied" in output, (
            "routine credential accepted on public endpoint",
            output,
        )
    allowed.wait_until_succeeds(
        command(
            "curl",
            "--fail",
            "--max-time",
            "4",
            "--resolve",
            f"{provider_dns}:80:{provider_ip}",
            f"http://{provider_dns}/fixture",
        ),
        timeout=timedelta(seconds=90),
    )
    code, output = ssh(allowed, provider_ip)
    assert code == 0 and output.strip() == "backup", (
        "authorized private SSH failed",
        output,
    )
    code, output = ssh(denied, provider_ip)
    assert code != 0, ("tailnet policy admitted denied client", output)

    # Same already-authorized SSH device key and endpoint succeed after changing
    # only the tailnet ACL; restore the original policy and require denial again.
    base_policy = json.loads(control.succeed("cat /etc/headscale/test-policy.json"))
    inbound_allowed = json.loads(json.dumps(base_policy))
    inbound_allowed["acls"].append(
        {"action": "accept", "src": ["denied@"], "dst": ["tag:storage:22"]}
    )
    set_policy(control, inbound_allowed)
    denied.wait_until_succeeds(
        command(*ssh_arguments(provider_ip)), timeout=timedelta(seconds=30)
    )
    set_policy(control, base_policy)
    wait_for_denied(denied, provider_ip)

    # This destination is reachable only through its own tailnet address.
    allowed.succeed(
        command(
            "systemd-run",
            "--unit=peer-http",
            "/run/current-system/sw/bin/python3",
            "-m",
            "http.server",
            "--bind",
            allowed_ip,
            "9999",
        )
    )
    denied.wait_until_succeeds(
        command("curl", "--fail", "--max-time", "4", f"http://{allowed_ip}:9999"),
        timeout=timedelta(seconds=90),
    )
    provider.succeed(outbound_probe(allowed_ip, allowed=False))
    outbound_allowed = json.loads(json.dumps(base_policy))
    outbound_allowed["acls"].append(
        {"action": "accept", "src": ["tag:storage"], "dst": ["allowed@:9999"]}
    )
    set_policy(control, outbound_allowed)
    provider.wait_until_succeeds(
        outbound_probe(allowed_ip, allowed=True), timeout=timedelta(seconds=30)
    )
    set_policy(control, base_policy)
    provider.wait_until_succeeds(
        outbound_probe(allowed_ip, allowed=False), timeout=timedelta(seconds=30)
    )
    assert (
        json.loads(provider.succeed("tailscale serve status --json")).get(
            "AllowFunnel", {}
        )
        == {}
    )
    provider.succeed("test ! -e /sys/class/net/tailscale0")
    print(
        json.dumps(
            {
                "real_tailscale_userspace_serve": True,
                "private_ssh_and_cache_from_allowed_client": True,
                "public_admin_preserved": True,
                "public_routine_keys_denied": True,
                "unauthorized_tailnet_client_denied": True,
                "storage_node_lateral_tailnet_connection_denied": True,
                "same_identity_and_userspace_dial_acl_counterfactuals": True,
                "production_tailnet_contacted": False,
                "freebsd_runtime_and_tailnet_lock_proven": False,
            }
        )
    )
