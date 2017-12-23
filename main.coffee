
# to-do
#   map
#   lookup

fs   = require 'fs-plus'
util = require 'util'
exec = require('child_process').execSync
mkdirp = require 'mkdirp'
console.log '.... starting tv.coffee ....'

TVDB = require 'node-tvdb/compat'
tvdb = new TVDB '2C92771D87CA8718'
request = require 'request'
parsePipeList = TVDB.utils.parsePipeList

################################
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
usbHost    = process.argv[2] + '@' + process.argv[3]

timeLimit = Date.now() - 3*7*24*60*60*1000 # 3 weeks ago

######################################################
# delete old files in usb and local videos/err folders

usbFiles = exec("ssh #{usbHost} " +
                '"find videos -type f -printf \'%CY-%Cm-%Cd %P\n\'"',
                {timeout:10000}).toString().split '\n'

for usbLine in usbFiles
  usbDate = new Date(usbLine.slice 0,10).getTime()
  fname   = usbLine.slice 11
  if usbDate < timeLimit
    console.log 'removing old file:', fname
    rimraf.sync videosPath + fname, {disableGlob:true}
    rimraf.sync errPath    + fname, {disableGlob:true}
    console.log exec("ssh #{usbHost} 'rm videos/#{fname}'",
                     {timeout:10000}).toString()


############################################################
# utilities to download file into local folder

getBadFile = (fname) ->
  console.log "downloading bad file...\n #{fname} \n... into err folder"
  console.log exec("rsync -av '#{usbHost}:videos/#{fname}' '#{errPath}'",
                   {timeout:60*60*1000}).toString()

getGoodFile = (fname, tvFilePath) ->
  console.log "downloading good folders/file: #{fname} \n  to: #{tvFilePath}"
  console.log exec("rsync -av '#{usbHost}:videos/#{fname}' '#{tvFilePath}'",
                   {timeout:60*60*1000}).toString()


############################################################
# check each remote file, compute series and episode numbers

usbFiles = exec("ssh #{usbHost} " +
                '"find videos -type f -printf \'%CY-%Cm-%Cd %P\n\'"',
                {timeout:10000}).toString().split '\n'

for usbLine in usbFiles
  title = season = type = null
  fname   = usbLine.slice 11
  guessItRes = exec("guessit -js '#{fname}'", {timeout:10000}).toString()
  try
    {title, season, type} = JSON.parse guessItRes
    if not type == 'episode'
      console.log 'skipping non-episode:', fname
      continue
    if not season
      console.log 'no season for ' + fname
      getBadFile fname
      continue
  catch
    console.log 'error parsing:' + fname
    continue

  tvFilePath = "#{tvPath}#{title}/Season #{season}/#{fname}"
  if fs.existsSync tvFilePath
    console.log "skipping existing file: #{fname}"
    continue

  mkdirp.sync "#{tvPath}#{title}/Season #{season}"
  getGoodFile fname, tvFilePath
  continue

return




















totalFiles = null

incSeq    = 0
incLabels = {}
incs      = {}
inc = (lbl) ->
  # log lbl
  if not (incsLbl = incs[lbl])
    seqTxt = ++incSeq + ''
    if seqTxt.length < 2 then seqTxt = ' ' + seqTxt
    incLabels[lbl] = lbl
    incs[lbl] = 0
  incs[lbl]++

if typeof Object.assign isnt "function"
  Object.assign = (target, argv...) ->
    output = Object target
    for source in argv when source?
      for own nextKey of source
        output[nextKey] = source[nextKey]
    output

dumpInc = ->
  total = incs.checkFile
  console.log
  console.log (new Date).toString()[16..20], total, 'of', totalFiles
  for k, v of incs when k isnt 'checkFile'
    log incLabels[k] + ': ' + v
  bad = 0
  for badLbl in [
      'tvdb hard error'
      'file no tvdb show'
      'bad-file-no-series'
      'bad-file-bad-number'
      'new episode no tvdb']
    bad += incs[badLbl] ? 0
  log bad, 'bad,', Math.round(bad*100/total) + '%'
  console.log()

fatal = (err, argv...) ->
  log 'fatal err:', util.inspect argv, depth:null
  if err then log util.inspect err, depth:null
  dumpInc()
  console.trace()
  process.exit 0

