
#todo
#  lazy-login to thetvdb
#  add episode dupes to counter summary
#  move episode dupes code to this file

fs   = require 'fs-plus'
util = require 'util'
exec = require('child_process').execSync
mkdirp = require 'mkdirp'
request = require 'request'
rimraf  = require 'rimraf'

usbHost = fileRegex = filterRegex = null

if process.argv.length == 3
  fileRegex = process.argv[2]
else
  usbHost = process.argv[2] + '@' + process.argv[3]

if process.argv.length == 5
  filterRegex = process.argv[4]

console.log ".... starting tv.coffee for #{usbHost || fileRegex} ...."
startTime = time = Date.now()
deleteCount = chkCount = recentCount = existsCount = errCount = downloadCount = 0;

findUsb = "ssh #{usbHost} find videos -type f -printf '%CY-%Cm-%Cd-%P\\\\\\n'"
if filterRegex
  findUsb += " | grep " + filterRegex

###########
# constants

map = {}
mapStr = fs.readFileSync 'tv-map', 'utf8'
mapLines = mapStr.split '\n'
for line in mapLines
  [f,t] = line.split ','
  if line.length then map[f.trim()] = t.trim()

recent = JSON.parse fs.readFileSync 'tv-recent', 'utf8'
errors = JSON.parse fs.readFileSync 'tv-errors', 'utf8'

tvPath    = '/mnt/media/tv/'

usbAgeLimit = Date.now() - 2*7*24*60*60*1000 # 2 weeks ago
recentLimit = Date.now() - 3*7*24*60*60*1000 # 3 weeks ago
fileTimeout = {timeout: 2*60*60*1000} # 2 hours

escQuotesS = (str) ->
  '"' + str.replace(/\\/g, '\\\\')
           .replace(/"/g,  '\\"')
           .replace(/'/g,  "\\'")
           .replace(/\(/g, "\\(")
           .replace(/\)/g, "\\)")
           .replace(/\s/g, '\\ ')  + '"'

escQuotes = (str) ->
  '"' + str.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"'
  # '"' + str.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/'/g, "\\'") + '"'

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
  usbFiles = exec(findUsb, {timeout:300000}).toString().split '\n'

  for usbLine in usbFiles
    usbDate = new Date(usbLine.slice 0,10).getTime()
    if usbDate < usbAgeLimit
      usbFilePath = usbLine.slice 11
      deleteCount++
      console.log 'removing old file:', usbFilePath
      res = exec("ssh #{usbHost} rm -rf #{escQuotesS "videos/" + usbFilePath}",
                       {timeout:300000}).toString()

  recentChgd = no
  for recentFname, recentTime of recent when recentTime < recentLimit
    delete recent[recentFname]
    recentChgd = yes
  if recentChgd
    fs.writeFileSync 'tv-recent', JSON.stringify recent

  console.log ".... downloading files ...."
  process.nextTick checkFiles

############################################################
# check each remote file, compute series and episode numbers

usbFilePath = usbFiles = seriesName = season = fname =
title = season = type = null
tvDbErrCount = 0

checkFiles = =>
  usbFiles = exec(findUsb, {timeout:300000}).toString().split '\n'
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
    if fext.length == 6 or fext in ['nfo','idx','sub','txt','jpg','gif','jpeg','part']
      process.nextTick checkFile
      return
    if recent[fname]
      recentCount++
      # console.log '------', downloadCount,'/', chkCount, 'SKIPPING RECENT:', fname
      process.nextTick checkFile
      return
    if errors[fname]
      # console.log '------', downloadCount,'/', chkCount, 'SKIPPING *ERROR*:', fname
      process.nextTick checkFile
      return
    console.log '>>>>>>', downloadCount,'/', chkCount, errCount, fname

    guessItRes = exec("/usr/local/bin/guessit -js '#{fname.replace "'", ''}'",
                      {timeout:300000}).toString()
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
    console.log '.... done ....'
    console.log  'skipped recent:  ', recentCount,
               '\ndeleted:         ', deleteCount,
               '\nskipped existing:', existsCount,
               '\nerrors:          ', errCount,
               '\ndownloaded:      ', downloadCount,
               '\nelapsed(mins):   ',
               ((Date.now()-startTime)/(60*1000)).toFixed(1)
    if deleteCount + existsCount + errCount + downloadCount > 0
      console.log "***********************************************************"
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
          setTimeout chkTvDB, 300000
        else
          process.nextTick badFile
      else
        seriesName = body.data[0].seriesName
        if map[seriesName]
          console.log '+++ Mapping', seriesName, 'to', map[seriesName]
          seriesName = map[seriesName]
        tvdbCache[title] = seriesName
        process.nextTick checkFileExists

checkFileExists = =>
  tvSeasonPath = "#{tvPath}#{seriesName}/Season #{season}"
  tvFilePath   = "#{tvSeasonPath}/#{fname}"
  videoPath    = "videos/#{usbFilePath}"
  usbLongPath  = "#{usbHost}:#{videoPath}"
  if fs.existsSync tvFilePath
    existsCount++
    console.log "skipping existing file: #{fname}"
  else
    mkdirp.sync tvSeasonPath
    if usbFilePath.indexOf('/') > -1
      console.log "downloading file in dir: #{usbFilePath}"
    else
      console.log "downloading file: #{usbFilePath}"
    # console.log escQuotes tvSeasonPath
    # console.log escQuotes tvFilePath
    # console.log escQuotes videoPath
    # console.log escQuotes usbLongPath
    # console.log "\nrsync -av #{escQuotesS usbLongPath} #{escQuotes tvFilePath}\n"

    # console.log(exec("rsync -av #{escQuotesS usbLongPath} #{escQuotes tvFilePath}",
    #                   fileTimeout).toString().replace('\n\n', '\n'),
    #                 ((Date.now() - time)/1000).toFixed(0) + ' secs')
    downloadCount++
    time = Date.now()

  recent[fname] = Date.now()
  fs.writeFileSync 'tv-recent', JSON.stringify recent
  process.nextTick checkFile

badFile = =>
  errCount++
  errors[fname] = true
  fs.writeFileSync 'tv-errors', JSON.stringify errors
  process.nextTick checkFile
