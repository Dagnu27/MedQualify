FROM node:24-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .
RUN npm run build --prefix frontend

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000
VOLUME ["/app/backend/server/data"]

CMD ["node", "backend/server/index.js"]