uuid = ->
  uuidStr = Date.now() + (Math.random() * 1e13).toFixed 0
  while uuidStr.length < 28 then uuidStr += (Math.floor Math.random() * 10)
  uuidStr

deleteNullProps = (obj) ->
  for k, v of obj when \
      not v? or v is 'undefined' or v is 'null' or v is NaN
    delete obj[k]

exports.getBitRateDuration = (filePath) ->
  {output, stdErr} = exec 'mediainfo', ['--Output=XML', filePath]
  matches = /<track\stype="Video">([\S\s]*?)<\/track>/i.exec output.toString()
  videoTrack = matches?[1] ? ''

  matches  = /<Overall_bit_rate>(\d+\s+)?([\d\.]+)\s+(\w+)<\/Overall_bit_rate>/i
              .exec videoTrack
  matches ?= /<Bit_rate>(\d+\s+)?([\d\.]+)\s+(\w+)<\/Bit_rate>/i
              .exec videoTrack
  matches ?= [null, null, 0, 'Kbps']
  switch matches[3]
    when 'Kbps' then rate = +matches[2] * 1024
    when 'Mbps' then rate = +matches[2] * 1024 * 1024
    else
      log 'bit rate units err', matches
      fatal()
  if rate > 10e6
    fs.appendFileSync 'files/high-bitrate.txt',
      matches[2] + ' ' + matches[3] + ' ' + rate + ' ' + filePath + '\n'

  parseDuration = (track) ->
    durRegex = /// <Duration>
                      ((\d+)h)?\s*
                      ((\d+)mn)?\s*
                      ((\d+)s)?\s*
                   <\/Duration>///i
    matches = durRegex.exec(track) or []
    +(matches[2] or 0) * 3600 + +(matches[4] or 0) * 60 + +(matches[6] or 0)

  duration = parseDuration videoTrack
  if not duration
    matches = /<track\stype="Audio">([\S\s]*?)<\/track>/i.exec output.toString()
    audioTrack = matches?[1] ? ''
    duration = parseDuration audioTrack
  if not duration and rate > 0
    stats = fs.statSync filePath
    duration = Math.ceil (stats.size * 8) / rate
    log 'guessing duration by rate', stats.size, rate, duration, filePath
    fs.appendFileSync 'files/duration-by-rate.txt',
                                     stats.size + ', ' + rate     + ', ' +
                                     duration   + ', ' + filePath + '\n'
  if not duration
    duration = 1260
    log 'no duration, assuming 21 mins ' + filePath
    fs.appendFileSync 'files/no-duration.txt',
                                     duration   + ', ' + filePath + '\n'
  {bitrate: rate, duration}

exports.guessit = (fileName) ->
  fileName = fileName.replace /[^\x20-\x7e]/g, ''
                     .replace /\(GB\)/i, '(UK)'
                     .replace /[\.\s]UK[\.\s]/i, ' (UK) '
                     .replace 'faks86', ''

  if fileName in [
        'Rik Mayall Presents  - s01e09 - Briefest Encounter.avi'
        'The.Comedians.US.S01E01.720p.HDTV.x264-KILLERS.mkv'
      ]
    fs.appendFileSync 'files/episode-no-tvdb.txt', fileName + '\n'

  {output} = exec 'guessit', [fileName], timeout: 10e3

  json = output.toString().replace /^[\s|\S]*?GuessIt\s+found\:\s+/i, ''
  try
    res = JSON.parse json.replace /[^\}]*$/, ''
  catch e
    fs.appendFileSync 'files/guessit-parse-error.txt',
      output.toString() + '\n' + json + '\n'
    return []

  if res.year
    res.title = res.title + ' (' + res.year + ')'
  if res.country is 'UNITED KINGDOM' and
       not /\(UK\)/i.test res.title
    res.title = res.title + ' (UK)'

  episodes = []
  switch typeof res.season + typeof res.episode
    when 'objectnumber'
      for seasonNumber in res.season.slice()
        res.season = +seasonNumber
        episodes.push res
    when 'numberobject'
      for episodeNumber in res.episode.slice()
        res.episode = +episodeNumber
        episodes.push res
    when 'objectobject'
      episodeNumbers = res.episode.slice()
      for seasonNumber, idx in res.season.slice()
        res.season  = +seasonNumber
        res.episode = +episodeNumbers[idx]
        episodes.push res
    else episodes = [res]
  episodes

