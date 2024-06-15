const axios = require("axios");

const name      = "mark";
const pwd       = "90-MNBbnmyui";
const apiKey    = "1c399bd079d549cba8c916244d3add2b"
const markUsrId = "894c752d448f45a3a1260ccaabd0adff";
const authHdr   = `UserId="${markUsrId}", `                +
                  'Client="MyClient", Device="myDevice", ' +
                  'DeviceId="123456", Version="1.0.0"';
let token = '';


////////////////////////  INIT  ///////////////////////

const getToken = async () => {
  const config = {
    method: 'post',
    url: "http://hahnca.com:8096" +
         "/emby/Users/AuthenticateByName" +
         `?api_key=${apiKey}`,
    headers: { Authorization: authHdr },
    data: { Username: name, Pw: pwd },
  };
  const showsRes = await axios(config);
  token = showsRes.data.AccessToken;
  // console.log('emby.js getToken:', token);
}


////////////////////////  SCAN LIBRARY  ///////////////////////

const scanLibrariesUrl = () => {
  return `http://localhost:8096 / emby / Library / Refresh
    ?Recursive=true
    &MetadataRefreshMode=Default
    &ImageRefreshMode=Default
    &ReplaceAllMetadata=false
    &ReplaceAllImages=false
    &api_key=${apiKey}
  `.replace(/\s*/g, "");
}

const scanLibrary = async () => {
  await axios.post(scanLibrariesUrl());
}

exports.scanLibrary = scanLibrary;

exports.init = async () => {
  await getToken();
}


