
Ruby / Redis Sample App on OpenShift
====================================

Contents
--------

- [Overview](#overview)
- [Host setup](#host-setup)
- [Projects](#projects)
- [Applications](#applications)
  * [Redis](#redis)
  * [Ruby](#ruby)
- [GitHub integration](#github-integration)
- [Templates](#templates)


Overview
--------

This is a guide on how to experiment with [OpenShift](https://github.com/openshift/origin) by setting up a simple Ruby application which will connect to a Redis server and check if it is alive. If it is, answer with a "Hello World!" message.

More information about OpenShift can be found at the [public documentation site](https://docs.okd.io/latest/welcome/).

If you already know about OpenShift [templates](https://docs.openshift.com/container-platform/3.10/dev_guide/templates.html) and want to start creating resource objects straight way, use the files in the **openshift** directory from this repository.

The rest of this document explains the steps I took to create an **OpenShift v3.10** cluster from scratch and then setup the sample Ruby / Redis application included in this repository. Of course, in the *real-world*, you normally go away with templates instead of creating everything manually.


Host setup
----------

I needed somewhere to host the OpenShift [control plane](https://docs.openshift.com/container-platform/3.10/architecture/infrastructure_components/kubernetes_infrastructure.html) so I started an **EC2** instance (virtual machine) on **Amazon Web Services** (**AWS**). This is a **t2.large** instance running **Ubuntu Server 16.04 LTS**. You can choose other base operating systems like [RHEL](https://access.redhat.com/products/red-hat-enterprise-linux) of course.

After waiting for some minutes I logged into my new instance and installed the [Docker](https://www.docker.com/) daemon (run these commands as **root** or use **sudo**).

	# curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	# echo 'deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable' > /etc/apt/sources.list.d/docker.list
	# apt-get update
	# apt-get install docker-ce

Once the Docker daemon is installed, if you will be running commands as the **ubuntu** user, be sure it has the required rights to communicate with the Docker daemon. Otherwise you'll have to run all commands as **root** or use **sudo**.

Ok, now we're ready to install OpenShift software. The easiest way to start up a cluster in a testing environment is using the **CLI** tool ([oc](https://docs.openshift.com/container-platform/3.10/cli_reference/get_started_cli.html)). So I downloaded the binary into my home directory and added that to my **PATH**.

	$ wget https://github.com/openshift/origin/releases/download/v3.10.0/openshift-origin-client-tools-v3.10.0-dd10d17-linux-64bit.tar.gz
	$ tar zxf openshift-origin-client-tools-v3.10.0-dd10d17-linux-64bit.tar.gz
	$ mv openshift-origin-client-tools-v3.10.0-dd10d17-linux-64bit openshift
	$ export PATH=~/openshift:$PATH && echo 'export PATH=~/openshift:$PATH' >> .bashrc 

This should give you a working ```oc``` command. Try running ```oc version```. If you want **Bash** command completion you can also run ```oc completion bash```. Check ```oc completion --help``` for examples.

A nice command provided by the CLI tool is ```oc cluster up```. This will create a new local cluster or start an existing one, if existing cluster files are detected in the current working directory. The first time I ran this command it failed because the Docker daemon was not configured to accept *insecure registries*. This check is done because OpenShift sets up a private registry to track images built by the container platform. So, if the IP address range for this new registry is not accepted by the Docker daemon, images will fail to push and no applications will be available. You can avoid this check with the ```--skip-registry-check``` option. But be aware this will surely bring further issues if not configured right. 

To configure Docker daemon to accept insecure registries in a specific range we will update the **systemd** service file. Once updated, restart the Docker service. Remember to use **root** or **sudo** for this.

	# sed -i -e '/ExecStart/s/dockerd/dockerd --insecure-registry 172.30.0.0\/16/' /lib/systemd/system/docker.service
	# systemctl daemon-reload
	# systemctl restart docker.service

Now we can run the ```oc cluster up``` command without issues. When finished we will be automatically logged in to OpenShift and will be given some hints by the command.


Projects
--------

When we first create the cluster we have a project created for us with the name **myproject**. Because the point is experimenting with OpenShift I created a new one. Creating a project automatically switches you to the new project. Use ```oc project``` to switch manually. To create the project I used the ```oc new-project``` command.

	$ oc new-project ruby-hello-world --display-name "Ruby Hello World" --description "Ruby / Redis sample application setup"


Applications
------------

We can create **applications** easily using the ```oc new-app``` command. There are several *strategies* available to build new applications. Which strategy is selected depends on the parameters supplied.

### Redis

The first application we can create is the Redis server. We can supply the name of a Docker image and it will be used to create the application with no further input. In my case I wanted to use a simple **Dockerfile** (which only includes a **FROM** line). Check **redis/Dockerfile** in this repository.

If the files you want to use are not stored using a source control management systems (like **Git**) you'll have to rely on **binary builds**. This means you can't trigger builds automatically, you must trigger them manually using the ```oc start-build``` command. Even if you don't specify a remote Git repository when running ```oc new-app```, if a Git *origin* remote is found, it will be used to trigger new builds.

The Docker build process needs a *context* directory where it can find the required files. So the next commands expect the current working directory to be that directory.

	$ oc new-app . --name=redis-app
	$ oc start-build redis-app --from-dir=. --follow

This will build the Redis application and let you know everything it is doing. If you're not interested on the build output information, remove the ```--follow``` option. Anyway, at any time you can review the output of the process with the ```oc logs bc/redis-app``` command.

To check if everything is working you can run the ```oc status``` command. You should see something like:

	In project Ruby Hello World (ruby-hello-world) on server https://127.0.0.1:8443
	
	svc/redis-app - 172.30.221.17:6379
	  dc/redis-app deploys istag/redis-app:latest <- bc/redis-app docker builds uploaded code on istag/redis:4.0.11
	    deployment #1 deployed 8 minutes ago - 1 pod

You can also check all resource objects created with the ```oc get all``` command.

To be sure everything is working as it should we can setup *readiness* and *liveness* probes. If these checks fail traffic will not be sent to the container or it might be restarted altogether. For the Redis application we will be running **redis-cli** on the container to *ping* the server regularly. We can set liveness and readiness probes using the ```oc set probe``` command.

### Ruby

The process for the Ruby application is similar to the previous one. We can use ```oc new-app``` and ```oc start-build``` as well. In this case we'll have some more files in the context directory. Check the **ruby** directory in this repository.

For the Ruby application we can try two different build strategies. We can go with the traditional **Dockerfile** strategy or we can use the **Source-to-Image** (**S2I**) builder. The later allows building Docker images straight away from an application source code directory, without needing a Dockerfile. All the process is customizable. Check the OpenShift online documentation for more information. I created two branches in this repository (**protected** / **s2i**) to test both strategies.

There is one side-effect of having the sample OpenShift templates installed. This makes a Ruby Docker image available which is not the Docker Hub official one. You won't be able to build with the Dockerfile from this repository and the included Ruby image. To fix this and use the Docker Hub image instead run the ```oc tag``` command before creating the app.

So, to create and build the Ruby application checkout the branch you want to test, change to the **ruby** directory, tag the correct Ruby image, create the application and start the build.

	$ oc tag --source=Docker library/ruby:2.5 ruby:2.5
	$ oc new-app . --name=ruby-app -e REDIS_HOST=redis-app -e REDIS_PORT=6379
	$ oc start-build ruby-app --from-dir=. --follow

In this case we are supplying environment variables which the Ruby application expects. We can also set environment variables on existing deployment configurations with the command ```oc set env```.

After the ```oc status``` command shows all **pods** are deployed succesfully you should be able to check the Ruby application. It should answer with "Hello World!".

	$ curl http://<put-your-service-ip-here>:4567

As we did with the Redis application, to be sure everything is working as it should, we can setup *readiness* and *liveness* probes. In this case we will be performing an HTTP request on the Ruby application regularly.


GitHub integration
------------------

To be able to trigger builds from GitHub we need to update build configurations to source files from there. We can update current resource objects with the ```oc edit``` command. Check template file for specific object properties to set. 

	$ oc edit bc/redis-app
	$ oc edit bc/ruby-app

Once the build configurations are updated we need to setup a GitHub webhook so we get notified of new push events on our remote repository. Steps to take on the GitHub repository are listed on the online [documentation](https://docs.openshift.com/container-platform/3.10/dev_guide/builds/triggering_builds.html#github-webhooks).


Templates
---------

Of course, there's an easier way to setup everything other than writing all the previous commands manually. To build the template which creates all the required objects in a single command I relied on the ```oc export``` command. Once this command exported the currently created objects I combined the resulting files and performed some edits which gave me the current **openshift/ruby-redis.json** file.

To create all the objectes described by the template I used ```oc process``` and ```oc create``` commands.

	$ oc process -f openshift/ruby-redis.json | oc create -f -

Templates can also be made available to others on OpenShift by using the ```oc create``` command. Currently available templates can be retrieved with ```oc get templates```. 

