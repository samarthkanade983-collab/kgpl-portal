import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { MongoClient } from 'mongodb';
import { MONGO_INDEXES, applyMongoIndexes } from '../config/mongodb.js';

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const MONGO_DB_NAME = process.env.MONGO_DB_NAME || 'kgpl_portal_nosql';
const DATA_DIR = path.resolve(process.cwd(), 'data', 'nosql');

async function main() {
  if (!fs.existsSync(DATA_DIR)) {
    console.log('No backend/data/nosql directory found, nothing to import.');
    return;
  }

  const client = new MongoClient(MONGO_URI, { serverSelectionTimeoutMS: 5000 });
  await client.connect();
  const db = client.db(MONGO_DB_NAME);
  console.log(`Importing into ${MONGO_URI}/${MONGO_DB_NAME}`);

  let imported = 0;
  let duplicates = 0;

  for (const file of fs.readdirSync(DATA_DIR)) {
    if (!file.endsWith('.json')) continue;
    const name = file.slice(0, -'.json'.length);
    let docs: any[] = [];
    try {
      const parsed = JSON.parse(fs.readFileSync(path.join(DATA_DIR, file), 'utf-8'));
      docs = Array.isArray(parsed) ? parsed : [];
    } catch (error: any) {
      console.warn(`Skipping ${file}: ${error?.message || error}`);
      continue;
    }
    if (docs.length === 0) {
      console.log(`${name}: empty, skipped`);
      continue;
    }
    try {
      const result = await db.collection(name).insertMany(docs, { ordered: false });
      imported += result.insertedCount;
      console.log(`${name}: imported ${result.insertedCount} documents`);
    } catch (error: any) {
      const inserted = Number(error?.result?.insertedCount || 0);
      const dup = (error?.writeErrors || []).filter((e: any) => e.code === 11000).length;
      imported += inserted;
      duplicates += dup;
      if (inserted === 0 && dup === 0) {
        console.warn(`${name}: import failed: ${error?.message || error}`);
      } else {
        console.log(`${name}: imported ${inserted}, skipped ${dup} existing`);
      }
    }
  }

  await applyMongoIndexes(db);
  console.log(`Indexes ensured: ${Object.keys(MONGO_INDEXES).join(', ')}`);
  console.log(`Done. ${imported} documents imported, ${duplicates} already present.`);
  await client.close();
}

main().catch((error) => {
  console.error('Import failed:', error?.message || error);
  process.exit(1);
});
