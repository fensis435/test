FROM node:16-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY app.js ./
EXPOSE 8000
CMD ["node","app.js"]

