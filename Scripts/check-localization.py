#!/usr/bin/env python3
# @name: 本地化完整性检查
# @Descripttion: 检查中文翻译、格式参数及可选的 Swift 编译器提取结果。
# @version: 1.0.0
# @Author: sm
# @Date: 2026-09-08 23:00:00
# @LastEditTime: 2026-09-08 23:00:00
# @FilePath: Scripts/check-localization.py
"""Usage: python3 Scripts/check-localization.py [stringsdata-directory]"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate key: {key}')
        result[key] = value
    return result


def placeholders(value):
    return re.findall(r'%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?(?:ll|l|h|z)?[@diuoxXfFeEgGcs]',
                      value.replace('%%', ''))


def main():
    catalog = json.loads((ROOT / 'Sources/Localizable.xcstrings').read_text(),
                         object_pairs_hook=unique_object)['strings']
    errors = []
    for key, item in catalog.items():
        unit = item.get('localizations', {}).get('zh-Hans', {}).get('stringUnit', {})
        if key and (unit.get('state') != 'translated' or not unit.get('value')):
            errors.append(f'Missing Chinese translation: {key}')
        if placeholders(key) != placeholders(unit.get('value', '')):
            errors.append(f'Format arguments differ: {key}')
    if len(sys.argv) > 1:
        files = list(Path(sys.argv[1]).glob('*.stringsdata'))
        if not files:
            errors.append('No compiler extraction files found')
        for path in files:
            data = json.loads(path.read_text())
            for item in data.get('tables', {}).get('Localizable', []):
                if item['key'] and item['key'] not in catalog:
                    errors.append(f"Untranslated extracted key ({path.name}): {item['key']}")
    # These validation messages reach NSLocalizedString through QueryError.invalid.
    for path in (ROOT / 'Sources').rglob('*.swift'):
        for key in re.findall(r'QueryError\.invalid\("([^"\\]+)"\)', path.read_text()):
            if key not in catalog:
                errors.append(f'Missing query error: {key}')
    if errors:
        print('\n'.join(sorted(set(errors))))
        return 1
    print(f'PASS: {len(catalog)} catalog entries; Chinese translations and format arguments verified')
    return 0


if __name__ == '__main__':
    sys.exit(main())
