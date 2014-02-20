# Towboat

Manages [Docker](http://www.docker.io) with configuration files.

A bash script that starts/manages Docker containers based on a set of config files matching `*.cfg` in, by default  `/etc/towboat`.


## Features

- Start containers if necessary
- Data-containers support. These do not have to be running.
- Dependency checking:
  - Required data-volume containers are auto-created if they don't exist.
  - Containers a container links with are started before the container itself is stated.
  - Rudimentary circular dependency checking (not perfect/super well tested, but works for simple situations)
- Detect configuration changes compared to the previous `towboat` run, and remove and restart the container with the new configuration if AUTO_REMOVE is enabled.
- Rudimentary [pipework](support https://github.com/jpetazzo/pipework/)
- Use ipv4 addresses from specific interfaces in port mappings. IP changes are detected as a configuration change.


## Overriding file/path locations

You can override paths of a few things by setting environment variables

An attempt is made to locate the `pipework` and `docker` executables in the path. When this fails, a fallback location is attempted.

 - `TOWBOAT_CONFIGPATH`: Override where `towboat` searches for the config files. The default is `/etc/towboat`.
 - `PIPEWORK`: the location of the `pipework` script. Only required when you have configurations where `PW_ENABLED` is set to true. Fallback: `/usr/bin/pipework`.
 - `DOCKER`: the location of the `docker` executable. Fallback: `/usr/bin/docker`.

## Config file format.

TODO. See `container.cfg.sample` - all options should be described.

Notes:
- Since configuration files are just bash scripts setting environment variables, you can add some intelligence. This however can lead to unexpected results. For the AUTO_REMOVE feature, which removes and restarts a container when a configuration file has changed, `towboat` currently checks the MD5 sum of the config file (and IP changes). If you dynamically set configuration options using external data sources, detections will not be detected.


## Examples

TODO: See the tests/ folder

