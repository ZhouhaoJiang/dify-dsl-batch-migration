curl 'https://your-dify.example.com/console/api/apps/<APP_ID>/export?include_secret=false' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'authorization: Bearer <YOUR_ACCESS_TOKEN>' \
  -H 'Referer: https://your-dify.example.com/apps' \
  -H 'sec-ch-ua: "Chromium"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'User-Agent: <YOUR_USER_AGENT>' \
  -H 'content-type: application/json'