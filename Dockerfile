# Default context
ARG BUILD_PKP_TOOL=ojs              \
    BUILD_PKP_VERSION=3.3.0-21      \
    BUILD_PKP_APP_PATH=/app         \
    BUILD_WEB_SERVER=php:8.1-apache \
    BUILD_OS=alpine:3.18            \
    BUILD_LABEL=notset

# GET PKP CODE
FROM ${BUILD_OS} AS pkp_code

# Context
ARG BUILD_PKP_TOOL                  \
    BUILD_PKP_VERSION               \
    BUILD_PKP_APP_PATH

RUN apk add --update --no-cache curl tar \
    && mkdir "${BUILD_PKP_APP_PATH}" 

WORKDIR "/${BUILD_PKP_APP_PATH}"

# ADD is supossed to download, extract and remove, but there is an issue with some docker
# versions so, for compatibility, doing it manually: https://github.com/moby/moby/issues/33849 
# ADD "https://pkp.sfu.ca/$BUILD_PKP_TOOL/download/$BUILD_PKP_TOOL-$BUILD_PKP_VERSION.tar.gz" "$BUILD_PKP_APP_PATH"

RUN curl -Ss -O "https://pkp.sfu.ca/${BUILD_PKP_TOOL}/download/${BUILD_PKP_TOOL}-${BUILD_PKP_VERSION}.tar.gz" \
    && tar --strip-components=1 -xvzf "${BUILD_PKP_TOOL}-${BUILD_PKP_VERSION}.tar.gz" -C "${BUILD_PKP_APP_PATH}" > /tmp/untar.lst

RUN echo    "===============================================================" \
    && echo " ---> PKP application:  ${PKP_TOOL}"                             \
    && echo " ---> Version:          ${BUILD_PKP_VERSION}"                    \
    && echo " ---> Web Server:       ${BUILD_WEB_SERVER}"                     \
    && echo " ---> Operating system: ${BUILD_OS}"                             \
    && echo "==============================================================="

# GET & SET THE LAMP
FROM ${BUILD_WEB_SERVER}

# TODO:
# - Move to debian-slim (test php plugins)
# - Concatenate calls to reduce the layers
# - Replace with PKP_variables when possible
# - Remove "vim" in production image
# - Ensure all required packages and php extensions
# - Test with OJS, OMP and OPS.
# - Redirect log output to stdout & FILE.

# Context
ARG BUILD_PKP_TOOL				\
    BUILD_PKP_VERSION				\
    BUILD_PKP_APP_PATH				\
    BUILD_WEB_SERVER				\
    BUILD_LABEL


LABEL maintainer="Public Knowledge Project <marc.bria@uab.es>"
LABEL org.opencontainers.image.vendor="Public Knowledge Project"
LABEL org.opencontainers.image.title="PKP ${BUILD_PKP_TOOL} Web Application"
LABEL org.opencontainers.image.description="Runs a ${BUILD_PKP_TOOL} application over ${BUILD_WEB_SERVER}-${BUILD_OS}."
LABEL build_version="${BUILD_PKP_TOOL}_${BUILD_PKP_VERSION}_${BUILD_LABEL}"

# ARGs only work during building time, so they need to be exported to ENVs:
ENV PKP_TOOL="${BUILD_PKP_TOOL:-ojs}"                       \
    PKP_VERSION="${BUILD_PKP_VERSION:-3.3.0-21}"            \
    SERVERNAME="localhost"                                  \
    WWW_USER="www-data"                                     \
    WWW_PATH_CONF="/etc/apache2/apache2.conf"               \
    WWW_PATH_ROOT="/var/www"                                \
    HTTPS="on"                                              \
    PKP_CLI_INSTALL="0"                                     \
    PKP_DB_HOST="localhost"                                 \
    PKP_DB_USER="${MYSQL_USER:-pkp}"                        \
    PKP_DB_PASSWORD="${MYSQL_PASSWORD:-changeMe}"           \
    PKP_DB_NAME="${MYSQL_DATABASE:-pkp}"                    \
    PKP_WEB_CONF="/etc/apache2/conf-enabled/pkp.conf"       \
    PKP_CONF="config.inc.php"                               \
    PKP_CMD="/usr/local/bin/pkp-start"


# Basic packages (todo: Remove what don't need to be installed)
ENV PACKAGES="cron rsyslog apache2-utils ca-certificates vim"

# DEV packages are not required in production images.
ENV PACKAGES_DEV="zlib1g-dev libmcrypt-dev libonig-dev libpng-dev libxslt-dev libpng-dev libfreetype6-dev libjpeg62-turbo-dev libzip-dev"

# PHP extensions
ENV PHP_EXTENSIONS="gd gettext iconv intl mbstring mysqli pdo_mysql xml xsl zip"

