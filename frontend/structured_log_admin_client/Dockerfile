# Serves the admin client's web build — nothing else. This image has no
# idea the API even exists: no hostname, no port, no proxy rule. Whoever
# puts it behind a single origin (a dedicated reverse proxy for Docker
# Compose, an Ingress for Kubernetes — see deploy/) owns that; baking that
# knowledge in here instead is what crash-looped this exact container the
# last time the topology around it changed (a static-file server has no
# business needing its sibling's Service name just to start).
#
# Expects `build/web` to exist already — `deploy/deploy.sh` produces it. There
# is no official Flutter image to build it from inside the Dockerfile, and a
# community one is not something to put in a deployment path unexamined; the
# SDK the repository already pins does the job on the host.
#
#   docker build -f frontend/structured_log_admin_client/Dockerfile .

FROM nginx:1.27-alpine

COPY frontend/structured_log_admin_client/nginx.conf /etc/nginx/conf.d/default.conf
COPY frontend/structured_log_admin_client/build/web/ /usr/share/nginx/html/

EXPOSE 80
