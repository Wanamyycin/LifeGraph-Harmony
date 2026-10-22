import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { NativeSqlConnection } from '../data/NativeSqlConnection';
import { SqlDatabase } from '../data/SqlDatabase';
import { LifeGraphService } from '../features/LifeGraphService';

export class AppServices {
  private static service: LifeGraphService | null = null;
  private static database: SqlDatabase | null = null;
  private static opening: Promise<LifeGraphService> | null = null;
  private static closing: Promise<void> | null = null;

  static async open(context: common.Context): Promise<LifeGraphService> {
    if (AppServices.closing !== null) { await AppServices.closing; }
    if (AppServices.service !== null) { return AppServices.service; }
    if (AppServices.opening !== null) { return AppServices.opening; }
    const opening = AppServices.create(context);
    AppServices.opening = opening;
    try { return await opening; } finally { AppServices.opening = null; }
  }

  private static async create(context: common.Context): Promise<LifeGraphService> {
    const connection = await NativeSqlConnection.open(context);
    const database = new SqlDatabase(connection);
    const service = new LifeGraphService(database, () => util.generateRandomUUID(), () => Date.now());
    try { await service.initialize(); } catch (error) {
      await database.close(); throw new Error(String(error));
    }
    AppServices.database = database; AppServices.service = service;
    return service;
  }

  static async close(): Promise<void> {
    if (AppServices.closing !== null) { return AppServices.closing; }
    const closing = AppServices.finishClose(); AppServices.closing = closing;
    try { await closing; } finally { AppServices.closing = null; }
  }

  private static async finishClose(): Promise<void> {
    if (AppServices.opening !== null) {
      try { await AppServices.opening; } catch (_) { return; }
    }
    const database = AppServices.database;
    AppServices.database = null; AppServices.service = null;
    if (database !== null) { await database.close(); }
  }
}