# Extension names as required by docker-php-ext-* helpers. Possible values are:
# bcmath bz2 calendar ctype curl dba dom enchant exif ffi fileinfo filter ftp gd gettext gmp hash iconv imap intl json ldap mbstring mysqli oci8 odbc opcache pcntl pdo pdo_dblib pdo_firebird pdo_mysql pdo_oci pdo_odbc pdo_pgsql pdo_sqlite pgsql phar posix pspell readline reflection session shmop simplexml snmp soap sockets sodium spl standard sysvmsg sysvsem sysvshm tidy tokenizer xml xmlreader xmlwriter xsl zend_test zip


WORKDIR ${WWW_PATH_ROOT}/html

# For Debian:
RUN apt-get update && apt-get install -y ${PACKAGES} ${PACKAGES_DEV}

# By default GD don't include jpeg and freetype support:
RUN docker-php-ext-configure gd --with-freetype --with-jpeg

# Installing PHP extensions:
RUN docker-php-ext-install -j$(nproc) ${PHP_EXTENSIONS}

# Enable installed extensions:
RUN docker-php-ext-enable ${PHP_EXTENSIONS}

# Enable mod_rewrite and mod_ssl
RUN a2enmod rewrite ssl

# Building PKP-TOOL (ie: OJS):

# Get the code
COPY --from=pkp_code "${BUILD_PKP_APP_PATH}" .

# Create directories
RUN mkdir -p /etc/ssl/apache2 "${WWW_PATH_ROOT}/files" /run/apache2

# Make php's etc indpendent of the php versio:
RUN PHP_INI_DIR=$(php --ini | grep "Configuration File (php.ini) Path" | cut -d: -f2 | xargs) 

# Redirect logs to stdout
RUN echo "log_errors = On" >> $PHP_INI_DIR/conf.d/log-errors.ini \
    && echo "error_log = /dev/stderr" >> $PHP_INI_DIR/conf.d/log-errors.ini

# PKP-app config
RUN echo "PKP_CONF: ${PKP_CONF}"
RUN cp -a config.TEMPLATE.inc.php "${WWW_PATH_ROOT}/html/${PKP_CONF}" 
RUN chown -R ${WWW_USER}:${WWW_USER} "${WWW_PATH_ROOT}"
# Prepare freefont for captcha 
#	&& ln -s /usr/share/fonts/TTF/FreeSerif.ttf /usr/share/fonts/FreeSerif.ttf \

# Prepare crontab
RUN echo "0 * * * *   pkp-run-scheduled" | crontab - 
# Prepare httpd.conf
RUN sed -i -e '\#<Directory />#,\#</Directory>#d' ${WWW_PATH_CONF} 
RUN sed -i -e "s/^ServerSignature.*/ServerSignature Off/" ${WWW_PATH_CONF} 
# Clear the image (files to be deleted were in exclude.list but this is not required with multi-build).
RUN rm -rf /tmp/* 
RUN rm -rf /root/.cache/* \
RUN apt-get clean autoclean \
    && apt-get autoremove --yes 

# # Optional: Some folders are not required (as .git .travis.yml test .gitignore .gitmodules ...)
# 	&& find . -name ".git" -exec rm -Rf '{}' \; \
# 	&& find . -name ".travis.yml" -exec rm -Rf '{}' \; \
# 	&& find . -name "test" -exec rm -Rf '{}' \; \
# 	&& find . \( -name .gitignore -o -name .gitmodules -o -name .keepme \) -exec rm -Rf '{}' \;

COPY "templates/pkp/root/" /
COPY "volumes/config/apache.pkp.conf" "${PKP_WEB_CONF}"

#RUN echo "${BUILD_PKP_TOOL}-${BUILD_PKP_VERSION} over $BUILD_WEB_SERVER on $(cat /etc/issue) [build:" $(date "+%Y%m%d-%H%M%S") "]" > "${WWW_PATH_ROOT}/container.version" \
RUN bash -c '\
    . /etc/os-release && \
    echo "${BUILD_PKP_TOOL}-${BUILD_PKP_VERSION} over ${BUILD_WEB_SERVER} on ${ID}-${VERSION_ID} [build: $(date +%Y%m%d-%H%M%S)]" \
    > "${WWW_PATH_ROOT}/container.version"' && \
    rm -f "${BUILD_PKP_TOOL}-${BUILD_PKP_VERSION}.tar.gz" && \
    cat "${WWW_PATH_ROOT}/container.version"

EXPOSE 80 
EXPOSE 443

VOLUME [ "${WWW_PATH_ROOT}/files", "${WWW_PATH_ROOT}/public" ]

# RUN chmod +x "/usr/local/bin/${BUILD_PKP_TOOL}-start"
RUN chmod +x "/usr/local/bin/pkp-start"

RUN echo    "==============================================================="   \
    && echo " ---> PKP application: ${PKP_TOOL}"                                \
    && echo " ---> Version:         ${BUILD_PKP_VERSION}"                       \
    && echo " ---> BUILD ID:        $(cat ${WWW_PATH_ROOT}/container.version)"  \
    && echo " ---> Run:             ${PKP_CMD}"                                 \
    && echo "==============================================================="

CMD "${PKP_CMD}"
