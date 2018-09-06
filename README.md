# Main Docker Repository for Tests

## 1. Install docker

https://github.com/docker/docker-install

_(You may want to add the user in the docker group)_

## 2. Install docker-compose (actually, download the script to run from a docker container)

```bash
curl -L --fail https://raw.githubusercontent.com/lucasbasquerotto/docker-scripts/master/docker-compose.sh -o ~/bin/docker-compose
chmod +x ~/bin/docker-compose
```

## 3. Install git (actually, download the script to run from a docker container)

```bash
curl -L --fail https://raw.githubusercontent.com/lucasbasquerotto/docker-scripts/master/git.sh -o ~/bin/git
chmod +x ~/bin/git
```

_(You may need to logout and login to make the changes apply. Make sure that `~/bin/` is in your `PATH`)_

## 4. Use git to clone this repository

```bash
git clone https://github.com/lucasbasquerotto/docker-main.git
cd docker-main
```

## 5. Start the containers with docker-compose

```bash
docker-compose up
```

## 6. Stop the containers with docker-compose

```bash
docker-compose down
```
