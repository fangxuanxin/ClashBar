import base64
import importlib.util
from pathlib import Path
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
PROJECT = Path(__file__).resolve().parents[2]
specification = importlib.util.spec_from_file_location("release_feed", PROJECT / "Scripts/release-feed.py")
release_feed = importlib.util.module_from_spec(specification)
specification.loader.exec_module(release_feed)
NAMESPACE = release_feed.NAMESPACE
SIGNATURE = base64.b64encode(bytes(64)).decode()
INFO = {
    "CFBundleShortVersionString": "0.1.2-beta.1",
    "CFBundleVersion": "3",
    "CFBundleIdentifier": "org.clashbar.ClashBar",
    "LSMinimumSystemVersion": "13.0",
    "SURequireSignedFeed": True,
    "SUVerifyUpdateBeforeExtraction": True,
}
PREVIOUS = f'<rss version="2.0" xmlns:sparkle="{NAMESPACE}"><channel><item><sparkle:version>2</sparkle:version></item></channel></rss>'.encode()

with tempfile.TemporaryDirectory(prefix="ClashBar release feed ") as folder:
    archive = Path(folder) / "ClashBar.zip"
    archive.write_bytes(b"synthetic archive")
    document = ET.fromstring(release_feed.create_feed(PREVIOUS, INFO, archive, SIGNATURE))
    items = document.findall("channel/item")
    assert len(items) == 2, "丢失已有更新记录"
    assert items[0].findtext(f"{{{NAMESPACE}}}channel") == "beta", "测试版未隔离到测试通道"
    assert items[0].findtext(f"{{{NAMESPACE}}}minimumSystemVersion") == "13.0"
    stable = dict(INFO, CFBundleShortVersionString="0.1.2")
    item = ET.fromstring(release_feed.create_feed(PREVIOUS, stable, archive, SIGNATURE)).find("channel/item")
    assert item.find(f"{{{NAMESPACE}}}channel") is None, "正式版被错误放到测试通道"
    for changes in [
        {"CFBundleVersion": "2"},
        {"CFBundleShortVersionString": "0.1.2;bad"},
        {"ClashBarUpdateTest": True},
        {"SURequireSignedFeed": False},
        {"LSMinimumSystemVersion": "14.0"},
    ]:
        try:
            release_feed.create_feed(PREVIOUS, dict(INFO, **changes), archive, SIGNATURE)
        except ValueError:
            pass
        else:
            raise AssertionError(f"未拒绝非法发布参数：{changes}")
print("✓ 更新源历史保留、正式/测试通道、最低系统版本和发布参数校验通过")