exports.getFileData = (filePath) ->
  inc 'getFileData'
  fileName = filePath.replace '/mnt/media/videos/', ''
  try
    stats = fs.statSync filePath
  catch e
    return 'not-file'
  fileSize = stats.size
  if not stats.isFile() then return 'not-file'
  {bitRate, duration} = exports.getBitRateDuration filePath

  episodes = exports.guessit fileName

  if not (fileData = episodes[0]) then return 'no-guessit'
  if typeof fileData.title isnt 'string'
    fileData.title = fileData.title[0]
  if not (series = fileData.title) then return 'no-series'

  fileTitle = series
  for map in mappings
    # log 'i fileTitle', {fileTitle, type: typeof fileTitle}
    regex = new RegExp(
      fileTitle.replace(/[\-\[\]\/\{\}\(\)\*\+\?\\\^\$\|]/g, '\\$&'), 'i')
    if regex.test map[0]
      fileTitle = map[1]
      if fileTitle is 'old' then return 'old-series'
      break
  fileTitle = fileTitle.replace /\./g, ' '
                       .replace /^(aaf-|daa-)/i, ''
  if (isNaN(fileData.season) or isNaN(fileData.episode))
    return 'bad-number'

  seasonNumber  = +fileData.season
  episodeNumber = +fileData.episode

  fileCountry = fileData.country
  if episodes.length > 1
    multipleEpisodes =
      for episode in episodes
        [episode.seasonNumber, episode.episodeNumber]
  else
    multipleEpisodes = null
  fileEpisodeTitle = fileData.episode_title

  {fileName, fileSize, bitRate, duration, fileTitle, seasonNumber,
   episodeNumber, multipleEpisodes, fileEpisodeTitle, fileCountry}

deleteShow = (showId) ->
  if not disableOutput
    db.view 'episodeByShowSeasonEpisode',
      {startkey: [showId, null, null]}
      {endkey:   [showId,   {},   {}]}
    , (err, body) ->
      if err then fatal err, {showId}
      for row in body.rows
        db.destroy row.id, row.rev
    db.get showId, (err, show) ->
      db.destroy show._id, show._rev
      fs.appendFileSync 'files/deletes.txt', show.tvdbTitle + '\n'

dbPutNewShow = (show, cb) ->
  log new Date().toString()[0..20], show.tvdbTitle
  show._id  = uuid()
  show.type = 'show'
  delete show.episodes
  deleteNullProps show
  tvdb.downloadBannersForShow show, ->
    if disableOutput then cb(); return
    db.put show, (err) ->
      if err then fatal err
      inc 'put new show'
      cb()

dbPutEpisode = (episode, cb) ->
  episode._id ?= uuid()
  episode.type = 'episode'
  episode.episodeTitle ?= episode.fileEpisodeTitle
  delete episode.fileEpisodeTitle
  delete episode.fileSize
  delete episode.bitRate
  delete episode.fileName
  deleteNullProps episode

  tvdb.downloadBanner episode.thumb, ->
    if disableOutput then cb(); return
    db.put episode, (err) ->
      if err then fatal err
      inc 'put episode'
      # log 'dbPutEpisode', episode
      cb()

getEpisode = (show, fileData, cb) ->
  {fileTitle, fileName, fileSize, bitRate} = fileData
  fileSizeRateName = [fileSize, bitRate, fileName]

  db.view 'episodeByShowSeasonEpisode',
    {key: [show._id, fileData.seasonNumber, fileData.episodeNumber]}
  , (err, body) ->
    if err then fatal err

    if (episode = body.rows[0]?.value)
      if episode.tvdbEpisodeId
        havefileName = no
        for sizePath in episode.filePaths
          if sizePath[2] is fileName
            havefileName = yes
            break
        if havefileName
          inc 'complete old episode'
          cb()
          return

        inc 'add file to tvdb episode'
        episode = Object.assign fileData, episode
        episode.filePaths.push fileSizeRateName
        log 'add file to tvdb episode', episode
        dbPutEpisode episode, cb
        return

      inc 'old episode no tvdb'
      cb()
      return

    inc 'new episode no tvdb'
    fs.appendFileSync 'files/episode-no-tvdb.txt', show._id + ', ' + fileName + '"\n'
    episode           = fileData
    episode.showId    = show._id
    episode.filePaths = [fileSizeRateName]
    log 'new episode no tvdb', episode
    dbPutEpisode episode, cb

