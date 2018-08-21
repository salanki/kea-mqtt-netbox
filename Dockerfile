FROM alpine:latest
LABEL maintainer "Peter Salanki <peter@salanki.st>"

RUN apk --no-cache add \
        bash \
        mosquitto-clients \
        curl \
        findutils \
        coreutils \
        jq
RUN mkdir -p /app

ADD ./napi.sh /app
ADD ./listen.sh /app

WORKDIR /app

CMD ./listen.sh
