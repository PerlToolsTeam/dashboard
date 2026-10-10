const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('src/js/onboarding.js', 'utf8');
const template = fs.readFileSync('tt_lib/add.tt', 'utf8');
function setup() {
  const fields = {};
  for (const match of template.matchAll(/id="(registration-[^"]+)"/g)) {
    fields[match[1]] = {value: '', checked: false, hidden: true, textContent: '',
      addEventListener(event, callback) { this[event] = callback; }};
  }
  const field = name => fields['registration-' + name];
  vm.runInNewContext(source, {document: {getElementById: id => fields[id]}});
  field('cpan').value = ' example ';
  function submit() {
    let prevented = false;
    field('form').submit({preventDefault() { prevented = true; }});
    assert.ok(prevented);
  }
  return {field, submit};
}
if (process.argv.includes('--fixture')) {
  const {field, submit} = setup();
  submit();
  process.stdout.write(field('json').value);
} else {
  test('minimal registration needs only an author ID and disables optional services', () => {
    const {field, submit} = setup();
    submit();
    const cfg = JSON.parse(field('json').value);
    assert.equal(cfg.author.cpan, 'EXAMPLE');
    assert.equal(cfg.author.github, '');
    assert.deepEqual(Object.values(cfg.ci).filter(v => typeof v === 'number'), [0,0,0,0]);
    assert.deepEqual(cfg.sort, {column: 'name', direction: 'asc'});
    assert.equal(field('filename').textContent, 'EXAMPLE.json');
    assert.equal(field('result').hidden, false);
  });
  test('workflow names and chosen services survive JSON generation safely', () => {
    const {field, submit} = setup();
    field('github').value = ' example-user ';
    field('actions').checked = true;
    field('coveralls').checked = true;
    field('workflows').value = ' CI & test\r\n\n Workflow "quoted" ';
    submit();
    const cfg = JSON.parse(field('json').value);
    assert.equal(cfg.author.github, 'example-user');
    assert.equal(cfg.ci.use_gh_actions, 1);
    assert.equal(cfg.ci.use_coveralls, 1);
    assert.deepEqual(cfg.ci.gh_workflow_names, ['CI & test', 'Workflow "quoted"']);
  });
  test('disabled Actions omits workflow names even if text remains', () => {
    const {field, submit} = setup();
    field('workflows').value = 'Unused';
    submit();
    assert.deepEqual(JSON.parse(field('json').value).ci.gh_workflow_names, []);
  });
  test('invalid IDs and usernames do not offer a registration', () => {
    for (const [name, value] of [['cpan','../BAD'], ['cpan',''], ['github','https://github.com/user'], ['github','<script>']]) {
      const {field, submit} = setup();
      field(name).value = value;
      submit();
      assert.equal(field('result').hidden, true);
      assert.ok(field('error').textContent);
    }
  });
  test('enabled Actions requires a workflow and hides stale output after an error', () => {
    const {field, submit} = setup();
    submit();
    assert.equal(field('result').hidden, false);
    field('actions').checked = true;
    submit();
    assert.equal(field('result').hidden, true);
    assert.match(field('error').textContent, /workflow name/);
  });
  test('workflow control characters fail validation', () => {
    const {field, submit} = setup();
    field('actions').checked = true;
    field('workflows').value = 'CI\x00evil';
    submit();
    assert.equal(field('result').hidden, true);
    assert.match(field('error').textContent, /control characters/);
  });
  test('script tolerates pages without the registration form', () => {
    vm.runInNewContext(source, {document: {getElementById: () => null}});
  });
}
