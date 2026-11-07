import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

PROJECT = Path(__file__).resolve().parents[1]
NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
RELEASES = "https://github.com/fangxuanxin/ClashBar/releases"
ET.register_namespace("sparkle", NAMESPACE)


def create_feed(previous, info, archive, signature):
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.\d+)?", version):
        raise ValueError("发布版本格式无效")
    if not re.fullmatch(r"[1-9]\d*", build) or info.get("ClashBarUpdateTest"):
        raise ValueError("构建号无效，或误用了升级测试副本")
    if info.get("CFBundleIdentifier") != "org.clashbar.ClashBar" or info.get("LSMinimumSystemVersion") != "13.0":
        raise ValueError("应用标识或最低系统版本不匹配")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        raise ValueError("应用必须启用更新源签名和解压前验签")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("更新签名无效")
    document = ET.fromstring(previous)
    channel = document.find("channel")
    if channel is None:
        raise ValueError("已有更新源格式无效")
    for item in channel.findall("item"):
        old = item.findtext(f"{{{NAMESPACE}}}version")
        if not old or not old.isdecimal() or int(old) >= int(build):
            raise ValueError("构建号必须高于更新源中的所有版本，包括测试版")
    item = ET.Element("item")
    ET.SubElement(item, "title").text = "ClashBar " + version
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f"{{{NAMESPACE}}}version").text = build
    ET.SubElement(item, f"{{{NAMESPACE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{NAMESPACE}}}minimumSystemVersion").text = "13.0"
    if "-" in version:
        ET.SubElement(item, f"{{{NAMESPACE}}}channel").text = "beta"
    ET.SubElement(item, "link").text = f"{RELEASES}/tag/v{version}"
    ET.SubElement(item, "enclosure", {
        "url": f"{RELEASES}/download/v{version}/ClashBar.zip",
        "length": str(archive.stat().st_size),
        "type": "application/octet-stream",
        f"{{{NAMESPACE}}}edSignature": signature,
    })
    channel.insert(0, item)
    ET.indent(document)
    return ET.tostring(document, encoding="utf-8", xml_declaration=True)


def main():
    destination = Path(os.environ["CLASHBAR_RELEASE_DIR"])
    app = Path(os.environ["CLASHBAR_RELEASE_APP"])
    private_key = Path(os.environ["CLASHBAR_SIGNING_KEY_FILE"])
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    public_key = (PROJECT / "Resources/UpdatePublicKey.txt").read_text().strip()
    if info.get("SUPublicEDKey") != public_key:
        raise ValueError("应用公钥与发布公钥不一致")
    signer = destination.parents[1] / "Dependencies/Sparkle-2.10.1/bin/sign_update"
    archive = destination / "ClashBar.zip"
    signature = subprocess.check_output([str(signer), "--ed-key-file", str(private_key), "-p", str(archive)], text=True).strip()
    feed = destination / "appcast.xml"
    feed.write_bytes(create_feed((PROJECT / "appcast.xml").read_bytes(), info, archive, signature))
    subprocess.run([str(signer), "--ed-key-file", str(private_key), str(feed)], check=True)
    subprocess.run([str(signer), "--ed-key-file", str(private_key), "--verify", str(feed)], check=True)
    subprocess.run([str(signer), "--ed-key-file", str(private_key), "--verify", str(archive), signature], check=True)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / "SHA256SUMS").write_text(f"{checksum}  ClashBar.zip\n")
    print(f"✓ 发布候选 {info['CFBundleShortVersionString']}，构建 {info['CFBundleVersion']}；SHA256：{checksum}")


if __name__ == "__main__":
    main()
