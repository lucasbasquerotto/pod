# (Under Construction) Pod Layer

This repository corresponds to the pod layer and is used to deploy interdependent services in a given host.

## Demo

Before start using this layer, it's easier to see it in action. Below is a simple demo used to deploy a project. The demo uses pre-defined [input variables](#cloud-input-vars), uses a cloud layer to deploy a project and then uses this layer to define the deployed pod.

To execute the demo more easily you will need a container engine (like `docker` or `podman`).

1. Create an empty directory somewhere in your filesystem, let's say, `/var/demo`.

2. Create 2 directories in it: `env` and `data` (the names could be different, just remember to use these directories when mapping volumes to the container).

3. Create a `demo.yml` file inside `env` with the data needed to deploy the project:

```yaml
# Enter the data here (see the demo examples)
```

4. Deploy the project:

```shell
docker run -it --rm -v /var/demo/env:/env:ro -v /var/demo/data:/lrd local/demo
```

**The above commands in a shell script:**

```shell
mkdir -p /var/demo/env /var/demo/data

cat <<'SHELL' > /var/demo/env/demo.yml
# Enter the data here (see the demo examples)
SHELL

docker run -it --rm -v /var/demo/env:/env:ro -v /var/demo/data:/lrd local/demo
```

**That's it. The project was deployed.**

