
log = require('./utils') 'tvdb'

fs   = require 'fs-plus'
url  = require 'url'
path = require 'path'
http = require 'http'
util = require 'util'
Fuzz = require 'fuzzyset.js'
TVDB = require 'node-tvdb/compat'
tvdb = new TVDB '2C92771D87CA8718'
request = require 'request'
parsePipeList = TVDB.utils.parsePipeList

showsByName         = {}
episodeListByTvdbId = {}

cleanEpisodes = (episodes) ->
  if episodes
    for episode in episodes
      {id, EpisodeName, EpisodeNumber, FirstAired, GuestStars, IMDB_ID,
        Overview, SeasonNumber, filename, thumb_height, thumb_width} = episode
      {tvdbEpisodeId: id, episodeTitle: EpisodeName, \
       seasonNumber: +SeasonNumber, episodeNumber: +EpisodeNumber,
       aired: FirstAired, guestStars: GuestStars, imdbEpisodeId: IMDB_ID,
       summary: Overview, thumb: filename,
       thumbW: +thumb_width or null, thumbH: +thumb_height or null}

cleanActors = (actors) ->
  if actors
    for actor in actors
      {Image, Name, Role} = actor
      {thumb: Image, name: Name, role: Role}

exports.getSeriesIdByName = (showNameIn, cb) ->
  seriesId = fuzzRes = null
  tryseq = 0
  do tryit = ->
    switch ++tryseq
      when 2 then showNameIn = showNameIn.replace /\./g, ' '
      when 3 then showNameIn = showNameIn.replace /\([^\)]*\)|\[[^\]]*\]/g, ''
      when 4
        fs.appendFileSync 'files/no-tvdb-match.txt',
                           showNameIn + ', ' + util.inspect(fuzzRes, depth:null) + '\n'
        cb()
        return
    showNameIn = showNameIn.replace /^\s+|\s+$/g, ''
    tvdb.getSeriesByName showNameIn, (err, res) ->
      if err then cb err; return
      if not (allSeries = res) then tryit(); return

      switch res.length
        when 0 then tryit(); return
        when 1 then seriesId = allSeries[0].seriesid
        else
          titles = []
          for series in allSeries
            titles.push series.SeriesName

          fuzz = new Fuzz titles
          fuzzRes = fuzz.get showNameIn

          if fuzzRes.length is 0 then tryit(); return
          score = fuzzRes[0][0]
          title = fuzzRes[0][1]
          if score < 0.65 then tryit(); return
          for series in allSeries
            if series.SeriesName is title
              seriesId = series.seriesid
              break

      cb null, seriesId, (if fuzzRes?.length > 1 then fuzzRes)

exports.getShowByName = (showNameIn, cb) ->
  if (show = showsByName[showNameIn]) then cb null, show; return
  if show is null then cb(); return

  exports.getSeriesIdByName showNameIn, (err, seriesId) ->
    if err then cb err; return

    if not seriesId
      showsByName[showNameIn] = null
      setImmediate cb
      return

    tvdb.getSeriesAllById seriesId, (err, tvdbSeries) ->
      if err then cb err; return
      {Airs_DayOfWeek, Airs_Time, FirstAired, Genre, IMDB_ID,
        Network, Overview, Runtime, SeriesName,
        Status, zap2it_id, Episodes} = tvdbSeries
      tags = {}
      tags[tag] = yes for tag in parsePipeList Genre ? ''
      showRes = {tvdbShowId: seriesId, tvdbTitle: SeriesName, \
                 imdbShowId: IMDB_ID, zap2itShowId: zap2it_id,
                 day: Airs_DayOfWeek, time: Airs_Time,
                 started: FirstAired, tags,
                 network: Network, summary: Overview,
                 length: (+Runtime)*60, status: Status}
      showRes.episodes = episodeListByTvdbId[seriesId] =
        cleanEpisodes Episodes

      showRes.banners = {}
      tvdb.getBanners seriesId, (err, banners) ->
        if err then cb err; return
        if banners
          for banner in banners
            {BannerType, BannerType2, BannerPath,ThumbnailPath} = banner
            key = BannerType + '-' + BannerType2
            if key.indexOf('season') > -1 then continue
            showRes.banners[key] ?= []
            showRes.banners[key].push  {BannerPath, ThumbnailPath}
        tvdb.getActors seriesId, (err, actors) ->
          if err then cb err; return
          if actors
            showRes.actors = cleanActors actors
          showsByName[showNameIn] = showRes

          cb null, showRes

exports.clearCache = ->
  showsByName         = {}
  episodeListByTvdbId = {}

exports.getEpisodesByTvdbShowId = (id, cb) ->
  if (episodes = episodeListByTvdbId[id]) then cb null, episodes; return

  tvdb.getEpisodesById id, (err, res) ->
    if err then log 'err from getEpisodesById'
    episodeListByTvdbId[id] = episodes = cleanEpisodes res
    cb null, episodes

getBanner = (file, cb) ->
  uri      = 'http://thetvdb.com/banners/' + file
  filename = '/archive/tvdb-banners/' + file
  metaName = filename + '.json'
  fileSize = null
  try
    stats    = fs.statSync filename
    fileSize = stats.size
    meta     = JSON.parse fs.readFileSync metaName, 'utf8'
    if +meta.length is fileSize
      setImmediate -> cb null, meta
      return
  catch e
  if fileSize?
    fs.removeSync filename
    fs.removeSync metaName
  fs.makeTreeSync path.dirname filename
  try
    request.head uri, (err, res) ->
      if err then cb err; return
      request(uri).pipe(fs.createWriteStream(filename)).on "close", ->
        meta =
          type:   res.headers["content-type"]
          length: res.headers["content-length"]
        fs.writeFileSync metaName, JSON.stringify meta
        cb null, meta
  catch e
    cb e

exports.downloadBanner = (banner, cb) ->
  if not banner then setImmediate cb; return
  getBanner banner, (err, meta) ->
    if err
      log 'getBanner error', banner, err
      fs.appendFileSync 'files/download-banner-errs.txt',
                     show._id + ', ' + banner + ',  ' + err.message + '\n'
    cb()

exports.downloadBannersForShow = (show, cb) ->
  if not show.banners then cb(); return

  allBanners = []
  addBanners = (obj) ->
    for k, v of obj
      if (matches = /\.(jpg|gif|png)$/i.exec v)
        allBanners.push v
      else if typeof v is 'object'
        addBanners v
  addBanners show.banners
  addBanners show.actors

  do oneBanner = ->
    if not (banner = allBanners.shift())
      cb()
      return
      
    exports.downloadBanner banner, oneBanner
