# Main Docker Repository for Tests

## 1. Install docker

https://github.com/docker/docker-install

_(You may want to add the user in the docker group)_

## 2. Install docker-compose (actually, download the script to run from a docker container)

```bash
curl -L --fail https://raw.githubusercontent.com/lucasbasquerotto/docker-scripts/master/docker-compose.sh -o ~/bin/docker-compose
chmod +x ~/bin/docker-compose
```

## 3. Download the script to run git (use git from a docker container)

```bash
curl -L --fail https://raw.githubusercontent.com/lucasbasquerotto/docker-scripts/master/main.sh -o ~/bin/main
chmod +x ~/bin/main
```

## 4. Download the script to run the preparation (pull the images before changing the configuration directory in production)

```bash
curl -L --fail https://raw.githubusercontent.com/lucasbasquerotto/docker-scripts/master/prep-main.sh -o ~/bin/prep-main
chmod +x ~/bin/prep-main
```

_(You may need to logout and login to make the changes apply. Make sure that `~/bin/` is in your `PATH`)_

## 5. Clone this repository inside `/docker/main/`

```bash
main init main https://github.com/lucasbasquerotto/docker-main.git
```

## 6. Prepare an identical repository in `/docker/.tmp/` for pulling up-to-date images beforehand

```bash
main init .tmp https://github.com/lucasbasquerotto/docker-main.git
```

## 7. Start the containers with docker-compose

```bash
cd /docker/main
docker-compose up
```

## 8. Stop the containers with docker-compose

```bash
cd /docker/main
docker-compose stop
```

# Notes

## 1. To update the git repository version (to a tag version, e.g. `0.0.1`)

```bash
main update main 0.0.1
```

## 2. To pull images of a new version (e.g. `0.0.2`) before changing the main repository

```bash
prep-main 0.0.2
```