addTvdbEpisodes = (show, fileData, tvdbEpisodes, cb) ->
  if not (tvdbEpisode = tvdbEpisodes.shift())
    getEpisode show, fileData, cb
    return

  inc 'episode from tvdb'
  db.view 'episodeByShowSeasonEpisode',
          {key: [show._id, tvdbEpisode.seasonNumber, tvdbEpisode.episodeNumber]}
  , (err, body) ->
    if err then fatal err

    if body.rows.length > 0
      dbEpisode = body.rows[0].value

      for val,key of tvdbEpisode when val?
        if dbEpisode[key] isnt val
          Object.assign dbEpisode, tvdbEpisode
          dbPutEpisode dbEpisode, ->
            addTvdbEpisodes show, fileData, tvdbEpisodes, cb
          return
      addTvdbEpisodes show, fileData, tvdbEpisodes, cb
      return

    inc 'new tvdb episode'
    Object.assign tvdbEpisode,
      showId:    show._id
      filePaths: []
    dbPutEpisode tvdbEpisode, ->
      addTvdbEpisodes show, fileData, tvdbEpisodes, cb

chkTvdbEpisodes = (show, fileData, cb) ->
  if mappings[show.tvdbTitle?] is 'old'
    deleteShow show._id
    cb()
    return
  if not (tvdbEpisodes = show.episodes)
    inc 'tvdb get episodes'
    if not show.tvdbShowId
      log 'chkTvdbEpisodes no tvdbShowId', show
      console.trace()
      fatal()
    tvdb.getEpisodesByTvdbShowId show.tvdbShowId
    , (err, tvdbEpisodes) ->
      if err then fatal err
      if not tvdbEpisodes
        log 'chkTvdbEpisodes, tvdbEpisodes isnt array',
          util.inspect {show, fileData, tvdbEpisodes}, depth:null
        cb()
      else
        addTvdbEpisodes show, fileData, tvdbEpisodes, cb
  else
    delete show.episodes
    addTvdbEpisodes show, fileData, tvdbEpisodes, cb

exports.checkFile = (filePath, cb) ->
  if /(\.[^\.]{6}|\.filepart)$/i.test filePath
    fs.appendFileSync 'files/partials.txt', 'rm -rf "' + filePath + '"\n'
    setImmediate cb
    return

  fileData = exports.getFileData filePath
  if fileData is 'not-file'  then setImmediate cb; return
  if typeof fileData is 'string'
    inc 'bad-file-' + fileData
    fs.appendFileSync 'files/file-' + fileData + '.txt', 'rm -rf "' + filePath + '"\n'
    setImmediate cb
    return
  {fileName, fileTitle} = fileData

  db.view 'episodeByFilePath', {key: fileName}, (err, body) ->
    if err then fatal err

    if body.rows.length > 0
      inc 'got episode by fileName'
      episode =  body.rows[0].value
      if episode.tvdbEpisodeId and episode.summary
        # if mappings[show.tvdbTitle?] is 'old'
        #   deleteShow episode.showId
        #   cb()
        #   return
        inc 'skipping complete episode'
        cb()
      else
        inc 're-checking episode with no tvdb'
        if not episode.showId
          log 'no episode.showId', fileName
          fatal body
        db.get episode.showId, (err, show) ->
          if err then fatal err
          if show.compact_running?
            log 'compact_running', episode
            fatal()
          chkTvdbEpisodes show, fileData, cb
      return

    db.view 'showByFileTitle', {key: fileTitle}, (err, body) ->
      if err then fatal err

      if body.rows.length > 0
        inc 'got showByFileTitle'
        show = body.rows[0].value
        chkTvdbEpisodes show, fileData, cb

      else
        inc 'tvdb show lookup'
        tvdb.getShowByName fileTitle, (err, show) ->
          # if err then fatal err, {fileTitle, fileData, body, show}
          if err
            log 'tvdb getShowByName err',
                 util.inspect {fileTitle, fileData, body, show}, depth:null
            inc 'tvdb hard error'
            cb()
            return

          if not show
            inc 'file no tvdb show'
            fs.appendFileSync 'files/file-no-tvdb-show.txt', fileName + '"\n'
            cb()
            return

          db.view 'showByTvdbShowId',
            {key: show.tvdbShowId}
          , (err, body) ->
            if err then fatal err

            if (oldShow = body.rows[0]?.value)
              inc 'add filetitle to show'
              if fileTitle not in oldShow.fileTitles
                oldShow.fileTitles.push fileTitle
                db.put oldShow, (err) ->
                  if err then fatal err
                  chkTvdbEpisodes oldShow, fileData, cb
              else
                chkTvdbEpisodes oldShow, fileData, cb
              return

            inc 'new show from tvdb'
            show.fileTitles = [fileTitle]
            dbPutNewShow show, (err) ->
              if err then fatal err
              chkTvdbEpisodes show, fileData, cb

