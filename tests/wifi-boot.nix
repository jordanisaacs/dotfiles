{
  pkgs,
  withFix ? true,
}:
let
  inherit (pkgs) lib;
  # mac80211_hwsim's second radio is the laptop client; the first is its AP.
  clientMac = "02:00:00:00:01:00";
  fixtureProfile = pkgs.writeText "vm-iwd-profile" ''
    [Security]
    Passphrase=vm-only-password
  '';
in
pkgs.testers.runNixOSTest {
  name = "wifi-stable-link-boot";
  nodes.machine = {
    imports = [
      ../modules/system/networking
      ({ lib, ... }: {
        options.jd = {
          users.users = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
          core.time = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          unbound.enable = lib.mkEnableOption "unbound fixture";
        };
      })
    ];
    virtualisation.memorySize = 1024;
    boot.kernelModules = [ "mac80211_hwsim" ];
    jd.networking.wifi = {
      enable = true;
      interface = "wifi0";
      permanentMACAddress = if withFix then clientMac else null;
    };
    # qemu-vm disables wireless by default even when the production module enables it.
    networking.wireless.enable = lib.mkOverride 0 true;
    networking.firewall.enable = false;
    systemd = {
      network = {
        wait-online.enable = false;
        links."90-predictable-fixture" = {
          matchConfig.PermanentMACAddress = clientMac;
          linkConfig = {
            NamePolicy = "";
            Name = "wlp170s0";
          };
        };
        networks."30-fixture-ap" = {
          matchConfig.Name = "wlan0";
          address = [ "192.168.77.1/24" ];
          linkConfig.RequiredForOnline = "no";
        };
      };
      tmpfiles.rules = [
        "d /var/lib/iwd 0700 root root -"
        "C /var/lib/iwd/fixture.psk 0600 root root - ${fixtureProfile}"
      ];
    };
    services.hostapd = {
      enable = true;
      radios.wlan0 = {
        band = "2g";
        channel = 6;
        countryCode = "US";
        networks.wlan0 = {
          ssid = "fixture";
          authentication = {
            mode = "wpa2-sha1";
            wpaPassword = "vm-only-password";
          };
        };
      };
    };
    services.dnsmasq = {
      enable = true;
      settings = {
        port = 0;
        interface = "wlan0";
        bind-dynamic = true;
        dhcp-range = [ "192.168.77.10,192.168.77.20,255.255.255.0,1h" ];
      };
    };
    environment.systemPackages = [ pkgs.iw ];
  };
  testScript = ''
    import json
    from datetime import timedelta

    start_all()
    machine.wait_for_unit("wifi-profile-migration.service")
    machine.wait_for_unit("hostapd.service")
    machine.wait_until_succeeds("test -e /sys/class/net/wifi0", timeout=timedelta(seconds=20))
    machine.succeed("udevadm info --query=property /sys/class/net/wifi0 | grep -F ID_NET_LINK_FILE=/etc/systemd/network/10-wifi.link")
    machine.wait_for_unit("wpa_supplicant-wifi0.service")
    try:
        machine.wait_until_succeeds("wpa_cli -i wifi0 status | grep -qx wpa_state=COMPLETED", timeout=timedelta(seconds=30))
    except Exception:
        print(machine.execute("wpa_cli -i wifi0 status"))
        print(machine.execute("journalctl -b -u wpa_supplicant-wifi0 -u hostapd --no-pager"))
        print(machine.execute("iw dev"))
        raise
    machine.wait_until_succeeds("ip -4 -j address show dev wifi0 | grep -F 192.168.77.", timeout=timedelta(seconds=30))
    addresses = json.loads(machine.succeed("ip -4 -j address show dev wifi0"))[0]["addr_info"]
    assert any(address["local"].startswith("192.168.77.") for address in addresses), addresses
    machine.succeed("test $(stat -c %a /etc/wpa_supplicant/imperative.conf) = 600")
    machine.succeed("systemctl is-active multi-user.target")
    machine.fail("systemctl is-enabled systemd-networkd-wait-online.service")
    # No association must also leave login usable, without a network-online delay.
    machine.succeed("systemctl stop hostapd.service")
    machine.wait_until_succeeds("wpa_cli -i wifi0 status | grep -v wpa_state=COMPLETED | grep -q wpa_state=")
    machine.succeed("systemctl is-active multi-user.target")
  '';
}
