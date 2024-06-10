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
  
################
# async routines
getUsbFiles = delOldFiles = checkFiles = checkFile = badFile =
checkFileExists = checkFile = chkTvDB = null

#######################################
# get the api token

# tvDbPin = 'HXEVSDFF'
# old apiKey             = '2C92771D87CA8718'
# v4 legacy type api key = 'ad42c85592acd18e340c8f371f47b29f'
# new v4 api key         = 'd7fa8c90-36e3-4335-a7c0-6cbb7b0320df'

theTvDbToken = null
request.post 'https://api4.thetvdb.com/v4/login',
 {json:true, body: {
    "apikey": "d7fa8c90-36e3-4335-a7c0-6cbb7b0320df",
    "pin": "HXEVSDFF"}},

#request.post 'https://api.thetvdb.com/login',
#  {json:true, body: {apikey: "2C92771D87CA8718"}},
  (error, response, body) =>
    if error or response.statusCode != 200
      console.error 'theTvDb login error:', error
      console.error 'theTvDb statusCode:', response && response.statusCode
      process.exit()
    else
      theTvDbToken = body.data.token
      # console.log({theTvDbToken});
      # process.exit();
      # if debug
      # console.log 'tvdb login', {error, response, body}
      #   process.exit()

      process.nextTick delOldFiles

######################################################
# delete old files in usb/files

delOldFiles = =>
  # console.log ".... checking for files to delete ...."
  # try
  #   usbFiles = exec(findUsb, {timeout:300000}).toString().split '\n'
  # catch e
  #   console.log "\nvvvvvvvv\nrsync find files to delete error: \n" +
  #               "#{e.message}^^^^^^^^^"
  #   process.nextTick checkFiles
  #   return;

  # for usbLine in usbFiles
  #   debug = false
  #   # if usbLine.indexOf('Island') > -1
  #   #   console.log 'DEBUG:', usbLine
  #   #   debug = true
    
  #   try
  #     usbDate = new Date(usbLine.slice 0,10).getTime()
  #     if usbDate < usbAgeLimit
  #       usbFilePath = usbLine.slice 11
  #       deleteCount++
  #       console.log 'removing old file from usb:', usbFilePath
  #       res = exec("ssh #{usbHost} rm #{escQuotes "files/" + usbFilePath}",
  #                       {timeout:300000}).toString()
  #       if res == ''
  #         console.log "\nvvvvvvvv\nrsync remove old file from usb error: \n" +
  #               "rm #{escQuotes "files/" + usbFilePath}\n#{usbFilePath}\n#{e.message}^^^^^^^^^"
  #   catch e
  #     console.log "\nvvvvvvvv\nrsync remove old file from usb error: \n" +
  #           "#{usbFilePath}\n#{e.message}^^^^^^^^^"

# ssh xobtlu@oracle.usbx.me rm -rf "Bob\'s.Burgers.S10E19.The.Handyman.Can.(1080p.HULU.Webrip.x265.10bit.EAC3.5.1.-.Goki)[TAoE]/Season 13/Bob\'s Burgers - S13E15 - The Show \(And Tell\) Must Go On WEBDL-1080p.mkv"

  recentChgd = no
  for recentFname, recentTime of recent when new Date(recentTime) < recentLimit
    delete recent[recentFname]
    recentChgd = yes
  if recentChgd
    writeMap 'tv-recent.json', recent
    # fs.writeFileSync 'tv-recent.json', JSON.stringify recent

  process.nextTick checkFiles

############################################################
# check each remote file, compute series and episode numbers

usbFilePath = usbFiles = seriesName = season = fname =
title = season = type = null
tvDbErrCount = 0

