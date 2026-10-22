"""Select existing test sources for a focused CI run; application sources stay intact."""
import os
from pathlib import Path
import shutil

root = Path.cwd()
targets = os.environ['TEST_TARGETS'].split()
project = (root / 'project.yml').read_text(encoding='utf-8')
for target, destination in [('vreaderTests', '.ci-unit-tests'), ('vreaderUITests', '.ci-ui-tests')]:
    requested = [value for value in targets if value == target or value.startswith(target + '/')]
    if target in requested:
        print(f'{target}: full target explicitly requested')
        continue
    output = root / destination
    output.mkdir()
    helpers = root / target / 'Helpers'
    if helpers.is_dir():
        shutil.copytree(helpers, output / 'Helpers')
    names = sorted({value.split('/')[1] for value in requested})
    for name in names:
        matches = list((root / target).rglob(name + '.swift'))
        if len(matches) != 1:
            raise SystemExit(f'Expected exactly one source for {target}/{name}, found {len(matches)}')
        shutil.copy2(matches[0], output / matches[0].name)
    if not list(output.rglob('*.swift')):
        (output / 'Empty.swift').write_text('import XCTest\n', encoding='utf-8')
    original = f'      - path: {target}\n'
    if project.count(original) != 1:
        raise SystemExit(f'Unexpected XcodeGen source declaration for {target}')
    project = project.replace(original, f'      - path: {destination}\n', 1)
    print(f'{target}: selected {names}; {len(list(output.rglob("*.swift")))} Swift sources including helpers')
(root / 'project.yml').write_text(project, encoding='utf-8')
