# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk

LABEL version="6.0.1"

RUN apt-get update && apt-get install -y curl unzip jq gosu && \
    rm -rf /var/lib/apt/lists/* && \
    adduser --uid 99 --gid 100 --home /data --disabled-password minecraft

COPY entrypoint.sh /entrypoint.sh
COPY launch.sh /launch.sh
RUN chmod +x /entrypoint.sh /launch.sh

VOLUME /data
WORKDIR /data

EXPOSE 25565/tcp

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/launch.sh"]

