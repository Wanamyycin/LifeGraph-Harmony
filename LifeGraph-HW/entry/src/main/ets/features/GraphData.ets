import { AppSnapshot, EventCard, Palette, RelationEdge } from '../domain/Models';
import { Person } from '../domain/Person';

export class GraphPerson {
  id: string = '';
  name: string = '';
  avatarUri: string | null = null;
  isCenter: boolean = false;
  nodeType: string = 'person';
}

export class GraphEvent {
  id: string = '';
  title: string = '';
  color: string = '#5B8C5A';
  coverUri: string | null = null;
  isCenter: boolean = false;
}

export class GraphEdge {
  source: string = '';
  target: string = '';
  label: string = '';
  color: string = '';
  opacity: number = 0.5;
  strength: number | null = null;
}

export class GraphPayload {
  personNodes: GraphPerson[] = [];
  eventNodes: GraphEvent[] = [];
  edges: GraphEdge[] = [];
}

export function buildGraph(data: AppSnapshot, mode: string, centerId: string, relationIds: string[], branchIds: string[],
  palette: Palette, images: Map<string, string> = new Map<string, string>()): GraphPayload {
  const graph = new GraphPayload();
  if (mode === 'branch') { centerId = data.profile.defaultPersonId; }
  const people = data.persons.filter((person: Person) => person.deletedAt === null);
  const ids = new Set<string>();
  const valid = new Set<string>(people.map((person: Person) => person.id));
  if (valid.has(centerId)) { ids.add(centerId); }
  const edges = data.edges.filter((edge: RelationEdge) => (edge.personAId === centerId || edge.personBId === centerId) &&
    valid.has(edge.personAId) && valid.has(edge.personBId) && (relationIds.length === 0 || relationIds.includes(edge.relationId)));
  if (mode !== 'branch') {
    for (const edge of edges) {
      ids.add(edge.personAId); ids.add(edge.personBId);
      const link = new GraphEdge(); link.source = edge.personAId; link.target = edge.personBId; link.strength = edge.strength;
      link.label = data.relations.find((item) => item.id === edge.relationId)?.name ?? '';
      const index = data.relations.findIndex((item) => item.id === edge.relationId);
      const colors: string[] = ['#C97B6B', '#7BA88A', '#6A8A8F', '#C49A6C', '#A88CB2'];
      link.color = colors[Math.max(0, index) % colors.length]; graph.edges.push(link);
    }
  }
  if (mode === 'person' || mode === 'branch') {
    const events = data.events.filter((card: EventCard) => card.personIds.includes(centerId) &&
      (branchIds.length === 0 || card.branchIds.some((id: string) => branchIds.includes(id))));
    for (const card of events) {
      const node = new GraphEvent(); node.id = card.event.id; node.title = card.event.title; node.color = card.event.color;
      node.coverUri = images.get(card.assets.find((asset) => asset.role === 'cover')?.id ?? '') ?? null;
      graph.eventNodes.push(node);
      if (mode === 'branch') {
        const link = new GraphEdge(); link.source = centerId; link.target = node.id; link.color = palette.primary; link.opacity = 0.8; graph.edges.push(link);
      }
      for (const personId of card.personIds) {
        if (!valid.has(personId) || (mode === 'branch' && personId === centerId)) { continue; }
        ids.add(personId);
        const link = new GraphEdge(); link.source = node.id; link.target = personId; link.color = mode === 'branch' ? palette.primary : palette.border;
        link.opacity = mode === 'branch' ? 0.8 : 0.5; graph.edges.push(link);
      }
    }
  }
  for (const person of people) {
    if (!ids.has(person.id)) { continue; }
    const node = new GraphPerson(); node.id = person.id; node.name = person.name;
    node.isCenter = person.id === centerId; node.avatarUri = images.get(person.avatarAssetId ?? '') ?? null;
    graph.personNodes.push(node);
  }
  return graph;
}
