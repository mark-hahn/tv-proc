// Generated by CoffeeScript 2.1.0
(function() {
  var badFile, checkFile, checkFileExists, checkFiles, chkCount, chkTvDB, delOldFiles, deleteCount, downloadCount, errCount, escQuotes, exec, existsCount, f, fileRegex, fileTimeout, findUsb, fname, fs, getUsbFiles, i, len, line, map, mapLines, mapStr, mkdirp, recent, recentCount, recentLimit, request, rimraf, season, seriesName, startTime, t, theTvDbToken, time, title, tvDbErrCount, tvPath, tvdbCache, type, usbAgeLimit, usbFilePath, usbFiles, usbHost, util;

  fs = require('fs-plus');

  util = require('util');

  exec = require('child_process').execSync;

  mkdirp = require('mkdirp');

  request = require('request');

  rimraf = require('rimraf');

  usbHost = fileRegex = null;

  if (process.argv.length === 3) {
    fileRegex = process.argv[2];
  } else {
    usbHost = process.argv[2] + '@' + process.argv[3];
  }

  console.log(`.... starting tv.coffee for ${usbHost || fileRegex} ....`);

  startTime = time = Date.now();

  deleteCount = chkCount = recentCount = existsCount = errCount = downloadCount = 0;

  findUsb = `ssh ${usbHost} find videos -type f -printf '%CY-%Cm-%Cd-%P\\\\\\n'`;

  //##########
  // constants
  map = {};

  mapStr = fs.readFileSync('tv-map', 'utf8');

  mapLines = mapStr.split('\n');

  for (i = 0, len = mapLines.length; i < len; i++) {
    line = mapLines[i];
    [f, t] = line.split(',');
    if (line.length) {
      map[f.trim()] = t.trim();
    }
  }

  recent = JSON.parse(fs.readFileSync('tv-recent', 'utf8'));

  tvPath = '/mnt/media/tv/';

  usbAgeLimit = Date.now() - 2 * 7 * 24 * 60 * 60 * 1000; // 2 weeks ago

  recentLimit = Date.now() - 3 * 7 * 24 * 60 * 60 * 1000; // 3 weeks ago

  fileTimeout = {
    timeout: 2 * 60 * 60 * 1000 // 2 hours
  };

  
  //###############
  // async routines
  getUsbFiles = delOldFiles = checkFiles = checkFile = badFile = checkFileExists = checkFile = chkTvDB = null;

  //######################################
  // get theTvDb api token
  theTvDbToken = null;

  request.post('https://api.thetvdb.com/login', {
    json: true,
    body: {
      apikey: "2C92771D87CA8718"
    }
  }, (error, response, body) => {
    if (error || response.statusCode !== 200) {
      console.log('theTvDb login error:', error);
      console.log('theTvDb statusCode:', response && response.statusCode);
      return process.exit();
    } else {
      theTvDbToken = body.token;
      return process.nextTick(delOldFiles);
    }
  });

  //#####################################################
  // delete old files in usb/videos
  delOldFiles = () => {
    var j, len1, recentChgd, recentFname, recentTime, res, usbDate, usbFilePath, usbFiles, usbLine;
    console.log(".... checking for files to delete ....");
    usbFiles = exec(findUsb, {
      timeout: 10000
    }).toString().split('\n');
    for (j = 0, len1 = usbFiles.length; j < len1; j++) {
      usbLine = usbFiles[j];
      usbDate = new Date(usbLine.slice(0, 10)).getTime();
      if (usbDate < usbAgeLimit) {
        usbFilePath = usbLine.slice(11);
        deleteCount++;
        console.log('removing old file:', usbFilePath);
        res = exec(`ssh ${usbHost} 'rm -rf videos/${usbFilePath}'`, {
          timeout: 10000
        }).toString();
        if (res.length > 1) {
          console.log(res);
        }
      }
    }
    recentChgd = false;
    for (recentFname in recent) {
      recentTime = recent[recentFname];
      if (!(recentTime < (Date.now() - recentLimit))) {
        continue;
      }
      delete recent[recentFname];
      recentChgd = true;
    }
    if (recentChgd) {
      fs.writeFileSync('tv-recent', JSON.stringify(recent));
    }
    console.log(".... downloading files ....");
    return process.nextTick(checkFiles);
  };

  //###########################################################
  // check each remote file, compute series and episode numbers
  usbFilePath = usbFiles = seriesName = season = fname = title = season = type = null;

  tvDbErrCount = 0;

  checkFiles = () => {
    usbFiles = exec(findUsb, {
      timeout: 10000
    }).toString().split('\n');
    return process.nextTick(checkFile);
  };

  checkFile = () => {
    var fext, guessItRes, parts, usbLine;
    tvDbErrCount = 0;
    if (usbLine = usbFiles.shift()) {
      chkCount++;
      usbFilePath = usbLine.slice(11);
      parts = usbFilePath.split('/');
      fname = parts[parts.length - 1];
      parts = fname.split('.');
      fext = parts[parts.length - 1];
      if (fext.length === 6 || (fext === 'nfo' || fext === 'idx' || fext === 'sub' || fext === 'txt' || fext === 'jpg' || fext === 'gif' || fext === 'jpeg')) {
        process.nextTick(checkFile);
        return;
      }
      if (recent[fname]) {
        recentCount++;
        // console.log '------', downloadCount,'/', chkCount, 'SKIPPING RECENT:', fname
        process.nextTick(checkFile);
        return;
      }
      console.log('>>>>>>', downloadCount, '/', chkCount, fname);
      guessItRes = exec(`/usr/local/bin/guessit -js '${fname.replace("'", '')}'`, {
        timeout: 10000
      }).toString();
      try {
        ({title, season, type} = JSON.parse(guessItRes));
        if (!type === 'episode') {
          console.log('\nskipping non-episode:', fname);
          process.nextTick(badFile);
          return;
        }
        if (!Number.isInteger(season)) {
          console.log('\nno season integer for ' + fname);
          process.nextTick(badFile);
          return;
        }
      } catch (error1) {
        console.log('\nerror parsing:' + fname);
        process.nextTick(badFile);
        return;
      }
      return process.nextTick(chkTvDB);
    } else {
      return console.log('.... done ....\ndeleted:         ', deleteCount, '\nskipped recent:  ', recentCount, '\nskipped existing:', existsCount, '\nerrors:          ', errCount, '\ndownloaded:      ', downloadCount, '\nelapsed(mins):   ', ((Date.now() - startTime) / (60 * 1000)).toFixed(1));
    }
  };

  tvdbCache = {};

  chkTvDB = () => {
    if (tvdbCache[title]) {
      seriesName = tvdbCache[title];
      process.nextTick(checkFileExists);
      return;
    }
    return request('https://api.thetvdb.com/search/series?name=' + encodeURIComponent(title), {
      json: true,
      headers: {
        Authorization: 'Bearer ' + theTvDbToken
      }
    }, (error, response, body) => {
      // console.log {error, response, body}
      if (error || ((response != null ? response.statusCode : void 0) !== 200)) {
        console.log('no series name found in theTvDB:', fname);
        console.log('search error:', error);
        console.log('search statusCode:', response && response.statusCode);
        console.log('search body:', body);
        if (error) {
          if (++tvDbErrCount === 15) {
            console.log('giving up, downloaded:', downloadCount);
            return;
          }
          console.log("tvdb err retry, waiting one minute");
          return setTimeout(chkTvDB, 60 * 1000);
        } else {
          return process.nextTick(checkFile);
        }
      } else {
        seriesName = body.data[0].seriesName;
        if (map[seriesName]) {
          console.log('+++ Mapping', seriesName, 'to', map[seriesName]);
          seriesName = map[seriesName];
        }
        tvdbCache[title] = seriesName;
        return process.nextTick(checkFileExists);
      }
    });
  };

  escQuotes = function(str) {
    return '"' + str.replace('\\', '\\\\').replace('"', '\"') + '"';
  };

  checkFileExists = () => {
    var tvFilePath, tvSeasonPath, usbLongPath;
    tvSeasonPath = `${tvPath}${seriesName}/Season ${season}`;
    tvFilePath = `${tvSeasonPath}/${fname}`;
    usbLongPath = `${usbHost}:videos/${usbFilePath}`;
    if (fs.existsSync(tvFilePath)) {
      existsCount++;
      console.log(`skipping existing file: ${fname}`);
    } else {
      mkdirp.sync(tvSeasonPath);
      if (usbFilePath.indexOf('/') > -1) {
        console.log(`downloading file in dir: ${usbFilePath}`);
      } else {
        console.log(`downloading file: ${usbFilePath}`);
      }
      console.log(exec(`rsync -av ${escQuotes(usbLongPath)} ${escQuotes(tvFilePath)}`, fileTimeout).toString().replace('\n\n', '\n'), ((Date.now() - time) / 1000).toFixed(0) + ' secs');
      downloadCount++;
      time = Date.now();
    }
    recent[fname] = Date.now();
    fs.writeFileSync('tv-recent', JSON.stringify(recent));
    return process.nextTick(checkFile);
  };

  badFile = () => {
    errCount++;
    console.log('******', downloadCount, '/', chkCount, '---BAD---:', fname);
    recent[fname] = Date.now();
    fs.writeFileSync('tv-recent', JSON.stringify(recent));
    downloadCount++;
    time = Date.now();
    return process.nextTick(checkFile);
  };

}).call(this);
