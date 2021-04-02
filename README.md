# Torque Development Environment

Herein lie scripts to set up a local development environment for the torque project (and other related Lever for Change repositories).

This repository heavily borrows from [PermanentOrg/devenv](https://github.com/PermanentOrg/devenv), but it is not a fork. That is because the purpose of these scripts (configuration of a development environment) and the differences between the projects mean there will never be upstream interaction.

## Usage
Follow these steps to get a development environment.

1. Install dependencies: [Vagrant](https://www.vagrantup.com/downloads) and [Virtualbox](https://www.virtualbox.org/wiki/Downloads).

2. Install [VirtualBox Guest Additions](https://www.virtualbox.org/manual/ch04.html) to support mounting shared folders.

3. Create *sibling* directories to `devenv`:

* `torque-sites`: a clone of the [torque-sites repository](https://github.com/OpenTechStrategies/torque-sites).
* `data`: an empty folder where competition data will be stored.
* `SimpleBook`: a clone of the [SimpleBook repository](https://github.com/OpenTechStrategies/SimpleBook).

Your directory structure should look something like this:
```
- lever-for-change
| - devenv
| - torque-sites
| - data
| - SimpleBook
```

4. (Optional) Populate necessary environment variables

```
$ cp .env.template .env
$ vi .env
$ source .env
```

The `.env.template` file explains the circumstances in which a developer may want to populate these variables.

5. Run `vagrant up`

This will build the machine and run the configuration. The final output will expose what the IP address of your guest machine is. This is dynamic and frequently changes between restarts.

The following competitions are enabled after provisioning:

* DemoView (accessed at `http://{GUEST_IP}/DemoView`)
* 100Change2020 (accessed at `http://{GUEST_IP}/100Change2020`)

## Viewing Logs

### SimpleBook

SimpleBook is run as a systemd service and logs can be found at:

```
/var/log/simplebook.output.log // output of the flask app is rendered here
/var/log/simplebook.error.log
```

## Tips

* To stop the virtual machine run `vagrant halt`
* To SSH into the virtual machine run `vagrant ssh`
* If you want to re-run the contents of the VagrantFile you can run `vagrant up --provision` to reprovision.
* If you really want to completely start fresh run `vagrant destroy`.
