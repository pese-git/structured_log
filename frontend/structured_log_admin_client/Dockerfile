# Serves the admin client's web build, and proxies the API to the server so
# both answer on one origin.
#
# Expects `build/web` to exist already — `deploy/deploy.sh` produces it. There
# is no official Flutter image to build it from inside the Dockerfile, and a
# community one is not something to put in a deployment path unexamined; the
# SDK the repository already pins does the job on the host.
#
#   docker build -f frontend/structured_log_admin_client/Dockerfile .

FROM nginx:1.27-alpine

# A .template (envsubst'd by the base image's own entrypoint), not a plain
# nginx.conf: it resolves its "server" upstream lazily, at request time, via
# whatever DNS the container actually has — see deploy/nginx.conf.template.
COPY deploy/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY frontend/structured_log_admin_client/build/web/ /usr/share/nginx/html/

ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1

EXPOSE 80
