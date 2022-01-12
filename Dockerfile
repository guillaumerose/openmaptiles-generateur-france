FROM debian
RUN apt-get update && apt-get install -y osmium-tool
WORKDIR /data
ENTRYPOINT [ "osmium" ]