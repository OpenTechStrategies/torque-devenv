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

Your directory structure should look something like this:
```
- lever-for-change
| - devenv
| - torque-sites
| - data
```

4. (Optional) Populate necessary environment variables

```
$ cp .env.template .env
$ vi .env
$ source .env
```

The `.env.template` file explains the circumstances in which a developer may want to populate these variables.

5. Run `vagrant up`

This will build the machine and run the configuration. The machine will not have any competitions set up yet; this will need to be done manually depending on which competition you want to work with.

## Tips

* To stop the virtual machine run `vagrant halt`
* To SSH into the virtual machine run `vagrant ssh`
* If you want to re-run the contents of the VagrantFile you can run `vagrant up --provision` to reprovision.
* If you really want to completely start fresh run `vagrant destroy`.
