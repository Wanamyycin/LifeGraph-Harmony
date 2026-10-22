// Local visual QA of the same graph HTML/D3 assets. It is not an ArkWeb test.
require('./ets-loader.cjs');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { buildGraph } = require('../entry/src/main/ets/features/GraphData.ets');
const { AppSnapshot, Palette, NamedItem, RelationEdge, EventCard } = require('../entry/src/main/ets/domain/Models.ets');
const { Person } = require('../entry/src/main/ets/domain/Person.ets');
const root = path.resolve(__dirname, '../entry/src/main/resources/rawfile/graph');
const data = new AppSnapshot(); data.profile.defaultPersonId = 'me';
const relation = new NamedItem(); relation.id = 'friend'; relation.name = '朋友'; data.relations = [relation];
['我', '林晓', '周远', '陈小雨', '王磊', '赵雨晴', '李欣然'].forEach((name, index) => {
  const person = new Person(); person.id = index === 0 ? 'me' : `person-${index}`; person.name = name; data.persons.push(person);
  if (index > 0) { const edge = new RelationEdge(); edge.id = `edge-${index}`; edge.personAId = 'me'; edge.personBId = person.id; edge.relationId = 'friend'; edge.strength = 1 + index % 5; data.edges.push(edge); }
});
const event = new EventCard(); event.event.id = 'walk'; event.event.title = '秋日散步'; event.personIds = ['me', 'person-1', 'person-2']; data.events = [event];
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  if (url.pathname.endsWith('d3.min.js')) { response.setHeader('Content-Type', 'application/javascript'); response.end(fs.readFileSync(path.join(root, 'd3.min.js'))); return; }
  const theme = /^[a-z]+-(light|dark)$/.test(url.searchParams.get('theme') || '') ? url.searchParams.get('theme') : 'forest-light';
  const file = path.join(root, `${theme}.html`);
  if (!fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
  const mode = url.searchParams.get('mode') === 'person' ? 'person' : 'home';
  const payload = JSON.stringify(buildGraph(data, mode, 'me', [], [], new Palette()));
  let html = fs.readFileSync(file, 'utf8');
  html = html.replace('</body>', `<script>document.dispatchEvent(new MessageEvent('message',{data:${JSON.stringify(payload)}}));</script></body>`);
  response.setHeader('Content-Type', 'text/html; charset=utf-8'); response.end(html);
});
server.listen(8795, '127.0.0.1', () => console.log('Graph-only visual QA: http://127.0.0.1:8795/'));
