// Field semantics follow life-graph-main/src/domain/account/entities/person.ts.
export class Person {
  id: string = '';
  name: string = '';
  description: string | null = null;
  avatarAssetId: string | null = null;
  createdAt: number = 0;
  updatedAt: number = 0;
  deletedAt: number | null = null;
}

export interface PersonRepository {
  listActive(): Promise<Person[]>;
  findActive(id: string): Promise<Person | null>;
  insert(person: Person): Promise<void>;
  update(person: Person): Promise<void>;
  archive(id: string, timestamp: number): Promise<void>;
}
