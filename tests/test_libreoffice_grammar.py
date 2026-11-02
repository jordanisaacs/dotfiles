"""Read effective LibreOffice settings through UNO, preserving existing profiles."""

import os
import subprocess
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import uno

REGISTRY = """<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry">
  <item oor:path="/org.openoffice.Office.Linguistic/GrammarChecking/LanguageTool">
    <prop oor:name="IsEnabled" oor:op="fuse"><value>true</value></prop>
    <prop oor:name="BaseURL" oor:op="fuse"><value>http://grammar.fixture.invalid/v2</value></prop>
  </item>
  <item oor:path="/org.openoffice.Office.Linguistic/SpellChecking">
    <prop oor:name="IsSpellAuto" oor:op="fuse"><value>true</value></prop>
  </item>
  <item oor:path="/org.openoffice.Office.Linguistic/GrammarChecking">
    <prop oor:name="IsAutoCheck" oor:op="fuse"><value>true</value></prop>
  </item>
  <item oor:path="/org.openoffice.UserProfile/Data">
    <prop oor:name="givenname" oor:op="fuse"><value>Unrelated fixture preference</value></prop>
  </item>
</oor:items>
"""


def verify(executable, expected_remote):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        profile = root / "profile"
        (profile / "user").mkdir(parents=True)
        registry = profile / "user/registrymodifications.xcu"
        registry.write_text(REGISTRY)
        pipe = "grammar-test-" + uuid.uuid4().hex
        environment = os.environ | {"HOME": str(root), "SAL_USE_VCLPLUGIN": "svp"}
        with (root / "office.log").open("w+") as log:
            process = subprocess.Popen(
                [
                    executable,
                    "--headless",
                    "--nologo",
                    "--nodefault",
                    "--norestore",
                    "--nofirststartwizard",
                    "-env:UserInstallation=" + profile.as_uri(),
                    f"--accept=pipe,name={pipe};urp;StarOffice.ComponentContext",
                ],
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            try:
                socket_name = f"OSL_PIPE_{os.getuid()}_{pipe}"
                for _ in range(200):
                    if any(
                        (base / socket_name).is_socket()
                        for base in {Path("/tmp"), Path(tempfile.gettempdir())}
                    ):
                        break
                    if process.poll() is not None:
                        raise RuntimeError("LibreOffice exited before UNO was ready")
                    time.sleep(0.05)
                else:
                    raise TimeoutError(
                        "LibreOffice did not expose its private UNO pipe"
                    )
                local = uno.getComponentContext()
                resolver = local.ServiceManager.createInstanceWithContext(
                    "com.sun.star.bridge.UnoUrlResolver", local
                )
                context = resolver.resolve(
                    f"uno:pipe,name={pipe};urp;StarOffice.ComponentContext"
                )
                provider = context.ServiceManager.createInstanceWithContext(
                    "com.sun.star.configuration.ConfigurationProvider", context
                )

                def read(path, name):
                    argument = uno.createUnoStruct("com.sun.star.beans.PropertyValue")
                    argument.Name = "nodepath"
                    argument.Value = path
                    access = provider.createInstanceWithArguments(
                        "com.sun.star.configuration.ConfigurationAccess", (argument,)
                    )
                    return access.getPropertyValue(name)

                linguistic = "/org.openoffice.Office.Linguistic"
                remote = linguistic + "/GrammarChecking/LanguageTool"
                assert read(remote, "IsEnabled") is expected_remote
                assert read(remote, "BaseURL") == "http://grammar.fixture.invalid/v2"
                assert read(linguistic + "/SpellChecking", "IsSpellAuto") is True
                assert read(linguistic + "/GrammarChecking", "IsAutoCheck") is True
                assert (
                    read("/org.openoffice.UserProfile/Data", "givenname")
                    == "Unrelated fixture preference"
                )
                desktop = context.ServiceManager.createInstanceWithContext(
                    "com.sun.star.frame.Desktop", context
                )
                desktop.terminate()
                process.wait(timeout=10)
                tree = ET.parse(registry)
                assert any(
                    value.text == "Unrelated fixture preference"
                    for value in tree.findall(".//value")
                )
            except Exception:
                log.seek(0)
                print(log.read())
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)


verify(os.environ["BASE_LIBREOFFICE"], expected_remote=True)
verify(os.environ["CONFIGURED_LIBREOFFICE"], expected_remote=False)
print("Remote grammar disabled; local spelling and existing preferences preserved")
