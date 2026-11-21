const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 8080;
const GREETING = process.env.GREETING || 'Hello from ECS Fargate';

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('ok');
  }
  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<h1>${GREETING}</h1><p>Served by container: <b>${os.hostname()}</b></p>`);
});

server.listen(PORT, '0.0.0.0', () => console.log(`listening on ${PORT}`));

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down');
  server.close(() => process.exit(0));
});
