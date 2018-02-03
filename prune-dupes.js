// Generated by CoffeeScript 2.1.0
(function() {
  var base, epis, exec, file, fs, i, key, len, matches, nfo, nfoFiles, parts, ref, seasonPath;

  fs = require('fs-plus');

  exec = require('child_process').execSync;

  console.log(".... pruning episodes ....");

  epis = {};

  nfoFiles = exec("find /mnt/media/tv -name '*.nfo'");

  ref = nfoFiles.toString().split('\n');
  for (i = 0, len = ref.length; i < len; i++) {
    file = ref[i];
    if (!(file && file.indexOf('/season.nfo') === -1)) {
      continue;
    }
    // if file.indexOf('Worst') == -1 then continue
    parts = file.split('/');
    parts.splice(-1, 1);
    seasonPath = parts.join('/');
    nfo = fs.readFileSync(file, 'utf8');
    matches = /<episode>(\d+)<\/episode>/i.exec(nfo);
    if (!matches) {
      // console.log '>>>>> no episode match', file
      continue;
    }
    key = seasonPath + '~' + matches[1];
    if (epis[key]) {
      parts = file.split('.');
      parts.splice(-1, 1);
      base = parts.join('.');
      console.log('deleting', key);
      exec('rm "' + base + '"*');
    }
    epis[key] = true;
  }

}).call(this);