# A static website (HTML, CSS, JavaScript) served by nginx as an unprivileged user on port 8080. The repository's
# files are the site: the first stage leaves out the build's own files. Read-only at run time: nginx writes to /tmp.
FROM busybox:1.36 AS site
COPY . /site
RUN cd /site && rm -rf Dockerfile nginx.conf .dockerignore .github test-app ./*.md
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=site /site/ /usr/share/nginx/html/
EXPOSE 8080
