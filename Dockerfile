FROM spk1/tarantool

RUN apt-get install sudo
RUN sudo apt-get update && sudo apt-get install -y tzdata git bash lua-dev gcc musl-dev make nodejs

RUN luarocks install inspect
RUN luarocks install luasocket
RUN luarocks install dump
RUN luarocks install cron-parser
RUN luarocks install lbase64
RUN luarocks install fun
RUN luarocks install md5
RUN luarocks install luajson
RUN luarocks install busted

ADD . /glial_dist
WORKDIR /glial_dist

RUN tarantoolctl rocks install http
RUN tarantoolctl rocks install dump
RUN tarantoolctl rocks install cron-parser

WORKDIR /glial_dist/tests
