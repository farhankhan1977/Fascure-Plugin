'use strict';

const http = require('http');

const port = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  const body = [
    '<!doctype html>',
    '<meta charset="utf-8">',
    '<title>Fascure Node.js App</title>',
    '<body style="font-family:sans-serif;margin:40px">',
    '<h1>Fascure Node.js App</h1>',
    '<p>This Node.js application is running through the plugin.</p>',
    '<ul>',
    '<li>Node.js ' + process.version + '</li>',
    '<li>Port ' + port + '</li>',
    '<li>Request ' + (req.url || '/') + '</li>',
    '<li>Time ' + new Date().toISOString() + '</li>',
    '</ul>',
    '</body>',
  ].join('\n');

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(body);
});

server.listen(port, '127.0.0.1');
