# dbus-broker ignores legacy eavesdrop attributes, but retains their allow
# rules. Normalize the reference implementation's default session policy
# without rebuilding D-Bus or changing the effective broker permissions.
final: prev:
let
  normalizePolicy = final.writeText "normalize-dbus-session-policy.py" ''
    from pathlib import Path
    import re
    import sys
    import xml.etree.ElementTree as ET

    path = Path(sys.argv[1])
    original = path.read_text(encoding="utf-8")
    root = ET.fromstring(original)
    legacy = root.findall(".//*[@eavesdrop]")
    if not legacy:
        sys.exit(0)

    # Restrict the compatibility fix to the two known upstream defaults.
    # An unexpected future policy must be reviewed rather than broadened.
    expected = [
        {"send_destination": "*", "eavesdrop": "true"},
        {"eavesdrop": "true"},
    ]
    assert [node.attrib for node in legacy] == expected, "Unexpected legacy D-Bus policy"
    defaults = root.findall("./policy[@context='default']/allow")
    assert all(node in defaults for node in legacy), "Unexpected D-Bus policy context"

    # Keep comments, whitespace, DOCTYPE and unrelated policy byte-for-byte.
    # A bare eavesdrop allow is the broker's default receive-all permission.
    def normalize(match):
        element = ET.fromstring(match[0])
        if "eavesdrop" not in element.attrib:
            return match[0]
        assert element.tag == "allow" and element.attrib in expected
        if len(element.attrib) == 1:
            return match[0].replace('eavesdrop="true"', 'receive_sender="*"')
        return match[0].replace(' eavesdrop="true"', "")

    result = re.sub(r"<allow\b[^>]*?/>", normalize, original)
    rewritten = ET.fromstring(result)
    assert not rewritten.findall(".//*[@eavesdrop]"), "Legacy D-Bus policy remains"
    rules = rewritten.findall("./policy[@context='default']/allow")
    assert any(node.attrib == {"send_destination": "*"} for node in rules)
    assert any(node.attrib == {"receive_sender": "*"} for node in rules)
    path.write_text(result, encoding="utf-8")
  '';
in
{
  makeDBusConf = prev.makeDBusConf.overrideAttrs (old: {
    # makeDBusConf uses runCommand, which does not execute postBuild hooks.
    buildCommand = old.buildCommand + ''
      ${final.python3}/bin/python ${normalizePolicy} "$out/session.conf"
    '';
    passthru = (old.passthru or { }) // {
      sessionPolicyNormalizer = normalizePolicy;
    };
  });
}