# log exports.getFileData videosPath + 'iZombie.S02E13.720p.HDTV.X264-DIMENSION.mkv'
# exports.checkFile videosPath + 'iZombie.S02E13.720p.HDTV.X264-DIMENSION.mkv', ->
  # dumpInc()
if process.argv[2] is 'all'
  files = fs.listTreeSync videosPath
  totalFiles = files.length
  do oneFile = ->
    if not (filePath = files.shift())
      log 'done'
      dumpInc()
      return
    inc 'checkFile'
    if incs.checkFile % 100 is 0 then dumpInc()
    exports.checkFile filePath, oneFile

###

{
   "_id": "_design/all",
   "language": "javascript",
   "views": {
       "showByFileTitle": {
           "map": "function(doc) { \n  if (doc.type == 'show' && doc.fileTitles)\n    for(i=0; i < doc.fileTitles.length; i++)\n      emit(doc.fileTitles[i], doc);\n}"
       },
       "episodeByShowSeasonEpisode": {
           "map": "function(doc) {\n  if (doc.type == 'episode' && doc.showId)\n    emit([doc.showId, doc.seasonNumber, doc.episodeNumber], doc);\n}"
       },
       "episodeByFilePath": {
           "map": "function(doc) { \n  if (doc.type == 'episode' && doc.filePaths)\n    for(i=0; i < doc.filePaths.length; i++)\n      emit(doc.filePaths[i][2], doc);\n}\n"
       },
       "showByTvdbShowId": {
           "map": "function(doc) {\n  if(doc.type == 'show' && doc.tvdbShowId)\n    emit(doc.tvdbShowId, doc);\n}"
       },
       "fileNoTvdb": {
           "map": "function(doc) { \n  if (doc.type == 'episode' && doc.filePaths && !doc.tvdbEpisodeId)\n    for(i=0; i < doc.filePaths.length; i++)\n      emit(doc.filePaths[i][2], doc);\n}\n"
       },
       "showByTvdbTitle": {
           "map": "function(doc) {\n  if (doc.type == 'show' && doc.tvdbShowId)\n    emit(doc.tvdbTitle, doc);\n}\n"
       },
       "episodeByFilenameSeasonEpisode": {
           "map": "function(doc) {\n  if (doc.type == 'episode' && doc.filePaths)\n    for (i=0; i < doc.filePaths.length; i++)\n      emit([doc.filePaths[i][2], doc.seasonNumber, doc.episodeNumber], doc);\n}"
       },
       "episodesWithFiles": {
           "map": "function(doc) {\n  if (doc.type == 'episode' && doc.showId && doc.filePaths && doc.filePaths.length > 0)\n    emit([doc.showId, doc.seasonNumber, doc.episodeNumber], doc);\n}"
       },
       "all": {
           "map": "function(doc) {\n  emit(null, null);\n}"
       },
       "tvdbNoFile": {
           "map": "function(doc) { \n  if (doc.tvdbEpisodeId && (!doc.filePaths || doc.filePaths.length == 0))\n    emit(doc._id, doc);\n}"
       },
       "showByTitle": {
           "map": "function(doc) { \n  if (doc.type == 'show' && (doc.fileTitles || doc.tvdbTitle))\n    if (doc.tvdbTitle)\n      emit(doc.tvdbTitle, doc);\n    else\n      emit(doc.fileTitles[0], doc);\n}"
       },
       "allShows": {
           "map": "function(doc) { \n  if (doc.type == 'show')\n     emit(doc.tvdbTitle + ', ' + (doc.fileTitles && doc.fileTitles[0]), doc);\n}"
       },
       "episodeByShowId": {
           "map": "function(doc) { \n  if (doc.type == 'episode')\n    emit(doc.showId, doc);\n}\n"
       }
   }
}

###
