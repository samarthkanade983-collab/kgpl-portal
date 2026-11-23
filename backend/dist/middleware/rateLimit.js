const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 5;
// Second budget per IP so rotating email addresses cannot bypass the limiter.
const MAX_IP_ATTEMPTS = 50;
const attempts = new Map();
setInterval(() => {
    const now = Date.now();
    for (const [key, window] of attempts) {
        if (window.resetAt <= now)
            attempts.delete(key);
    }
}, WINDOW_MS).unref();
function attemptKeys(req) {
    const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
    const ip = req.ip || 'unknown';
    return { emailKey: `${ip}|${email}`, ipKey: `${ip}|*` };
}
function activeWindow(key, now) {
    const window = attempts.get(key);
    return window && window.resetAt > now ? window : undefined;
}
export function loginRateLimit(req, res, next) {
    const { emailKey, ipKey } = attemptKeys(req);
    const now = Date.now();
    const emailWindow = activeWindow(emailKey, now);
    const ipWindow = activeWindow(ipKey, now);
    const emailBlocked = emailWindow !== undefined && emailWindow.count >= MAX_ATTEMPTS;
    const ipBlocked = ipWindow !== undefined && ipWindow.count >= MAX_IP_ATTEMPTS;
    if (emailBlocked || ipBlocked) {
        const resetAt = Math.max(emailBlocked ? emailWindow.resetAt : 0, ipBlocked ? ipWindow.resetAt : 0);
        const retryAfterMinutes = Math.max(1, Math.ceil((resetAt - now) / 60000));
        res.status(429).json({
            error: `Too many login attempts. Please try again in ${retryAfterMinutes} minute(s).`,
        });
        return;
    }
    next();
}
export function recordFailedLogin(req) {
    const { emailKey, ipKey } = attemptKeys(req);
    const now = Date.now();
    for (const key of [emailKey, ipKey]) {
        const window = activeWindow(key, now);
        if (window) {
            window.count += 1;
        }
        else {
            attempts.set(key, { count: 1, resetAt: now + WINDOW_MS });
        }
    }
}
export function clearFailedLogins(req) {
    // Keep the IP-wide counter so a successful sign-in from a shared network
    // cannot wipe out an attacker's budget.
    attempts.delete(attemptKeys(req).emailKey);
}
function createWindowLimiter(options) {
    const counters = new Map();
    const sweep = setInterval(() => {
        const now = Date.now();
        for (const [key, counter] of counters) {
            if (counter.resetAt <= now)
                counters.delete(key);
        }
    }, Math.max(options.windowMs, 60_000));
    sweep.unref();
    return (req, res, next) => {
        const key = options.key ? options.key(req) : req.ip || 'unknown';
        const now = Date.now();
        const counter = counters.get(key);
        if (!counter || counter.resetAt <= now) {
            counters.set(key, { count: 1, resetAt: now + options.windowMs });
            next();
            return;
        }
        counter.count += 1;
        if (counter.count > options.max) {
            const retryAfterSeconds = Math.max(1, Math.ceil((counter.resetAt - now) / 1000));
            res.setHeader('Retry-After', String(retryAfterSeconds));
            res.status(429).json({ error: options.message });
            return;
        }
        next();
    };
}
// Guards the whole API against scripted abuse and enumeration sweeps.
export const apiRateLimit = createWindowLimiter({
    windowMs: 60 * 1000,
    max: 600,
    message: 'Too many requests. Please slow down and try again shortly.',
});
// Self-registration creates intern accounts, so cap how many one network can
// create per hour.
export const registrationRateLimit = createWindowLimiter({
    windowMs: 60 * 60 * 1000,
    max: 10,
    message: 'Too many accounts created from this network. Please try again later.',
});
// AI replies are costly, so allow a smaller per-account budget.
export const aiChatRateLimit = createWindowLimiter({
    windowMs: 10 * 60 * 1000,
    max: 30,
    message: 'Too many assistant messages. Please wait a few minutes before asking again.',
    key: (req) => {
        const user = req.user;
        return user?.id ? `ai-user-${user.id}` : `ai-ip-${req.ip || 'unknown'}`;
    },
});
