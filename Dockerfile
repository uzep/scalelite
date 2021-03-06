FROM alpine:3.11 AS alpine

### nginx proxy with recordings: step 1
FROM ubuntu:16.04 AS bbb-playback
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y language-pack-en \
    && update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8
RUN apt-get update \
    && apt-get install -y software-properties-common curl net-tools
RUN curl -sL https://ubuntu.bigbluebutton.org/repo/bigbluebutton.asc | apt-key add - \
    && echo "deb http://ubuntu.bigbluebutton.org/xenial-220/ bigbluebutton-xenial main" >/etc/apt/sources.list.d/bigbluebutton.list
RUN useradd --system --user-group --home-dir /var/bigbluebutton bigbluebutton
RUN touch /.dockerenv
RUN apt-get update \
    && apt-get download bbb-playback-notes bbb-playback-podcast bbb-playback-presentation bbb-playback-screenshare \
    && dpkg -i --force-depends *.deb

### nginx proxy with recordings: step 2
FROM alpine AS nginx
RUN apk add --no-cache nginx tini gettext \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
RUN rm /etc/nginx/conf.d/default.conf
COPY --from=bbb-playback /etc/bigbluebutton/nginx /etc/bigbluebutton/nginx/
COPY --from=bbb-playback /var/bigbluebutton/playback /var/bigbluebutton/playback/
COPY nginx /etc/nginx/
EXPOSE 80
EXPOSE 443
ENV NGINX_HOSTNAME=localhost
CMD [ "/etc/nginx/start", "-g", "daemon off;" ]


### recordings with support for bbb23: step 1
FROM ubuntu:18.04 AS bbb23-playback
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y language-pack-en \
    && update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8
RUN apt-get update \
    && apt-get install -y software-properties-common curl net-tools nginx
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys CC86BB64 \
    && add-apt-repository ppa:rmescandon/yq
RUN apt-get update \
    && apt-get install -y yq
RUN curl -sL https://ubuntu.bigbluebutton.org/repo/bigbluebutton.asc | apt-key add - \
    && echo "deb https://ubuntu.bigbluebutton.org/bionic-23-dev bigbluebutton-bionic main" >/etc/apt/sources.list.d/bigbluebutton.list
RUN useradd --system --user-group --home-dir /var/bigbluebutton bigbluebutton
RUN touch /.dockerenv
RUN apt-get update \
    && apt-get download bbb-playback bbb-playback-presentation \
    && dpkg -i --force-depends *.deb

### recordings: step 2
FROM alpine AS recordings
RUN apk add --no-cache nginx tini gettext \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
RUN rm /etc/nginx/conf.d/default.conf
COPY --from=bbb23-playback /etc/bigbluebutton/nginx /etc/bigbluebutton/nginx/
COPY --from=bbb23-playback /var/bigbluebutton/playback /var/bigbluebutton/playback/
COPY nginx /etc/nginx/
EXPOSE 80
ENV NGINX_HOSTNAME=localhost
ENV NGINX_RECORDINGS_ONLY=true
CMD [ "/etc/nginx/start", "-g", "daemon off;" ]


### scalelite: step 1
FROM alpine AS base
RUN apk add --no-cache \
    libpq \
    libxml2 \
    libxslt \
    ruby \
    ruby-bigdecimal \
    ruby-bundler \
    ruby-json \
    tini \
    tzdata \
    && addgroup scalelite \
    && adduser -h /srv/scalelite -G scalelite -D scalelite
WORKDIR /srv/scalelite

### scalelite: step 2
FROM base as builder
RUN apk add --no-cache \
    build-base \
    libxml2-dev \
    libxslt-dev \
    pkgconf \
    postgresql-dev \
    ruby-dev \
    && ( echo 'install: --no-document' ; echo 'update: --no-document' ) >>/etc/gemrc
USER scalelite:scalelite
COPY --chown=scalelite:scalelite Gemfile* ./
RUN bundle config build.nokogiri --use-system-libraries \
    && bundle install --deployment --without development:test -j4 \
    && rm -rf vendor/bundle/ruby/*/cache \
    && find vendor/bundle/ruby/*/gems/ \( -name '*.c' -o -name '*.o' \) -delete
COPY --chown=scalelite:scalelite . ./
RUN rm -rf nginx

### scalelite: step 3
FROM base AS application
USER scalelite:scalelite
ENV RAILS_ENV=production RAILS_LOG_TO_STDOUT=1
COPY --from=builder --chown=scalelite:scalelite /srv/scalelite ./

### scalelite: step 4
ARG BUILD_NUMBER
ENV BUILD_NUMBER=${BUILD_NUMBER}

### scalelite: step 4.1, recording-importer
FROM application AS recording-importer
ENV RECORDING_IMPORT_POLL=true
CMD [ "bin/start-recording-importer" ]

### scalelite: step 4.2, poller
FROM application AS poller
CMD [ "bin/start-poller" ]

### scalelite: step 4.3, api
FROM application AS api
EXPOSE 3000
CMD [ "bin/start" ]
