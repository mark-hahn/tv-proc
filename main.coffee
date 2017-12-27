
fs   = require 'fs-plus'
util = require 'util'
exec = require('child_process').execSync
mkdirp = require 'mkdirp'
request = require 'request'
rimraf  = require 'rimraf'

usbHost = fileRegex = null

if process.argv.length == 3
  fileRegex = process.argv[2]
else
  usbHost = process.argv[2] + '@' + process.argv[3]

console.log ".... starting tv.coffee for #{usbHost || fileRegex} ...."
time = Date.now()
chkCount = 0
downloadCount = 0;
findUsb = "ssh #{usbHost} find videos -type f -printf '%CY-%Cm-%Cd-%P\\\\\\n'"

###########
# constants

map = {}
mapStr = fs.readFileSync 'tv-map', 'utf8'
mapLines = mapStr.split '\n'
for line in mapLines
  [f,t] = line.split ','
  if line.length then map[f.trim()] = t.trim()

recent = JSON.parse fs.readFileSync 'tv-recent', 'utf8'

tvPath    = '/mnt/media/tv/'

usbAgeLimit = Date.now() - 2*7*24*60*60*1000 # 2 weeks ago
recentLimit = Date.now() - 3*7*24*60*60*1000 # 3 weeks ago
fileTimeout = {timeout: 2*60*60*1000} # 2 hours

################
# async routines
getUsbFiles = delOldFiles = checkFiles = checkFile = badFile =
checkFileExists = checkFile = chkTvDB = null

#######################################
# get theTvDb api token
theTvDbToken = null

request.post 'https://api.thetvdb.com/login',
  {json:true, body: {apikey: "2C92771D87CA8718"}},
  (error, response, body) =>
    if error or response.statusCode != 200
      console.log 'theTvDb login error:', error
      console.log 'theTvDb statusCode:', response && response.statusCode
      process.exit()
    else
      theTvDbToken = body.token
      process.nextTick delOldFiles

######################################################
# delete old files in usb/videos

delOldFiles = =>
  console.log ".... checking for files to delete ...."
  usbFiles = exec(findUsb, {timeout:10000}).toString().split '\n'

  for usbLine in usbFiles
    usbDate = new Date(usbLine.slice 0,10).getTime()
    if usbDate < usbAgeLimit
      usbFilePath = usbLine.slice 11
      console.log 'removing old file:', usbFilePath
      res = exec("ssh #{usbHost} 'rm -rf videos/#{usbFilePath}'",
                       {timeout:10000}).toString()
      if (res.length > 1) then console.log res

  recentChgd = no
  for recentFname, recentTime of recent when recentTime < (Date.now() - recentLimit)
    delete recent[recentFname]
    recentChgd = yes
  if recentChgd
    fs.writeFileSync 'tv-recent', JSON.stringify recent

  process.nextTick checkFiles

############################################################
# check each remote file, compute series and episode numbers

usbFilePath = usbFiles = seriesName = season = fname =
title = season = type = null
tvDbErrCount = 0

checkFiles = =>
  usbFiles = exec(findUsb, {timeout:10000}).toString().split '\n'
  process.nextTick checkFile

checkFile = =>
  tvDbErrCount = 0
  if usbLine = usbFiles.shift()
    chkCount++
    usbFilePath = usbLine.slice(11)
    parts = usbFilePath.split '/'
    fname = parts[parts.length-1]
    parts = fname.split '.'
    fext  = parts[parts.length-1]
    if fext.length == 6 or fext in ['nfo','idx','sub','txt','jpg','gif','jpeg']
      process.nextTick checkFile
      return
    if recent[fname]
      console.log '------', downloadCount,'/', chkCount, 'SKIPPING RECENT:', fname
      process.nextTick checkFile
      return
    console.log '\n>>>>>>', downloadCount,'/', chkCount, fname

    guessItRes = exec("guessit -js '#{fname.replace "'", ''}'",
                      {timeout:10000}).toString()
    try
      {title, season, type} = JSON.parse guessItRes
      if not type == 'episode'
        console.log '\nskipping non-episode:', fname
        process.nextTick badFile
        return
      if not Number.isInteger season
        console.log '\nno season integer for ' + fname
        process.nextTick badFile
        return
    catch
      console.log '\nerror parsing:' + fname
      process.nextTick badFile
      return
    process.nextTick chkTvDB
  else
    console.log 'DONE - downloaded:', downloadCount

tvdbCache = {}

chkTvDB = =>
  if tvdbCache[title]
    seriesName = tvdbCache[title]
    process.nextTick checkFileExists
    return

  request 'https://api.thetvdb.com/search/series?name=' + encodeURIComponent(title),
    {json:true, headers: {Authorization: 'Bearer ' + theTvDbToken}},
    (error, response, body) =>
      # console.log {error, response, body}
      if error or (response?.statusCode != 200)
        console.log 'no series name found in theTvDB:', fname
        console.log 'search error:', error
        console.log 'search statusCode:', response && response.statusCode
        console.log 'search body:', body
        if error
          if ++tvDbErrCount == 15
            console.log 'giving up, downloaded:', downloadCount
            return
          console.log "tvdb err retry, waiting one minute"
          setTimeout chkTvDB, 60*1000
        else
          process.nextTick checkFile
      else
        seriesName = body.data[0].seriesName
        if map[seriesName] then seriesName = map[seriesName]
        tvdbCache[title] = seriesName
        process.nextTick checkFileExists

escQuotes = (str) ->
  '"' + str.replace('\\', '\\\\').replace('"', '\"') + '"'

checkFileExists = =>
  tvSeasonPath = "#{tvPath}#{seriesName}/Season #{season}"
  tvFilePath   = "#{tvSeasonPath}/#{fname}"
  usbLongPath  = "#{usbHost}:videos/#{usbFilePath}"
  if fs.existsSync tvFilePath
    console.log "skipping existing file: #{fname}"
  else
    mkdirp.sync tvSeasonPath
    if usbFilePath.indexOf('/') > -1
      console.log "downloading file in dir: #{usbFilePath}"
    else
      console.log "downloading file: #{usbFilePath}"
    console.log(exec("rsync -av #{escQuotes usbLongPath} #{escQuotes tvFilePath}",
                      fileTimeout).toString().replace('\n\n', '\n'),
                    ((Date.now() - time)/1000).toFixed(0) + ' secs')
    downloadCount++
    time = Date.now()

  recent[fname] = Date.now()
  fs.writeFileSync 'tv-recent', JSON.stringify recent
  process.nextTick checkFile

badFile = =>
  console.log '******', downloadCount,'/', chkCount, '---BAD---:', fname
  recent[fname] = Date.now()
  fs.writeFileSync 'tv-recent', JSON.stringify recent
  downloadCount++
  time = Date.now()
  process.nextTick checkFile