checkFiles = =>
  usbFiles = exec(findUsb, {timeout:300000}).toString().split '\n'
  # fs.writeFileSync 'tv-files.txt', usbFiles.join('\n')
  if filterRegex
    console.log usbFiles
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
    # console.log('not recent', usbLine);
    for blkName of blocked
      if fname.indexOf(blkName) > -1
        recent[fname] = Date.now()
        writeMap 'tv-recent.json', recent
        # fs.writeFileSync 'tv-recent.json', JSON.stringify recent
        blockedCount++
        console.log '-- BLOCKED:', {blkName, fname}
        process.nextTick checkFile
        return
    # console.log('not blocked', usbLine);
    if errors[fname]
      # console.log '------', downloadCount,'/', chkCount, 'SKIPPING *ERROR*:', fname
      process.nextTick checkFile
      return
    console.log '\n>>>>>>', downloadCount,'/', chkCount, errCount, fname

    guessItRes = exec("/usr/local/bin/guessit -js '#{fname.replace /'|`/g, ''}'",
                      {timeout:300000}).toString()
    # console.log {guessItRes}
    try
      {title, season, type} = JSON.parse guessItRes
      if not type == 'episode'
        console.log '\nskipping non-episode:', fname
        process.nextTick badFile
        return
      if not Number.isInteger season
        console.log '\nno season integer for ' + fname + ', defaulting to season 1'
        season = 1
    catch
      console.error '\nerror parsing:' + fname
      process.nextTick badFile
      return
    process.nextTick chkTvDB
  else
    # console.log '.... done ....'
    if (deleteCount + existsCount + errCount + downloadCount + blockedCount) > 0
      console.log "***********************************************************"
    if (recentCount > 0)
      console.log  'skipped recent:  ', recentCount
    if (blockedCount > 0)
      console.log  'blocked:         ', blockedCount
    if (deleteCount > 0)
      console.log  'deleted:         ', deleteCount
    if (existsCount > 0)
      console.log  'skipped existing:', existsCount
    if (errCount > 0)
      console.log  'errors:          ', errCount
    if (downloadCount > 0)
      console.log  'downloaded:      ', downloadCount
    console.log 'elapsed(mins):   ',
               ((Date.now()-startTime)/(60*1000)).toFixed(1)
    if (deleteCount + existsCount + errCount + downloadCount + blockedCount) > 0
      console.log "***********************************************************"

tvdbCache = {}
tvdburl = ''

chkTvDB = =>
  if title.includes('Faraway')
    seriesName = 'Faraway Downs'
    setTimeout checkFileExists, rsyncDelay
    return

  if tvdbCache[title]
    seriesName = tvdbCache[title]
    # process.nextTick checkFileExists
    setTimeout checkFileExists, rsyncDelay
    return
    
  # console.log('search:', title);
  tvdburl = 'https://api4.thetvdb.com/v4/search?type=series&q=' + 
              encodeURIComponent(title)
  request tvdburl,
    {json:true, headers: {Authorization: 'Bearer ' + theTvDbToken}},
    (error, response, body) =>
      # console.log 'thetvdb', {tvdburl, error, response, body}
      if error or not body.data?[0] or (response?.statusCode != 200)
        console.error 'no series name found in theTvDB:', {fname, tvdburl}
        console.error 'search error:', error
        console.error 'search statusCode:', response && response.statusCode
        console.error 'search body:', body
        if error
          if ++tvDbErrCount == 15
            console.error 'giving up, downloaded:', downloadCount
            return
          console.error "tvdb err retry, waiting one minute"
          setTimeout chkTvDB, rsyncDelay
        else
          process.nextTick badFile
      else
        seriesName = body.data[0].name
        if map[seriesName]
          console.log '+++ Mapping', seriesName, 'to', map[seriesName]
          seriesName = map[seriesName]
        tvdbCache[title] = seriesName
        # process.nextTick checkFileExists
        setTimeout checkFileExists, rsyncDelay

checkFileExists = =>
  tvSeasonPath = "#{tvPath}#{seriesName}/Season #{season}"
  tvFilePath   = "#{tvSeasonPath}/#{fname}"
  videoPath    = "files/#{usbFilePath}"
  usbLongPath  = "#{usbHost}:#{videoPath}"
  if fs.existsSync tvFilePath
    existsCount++
    console.log "-- EXISTING: " + fname
  else
    # console.log escQuotes tvSeasonPath
    # console.log escQuotes tvFilePath
    # console.log escQuotes videoPath
    # console.log escQuotes usbLongPath

    mkdirp.sync tvSeasonPath

    console.log "usb path: #{usbFilePath}\nlocalPath: #{tvFilePath}"
    # if usbFilePath.indexOf('/') > -1
    #   console.log "downloading file (dir: #{usbFilePath}"
    # else
      # console.log "... downloading file ..."
    # console.log "\nrsync -av #{escQuotes usbLongPath} #{escQuotes tvFilePath}\n"

    try
      console.log(exec("rsync -av #{escQuotes usbLongPath} #{escQuotes tvFilePath}",
                        fileTimeout).toString().replace('\n\n', '\n'),
                      ((Date.now() - time)/1000).toFixed(0) + ' secs')
    catch e
      console.log "\nvvvvvvvv\nrsync download error: \n#{e.message}^^^^^^^^^"
      badFile();
      return;
      
    downloadCount++
    time = Date.now()

  recent[fname] = Date.now()
  writeMap 'tv-recent.json', recent
  # fs.writeFileSync 'tv-recent.json', JSON.stringify recent
  process.nextTick checkFile

badFile = =>
  errCount++
  errors[fname] = Date.now()
  writeMap 'tv-errors', errors
  # fs.writeFileSync 'tv-errors', JSON.stringify errors
  process.nextTick checkFile
