import test from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

test('Smoke Test: Config files are valid JSON', () => {
  const configDir = path.join(process.cwd(), 'config');
  const files = fs.readdirSync(configDir);
  let checkedCount = 0;
  
  for (const file of files) {
    if (file.endsWith('.json')) {
      const filePath = path.join(configDir, file);
      try {
        const content = fs.readFileSync(filePath, 'utf8');
        JSON.parse(content);
        checkedCount++;
      } catch (err) {
        assert.fail(`${file} is not valid JSON: ${err.message}`);
      }
    }
  }
  assert.ok(checkedCount > 0, `Successfully validated ${checkedCount} JSON config files.`);
});

test('Smoke Test: Middleware rate-limit module exists', () => {
  const middlewarePath = path.join(process.cwd(), 'middleware.ts');
  assert.ok(fs.existsSync(middlewarePath), 'middleware.ts should exist for API rate limiting');
  const src = fs.readFileSync(middlewarePath, 'utf8');
  assert.ok(src.includes('isRateLimited'), 'middleware should implement rate limiting');
});

test('Smoke Test: Performance cache helper exists', () => {
  const cachePath = path.join(process.cwd(), 'lib', 'perf', 'response-cache.js');
  assert.ok(fs.existsSync(cachePath), 'response-cache.js should exist');
});
