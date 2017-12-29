
fs = require 'fs-plus'
exec = require('child_process').execSync

epis = {}
nfoFiles = exec "find /mnt/media/tv -name '*.nfo'"
for file in nfoFiles.toString().split '\n' when file and file.indexOf('/season.nfo') == -1
  matches = /<imdbid>tt(\d+)<\/imdbid>/i.exec fs.readFileSync file
  if not matches then continue
  if epis[matches[1]]
    parts = file.split '.'
    parts.splice -1, 1
    base = parts.join '.'
    console.log 'deleting', matches[1], base + '*'
    exec 'rm "' + base + '"*'
  epis[matches[1]] = yes
