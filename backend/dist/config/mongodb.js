import { MongoClient } from 'mongodb';
import fs from 'fs';
import path from 'path';
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017';
const MONGO_DB_NAME = process.env.MONGO_DB_NAME || 'kgpl_portal_nosql';
let mongoDbInstance = null;
let isLiveMongo = false;
// Local persistent JSON storage fallback if MongoDB daemon is not running
const dataDir = path.resolve(process.cwd(), 'data', 'nosql');
if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true });
}
class FallbackMongoCollection {
    collectionName;
    filePath;
    documents = [];
    constructor(collectionName) {
        this.collectionName = collectionName;
        this.filePath = path.join(dataDir, `${collectionName}.json`);
        this.load();
    }
    load() {
        try {
            if (fs.existsSync(this.filePath)) {
                const raw = fs.readFileSync(this.filePath, 'utf-8');
                this.documents = JSON.parse(raw);
            }
        }
        catch {
            this.documents = [];
        }
    }
    save() {
        try {
            fs.writeFileSync(this.filePath, JSON.stringify(this.documents, null, 2), 'utf-8');
        }
        catch { }
    }
    async insertOne(doc) {
        const newDoc = {
            _id: `doc_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`,
            ...doc,
            created_at: new Date().toISOString(),
        };
        this.documents.push(newDoc);
        this.save();
        return { acknowledged: true, insertedId: newDoc._id };
    }
    async deleteOne(query = {}) {
        const index = this.documents.findIndex((d) => {
            for (const k in query) {
                if (d[k] !== query[k])
                    return false;
            }
            return true;
        });
        if (index === -1)
            return { acknowledged: true, deletedCount: 0 };
        this.documents.splice(index, 1);
        this.save();
        return { acknowledged: true, deletedCount: 1 };
    }
    find(query = {}) {
        const matches = this.documents.filter((d) => {
            for (const k in query) {
                if (d[k] !== query[k])
                    return false;
            }
            return true;
        });
        let sortKey = null;
        let sortDirection = 1;
        let take = 0;
        const cursor = {
            sort(spec) {
                const keys = Object.keys(spec || {});
                if (keys.length > 0) {
                    sortKey = keys[0];
                    sortDirection = Number(spec[keys[0]]) < 0 ? -1 : 1;
                }
                return cursor;
            },
            limit(n) {
                take = Math.max(0, Number(n) || 0);
                return cursor;
            },
            async toArray() {
                let rows = [...matches];
                if (sortKey) {
                    const key = sortKey;
                    rows.sort((a, b) => {
                        const av = a?.[key] ?? '';
                        const bv = b?.[key] ?? '';
                        return av < bv ? -sortDirection : av > bv ? sortDirection : 0;
                    });
                }
                if (take > 0)
                    rows = rows.slice(0, take);
                return rows;
            },
        };
        return cursor;
    }
    async findOne(query) {
        return this.documents.find((d) => {
            for (const k in query) {
                if (d[k] !== query[k])
                    return false;
            }
            return true;
        }) || null;
    }
    async updateOne(query, update, options = {}) {
        let existing = await this.findOne(query);
        if (existing) {
            if (update.$set)
                Object.assign(existing, update.$set);
            if (update.$inc) {
                for (const k in update.$inc) {
                    existing[k] = (existing[k] || 0) + update.$inc[k];
                }
            }
            existing.updated_at = new Date().toISOString();
            this.save();
            return { acknowledged: true, modifiedCount: 1 };
        }
        else if (options.upsert) {
            const newDoc = { ...query };
            if (update.$set)
                Object.assign(newDoc, update.$set);
            if (update.$inc) {
                for (const k in update.$inc) {
                    newDoc[k] = (newDoc[k] || 0) + update.$inc[k];
                }
            }
            return this.insertOne(newDoc);
        }
        return { acknowledged: false, modifiedCount: 0 };
    }
}
const fallbackCollections = {
    video_telemetry: new FallbackMongoCollection('video_telemetry'),
    video_usage: new FallbackMongoCollection('video_usage'),
    code_playground: new FallbackMongoCollection('code_playground'),
};
export const MONGO_INDEXES = {
    video_telemetry: [
        { key: { video_id: 1, timestamp: -1 } },
        { key: { user_id: 1, timestamp: -1 } },
    ],
    video_usage: [{ key: { user_id: 1, video_id: 1 }, unique: true }],
    llama_chat_history: [{ key: { userId: 1, createdAt: -1 } }],
    question_replies: [
        { key: { questionId: 1 } },
        { key: { internId: 1, teamLeaderId: 1 } },
    ],
    sops: [{ key: { id: 1 } }],
    code_playground: [{ key: { userId: 1, createdAt: -1 } }],
};
export async function applyMongoIndexes(db) {
    for (const [name, specs] of Object.entries(MONGO_INDEXES)) {
        for (const spec of specs) {
            try {
                await db.collection(name).createIndex(spec.key, spec.unique ? { unique: true } : {});
            }
            catch (error) {
                console.warn(`🍃 Could not create index on ${name}: ${error?.message || error}`);
            }
        }
    }
}
export async function connectMongo() {
    try {
        const client = new MongoClient(MONGO_URI, { serverSelectionTimeoutMS: 800 });
        await client.connect();
        mongoDbInstance = client.db(MONGO_DB_NAME);
        await applyMongoIndexes(mongoDbInstance);
        isLiveMongo = true;
        console.log(`🍃 Connected to live MongoDB instance: ${MONGO_URI}/${MONGO_DB_NAME}`);
    }
    catch {
        isLiveMongo = false;
        console.log('🍃 MongoDB daemon not found on port 27017. Initialized persistent NoSQL storage engine in backend/data/nosql/');
    }
}
function fallbackCollection(name) {
    if (!fallbackCollections[name]) {
        fallbackCollections[name] = new FallbackMongoCollection(name);
    }
    return fallbackCollections[name];
}
function degradeToFallback(error) {
    if (isLiveMongo) {
        const detail = error?.message ? ` (${error.message})` : '';
        console.warn(`🍃 MongoDB connection lost, switching to local storage in backend/data/nosql/${detail}`);
    }
    isLiveMongo = false;
}
// Wraps live Mongo operations so a daemon that dies after startup degrades to
// the JSON fallback instead of failing the request.
class LiveCollectionFacade {
    name;
    constructor(name) {
        this.name = name;
    }
    async insertOne(doc) {
        if (!isLiveMongo || !mongoDbInstance)
            return fallbackCollection(this.name).insertOne(doc);
        try {
            return await mongoDbInstance.collection(this.name).insertOne(doc);
        }
        catch (error) {
            degradeToFallback(error);
            return fallbackCollection(this.name).insertOne(doc);
        }
    }
    async findOne(query = {}) {
        if (!isLiveMongo || !mongoDbInstance)
            return fallbackCollection(this.name).findOne(query);
        try {
            return await mongoDbInstance.collection(this.name).findOne(query);
        }
        catch (error) {
            degradeToFallback(error);
            return fallbackCollection(this.name).findOne(query);
        }
    }
    async updateOne(query, update, options = {}) {
        if (!isLiveMongo || !mongoDbInstance) {
            return fallbackCollection(this.name).updateOne(query, update, options);
        }
        try {
            return await mongoDbInstance.collection(this.name).updateOne(query, update, options);
        }
        catch (error) {
            degradeToFallback(error);
            return fallbackCollection(this.name).updateOne(query, update, options);
        }
    }
    async deleteOne(query = {}) {
        if (!isLiveMongo || !mongoDbInstance)
            return fallbackCollection(this.name).deleteOne(query);
        try {
            return await mongoDbInstance.collection(this.name).deleteOne(query);
        }
        catch (error) {
            degradeToFallback(error);
            return fallbackCollection(this.name).deleteOne(query);
        }
    }
    find(query = {}) {
        return new LiveCursorFacade(this.name, query);
    }
}
class LiveCursorFacade {
    name;
    query;
    sortSpec = null;
    limitCount = 0;
    constructor(name, query) {
        this.name = name;
        this.query = query;
    }
    sort(spec) {
        this.sortSpec = spec;
        return this;
    }
    limit(n) {
        this.limitCount = Math.max(0, Number(n) || 0);
        return this;
    }
    async toArray() {
        if (!isLiveMongo || !mongoDbInstance) {
            return this.fallbackCursor().toArray();
        }
        try {
            let cursor = mongoDbInstance.collection(this.name).find(this.query);
            if (this.sortSpec)
                cursor = cursor.sort(this.sortSpec);
            if (this.limitCount > 0)
                cursor = cursor.limit(this.limitCount);
            return await cursor.toArray();
        }
        catch (error) {
            degradeToFallback(error);
            return this.fallbackCursor().toArray();
        }
    }
    fallbackCursor() {
        let cursor = fallbackCollection(this.name).find(this.query);
        if (this.sortSpec)
            cursor = cursor.sort(this.sortSpec);
        if (this.limitCount > 0)
            cursor = cursor.limit(this.limitCount);
        return cursor;
    }
}
export function isMongoLive() {
    return isLiveMongo;
}
export function getMongoCollection(name) {
    if (isLiveMongo && mongoDbInstance) {
        return new LiveCollectionFacade(name);
    }
    return fallbackCollection(name);
}
