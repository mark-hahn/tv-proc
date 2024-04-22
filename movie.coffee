###
convert to js:
  https://decaffeinate-project.org/repl/
  use these options:
    --prefer-const
    --loose-default-params
    --disable-babel-constructor-workaround
###

#todo
#  lazy-login to thetvdb
#  add episode dupes to counter summary
#  move episode dupes code to this file

# debug = true

rsyncDelay = 3000  # 3 secs

usbHost =  "xobtlu@oracle.usbx.me"

usbAgeLimit = Date.now() - 2*7*24*60*60*1000 # 2 weeks ago
recentLimit = new Date(Date.now() - 3*7*24*60*60*1000) # 3 weeks ago
fileTimeout = {timeout: 2*60*60*1000} # 2 hours

fs   = require 'fs-plus'
util = require 'util'
exec = require('child_process').execSync
mkdirp = require 'mkdirp'
request = require 'request'
rimraf  = require 'rimraf'

filterRegex = null
filterRegexTxt = ''
if process.argv.length == 3
  filterRegex = process.argv[2]
  filterRegexTxt = 'filter:' + filterRegex

# console.log ".... starting tv.coffee v4 #{filterRegexTxt} ...."
startTime = time = Date.now()
deleteCount = chkCount = recentCount = 0
existsCount = errCount = downloadCount = blockedCount = 0;

findUsb = "ssh #{usbHost} find files -type f -printf '%CY-%Cm-%Cd-%P\\\\\\n' | grep -v .r[0-9][0-9]$ | grep -v .rar$"

if filterRegex
  findUsb += " | grep -i " + filterRegex

# console.log findUsb

dateStr = (date) =>
  date    = new Date date
  year    = date.getFullYear();
  month   = (date.getMonth() + 1).toString().padStart(2, '0');
  day     = date.getDate().toString().padStart(2, '0');
  hours   = date.getHours().toString().padStart(2, '0');
  minutes = date.getMinutes().toString().padStart(2, '0');
  seconds = date.getSeconds().toString().padStart(2, '0');
  "#{year}/#{month}/#{day}-#{hours}:#{minutes}:#{seconds}"

readMap = (fname) =>
  map = JSON.parse fs.readFileSync fname, 'utf8'
  for entry, timex of map
    map[entry] = new Date(timex).getTime()
  map

writeMap = (fname, map) =>
  for entry, timex of map
    map[entry] = dateStr timex
  fs.writeFileSync fname, JSON.stringify map

recent  = readMap 'tv-recent.json'
errors  = readMap 'tv-errors'
blocked = JSON.parse fs.readFileSync 'tv-blocked.json', 'utf8'

###########
# constants

map = {}
mapStr = fs.readFileSync 'tv-map', 'utf8'
mapLines = mapStr.split '\n'
for line in mapLines
  [f,t] = line.split ','
  if line.length then map[f.trim()] = t.trim()

tvPath    = '/mnt/media/tv/'

escQuotes = (str) ->
  '"' + str.replace(/\\/g, '\\\\')
           .replace(/"/g,  '\\"') + '"'
          #  .replace(/'|`/g,  "\\'")
          #  .replace(/\(/g, "\\(")
          #  .replace(/\)/g, "\\)")
          #  .replace(/\&/g, "\\&")
          #  .replace(/\s/g, '\\ ')  
  
usbFiles = exec(findUsb, {timeout:300000}).toString().split '\n'
console.log usbFiles

while true
  if usbLine = usbFiles.shift()
    chkCount++
    usbFilePath = usbLine.slice(11)
    parts = usbFilePath.split '/'
    fname = parts[parts.length-1]
    parts = fname.split '.'
    fext  = parts[parts.length-1]
    if (fext.length == 6 or fext in ['mkv','mp4']) and 
        not fname.includes 'sample'
      break
  else
    console.log "no files found"
    process.exit()

videoPath    = "files/#{usbFilePath}"
usbLongPath  = "#{usbHost}:#{videoPath}"

console.log()

try
  exec("rsync -avP #{escQuotes usbLongPath} " +
         "#{escQuotes '/mnt/media/movies/'}", {stdio: 'inherit'})
catch e
  console.log "\nvvvvvvvv\nrsync download error: \n#{e.message}^^^^^^^^^"
  badFile();
  return;
