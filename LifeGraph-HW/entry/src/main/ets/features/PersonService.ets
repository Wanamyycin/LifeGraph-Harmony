import { Person, PersonRepository } from '../domain/Person';

// No React, Expo or UI context. A deliberately small port of the person service.
export class PersonService {
  private repository: PersonRepository;
  private makeId: () => string;
  private now: () => number;

  constructor(
    repository: PersonRepository,
    makeId: () => string,
    now: () => number
  ) {
    this.repository = repository;
    this.makeId = makeId;
    this.now = now;
  }

  async list(): Promise<Person[]> {
    return this.repository.listActive();
  }

  filter(people: Person[], query: string): Person[] {
    const keyword = query.trim().toLocaleLowerCase();
    return people.filter((person: Person) =>
      person.name.toLocaleLowerCase().includes(keyword) ||
      (person.description ?? '').toLocaleLowerCase().includes(keyword));
  }

  async save(id: string, rawName: string, rawDescription: string): Promise<Person> {
    const name = rawName.trim();
    if (name.length === 0) {
      throw new Error('请填写人物姓名');
    }
    const person = id.length > 0 ? await this.repository.findActive(id) : new Person();
    if (person === null) {
      throw new Error('这位人物已不存在，请返回列表刷新');
    }
    const timestamp = this.now();
    person.name = name;
    person.description = rawDescription.trim().length > 0 ? rawDescription.trim() : null;
    person.updatedAt = timestamp;
    if (id.length === 0) {
      person.id = this.makeId();
      person.createdAt = timestamp;
      await this.repository.insert(person);
    } else {
      await this.repository.update(person);
    }
    return person;
  }

  confirmsSave(people: Person[], expected: Person): boolean {
    return people.some((person: Person) => person.id === expected.id &&
      person.name === expected.name && person.description === expected.description &&
      person.updatedAt === expected.updatedAt);
  }

  async archive(id: string): Promise<void> {
    if (await this.repository.findActive(id) === null) {
      throw new Error('这位人物已不存在，请返回列表刷新');
    }
    await this.repository.archive(id, this.now());
  }
}
