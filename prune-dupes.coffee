
fs   = require 'fs-plus'
exec = require('child_process').execSync

# console.log ".... pruning local duplicate episode files ...."

epis = {}
nfoFiles = exec "find /mnt/media/tv -name '*.nfo'"
for file in nfoFiles.toString().split '\n' when file and file.indexOf('/season.nfo') == -1

  # if file.indexOf('Worst') == -1 then continue

  parts = file.split '/'
  parts.pop()
  seasonPath = parts.join '/'

  nfo = fs.readFileSync file, 'utf8'
  matches = /<episode>(\d+)<\/episode>/i.exec nfo
  if not matches
    # console.log '>>>>> no episode match', file
    continue

  key = seasonPath + '~' + matches[1]

  if epis[key]
    parts = file.split '.'
    parts.pop()
    base = parts.join '.'
    cmd = 'rm "' + base + '"*'
    console.log 'deleting local duplicate file:\n    ', key, '\n    ', cmd
    exec cmd

  epis[key] = yes
