exec = require('child_process').execSync

usbHost =  "xobtlu@oracle.usbx.me"

filterRegex = null
if process.argv.length == 3
  filterRegex = process.argv[2]
else
  console.log "usage: regex for filename missing"
  process.exit()

escQuotes = (str) ->
  '"' + str.replace(/\\/g, '\\\\')
           .replace(/"/g,  '\\"') + '"'

findUsb = "ssh #{usbHost} find files -type f -printf " +
    "'%CY-%Cm-%Cd-%P\\\\\\n' | " +
    "grep -v .r[0-9][0-9]$   | " +
    "grep -v .rar$"              +
    " | grep -i " + filterRegex
  
usbFiles = exec(findUsb, {timeout:300000}).toString().split '\n'
console.log usbFiles

while true
  if usbLine = usbFiles.shift()
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

usbLongPath = "#{usbHost}:files/#{usbFilePath}"

console.log()

try
  exec("rsync -avP #{escQuotes usbLongPath} " +
         "#{escQuotes '/mnt/media/movies/'}", {stdio: 'inherit'})
catch e
  console.log "\nrsync download error: \n#{e.message}"
