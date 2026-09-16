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

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY frontend/structured_log_admin_client/build/web/ /usr/share/nginx/html/

EXPOSE 80
