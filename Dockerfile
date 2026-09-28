FROM node:20-alpine AS frontend-builder
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install --legacy-peer-deps
COPY frontend/ ./
RUN npm run build

FROM node:20-alpine AS backend-builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev --legacy-peer-deps

FROM nginx:alpine AS runtime
RUN apk add --no-cache nodejs npm && mkdir -p /run/nginx /etc/nginx/http.d /etc/nginx/conf.d

WORKDIR /usr/src/app

COPY --from=backend-builder /app/node_modules ./node_modules
COPY backend/ ./backend
COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html

RUN printf 'server {\n\
    listen 80;\n\
    server_name _;\n\
    client_max_body_size 20m;\n\
\n\
    location /api/ {\n\
        proxy_pass http://127.0.0.1:5000;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Host $host;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto $scheme;\n\
    }\n\
\n\
    location / {\n\
        root /usr/share/nginx/html;\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
}\n' > /etc/nginx/http.d/default.conf

ENV NODE_ENV=production
ENV PORT=5000

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/ || exit 1

CMD ["sh", "-c", "mkdir -p /run/nginx && (node /usr/src/app/backend/server.js &) && nginx -g 'daemon off;'"]