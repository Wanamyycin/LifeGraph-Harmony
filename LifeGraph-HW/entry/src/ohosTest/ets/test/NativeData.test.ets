import { abilityDelegatorRegistry } from '@kit.TestKit';
import { application } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { describe, it, expect } from '@ohos/hypium';
import { NativeSqlConnection } from '../../../main/ets/data/NativeSqlConnection';
import { SqlDatabase } from '../../../main/ets/data/SqlDatabase';
import { LifeGraphService } from '../../../main/ets/features/LifeGraphService';
import { PersonDraft, EventDraft, RelationInput } from '../../../main/ets/domain/Models';

// Runs against a unique native RDB file. Never opens or removes the user's store.
export default function nativeDataTest() {
  describe('NativeLifeGraphData', () => {
    it('persistsReopensAndRollsBack', 0, async () => {
      const context = await application.createModuleContext(
        abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext(), 'entry_test');
      const name = 'test-' + util.generateRandomUUID() + '.db';
      let db: SqlDatabase | null = null;
      try {
        db = new SqlDatabase(await NativeSqlConnection.open(context, name));
        let service = new LifeGraphService(db, () => util.generateRandomUUID(), () => Date.now());
        await service.initialize();
        const initial = await service.snapshot();
        expect(initial.persons.length).assertEqual(1);
        const person = new PersonDraft(); person.name = '原生持久化测试'; person.description = '关闭后应保留';
        const id = await service.savePerson(person);
        const event = new EventDraft(); event.title = '原生事件'; event.personIds = [id, initial.profile.defaultPersonId];
        await service.saveEvent(event);
        const invalid = new PersonDraft(); invalid.name = '应当回滚';
        const relation = new RelationInput(); relation.targetPersonId = 'nonexistent'; relation.relationId = initial.relations[0].id;
        invalid.relations = [relation];
        let failed = false;
        try { await service.savePerson(invalid); } catch (_) { failed = true; }
        expect(failed).assertTrue();
        await db.close(); db = null;
        db = new SqlDatabase(await NativeSqlConnection.open(context, name));
        service = new LifeGraphService(db, () => util.generateRandomUUID(), () => Date.now());
        await service.initialize();
        const restored = await service.snapshot();
        expect(restored.persons.length).assertEqual(2);
        expect(restored.persons.some((item) => item.id === id && item.description === '关闭后应保留')).assertTrue();
        expect(restored.events.length).assertEqual(1);
        expect(restored.events[0].personIds.length).assertEqual(2);
        expect(restored.profile.defaultPersonId).assertEqual(initial.profile.defaultPersonId);
      } finally {
        if (db !== null) { await db.close(); }
        await relationalStore.deleteRdbStore(context, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      }
    });
  });
}
