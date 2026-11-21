const http = require('http');
const os = require('os');
const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const PORT = process.env.PORT || 8080;
const GREETING = process.env.GREETING || 'Hello from ECS Fargate';
const TOPIC_ARN = process.env.TOPIC_ARN; // подставляет шаблон CloudFormation
const sns = new SNSClient({});           // регион берётся из окружения задачи

function send(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 10000) req.destroy(); // защита от слишком больших запросов
    });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('ok');
  }

  console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);

  // Новый адрес: принять заказ и опубликовать событие OrderPlaced в SNS
  if (req.method === 'POST' && req.url === '/orders') {
    let order;
    try {
      order = JSON.parse(await readBody(req));
    } catch {
      return send(res, 400, { error: 'body must be JSON' });
    }

    const orderId = order.orderId;
    const total = Number(order.total ?? 0);
    if (typeof orderId !== 'string' || orderId.length === 0 || orderId.length > 100 || Number.isNaN(total)) {
      return send(res, 400, { error: 'need {"orderId": "text", "total": number}' });
    }
    if (!TOPIC_ARN) {
      return send(res, 500, { error: 'TOPIC_ARN is not set' });
    }

    try {
      const out = await sns.send(new PublishCommand({
        TopicArn: TOPIC_ARN,
        Message: JSON.stringify({ orderId, total }),
        MessageAttributes: {
          eventType: { DataType: 'String', StringValue: 'OrderPlaced' },
        },
      }));
      console.log('PUBLISHED', orderId, out.MessageId);
      return send(res, 202, { status: 'accepted', orderId, messageId: out.MessageId });
    } catch (err) {
      console.error('PUBLISH FAILED', orderId, err.name, err.message);
      return send(res, 500, { error: 'could not publish order' });
    }
  }

  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<h1>${GREETING}</h1><p>Served by container: <b>${os.hostname()}</b></p>`);
});

server.listen(PORT, '0.0.0.0', () => console.log(`listening on ${PORT}`));

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down');
  server.close(() => process.exit(0));
});
