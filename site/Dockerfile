# Build context is the repository root, not this directory:
# scripts/migrate_docs.py generates site content from ../docs/ and
# ../emb/<package>/README(.ru).md, both relative to itself — see
# site/README.md.
#
#   docker build -f site/Dockerfile .

FROM node:22-alpine AS build

# python3 for scripts/migrate_docs.py, which `npm run build`'s `prebuild`
# hook runs automatically (see site/package.json).
RUN apk add --no-cache python3

WORKDIR /workspace

COPY docs/ docs/
COPY emb/ emb/

# Dependencies first, so a docs/ or source change doesn't invalidate the
# npm install layer.
COPY site/package.json site/package-lock.json site/
WORKDIR /workspace/site
RUN npm ci

COPY site/ .
RUN npm run build

FROM nginx:1.27-alpine

COPY site/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /workspace/site/dist/ /usr/share/nginx/html/

EXPOSE 80
