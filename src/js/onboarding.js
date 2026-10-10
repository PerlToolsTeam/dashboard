(function () {
  'use strict';
  var form = document.getElementById('registration-form');
  if (!form) return;
  function field(name) { return document.getElementById('registration-' + name); }
  form.addEventListener('submit', function (event) {
    event.preventDefault();
    field('result').hidden = true;
    field('error').textContent = '';
    var cpan = field('cpan').value.trim().toUpperCase();
    var github = field('github').value.trim();
    var names = field('workflows').value.split(/\r?\n/).map(function (name) {
      return name.trim();
    }).filter(Boolean);
    var actions = field('actions').checked;
    if (!/^[A-Z][A-Z0-9]*$/.test(cpan)) {
      field('error').textContent = 'Enter a CPAN author ID using letters and digits.';
      return;
    }
    if (github && !/^[A-Za-z0-9][A-Za-z0-9-]*$/.test(github)) {
      field('error').textContent = 'Enter a GitHub username, or leave it empty.';
      return;
    }
    if (actions && !names.length) {
      field('error').textContent = 'List at least one workflow name for GitHub Actions.';
      return;
    }
    if (names.some(function (name) { return /[\x00-\x1f\x7f]/.test(name); })) {
      field('error').textContent = 'Workflow names cannot contain control characters.';
      return;
    }
    var config = {
      author: { cpan: cpan, github: github },
      ci: {
        use_gh_actions: actions ? 1 : 0,
        gh_workflow_names: actions ? names : [],
        use_coveralls: field('coveralls').checked ? 1 : 0,
        use_codecov: field('codecov').checked ? 1 : 0,
        use_cirrus: field('cirrus').checked ? 1 : 0
      },
      sort: { column: 'name', direction: 'asc' }
    };
    field('json').value = JSON.stringify(config, null, 2) + '\n';
    field('filename').textContent = cpan + '.json';
    field('result').hidden = false;
  });
}());
