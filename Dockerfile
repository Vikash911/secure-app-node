# Build stage
FROM node:20-alpine AS builder
WORKDIR /app


COPY package*.json ./
RUN npm ci --only=production


FROM node:20-alpine


RUN addgroup -S appgroup && adduser -S appuser -G appgroup


WORKDIR /app


COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
COPY src ./src


RUN chown -R appuser:appgroup /app


USER appuser


EXPOSE 3000


CMD ["npm", "start"]