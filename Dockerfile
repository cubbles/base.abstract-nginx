FROM cubbles/base.abstract-node:0.2.0

MAINTAINER Hd Böhlau hans-dieter.boehlau@incowia.com

######################################################
# Provide the jessie-backports repo to allow upgrading openssl from 1.0.1 to 1.0.2
# ====================================================
# @see https://www.nginx.com/blog/supporting-http2-google-chrome-users/
# @see http://serverfault.com/a/791953/339942 (debian-jessie-nginx-with-openssl-1-0-2...)
# @see https://packages.debian.org/jessie-backports/openssl
RUN echo "deb http://ftp.debian.org/debian jessie-backports main" >> /etc/apt/sources.list \
    &&set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends openssl

#############################
# nginx: get sources
# ==================

# Please modify if it's neccessary to use another version
# https://nginx.org/en/CHANGES
ENV NGINX_VERSION 1.11.3
ENV NGINX_DEV_KIT 0.2.19
ENV VER_LUAJIT 2.0.4
ENV LUAJIT_LIB /usr/local/lib
ENV LUAJIT_INC /usr/local/include/luajit-2.0
ENV NGINX_LUA_MODULE 0.10.6
ENV nginxHome /usr/local/nginx
ENV nginxConf /etc/nginx/nginx.conf


# Packages needed to actually build nginx
    # build-essential = basic build tools, eg. 'gcc' and 'make'
    # curl (from parent image) = tool to download the nginx tarball
    # ca-certificates (from parent image) = needed to download additional modules (shipped version is to old)
    # libpcre3-dev = library needed to build the rewrite module of nginx
    # libssl-dev = library needed to build ssl/https support in nginx
    # libncurses-dev, libreadline-dev = needed for LUA module
ENV buildDeps='build-essential libpcre3-dev libncurses-dev libreadline-dev'
ENV buildDepsBackports='libssl-dev'

# prepare the system
RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends ${buildDeps} \
    && apt-get install -y --no-install-recommends -t jessie-backports ${buildDepsBackports} \
    && groupadd -r nginx && useradd -d ${nginxHome} -s /bin/false -g nginx nginx

# get the packages
RUN set -x \
  && curl -SLO "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
  && curl -SLO "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz.asc" \
# key which has been used for signing the package may vary from version to version
# list of all possible keys can be found here: http://nginx.org/en/pgp_keys.html
# Andrew Alexeev's PGP public key
  && curl -SLO "http://nginx.org/keys/aalexeev.key" \
# Igor Sysoev's PGP public key
  && curl -SLO "http://nginx.org/keys/is.key" \
# Maxim Dounin's PGP public key
  && curl -SLO "http://nginx.org/keys/mdounin.key" \
# Maxim Konovalov's PGP public key
  && curl -SLO "http://nginx.org/keys/maxim.key" \
# Sergey Budnevitch's PGP public key
  && curl -SLO "http://nginx.org/keys/sb.key" \
# Gleb Smirnoff's PGP public key
  && curl -SLO "http://nginx.org/keys/glebius.key" \
# nginx public key {used for signing packages and repositories}
  && curl -SLO "http://nginx.org/keys/nginx_signing.key" \
# ngx_devel_kit {NDK} module
  && curl -SLO "https://github.com/simpl/ngx_devel_kit/archive/v${NGINX_DEV_KIT}.tar.gz" \
# ngx_lua module
  && curl -SLO "http://luajit.org/download/LuaJIT-${VER_LUAJIT}.tar.gz" \
  && curl -SLO "https://github.com/openresty/lua-nginx-module/archive/v${NGINX_LUA_MODULE}.tar.gz"

# verify the packages
RUN set -x \
  && gpg --import *.key \
  && gpg --verify nginx-${NGINX_VERSION}.tar.gz.asc

##############################
# lua: get sources and install
# ============================

ENV LUA_LIB /usr/local/lib
ENV LUA_INC /usr/local/include

# extract archives
RUN set -x \
  && tar xfz v${NGINX_DEV_KIT}.tar.gz -C /usr/local/src \
  && tar xfz v${NGINX_LUA_MODULE}.tar.gz -C /usr/local/src \
  && tar xfz LuaJIT-${VER_LUAJIT}.tar.gz -C /usr/local/src \
  && tar xfz nginx-${NGINX_VERSION}.tar.gz -C /usr/local/src

# compile and install LuaJIT
WORKDIR /usr/local/src/LuaJIT-${VER_LUAJIT}
RUN make && make install

###############################
# nginx: configure and compile
# =============================

RUN set -x \
    && cd /usr/local/src/nginx-${NGINX_VERSION} \
    && ./configure \
        --prefix=${nginxHome} \
        --conf-path=${nginxConf} \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-ld-opt="-Wl,-rpath,${LUAJIT_LIB}" \
        --add-module=/usr/local/src/ngx_devel_kit-${NGINX_DEV_KIT} \
        --add-module=/usr/local/src/lua-nginx-module-${NGINX_LUA_MODULE} \
    && make -j2 && make install

# load modules: lua-cjson
ENV LUA_CJSON lua-cjson-2.1.0
RUN curl -SLO "http://www.kyne.com.au/%7Emark/software/download/${LUA_CJSON}.tar.gz" && \
    tar xzvf ${LUA_CJSON}.tar.gz && \
    cd ${LUA_CJSON} && \
    make LUA_INCLUDE_DIR=$LUAJIT_INC && \
    make install

# cleanup
RUN set -x \
  && apt-get -y purge $buildDeps && apt-get autoremove -y \
# autoremove is a bit too ambitious, so we need to reinstall some necessary libs
  && apt-get install -y libpcre3  \
  && apt-get install -y --no-install-recommends -t jessie-backports libssl1.0.0 \
  && rm -rf /var/lib/apt/lists/* \
  && rm -rf /usr/local/src/* \
  && rm -f /*.tar.gz

###############################
# docker related configs
# =============================

# forward request logs to Docker log collector
RUN ln -sf /dev/stdout /var/log/nginx-access.log
RUN ln -sf /dev/stderr /var/log/nginx-error.log

EXPOSE 80
WORKDIR $nginxHome
