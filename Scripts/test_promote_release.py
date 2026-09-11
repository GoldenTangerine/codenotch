# @name: 最新版本发布保护测试
# @Descripttion: 验证版本排序、附件要求及发布失败时不会修改 Latest。
# @version: 1.0.0
# @Author: sm
# @Date: 2026-09-11 11:10:33
# @LastEditTime: 2026-09-11 11:10:33
# @FilePath: Scripts/test_promote_release.py
import importlib.util
import json
from pathlib import Path
import subprocess
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

    @patch.object(promotion.subprocess, "run")
    def test_latest_changes_only_after_validation(self, run):
        run.return_value.stdout = json.dumps([[release("v1.0.0")]])
        self.assertTrue(promotion.promote("v1.0.0"))
        self.assertEqual(run.call_args.args[0], ["gh", "release", "edit", "v1.0.0", "--repo",
                                               "GoldenTangerine/codenotch", "--latest"])


if __name__ == "__main__":
    unittest.main()
