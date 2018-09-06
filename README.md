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

_(You may need to logout and login to make the changes apply. Make sure that `~/bin/` is in your `PATH`)_

## 4. Clone this repository inside `/docker/main/`

```bash
main init main https://github.com/lucasbasquerotto/docker-main.git
```

## 5. Start the containers with docker-compose

```bash
cd /docker/main
docker-compose up
```

## 6. Stop the containers with docker-compose

```bash
cd /docker/main
docker-compose down
```

# Notes

## 1. To update the git repository version (to a tag version, e.g. `0.0.2`)

```bash
main update main 0.0.2
```
