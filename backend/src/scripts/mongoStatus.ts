import 'dotenv/config';
import { MongoClient } from 'mongodb';

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const MONGO_DB_NAME = process.env.MONGO_DB_NAME || 'kgpl_portal_nosql';

async function main() {
  const client = new MongoClient(MONGO_URI, { serverSelectionTimeoutMS: 5000 });
  await client.connect();
  const db = client.db(MONGO_DB_NAME);
  const collections = await db.listCollections().toArray();
  console.log(`${MONGO_URI}/${MONGO_DB_NAME}`);
  if (collections.length === 0) {
    console.log('No collections yet.');
  }
  for (const info of collections.sort((a, b) => a.name.localeCompare(b.name))) {
    const count = await db.collection(info.name).estimatedDocumentCount();
    console.log(`${info.name.padEnd(24)} ${count}`);
  }
  await client.close();
}

main().catch((error) => {
  console.error('MongoDB status failed:', error?.message || error);
  process.exit(1);
});