🚀 You can see examples of project deployment demos [here](#TODO).

The demos are great for what they are meant to be: demos, prototypes. **They shouldn't be used for development** (bad DX if you need real time changes without having to push and pull newer versions of repositories, furthermore you are unable to clone repositories in specific locations defined by you in the project folder). **They also shouldn't be used in production environments** due to bad security (the vault value used for decryption is `123456`, and changes to the [project environment repository](#project-environment) may be lost if you forget to push them).

## About this repository

This repository specifically expects the services to run inside containers because they are easier to organize and upgrade. Containers avoid package conflicts in the host and halps in isolating service dependencies.

The focus here is to provide scripts and templates to be used to run containers, avoiding boilerplate to be repeatedly included in different projects.

This repository is a generic implementation that actually isn't complete, and need another repository to complent it and to actually deploy a pod. An example of such a repository is: http://github.com/lucasbasquerotto/ext-pod

## Scripts

The scripts entrypoint is [/run](/run) at the root of this repository, from which the other scripts are executed. The way the scripts work is as follows:

1. A file `vars.sh` must be generated before running the commands. This file must define variables in the form `var=value` and will be loaded in a bash script.

2. They expect a command to define what is needed to run. For example, `./run upgrade` and `./run build my-service` are 2 examples that run the commands upgrade and build, respectively. The commands may also receive additional arguments (for example, the `build` command received the argument `my-service`). There are some exceptions for scripts that are very specific and need only one command, like [cron.sh](/shared/scripts/services/cron.sh), but they cannot be run directly, instead, they are called by another script that runs them (for example, `./run service:cron` at [shared.sh](/shared/scripts/shared.sh) calls the same command at [services.sh](/shared/scripts/services.sh), that then call [cron.sh](/shared/scripts/services/cron.sh) passing only the arguments after the command).

3. Some scripts, like [main.sh](/main/scripts/main.sh), [shared.sh](/shared/scripts/shared.sh) and [services.sh](/shared/scripts/services.sh), act like a hub for other scripts, while others, like [awscli.sh](/shared/scripts/services/awscli.sh) and [mysql.sh](/shared/scripts/services/mysql.sh), are more specific.

4. When the command is not defined in the script that receives it, the script must throw an error (like [nginx.sh](/shared/scripts/services/nginx.sh)) or call another script to run the code (like [shared.sh](/shared/scripts/shared.sh)), running in a cascade fashion. They can also act as a hook, running instructions before and after a given command. For example, `./run build`, when at the file [shared.sh](/shared/scripts/shared.sh), runs `before:build` at [services.sh](/shared/scripts/services.sh) (acting as a `before` hook) and then call the `build` command at [main.sh](/main/scripts/main.sh).

5. If one of the variables defined in this file is `var_load_script_path`, a file whose relative path is defined is in this variable must exist and will be loaded before running the command. The convention, in this case, is to define all variables in the `vars.sh` file to start with the prefix `var_load_`, and use then, in the file at `var_load_script_path` export the variables that will be used in the commands (it may load another script that that export variables, that can be reused accross different pods, like the script [shared.vars.sh](/shared/scripts/shared.vars.sh). This `var_load_script_path` variable is optional, tough, and, when not used, there's no need for the convention of the `var_load_` prefix for the variables.

6. The `vars.sh` file (or the `var_load_script_path` file) must export at least the 3 following variables:

- `var_pod_script`: the full path to the script that will run the commands (or alternatively, the path relative to the pod directory, `var_pod_script_relpath`).
- `var_pod_tmp_dir`: the full path to the temporary directory that may be used by the commands (or alternatively, the path relative to the pod directory, `var_pod_tmp_dir_relpath`).
- `var_pod_data_dir`: the full path to the data directory that may be used by commands (or alternatively, the path relative to the pod directory, `var_pod_data_dir_relpath`).

7. There are meta variables that can be defined in the `vars.sh` file to customize some execution behaviours:

- `var_run__meta__no_stacktrace`: don't print stacktraces on errors (triggered in `trap` commands).
- `var_run__meta__no_info`: don't show general information (command `util:info`).
- `var_run__meta__no_warn`: don't show warnings (command `util:warn`).
- `var_run__meta__no_error`: don't show errors (command `util:error`).
- `var_run__meta__no_info_wrap`: don't show information about before and after commands (commands `util:info:start` and `util:info:end`).
- `var_run__meta__no_summary`: don't show command summaries (command `util:info:summary`).
- `var_run__meta__no_colors`: don't print colors in information, warnings, errors and summaries.
- `var_run__meta__error_on_warn`: throw errors on warnings.

Among the scripts are those that have common code for different services (like backing up and restoring databases, graceful reload, tls certification generation, syncing to a S3 bucket, among other use cases) that can be seen at [services.sh](/shared/scripts/services.sh), which, then, call the expected service, if any.

There are also scripts for generic execution, that can be seen at the directory [/main/scripts](/main/scripts). Some of what they offer are the possibility to run an upgrade command, that runs the following commands: `build`, `prepare` and `setup`, and can be used for deployments in general. Other commands include the pod tasks, whose inputs can be defined as variables in `vars.sh`, and then used generically.

### Scripts Example

A simple example of a setup (this can be considered one of the simplest setups) that runs a sleep command, but gives an error if the command is already running, is as follows:

_vars.sh:_

```bash
export var_pod_script_relpath='test/run'
export var_pod_tmp_dir_relpath='test/tmp'
export var_pod_data_dir_relpath='test/data'
```

Then run `./run unique:next shared:test:sleep`. This command will run a sleep command that waits 5 seconds and is equivalent to `./run shared:test:sleep` as long as there's a single process running it. If a new process runs it, an error is thrown (but is not thrown when running `./run shared:test:sleep`; instead, it will run in parallel the same command). If, instead, the new process is the one that must run, killing the first, you can run `./run unique:next:force shared:test:sleep`

The execution of `./run unique:next shared:test:sleep` does the following:

1. Runs the [/run](/run) file with the command `unique:next`.
2. Runs the [/test/run](/test/run) file (due to the value of `var_pod_script_relpath`) with the command `unique:next`.
3. Runs the [shared.sh](/shared/scripts/shared.sh) file with the command `unique:next`.
4. Runs the [main.sh](/main/scripts/main.sh) file with the command `unique:next`, which runs the command `run-one` in the host (the `run-one` package must be installed in the host) with the arguments defined after the command (`shared:test:sleep`) as arguments to the [/test/run](/test/run) file.
5. Runs the [/test/run](/test/run) file with the command `shared:test:sleep`.
6. Runs the [shared.sh](/shared/scripts/shared.sh) file with the command `shared:test:sleep`.
7. Runs the [test.sh](/shared/scripts/test.sh) file with the command `shared:test:sleep`, which runs the command sleep in the host (printing messages to `stderr` before and after the sleep command).

The following vars.sh file do the same as the above, but with some meta variables to not print stacktraces nor information about the execution:

_vars.sh:_

```bash
export var_pod_script_relpath='test/run'
export var_pod_tmp_dir_relpath='test/tmp'
export var_pod_data_dir_relpath='test/data'
export var_run__meta__no_info='true'
export var_run__meta__no_info_wrap='true'
export var_run__meta__no_stacktrace='true'
export var_run__meta__no_summary='true'
```

## Templates

This repository includes some Jinja2 templates that can be used in projects, so as to not have to include them in each project, and to not have to dispend time creating similar templates.

The templates are in the directory [/shared/templates](/shared/templates) and can be defined in a [pod context](http://github.com/lucasbasquerotto/cloud#pod-context) file. The use of templates allows to use complex templates and adapt them to specific environment requirements.

### Template Example

Below you can see an example of how the [nginx](/shared/templates/nginx/nginx.tpl.conf) template can be used in a pod context file:

```yaml
templates:

- dest: "env/nginx/nginx.conf"
  src: "shared/templates/nginx/nginx.tpl.conf"
  schema: "shared/templates/nginx/nginx.schema.yml"
  params:
    main_domain: "example.com"
    conf:
      ssl: false
    ports:
      public_http_port: 8080
      private_http_port: 9080
    domains:
      demo: "example.com"
      theia: "theia.example.com"
    services:
      - name: "demo"
        locations:
          - location: "= /nginx/basic_status"
            data: "stub_status;"
          - location: "/"
            data: "return 200 '[demo] template result (access /nginx/basic_status)';"
      - name: "theia"
        endpoint: "http://theia:3000"
        upgrade: true
        private: true
```

The above template will generate a nginx configuration file at `env/nginx/nginx.conf`.

Then, you can place a `docker-compose.yml` file at the root of this repository with the following content:

```yaml
services:
  nginx:
    image: "nginx:1.14.2-alpine"
    restart: "unless-stopped"
    ports:
    - "8080:80"
    - "9080:9080"
    volumes:
    - "./env/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
    - "./shared/containers/nginx/include:/etc/nginx/include:ro"

  theia:
    image: "theiaide/theia:1.3.0"
    restart: "unless-stopped"
    user: root
    volumes:
    - "./test/data/.git:/home/project/.git:ro"
    - "./test/data:/home/project/data:rw"
    - "./env:/home/project/env:ro"
```

Then, run `docker-compose up -d` and you will be able to access the nginx service with the generated configuration.

You can deploy this project locally with the [project environment file](http://github.com/lucasbasquerotto/cloud#project-environment-file):

```yaml
name: "demo-template-local"
ctxs: ["local"]
env:
  repo:
    src: "https://github.com/lucasbasquerotto/env-base.git"
    version: "master"
  repo_dir: "env-base"
  file: "demos/demo-template.yml"
params:
  main_domain: "localhost"
```

And remotely at DigitalOcean with Cloudflare for DNS with:

```yaml
name: "demo-template-remote"
ctxs: ["remote"]
env:
  repo:
    src: "https://github.com/lucasbasquerotto/env-base.git"
    version: "master"
  repo_dir: "env-base"
  file: "demos/demo-template.yml"
params:
  private_ips: ["<< your_ip >>"]
  main_domain: "<< your_domain >>"
credentials:
  digital_ocean_api_token: "<< digital_ocean_api_token >>"
  cloudflare_email: "<< cloudflare_email >>"
  cloudflare_token: "<< cloudflare_token >>"
```

*Replace the variables between `<<` and `>>` with the corresponding values of your environment.*

In the local deployment, you need to run `docker-compose up -d` to start the services. Then, you can access the initial page at `localhost:8080`, the nginx stats page at `localhost:8080/nginx/basic_status` the theia service at `theia.localhost:9080`.

In the remote deployment there's no need to run `docker-compose up -d` (it runs in the deployment). You can access the same paths as the local deployment, just changing `localhost` in the urls with `<< your_domain >>`, but the theia service can only be accessed at `theia.<< your_domain >>:9080` if the ip of your machine (or a subnet that includes it) is defined at `private_ips` (the `private: true` in the pod context file makes the port of the `theia` service to be `9080`, as defined in the `private_http_port` property, and the `private_ips` property in the environment file defines the ips that can access the port `9080` in the environment base file).

## Real Examples

This repository just provide a base upon which a pod will be deployed, providing scripts and templates that can be used by them. To deploy a real pod, this repository alone should not be enough. Below you can see examples of pods that depend on this repository:

- [Ghost](http://github.com/lucasbasquerotto/ext-pod/tree/master/ghost)
- [Mattermost](http://github.com/lucasbasquerotto/ext-pod/tree/master/mattermost)
- [Mediawiki](http://github.com/lucasbasquerotto/ext-pod/tree/master/mediawiki)
- [Rocketchat](http://github.com/lucasbasquerotto/ext-pod/tree/master/rocketchat)
- [Wordpress](http://github.com/lucasbasquerotto/ext-pod/tree/master/wordpress)
