import contextlib
import hashlib
import http.server
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import threading
import time
import uuid
import xml.etree.ElementTree as ET

PROJECT = Path(__file__).resolve().parents[2]
BUILD = Path(subprocess.check_output(["bash", "-c", 'source Scripts/build-env.sh >/dev/null; printf "%s" "$CLASHBAR_BUILD_DIR"'], cwd=PROJECT, text=True))
SPARKLE = BUILD / "Dependencies/Sparkle-2.10.1"
PRIVATE_KEY = Path(os.environ.get("CLASHBAR_SIGNING_KEY_FILE", Path.home() / "Library/Application Support/ClashBar/UpdateSigning/ed25519.privatekey"))
ROOT = BUILD / "UpdateSmoke" / str(uuid.uuid4())
TIMEOUT = 180
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NAMESPACE)
ROOT.mkdir(parents=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, *args):
        pass


def run(arguments, **kwargs):
    return subprocess.run([str(argument) for argument in arguments], cwd=PROJECT, check=True, **kwargs)


def write_plist(path, changes):
    with path.open("rb") as source:
        data = plistlib.load(source)
    data.update(changes)
    with path.open("wb") as destination:
        plistlib.dump(data, destination)


def scenario(corrupt, server):
    name = "invalid-signature" if corrupt else "valid-update"
    folder = ROOT / name
    folder.mkdir()
    identifier = "org.clashbar.update-test." + uuid.uuid4().hex
    feed = f"http://127.0.0.1:{server.server_port}/{name}/appcast.xml"
    environment = dict(os.environ, CLASHBAR_UPDATE_TEST="1", CLASHBAR_UPDATE_TEST_ROOT=str(folder), CLASHBAR_UPDATE_TEST_ID=identifier, CLASHBAR_UPDATE_TEST_FEED=feed)
    run(["Scripts/build.sh"], env=environment)
    installed = folder / "Installed/ClashBar.app"
    candidate = folder / "Candidate/ClashBar.app"
    installed.parent.mkdir()
    candidate.parent.mkdir()
    run(["ditto", BUILD / "UpdateSmoke/Build/ClashBar.app", installed])
    run(["ditto", installed, candidate])
    write_plist(candidate / "Contents/Info.plist", {"CFBundleVersion": "9002", "CFBundleShortVersionString": "0.1.2-beta.2"})
    run(["codesign", "--force", "--sign", "-", candidate])
    archive = folder / "ClashBar.zip"
    run(["ditto", "-c", "-k", "--keepParent", candidate, archive])
    signature = subprocess.check_output([str(SPARKLE / "bin/sign_update"), "--ed-key-file", str(PRIVATE_KEY), "-p", str(archive)], text=True).strip()
    if corrupt:
        with archive.open("ab") as output:
            output.write(b"invalid-update-test")
    document = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(document, "channel")
    ET.SubElement(channel, "title").text = "ClashBar update integration test"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, f"{{{NAMESPACE}}}version").text = "9002"
    ET.SubElement(item, f"{{{NAMESPACE}}}shortVersionString").text = "0.1.2-beta.2"
    ET.SubElement(item, f"{{{NAMESPACE}}}channel").text = "beta"
    ET.SubElement(item, f"{{{NAMESPACE}}}minimumSystemVersion").text = "13.0"
    ET.SubElement(item, "enclosure", {"url": f"http://127.0.0.1:{server.server_port}/{name}/ClashBar.zip", "length": str(archive.stat().st_size), "type": "application/octet-stream", f"{{{NAMESPACE}}}edSignature": signature})
    appcast = folder / "appcast.xml"
    ET.ElementTree(document).write(appcast, encoding="utf-8", xml_declaration=True)
    run([SPARKLE / "bin/sign_update", "--ed-key-file", PRIVATE_KEY, appcast])
    configuration = folder / "controllers.json"
    configuration.write_text('[{"name":"test-controller","secret":"synthetic-test-secret"}]')
    expected = hashlib.sha256(configuration.read_bytes()).digest()
    with (folder / "process.log").open("wb") as log:
        process = subprocess.Popen([str(installed / "Contents/MacOS/ClashBar")], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + TIMEOUT
            while time.monotonic() < deadline:
                result = folder / "result.txt"
                error = folder / "error.txt"
                if result.exists() or error.exists():
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError(f"升级测试超时，日志：{folder / 'process.log'}")
            if corrupt:
                assert error.exists() and not result.exists(), "错误签名未被拒绝"
                with (installed / "Contents/Info.plist").open("rb") as source:
                    assert plistlib.load(source)["CFBundleVersion"] == "9001", "错误更新替换了旧应用"
            else:
                assert result.exists(), error.read_text() if error.exists() else "未完成升级"
                assert result.read_text() == "success", "升级丢失偏好"
                with (installed / "Contents/Info.plist").open("rb") as source:
                    assert plistlib.load(source)["CFBundleVersion"] == "9002", "没有实际替换应用"
            assert hashlib.sha256(configuration.read_bytes()).digest() == expected, "升级修改了配置"
            print(f"✓ {name}：{'拒绝错误签名，保留旧版' if corrupt else '真实下载、验签、替换、重启及偏好保留通过'}", flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            subprocess.run(["defaults", "delete", identifier], capture_output=True)


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    scenario(False, server)
    scenario(True, server)
finally:
    server.shutdown()
    server.server_close()
print(f"升级测试产物：{ROOT}")
