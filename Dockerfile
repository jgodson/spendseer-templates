FROM ruby:3.2-alpine AS build

WORKDIR /app
COPY schemas ./schemas
COPY scripts ./scripts
COPY site ./site
COPY templates ./templates

ARG SITE_BASE_URL=https://templates.spendseer.com
ARG RAW_TEMPLATE_BASE_URL=https://templates.spendseer.com
ARG APP_INSTALL_BASE_URL=https://app.spendseer.com
ENV SITE_BASE_URL=${SITE_BASE_URL}
ENV RAW_TEMPLATE_BASE_URL=${RAW_TEMPLATE_BASE_URL}
ENV APP_INSTALL_BASE_URL=${APP_INSTALL_BASE_URL}

RUN ruby scripts/build.rb

FROM nginx:alpine

COPY --from=build /app/dist/site /usr/share/nginx/html

RUN sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf && \
    sed -i '/user  nginx;/d' /etc/nginx/nginx.conf && \
    chown -R 10001:10001 /var/cache/nginx /var/log/nginx /etc/nginx/conf.d /usr/share/nginx/html && \
    touch /var/run/nginx.pid && \
    chown 10001:10001 /var/run/nginx.pid

USER 10001

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
