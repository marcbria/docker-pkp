# Docker for PKP

A docker image generator for PKP tools (aka. OJS, OMP, OPS).

This is a proof of concept to test ideas to refactor docker-ojs project.

New approach includes:

- [x] Able to generate images for different PKP tools.
- [x] Multi-stage approach.
- [x] Debian based images.
- [x] Building from tarball.

# ToDo
- [ ] gitHub Actions to build images based on commits.
- [ ] Dockerfile and docker-compose created from templates.
- [ ] gitHub Actions to autopush to DockerHub.
- [ ] Move from debian to debian-slim.
- [ ] Add and test "OPS" images.
- [ ] Add docker-ojs feature requests (see issues).

# Howto

    $ git clone https://github.com/marcbria/docker-pkp.git
    $ vim .env
    $ docker-compose build --build-arg BUILD_PKP_TOOL=omp --build-arg BUILD_LABEL=$(date "+%Y%m%d-%H%M%S") --no-cache
    $ docker-compose up -d

Done.

Visit your new site at https://localhost:8089 and install with parameters found in .env

