// Stub server used only by cold-start-test.ps1 to prove the launcher chain works
// without touching a real DeepSeek Harness instance.
// It mirrors "dsh web" behaviour: it opens the browser itself unless --no-open is passed.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const port = Number(process.env.FAKE_PORT || 3099);
const url = 'http://127.0.0.1:' + port + '/';
const noOpen = process.argv.includes('--no-open');
const logFile = path.join(__dirname, 'fake-server.log');
const log = (m) => fs.appendFileSync(logFile, new Date().toISOString() + ' ' + m + '\n');

const server = http.createServer((req, res) => {
  log('HTTP request: ' + req.method + ' ' + req.url + ' ua=' + (req.headers['user-agent'] || ''));
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<html><head><title>DSH launcher self-test</title></head><body style="font-family:sans-serif;padding:2rem">' +
          '<h2>启动链路自检成功</h2><p>Copilot 键 -> 启动 DSH 的冷启动链路工作正常。这个标签页可以关闭。</p></body></html>');
});
server.listen(port, '127.0.0.1', () => {
  log('stub listening on ' + port + ' argv=[' + process.argv.slice(2).join(' ') + ']');
  if (!noOpen) {
    log('stub opens the browser itself (mirrors "dsh web")');
    spawn('cmd', ['/c', 'start', '', url], { detached: true, stdio: 'ignore' }).unref();
  }
});
setTimeout(() => { log('stub exiting'); process.exit(0); }, 30000);
