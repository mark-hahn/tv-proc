
# to-do
#  map
#  usb - recurse in dirs

fs   = require 'fs-plus'
util = require 'util'
exec = require('child_process').execSync
mkdirp = require 'mkdirp'
request = require 'request'
rimraf  = require 'rimraf'

localSrcPath = usbHost = fileRegex = null
if process.argv.length < 4
  localSrcPath = '/mnt/media-old/videos/'
  if process.argv[2]
    fileRegex = process.argv[2]
else
  usbHost = process.argv[2] + '@' + process.argv[3]

console.log ".... starting tv.coffee for #{usbHost || fileRegex || localSrcPath} ...."
time = Date.now()
downloadCount = 0;

###########
# constants

map = []
mapStr = fs.readFileSync 'tv-map', 'utf8'
mapLines = mapStr.split '\n'
for line in mapLines
  [f,t] = line.split ','
  if line.length then map.push [ f.trim(), t.trim() ]

videosPath = '/mnt/media/videos/'
tvPath     = '/mnt/media/tv/'
errPath    = '/mnt/media/err/'

ageLimit = Date.now() - 3*7*24*60*60*1000 # 3 weeks ago
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
# delete old files in usb and local videos/err folders

delOldFiles = =>
  if localSrcPath then process.nextTick checkFiles; return

  console.log "\n.... checking for files to delete ...."
  usbFiles = exec("ssh #{usbHost} " +
                  '"find videos -type f -printf \'%CY-%Cm-%Cd %P\n\'"',
                  {timeout:10000}).toString().split '\n'

  for usbLine in usbFiles
    usbDate = new Date(usbLine.slice 0,10).getTime()
    if usbDate < ageLimit
      fname = usbLine.slice 11
      console.log 'removing old file:', fname
      rimraf.sync videosPath + fname, {disableGlob:true}
      rimraf.sync errPath    + fname, {disableGlob:true}
      res = exec("ssh #{usbHost} 'rm videos/#{fname}'",
                       {timeout:10000}).toString()
      if (res.length > 1) then console.log res
  process.nextTick checkFiles

############################################################
# utilities to download file into local folder

getBadFile = (fname) ->
  if localSrcPath then return
  console.log "downloading bad file...\n #{fname} \n... into err folder"
  console.log exec("rsync -av '#{usbHost}:videos/#{fname}' '#{errPath}'",
                   fileTimeout).toString()

getGoodFile = (fname, tvFilePath) ->
  console.log "downloading file: #{tvFilePath}"
  if localSrcPath
    fnamex = localSrcPath+fname
    cmd =  'cp -a "' + fnamex + '" /mnt/media/tv-temp'
    # console.log cmd
    res = exec cmd
    if res.length > 1
      console.log res.toString()
    fs.moveSync '/mnt/media/tv-temp', tvFilePath
    console.log 'copied', '-', ((Date.now() - time)/1000).toFixed(0) + ' secs'
  else
    console.log exec("rsync -av '#{usbHost}:videos/#{fname}' '#{tvFilePath}'",
                      fileTimeout).toString(), '-',
                    ((Date.now() - time)/1000).toFixed(0) + ' secs'
  downloadCount++
  time = Date.now()

############################################################
# check each remote file, compute series and episode numbers

usbFiles = seriesName = season = fname = tvFilePath = null

checkFiles = =>
  if localSrcPath
    usbFiles = fs.listTreeSync localSrcPath
  else
    usbFiles = exec("ssh #{usbHost} " +
                    '"find videos -type f -printf \'%CY-%Cm-%Cd %P\n\'"',
                    {timeout:10000}).toString().split '\n'
  process.nextTick checkFile

badFile = =>
  getBadFile fname
  process.nextTick checkFile

tvDbErrCount = 0
title = season = type = null

checkFile = =>
  tvDbErrCount = 0
  if usbLine = usbFiles.shift()
    if localSrcPath
      if fileRegex and (new RegExp fileRegex).exec(usbLine) == null
        process.nextTick checkFile
        return
      parts = usbLine.split('.')
      if parts[parts.length-1].length == 6
        process.nextTick checkFile
        return
      fname = usbLine.replace '/mnt/media-old/videos/', ''
    else
      fname = usbLine.slice 11

    console.log '\n>>>>>>', downloadCount, fname

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
        tvdbCache[title] = seriesName
        process.nextTick checkFileExists

checkFileExists = =>
  tvSeasonPath = "#{tvPath}#{seriesName}/Season #{season}"
  tvFilePath = "#{tvSeasonPath}/#{fname}"
  if fs.existsSync tvFilePath
    console.log "skipping existing file: #{fname}"
  else if localSrcPath and fs.getSizeSync(localSrcPath + fname) < 1e6
    console.log "skipping tiny file: #{fname}"
  else
    mkdirp.sync tvSeasonPath
    getGoodFile fname, tvFilePath

  process.nextTick checkFile
