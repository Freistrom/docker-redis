# docker-redis

## Build Docker Image

`
$ git clone https://github.com/Freistrom/docker-redis.git
$ cd docker-redis
$ sudo docker build -t freistrom/redis:5.0-rc4 .
$ sudo docker tag freistrom/redis:5.0-rc4 REGISTRY_HOST:5000/freistrom/redis:5.0-rc4
$ sudo docker push REGISTRY_HOST:5000/freistrom/redis:5.0-rc4
`