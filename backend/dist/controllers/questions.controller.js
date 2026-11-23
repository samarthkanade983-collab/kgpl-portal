import { pool } from '../config/db.js';
import { getMongoCollection } from '../config/mongodb.js';
async function listQuestions(req, res, forLeader) {
    const userId = req.user.id;
    try {
        const [questions] = await pool.query(`SELECT q.id, q.comments AS question, q.created_at, q.from_user_id, q.to_user_id,
              intern.name AS intern_name, leader.name AS team_leader_name
       FROM feedback q
       JOIN users intern ON intern.id = q.from_user_id AND intern.role = 'intern'
       LEFT JOIN users leader ON leader.id = q.to_user_id
       WHERE q.context_type = 'question' AND q.${forLeader ? 'to_user_id' : 'from_user_id'} = ?
         AND intern.deleted_at IS NULL
       ORDER BY q.created_at DESC, q.id DESC`, [userId]);
        const cursor = await getMongoCollection('question_replies').find(forLeader ? { teamLeaderId: userId } : { internId: userId });
        const replies = await cursor.toArray();
        const grouped = new Map();
        for (const reply of replies) {
            const bucket = grouped.get(reply.questionId) || [];
            bucket.push(reply);
            grouped.set(reply.questionId, bucket);
        }
        res.json({
            questions: questions.map((q) => ({
                id: q.id,
                question: q.question,
                created_at: q.created_at,
                intern_name: q.intern_name,
                team_leader_name: q.team_leader_name,
                replies: (grouped.get(Number(q.id)) || [])
                    .filter((r) => r.internId === Number(q.from_user_id) && r.teamLeaderId === Number(q.to_user_id))
                    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
                    .map((r) => ({ id: String(r._id), reply: r.reply, created_at: r.createdAt })),
            })),
        });
    }
    catch (error) {
        console.error('List questions error:', error);
        res.status(500).json({ error: 'Could not load questions. Please try again.' });
    }
}
export async function getTeamLeaderQuestions(req, res) {
    await listQuestions(req, res, true);
}
export async function getInternQuestions(req, res) {
    await listQuestions(req, res, false);
}
export async function replyToQuestion(req, res) {
    const id = String(req.params.id);
    const questionId = Number(id);
    const reply = typeof req.body?.reply === 'string' ? req.body.reply.trim() : '';
    if (!/^\d+$/.test(id) || !Number.isSafeInteger(questionId) || questionId <= 0) {
        res.status(400).json({ error: 'Invalid question.' });
        return;
    }
    if (!reply || reply.length > 4000) {
        res.status(400).json({ error: 'Enter a reply between 1 and 4000 characters.' });
        return;
    }
    const teamLeaderId = req.user.id;
    try {
        const [questions] = await pool.query(`SELECT q.id, q.from_user_id
       FROM feedback q
       JOIN users intern ON intern.id = q.from_user_id AND intern.role = 'intern'
       WHERE q.id = ? AND q.to_user_id = ? AND q.context_type = 'question'
         AND intern.deleted_at IS NULL`, [questionId, teamLeaderId]);
        if (!questions.length) {
            res.status(404).json({ error: 'Question not found.' });
            return;
        }
        const createdAt = new Date().toISOString();
        const result = await getMongoCollection('question_replies').insertOne({
            questionId,
            teamLeaderId,
            internId: Number(questions[0].from_user_id),
            reply,
            createdAt,
        });
        res.status(201).json({
            message: 'Reply sent',
            reply: { id: String(result.insertedId), reply, created_at: createdAt },
        });
    }
    catch (error) {
        console.error('Reply to question error:', error);
        res.status(500).json({ error: 'Could not send your reply. Please try again.' });
    }
}
