# ==============================================================================
# Dockerfile - oidc-dev-server
# マルチステージビルドでビルド依存とランタイムを分離し、最終イメージを最小化する。
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: deps - 依存関係のインストール(ビルド用: devDependencies含む)
# ------------------------------------------------------------------------------
FROM node:22-alpine AS deps
# Prisma engineの実行にopensslが必要(alpine base)
RUN apk add --no-cache openssl libc6-compat
WORKDIR /app
COPY package.json package-lock.json* ./
COPY prisma ./prisma
RUN npm ci

# ------------------------------------------------------------------------------
# Stage 2: build - TypeScriptビルド + Prisma Client生成
# ------------------------------------------------------------------------------
FROM node:22-alpine AS build
RUN apk add --no-cache openssl libc6-compat
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx prisma generate --schema=prisma/schema.prisma
RUN npm run build

# ------------------------------------------------------------------------------
# Stage 3: prod-deps - 本番用依存関係のみ(devDependencies除外)
# ------------------------------------------------------------------------------
FROM node:22-alpine AS prod-deps
RUN apk add --no-cache openssl libc6-compat
WORKDIR /app
COPY package.json package-lock.json* ./
COPY prisma ./prisma
RUN npm ci --omit=dev && npx prisma generate --schema=prisma/schema.prisma

# ------------------------------------------------------------------------------
# Stage 4: runtime - 最小構成の実行イメージ
# ------------------------------------------------------------------------------
FROM node:22-alpine AS runtime

RUN apk add --no-cache openssl dumb-init \
    && addgroup -g 1001 -S appgroup \
    && adduser -u 1001 -S appuser -G appgroup

WORKDIR /app
ENV NODE_ENV=production

COPY --from=prod-deps --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=prod-deps --chown=appuser:appgroup /app/prisma ./prisma
COPY --from=build --chown=appuser:appgroup /app/dist ./dist
COPY --from=build --chown=appuser:appgroup /app/package.json ./package.json

# SQLiteファイル/JWKS用のマウントポイント(K8s PVCと対応)
RUN mkdir -p /data /secrets/jwks && chown -R appuser:appgroup /data /secrets/jwks

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/.well-known/openid-configuration').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# dumb-initでシグナルを正しくハンドリングし、ゾンビプロセスを防ぐ
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
