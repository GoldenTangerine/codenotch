# @name: 最新版本发布保护测试
# @Descripttion: 验证版本排序、附件要求及发布失败时不会修改 Latest。
# @version: 1.0.0
# @Author: sm
# @Date: 2026-09-11 11:10:33
# @LastEditTime: 2026-09-11 11:10:33
# @FilePath: Scripts/test_promote_release.py
import importlib.util
import base64
import json
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("promote_release", Path(__file__).with_name("promote-release.py"))
promotion = importlib.util.module_from_spec(spec)
spec.loader.exec_module(promotion)


def release(tag, **changes):
    value = {"tag_name": tag, "draft": False, "prerelease": False,
             "assets": [{"name": "appcast.xml"}, {"name": "Codenotch.dmg"}]}
    return dict(value, **changes)


class PromotionTests(unittest.TestCase):
    def test_numeric_order_and_first_release(self):
        self.assertTrue(promotion.should_promote("v1.10.0", [release("v1.10.0")]))
        self.assertTrue(promotion.should_promote("v1.10.0", [release("v1.9.9"), release("v1.10.0")]))
        self.assertFalse(promotion.should_promote("v1.9.9", [release("v1.9.9"), release("v1.10.0")]))

    def test_same_version_can_be_republished(self):
        self.assertTrue(promotion.should_promote("v1.10.0", [release("v1.10.0")]))

    def test_drafts_and_prereleases_do_not_affect_stable_order(self):
        releases = [release("v1.0.0"), release("v2.0.0", draft=True),
                    release("v3.0.0-beta.1", prerelease=True)]
        self.assertTrue(promotion.should_promote("v1.0.0", releases))
        self.assertFalse(promotion.should_promote("v2.0.0", releases))
        self.assertFalse(promotion.should_promote("v3.0.0-beta.1", releases))

    def test_missing_release_or_update_asset_blocks_promotion(self):
        for releases in [[], [release("v1.0.0", assets=[{"name": "Codenotch.dmg"}])]]:
            with self.subTest(releases=releases), self.assertRaises(ValueError):
                promotion.should_promote("v1.0.0", releases)

    def test_unknown_stable_tag_blocks_promotion(self):
        with self.assertRaises(ValueError):
            promotion.should_promote("v1.0.0", [release("nightly"), release("v1.0.0")])

    @patch.object(promotion.subprocess, "run")
    def test_newer_release_on_later_page_prevents_write(self, run):
        run.return_value.stdout = json.dumps([[release("v1.0.0")], [release("v2.0.0")]])
        self.assertFalse(promotion.promote("v1.0.0"))
        self.assertEqual(run.call_count, 1)
        self.assertIn("--paginate", run.call_args.args[0])

    @patch.object(promotion.subprocess, "run")
    def test_api_failure_prevents_write(self, run):
        run.side_effect = subprocess.CalledProcessError(1, "gh")
        with self.assertRaises(subprocess.CalledProcessError):
            promotion.promote("v1.0.0")
        self.assertEqual(run.call_count, 1)

    @patch.object(promotion, "validate_published_appcast")
    @patch.object(promotion.subprocess, "run")
    def test_latest_changes_only_after_validation(self, run, validate):
        run.side_effect = [
            subprocess.CompletedProcess([], 0, json.dumps([[release("v1.0.0")]])),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0, json.dumps(release("v1.0.0"))),
        ]
        self.assertTrue(promotion.promote("v1.0.0"))
        validate.assert_called_once()
        self.assertEqual(run.call_args_list[1].args[0], ["gh", "release", "edit", "v1.0.0", "--repo",
                                               "GoldenTangerine/codenotch", "--latest"])

    @patch.object(promotion, "validate_published_appcast")
    @patch.object(promotion.subprocess, "run")
    def test_latest_mismatch_fails_release(self, run, validate):
        run.side_effect = [
            subprocess.CompletedProcess([], 0, json.dumps([[release("v1.0.0")]])),
            subprocess.CompletedProcess([], 0),
            subprocess.CompletedProcess([], 0, json.dumps(release("v0.9.0"))),
        ]
        with self.assertRaisesRegex(ValueError, "GitHub Latest"):
            promotion.promote("v1.0.0")

    @patch.object(promotion, "validate_published_appcast", side_effect=ValueError("Empty feed"))
    @patch.object(promotion.subprocess, "run")
    def test_invalid_published_feed_prevents_latest_write(self, run, validate):
        run.return_value.stdout = json.dumps([[release("v1.0.0")]])
        with self.assertRaises(ValueError):
            promotion.promote("v1.0.0")
        self.assertEqual(run.call_count, 1)


class AppcastTests(unittest.TestCase):
    def feed(self):
        signature = base64.b64encode(bytes(64)).decode()
        return f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item>
            <sparkle:version>123</sparkle:version>
            <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
            <enclosure url="https://github.com/GoldenTangerine/codenotch/releases/download/v1.0.0/Codenotch.dmg"
              length="42" sparkle:edSignature="{signature}" />
          </item></channel></rss>'''

    def test_complete_feed(self):
        promotion.validate_appcast("v1.0.0", self.feed(), 42)

    def test_empty_feed(self):
        with self.assertRaises(ValueError):
            promotion.validate_appcast("v1.0.0", "<rss><channel/></rss>", 42)

    def test_mismatched_or_missing_update_metadata(self):
        for before, after in [
            ("/v1.0.0/", "/v0.9.0/"),
            (">1.0.0<", ">0.9.0<"),
            ('length="42"', 'length="41"'),
            ("sparkle:edSignature", "signature"),
            ("<sparkle:version>123</sparkle:version>", ""),
        ]:
            with self.subTest(before=before), self.assertRaises(ValueError):
                promotion.validate_appcast("v1.0.0", self.feed().replace(before, after), 42)


class ArchiveSignatureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ephemeral test keys never touch the login Keychain or release secrets.
        fixture = subprocess.run(["swift", "-"], input='''
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let other = Curve25519.Signing.PrivateKey()
let data = Data("test update archive".utf8)
let signature = try key.signature(for: data)
print(key.publicKey.rawRepresentation.base64EncodedString())
print(other.publicKey.rawRepresentation.base64EncodedString())
print(signature.base64EncodedString())
''', check=True, capture_output=True, text=True)
        cls.public_key, cls.other_key, cls.signature = fixture.stdout.splitlines()

    def test_archive_signature_accepts_matching_key_and_rejects_tampering(self):
        with tempfile.TemporaryDirectory() as folder:
            dmg = Path(folder) / "Codenotch.dmg"
            info = Path(folder) / "Info.plist"
            for key, content, valid in [
                (self.public_key, b"test update archive", True),
                (self.other_key, b"test update archive", False),
                (self.public_key, b"modified update archive", False),
            ]:
                with self.subTest(valid=valid, key=key):
                    dmg.write_bytes(content)
                    info.write_bytes(plistlib.dumps({"SUPublicEDKey": key}))
                    if valid:
                        promotion.verify_archive(dmg, self.signature, info)
                    else:
                        with self.assertRaises(subprocess.CalledProcessError):
                            promotion.verify_archive(dmg, self.signature, info)


if __name__ == "__main__":
    unittest.main()
