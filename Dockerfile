FROM node:20-alpine

WORKDIR /app

# Copy and install backend packages
COPY backend/package*.json ./backend/
WORKDIR /app/backend
RUN npm install

# Copy application code and pre-compiled Flutter web build
WORKDIR /app
COPY backend ./backend
COPY frontend/build/web ./frontend/build/web

# Compile TypeScript
WORKDIR /app/backend
RUN npm run build

# Ensure uploads directories exist inside the container with proper permissions
RUN mkdir -p /app/backend/uploads/videos /app/backend/uploads/tmp && chmod -R 777 /app/backend/uploads

# Production settings
ENV NODE_ENV=production
ENV PORT=5000
ENV JWT_SECRET=kgpl_portal_production_jwt_secret_key_2026_secured
EXPOSE 5000

CMD ["sh", "-c", "node scripts/init-db.mjs && npm start"]
