# Towboat

## WARNING

*Not recommended to use in production.*

Currently, things change rather quickly and are not always backwards compatible. Especially the AUTO_REMOVE feature combined with a change in the way configuration changes are detected now (it has changed) can have unexpected consequences.

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
- Use ipv4 addresses from specific interfaces in port mappings. IP changes are detected as a configuration change. Use the `"@<interfacename>"` in the PORTS setting instead of the host IP address.

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
** dependencies are NOT checked when stopping containers! **

```
towboat stop
```
Stops all containers which are configured.


Or to stop only container `container-to-stop`:
```
towboat stop container-to-stop
```
Stops a specific container.

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

## Notes on containers started/managed by Towboat

There are a few specific things that are always applied to containers started by Towboat:

- A containername *has* to be specified in the `NAME` configuration setting, and the the filename *has* to match `<NAME>.cfg` to load correctly.
- The hostname, if not specified with the `CONTAINER_HOSTNAME` configuration setting, will be set to the `NAME` setting.
- An environment variable named `TOWBOAT_CONFIG` with an version + MD5 of the Towboat configuration will be set. This is used to detect configuration changes.
- An environment varuable named `ETHDEVS` will be set with the ethernet devices that should be available. By default this is only `'eth0'`,  but when [pipework](https://github.com/jpetazzo/pipework/) is used, this can become `'eth0 eth1'`, or if networking is disabled, this can be empty.

## Config file format.

| Name | Type | Default Value/Required | Description | Example |
|------|------|------------------------|-------------|---------|
| `NAME` | String | *Required* | The name to give the container. Has to match the filename (`<NAME>.cfg`). |  `NAME=mycontainer` |
| `ENABLED` | Bool (true/false) | `true` | Flag to indicate if this container is enabled | `ENABLED=false` |
| `IMAGE` | String | *Required* | The name of the image this container uses | `IMAGE=ubuntu:12.04` |
| `AUTO_REMOVE` | Bool (true/false) | `false` | Flag to indicate if this container can be killed, removed and re-created when a configuration change is detected. | `AUTO_REMOVE=true` |
| `DATA_CONTAINER` | Bool (true/false) | `false` | Flag to indicate if this container is a data container. This means this container will never be removed automatically, and that this container only has to exist, and not be running to meet dependency requirements. | `DATA_CONTAINER=true` |
| `DOCKER_HOST` | String | *Empty* | Run this container on a specific Docker host. Sets the --host parameter when running a `docker` command. | `DOCKER_HOST="tcp://my.docker:1234"` |
| `DOCKER_PARAM` | String | *Empty* | Extra parameters to pass to the `docker run` command when creating a new container. Note that these parameters **only** apply to `docker run`. See `docker run --help` which commands are available. | `DOCKER_PARAM="--cidfile=/path/to/containerid.txt"` |
| `CONTAINER_HOSTNAME` | String | The `NAME` setting | Overrides the hostname the container is given. | `CONTAINER_HOSTNAME="myhost"` |
| `CONTAINER_PARAM` | String | *Empty* | The parameters passed to the container. Typically this is the command to execute inside the container. | `CONTAINER_PARAM="/usr/bin/supervisord"` |
| `CONTAINER_ENV` | Array | *Empty* | An array of environment variables to set in the container. | `CONTAINER_ENV=( "VAR=value" "VAR2=othervalue")` |
| `NETWORK_DISABLED` | Bool (true/false) | `false` | Flag to disable the network | `NETWORK_DISABLED=true` |
| `PORTS_ALL` | Bool (true/false) | `false` | Flag publish all ports exposed by the image of this container. See the `-P` or `--publish-all` parameter for `docker run` | `PORTS_ALL=true` |
| `PORTS` | Array | *Empty* | Array containing port forwards to the host. It supports the `ip:hostPort:containerPort`, `ip::containerPort` and `hostPort:containerPort` notation the `-p`/`--publish` `docker run` parameter supports, with the addition that the IP can be replaces with an `@interface`, looking up the first IPv4 address configured on that interface, and using that-one. | `PORTS=( "@eth0:80:80" "@eth1:2022:22" )` |
| `VOLUMES` | Array | *Empty* | List of `/host:/container` volumes to mount. | `VOLUMES=( "/host/data1:/data1/" "/host/data2:/data2")` |
| `VOLUMES_FROM` | Array | *Empty* | List of containers to use the exposed volumes from. Used for the dependency checking. | `VOLUMES_FROM=("datacontainer1" "datacontainer2")` |
| `LINKS` | Array | *Empty* | List of containers to link with. See the `docker` documentation for linked containers. | `LINKS=("container-to-link")` |

For more information, see the `container.cfg.sample` file.

### Configuration file notes:
~~Since configuration files are just bash scripts setting environment variables, you can add some intelligence. This however can lead to unexpected results. For the AUTO_REMOVE feature, which removes and restarts a container when a configuration file has changed, `towboat` currently checks the MD5 sum of the config file (and IP changes). If you dynamically set configuration options using external data sources, changes will not be detected.~~

Not true anymore, the new way of detecting changes calculates an MD5 on all resulting environment variables, not on the configuration file itself, so you can add some logic into the configuration files with bash-scripting to influence the configuration.

### Pipework settings
*This feature is not tested at all, and it is most likely not working.*

Available settings:

- `PW_ENABLED`
- `PW_HOSTIF`
- `PW_CONTAINER_IF`
- `PW_IP`
- `PW_GATEWAY`
- `PW_MAC`

## Examples

TODO: See the tests/ folder

