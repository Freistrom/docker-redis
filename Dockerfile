FROM debian:stretch-slim

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r redis && useradd -r -g redis redis

# grab gosu for easy step-down from root
# https://github.com/tianon/gosu/releases
ENV GOSU_VERSION 1.10
RUN set -ex; \
	\
	fetchDeps=" \
		ca-certificates \
		dirmngr \
		gnupg2 \
		wget \
	"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $fetchDeps; \
	rm -rf /var/lib/apt/lists/*; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg2 --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg2 --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	gpgconf --kill all; \
	rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	chmod +x /usr/local/bin/gosu; \
	gosu nobody true; \
	\
	apt-get purge -y --auto-remove $fetchDeps

ENV REDIS_VERSION 5.0-rc5
ENV REDIS_DOWNLOAD_URL https://github.com/antirez/redis/archive/5.0-rc5.tar.gz
ENV REDIS_DOWNLOAD_SHA d070c8a3514e40da5cef9ec26dfd594df0468c203c36398ef2d359a32502b548
ENV REDIS_GRAPH_VERSION 1.0.0-rc2
ENV REDIS_GRAPH_DOWNLOAD_URL https://github.com/RedisLabsModules/redis-graph/archive/v1.0.0-rc2.tar.gz 
ENV REDIS_ML_VERSION 0.99.1
ENV REDIS_ML_DOWNLOAD_URL https://github.com/RedisLabsModules/redis-ml/archive/v0.99.1.tar.gz

# for redis-sentinel see: http://redis.io/topics/sentinel
RUN set -ex; \
	\
	buildDeps=' \
		ca-certificates \
		wget \
		\
		gcc \
		libc6-dev \
		make \
		build-essential \
		cmake \
		libatlas-base-dev \
	'; \
	apt-get update; \
	apt-get install -y $buildDeps --no-install-recommends; \
	rm -rf /var/lib/apt/lists/*; \
	mkdir /var/lib/redis; \
	\
	wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
	echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
	mkdir -p /usr/src/redis; \
	tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
	rm redis.tar.gz; \
	\
# disable Redis protected mode [1] as it is unnecessary in context of Docker
# (ports are not automatically exposed when running inside Docker, but rather explicitly by specifying -p / -P)
# [1]: https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
	sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
# for future reference, we modify this directly in the source instead of just supplying a default configuration flag because apparently "if you specify any argument to redis-server, [it assumes] you are going to specify everything"
# see also https://github.com/docker-library/redis/issues/4#issuecomment-50780840
# (more exactly, this makes sure the default behavior of "save on SIGTERM" stays functional by default)
	\
	make -C /usr/src/redis -j "$(nproc)"; \
	make -C /usr/src/redis install; \
	\
	rm -r /usr/src/redis; \
	\
	wget -O redis-graph.tar.gz "$REDIS_GRAPH_DOWNLOAD_URL"; \
	mkdir -p /usr/src/redis-graph; \
	tar -xzf redis-graph.tar.gz -C /usr/src/redis-graph --strip-components=1; \
	rm redis-graph.tar.gz; \
	\
	make -C /usr/src/redis-graph -j "$(nproc)"; \
	cp /usr/src/redis-graph/src/redisgraph.so /var/lib/redis/; \
	\
	rm -r /usr/src/redis-graph; \
	\
	wget -O redis-ml.tar.gz "$REDIS_ML_DOWNLOAD_URL"; \
	mkdir -p /usr/src/redis-ml; \
	tar -xzf redis-ml.tar.gz -C /usr/src/redis-ml --strip-components=1; \
	rm redis-ml.tar.gz; \
	\
	make -C /usr/src/redis-ml/src -j "$(nproc)"; \
	cp /usr/src/redis-ml/src/redis-ml.so /var/lib/redis/; \
	\
	rm -r /usr/src/redis-ml; \
	\
	apt-get purge -y --auto-remove $buildDeps

RUN mkdir /data && chown redis:redis /data
VOLUME /data
WORKDIR /data

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 6379
CMD ["redis-server"]
