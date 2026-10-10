const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../src/js/dashboard.js'), 'utf8');

function initialize(headers, settings, present = true) {
  let options;
  let imageError;
  const image = { src: 'bad.svg' };
  const document = {};
  const table = {
    length: present ? 1 : 0,
    find: () => ({ each: callback => headers.forEach((header, index) => callback.call(header, index)) }),
    DataTable: value => { options = value; }
  };
  function $(value) {
    if (value === document) return { ready: callback => callback() };
    if (value === '#sort_table') return table;
    if (value === '.backup_picture') return { on: (event, callback) => { imageError = callback; } };
    return { attr: (name, update) => {
      if (update !== undefined) value[name] = update;
      return value[name];
    } };
  }
  vm.runInNewContext(source, { $, document, window: { dashboardSort: settings } });
  return { options: options && JSON.parse(JSON.stringify(options)),
    failImage: () => { imageError.call(image); return image.src; } };
}

test('date sorting follows the named header after columns move', () => {
  const result = initialize([
    {'data-sort-name': 'date'}, {}, {}, {'data-sort-name': 'name'}
  ], {column: 'date', direction: 'desc'});
  assert.deepEqual(result.options.order, [[0, 'desc']]);
  assert.deepEqual(result.options.columnDefs[0].targets, [0, 3]);
});

test('name sorting follows a moved repository column', () => {
  const result = initialize([
    {}, {'data-sort-name': 'date'}, {}, {}, {'data-sort-name': 'name'}
  ], {column: 'name', direction: 'asc'});
  assert.deepEqual(result.options.order, [[4, 'asc']]);
  assert.deepEqual(result.options.columnDefs[0].targets, [1, 4]);
});

test('home and onboarding pages initialize without author sort globals', () => {
  const result = initialize([], undefined, false);
  assert.equal(result.options, undefined);
  assert.equal(result.failImage(), '/images/missing_image.png');
});
