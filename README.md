# Towboat

## WARNING

*Not recommended to use in production.* Currently, things change rather quickly and are not always backwards compatible. The AUTO_REMOVE feature combined with a change in the way configuration changes are detected now (it has changed) can have unexpected consequences.

You have been warned.

## What is it?

Manages [Docker](http://www.docker.io) with configuration files.

A bash script that starts/manages Docker containers based on a set of config files matching `*.cfg` in, by default  `/etc/towboat`.


## Features

- Start containers if necessary
- Data-containers support. These do not have to be running.
- Dependency checking:
  - Required data-volume containers are auto-created if they don't exist.
  - The linked containers are started before the container itself is started.
  - Rudimentary circular dependency checking (not perfect/super well tested, but works for simple situations)
- Detect configuration changes compared to the previous `towboat` run, and remove and restart the container with the new configuration if AUTO_REMOVE is enabled.
- Rudimentary [pipework](https://github.com/jpetazzo/pipework/) support
- Use ipv4 addresses from specific interfaces in port mappings. IP changes are detected as a configuration change. Use the "@<interfacename>" in the PORTS setting instead of the host IP address.

## Running towboat

### Starting containers
Executing towboat is as simple as running:
```
towboat start
```
This starts all containers for which it finds a valid `*.cfg` file in the `TOWBOAT_CONFIGPATH` directory.

If you want to test only a specific docker image (check if it can resolve it's dependencies for example), you do that like this:
```
towboat start container-to-test
```
### Stopping containers

```
towboat stop
```
Stops all containers which are configured.


Or to stop only container `container-to-stop`:
```
towboat stop container-to-stop
```
Stops a specific container.
** dependencies are NOT checked when stopping containers! **

### Restarting

As expected, it works like this:
```
towboat restart
```
or to only restart `container-to-restart`:
```
towboat restart container-to-restart
```

### Requesting the status

```
towboat status
```
Gives you a status overview of all containers.

```
towboat status container-to-check
```
Gives you the status of only the container with the name `container-to-check`


## Overriding file/path locations

You can override paths of a few things by setting environment variables

An attempt is made to locate the `pipework` and `docker` executables in the path. When this fails, a fallback location is attempted.

| Environment variable | Description | Default/Fallback |
|---------------|---------------|---------------|
| `TOWBOAT_CONFIGPATH` | Override where `towboat` searches for the config files. | The default is `/etc/towboat` |
| `PIPEWORK` | The location of the `pipework` script. Only required when you have configurations where `PW_ENABLED` is set to true. | Fallback: `/usr/bin/pipework` |
| `DOCKER` | The location of the `docker` executable. | Fallback: `/usr/bin/docker` |

## Config file format.

TODO. See `container.cfg.sample` - all options should be described.

Notes:
- ~~Since configuration files are just bash scripts setting environment variables, you can add some intelligence. This however can lead to unexpected results. For the AUTO_REMOVE feature, which removes and restarts a container when a configuration file has changed, `towboat` currently checks the MD5 sum of the config file (and IP changes). If you dynamically set configuration options using external data sources, changes will not be detected.~~ *not true anymore, the new way of detecting changes calculates an MD5 on all resulting environment variables, not on the configuration file itself*


## Examples

TODO: See the tests/ folder

